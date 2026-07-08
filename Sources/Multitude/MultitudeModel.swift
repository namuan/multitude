import SwiftUI
import WebKit
import UserNotifications

// MARK: - MultitudeModel

/// Central state owner for Multitude.
///
/// Responsibilities:
/// - Account CRUD and persistence (via JSON in `Application Support`)
/// - Room lifecycle: create, keep alive, switch, destroy
/// - Navigation (Gmail, Calendar, Drive, Meet)
/// - Unread badge polling via JavaScript injection
/// - macOS Dock badge and native notifications
/// - `WKNavigationDelegate` and `WKUIDelegate` for all web views
@MainActor
final class MultitudeModel: NSObject, ObservableObject {
    // MARK: Published state

    @Published var accounts: [MultitudeAccount] = []
    @Published var activeAccountId: UUID?
    @Published var unreadBadges: [UUID: Int] = [:]
    @Published var showingAddAccount = false
    @Published var showingDebugPanel = false
    @Published var debugMessages: [String] = []

    // Live web‑view metadata (updated for the active room)
    @Published var currentURL: String = ""
    @Published var pageTitle: String = ""
    @Published var currentService: GoogleService = .gmail

    // MARK: Internal state

    /// All rooms — keyed by account `id`.
    private var rooms: [UUID: WKWebView] = [:]

    /// Tracks the last-known unread count per account so we can detect *new* mail.
    private var lastKnownBadges: [UUID: Int] = [:]

    private var badgeTimer: Timer?

    // MARK: Computed

    var activeWebView: WKWebView? {
        guard let id = activeAccountId else { return nil }
        return rooms[id]
    }

    var totalUnread: Int {
        unreadBadges.values.reduce(0, +)
    }

    // MARK: - Initialization

    override init() {
        super.init()
        loadAccounts()
        buildRooms()
        startBadgeTimer()
        requestNotificationPermission()

        if let first = accounts.first {
            switchTo(first.id)
            loadService(first.lastService)
        }
    }

    // MARK: - Account Persistence

    private static func accountsURL() -> URL? {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths.first?.appendingPathComponent("Multitude", isDirectory: true)
        if let dir = dir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir?.appendingPathComponent("accounts.json")
    }

    private func loadAccounts() {
        guard let url = Self.accountsURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([MultitudeAccount].self, from: data)
        else {
            // First launch — create a starter account
            accounts = [MultitudeAccount(displayName: "Work", order: 0)]
            saveAccounts()
            return
        }
        accounts = decoded.sorted { $0.order < $1.order }
    }

    private func saveAccounts() {
        guard let url = Self.accountsURL(),
              let data = try? JSONEncoder().encode(accounts)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Account CRUD

    func addAccount(displayName: String, email: String = "") {
        let account = MultitudeAccount(
            displayName: displayName,
            email: email,
            order: accounts.count
        )
        accounts.append(account)
        saveAccounts()

        // Build its room and load Gmail
        let wv = WebViewFactory.makeWebView(for: account, uiDelegate: self, navigationDelegate: self)
        rooms[account.id] = wv
        wv.load(URLRequest(url: GoogleService.gmail.url))

        addDebug("Added room '\(displayName)'")
        switchTo(account.id)
    }

    func removeAccount(_ id: UUID) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        let account = accounts[idx]

        accounts.remove(at: idx)
        saveAccounts()

        // Tear down the room
        rooms.removeValue(forKey: id)
        unreadBadges.removeValue(forKey: id)
        lastKnownBadges.removeValue(forKey: id)

        // Wipe the persistent data store from disk.
        clearWebsiteData(for: account) { }

        addDebug("Removed room '\(account.displayName)'")

        // Switch to the nearest remaining account
        if activeAccountId == id {
            switchTo(accounts.first?.id)
        }
    }

    /// Clears this room's isolated website data, recreates its WKWebView, and
    /// loads Gmail. The account entry remains in the sidebar.
    ///
    /// Use this when Google caches bad browser-check state, a sign-in gets
    /// wedged, or the user wants to fully sign out/recover one room without
    /// touching any other account.
    func resetAccount(_ id: UUID) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        addDebug("Resetting room '\(account.displayName)'…")

        if let oldWebView = rooms[id] {
            oldWebView.stopLoading()
            oldWebView.navigationDelegate = nil
            oldWebView.uiDelegate = nil
        }
        rooms.removeValue(forKey: id)
        unreadBadges[id] = 0
        lastKnownBadges[id] = 0

        clearWebsiteData(for: account) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                let newWebView = WebViewFactory.makeWebView(
                    for: account,
                    uiDelegate: self,
                    navigationDelegate: self
                )
                self.rooms[id] = newWebView
                self.addDebug("Room '\(account.displayName)' reset complete")
                newWebView.load(URLRequest(url: GoogleService.gmail.url))

                if self.activeAccountId == id {
                    self.objectWillChange.send()
                    self.syncActiveState()
                    self.switchTo(id)
                }
            }
        }
    }

    private func clearWebsiteData(for account: MultitudeAccount, completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore(forIdentifier: account.storeIdentifier)
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: dataTypes) { records in
            store.removeData(ofTypes: dataTypes, for: records) {
                completion()
            }
        }
    }

    func renameAccount(_ id: UUID, to name: String) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].displayName = name
        saveAccounts()
    }

    func setEmail(_ id: UUID, email: String) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].email = email
        saveAccounts()
    }

    func reorderAccounts(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        for (i, _) in accounts.enumerated() {
            accounts[i].order = i
        }
        saveAccounts()
    }

    // MARK: - Room Switching

    func switchTo(_ id: UUID?) {
        guard let id = id, rooms[id] != nil else { return }
        activeAccountId = id
        // Restore the last active service for this room
        if let account = accounts.first(where: { $0.id == id }) {
            currentService = account.lastService
        }
        syncActiveState()
        addDebug("Switched to \(displayName(for: id))")

        // Focus the web view so keyboard input works immediately
        if let wv = rooms[id] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                wv.becomeFirstResponder()
            }
        }
    }

    func switchToIndex(_ index: Int) {
        guard index >= 0, index < accounts.count else { return }
        switchTo(accounts[index].id)
    }

    private func displayName(for id: UUID) -> String {
        accounts.first { $0.id == id }?.displayName ?? "?"
    }

    private func syncActiveState() {
        guard let id = activeAccountId, let wv = rooms[id] else {
            currentURL = ""
            pageTitle = ""
            return
        }
        currentURL = wv.url?.absoluteString ?? ""
        pageTitle = wv.title ?? ""
    }

    // MARK: - Room Lifecycle

    private func buildRooms() {
        // Log the full compatibility user agent being applied
        addDebug("UA mode: full Safari compatibility override")
        addDebug("UA: \(WebViewFactory.safariCompatibilityUserAgent())")

        for account in accounts {
            let wv = WebViewFactory.makeWebView(for: account, uiDelegate: self, navigationDelegate: self)
            rooms[account.id] = wv
        }

        // Asynchronously log the actual user agent for the first room
        if let firstWV = rooms.first?.value {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                firstWV.evaluateJavaScript("navigator.userAgent") { result, _ in
                    guard let self = self, let ua = result as? String else { return }
                    Task { @MainActor in
                        self.addDebug("Actual UA: \(ua)")
                    }
                }
            }
        }
    }

    // MARK: - Navigation

    func loadService(_ service: GoogleService) {
        guard let id = activeAccountId, let wv = rooms[id] else { return }
        currentService = service
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            accounts[idx].lastService = service
            saveAccounts()
        }
        wv.load(URLRequest(url: service.url))
        addDebug("\(service.title) loaded in \(displayName(for: id))")
    }

    func reload() {
        activeWebView?.reload()
    }

    func goBack() {
        activeWebView?.goBack()
    }

    func goForward() {
        activeWebView?.goForward()
    }

    // MARK: - Debug

    func addDebug(_ message: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(df.string(from: Date()))] \(message)"
        debugMessages.append(line)
        print(line)
    }

    // MARK: - Slot lookup (used by delegates)

    /// Returns the display name for the account that owns `webView`.
    fileprivate func name(for webView: WKWebView) -> String {
        for (id, wv) in rooms where wv === webView {
            return displayName(for: id)
        }
        return "?"
    }
}

// MARK: - Unread Badges & Notifications

extension MultitudeModel {
    private func startBadgeTimer() {
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAllUnreadCounts()
            }
        }
        // Also check immediately after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            Task { @MainActor in
                self?.checkAllUnreadCounts()
            }
        }
    }

    func checkAllUnreadCounts() {
        for (id, wv) in rooms {
            wv.evaluateJavaScript("document.title") { [weak self] result, _ in
                guard let self = self,
                      let title = result as? String
                else { return }
                let count = Self.parseGmailUnreadCount(from: title)
                let old = self.lastKnownBadges[id] ?? 0
                Task { @MainActor in
                    self.unreadBadges[id] = count
                    self.lastKnownBadges[id] = count
                    // Dock badge
                    let total = self.unreadBadges.values.reduce(0, +)
                    NSApplication.shared.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
                    // Notification for new mail
                    if count > old, let acct = self.accounts.first(where: { $0.id == id }) {
                        self.postLocalNotification(for: acct, count: count)
                    }
                }
            }
        }
    }

    /// Parse Gmail's unread count from the page title.
    /// Gmail formats: `"(3) Inbox - user@gmail.com - Gmail"`
    private static func parseGmailUnreadCount(from title: String) -> Int {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("("), let end = t.firstIndex(of: ")") else { return 0 }
        let num = t[t.index(after: t.startIndex) ..< end]
        return Int(num) ?? 0
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { granted, _ in
            print("Multitude notification permission: \(granted)")
        }
    }

    private func postLocalNotification(for account: MultitudeAccount, count: Int) {
        let content = UNMutableNotificationContent()
        content.title = account.displayName
        content.body = "\(count) unread \(count == 1 ? "message" : "messages")"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "multitude-\(account.id.uuidString)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - WKNavigationDelegate

extension MultitudeModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let room = name(for: webView)
        addDebug("[\(room)] Start: \(webView.url?.absoluteString ?? "?")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let room = name(for: webView)
        let url = webView.url?.absoluteString ?? ""
        addDebug("[\(room)] Finish: \(url)")
        if webView === activeWebView {
            currentURL = url
            pageTitle = webView.title ?? ""
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let room = name(for: webView)
        addDebug("[\(room)] Error: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let room = name(for: webView)
        addDebug("[\(room)] Provisional error: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let room = name(for: webView)
        addDebug("[\(room)] Redirect: \(webView.url?.absoluteString ?? "?")")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let room = name(for: webView)
        addDebug("[\(room)] Process terminated")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        decisionHandler(.allow, preferences)
    }
}

// MARK: - WKUIDelegate

extension MultitudeModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let room = name(for: webView)
        addDebug("[\(room)] Media permission: \(type) from \(origin.host)")
        decisionHandler(.grant)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            let room = name(for: webView)
            addDebug("[\(room)] Popup, loading in-room: \(url.absoluteString)")
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let room = name(for: webView)
        addDebug("[\(room)] JS Alert: \(message.prefix(120))")
        completionHandler()
    }
}
