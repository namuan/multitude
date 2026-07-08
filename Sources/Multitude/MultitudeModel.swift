import SwiftUI
import WebKit
import UserNotifications
import AVFoundation

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
        let log = FileLogger.shared
        log.info("═══════════════════════════════════════════")
        log.info("Multitude starting up")
        super.init()

        log.info("Loading accounts…")
        loadAccounts()
        log.info("Accounts loaded: \(accounts.count)")

        log.info("Building rooms…")
        buildRooms()
        log.info("Rooms built: \(rooms.count)")

        log.info("Starting badge timer…")
        startBadgeTimer()

        log.info("Requesting notification permission…")
        requestNotificationPermission()

        log.info("Requesting camera / microphone permission…")
        requestMediaPermissions()

        if let first = accounts.first {
            log.info("Switching to first account: \(first.displayName) (lastService: \(first.lastService.title))")
            switchTo(first.id)
        } else {
            log.warning("No accounts found on startup")
        }
        log.info("═══════════════════════════════════════════ Startup complete")
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
            FileLogger.shared.info("No saved accounts found, creating starter 'Work' account")
            accounts = [MultitudeAccount(displayName: "Work", order: 0)]
            saveAccounts()
            return
        }
        accounts = decoded.sorted { $0.order < $1.order }
        FileLogger.shared.debug("Loaded \(accounts.count) accounts from \(url.path)")
    }

    private func saveAccounts() {
        guard let url = Self.accountsURL(),
              let data = try? JSONEncoder().encode(accounts)
        else {
            FileLogger.shared.error("Failed to encode or locate accounts URL for saving")
            return
        }
        try? data.write(to: url, options: .atomic)
        FileLogger.shared.debug("Saved \(accounts.count) accounts to \(url.path)")
    }

    // MARK: - Account CRUD

    func addAccount(displayName: String, email: String = "") {
        FileLogger.shared.info("addAccount called — displayName: \(displayName), email: \(email)")
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
        FileLogger.shared.info("Room built and Gmail loading for account: \(displayName) (id: \(account.id))")

        addDebug("Added room '\(displayName)'")
        switchTo(account.id)
    }

    func removeAccount(_ id: UUID) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else {
            FileLogger.shared.warning("removeAccount called for unknown id: \(id)")
            return
        }
        let account = accounts[idx]
        FileLogger.shared.info("Removing account: \(account.displayName) (id: \(id))")

        accounts.remove(at: idx)
        saveAccounts()

        // Tear down the room
        rooms.removeValue(forKey: id)
        unreadBadges.removeValue(forKey: id)
        lastKnownBadges.removeValue(forKey: id)

        // Wipe the persistent data store from disk.
        clearWebsiteData(for: account) {
            FileLogger.shared.info("Website data cleared for: \(account.displayName)")
        }

        addDebug("Removed room '\(account.displayName)'")

        // Switch to the nearest remaining account
        if activeAccountId == id {
            let nextId = accounts.first?.id
            FileLogger.shared.info("Active account was removed, switching to: \(nextId?.uuidString ?? "nil")")
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
        guard let account = accounts.first(where: { $0.id == id }) else {
            FileLogger.shared.warning("resetAccount called for unknown id: \(id)")
            return
        }
        FileLogger.shared.info("Resetting room: \(account.displayName) (id: \(id))")
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
                FileLogger.shared.info("Website data cleared for reset, rebuilding room")
                let newWebView = WebViewFactory.makeWebView(
                    for: account,
                    uiDelegate: self,
                    navigationDelegate: self
                )
                self.rooms[id] = newWebView
                self.addDebug("Room '\(account.displayName)' reset complete")
                newWebView.load(URLRequest(url: GoogleService.gmail.url))
                FileLogger.shared.info("Loading Gmail in reset room")

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
            FileLogger.shared.debug("Clearing \(records.count) data records for store: \(account.storeIdentifier)")
            store.removeData(ofTypes: dataTypes, for: records) {
                completion()
            }
        }
    }

    func renameAccount(_ id: UUID, to name: String) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else {
            FileLogger.shared.warning("renameAccount called for unknown id: \(id)")
            return
        }
        let oldName = accounts[idx].displayName
        accounts[idx].displayName = name
        saveAccounts()
        FileLogger.shared.info("Renamed account '\(oldName)' → '\(name)' (id: \(id))")
    }

    func setEmail(_ id: UUID, email: String) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else {
            FileLogger.shared.warning("setEmail called for unknown id: \(id)")
            return
        }
        accounts[idx].email = email
        saveAccounts()
        FileLogger.shared.debug("Set email for account \(id) to: \(email)")
    }

    func reorderAccounts(from source: IndexSet, to destination: Int) {
        FileLogger.shared.debug("Reordering accounts: source=\(source), destination=\(destination)")
        accounts.move(fromOffsets: source, toOffset: destination)
        for (i, _) in accounts.enumerated() {
            accounts[i].order = i
        }
        saveAccounts()
    }

    // MARK: - Room Switching

    func switchTo(_ id: UUID?) {
        guard let id = id, rooms[id] != nil else {
            FileLogger.shared.warning("switchTo called with id=\(id?.uuidString ?? "nil") but no matching room")
            return
        }
        let name = displayName(for: id)
        let prevId = activeAccountId
        FileLogger.shared.info("switchTo: \(name) (id: \(id)), previous active=\(prevId?.uuidString ?? "nil")")

        activeAccountId = id
        // Restore the last active service for this room
        if let account = accounts.first(where: { $0.id == id }) {
            currentService = account.lastService
            FileLogger.shared.debug("Restored lastService=\(account.lastService.title) for \(name)")
            // Navigate the web view to that service
            loadService(account.lastService)
        } else {
            FileLogger.shared.warning("No account found for id \(id) during switchTo")
        }
        syncActiveState()
        addDebug("Switched to \(displayName(for: id))")

        let roomCount = rooms.count
        let badgeCount = unreadBadges.count
        FileLogger.shared.debug("Room state: rooms=\(roomCount), badges=\(badgeCount), activeId=\(activeAccountId?.uuidString ?? "nil")")

        // Focus the web view so keyboard input works immediately
        if let wv = rooms[id] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                wv.becomeFirstResponder()
            }
            // Check unread immediately — page may already be loaded
            FileLogger.shared.debug("Triggering unread check after switch for \(name)")
            checkUnread(for: wv, accountId: id)
        }
    }

    func switchToIndex(_ index: Int) {
        guard index >= 0, index < accounts.count else {
            FileLogger.shared.warning("switchToIndex called with out-of-range index: \(index) (accounts: \(accounts.count))")
            return
        }
        FileLogger.shared.debug("switchToIndex: \(index) → \(accounts[index].displayName)")
        switchTo(accounts[index].id)
    }

    private func displayName(for id: UUID) -> String {
        accounts.first { $0.id == id }?.displayName ?? "?"
    }

    private func syncActiveState() {
        guard let id = activeAccountId, let wv = rooms[id] else {
            currentURL = ""
            pageTitle = ""
            FileLogger.shared.debug("syncActiveState: no active account or web view")
            return
        }
        currentURL = wv.url?.absoluteString ?? ""
        pageTitle = wv.title ?? ""
        FileLogger.shared.debug("syncActiveState: url='\(currentURL)', title='\(pageTitle)'")
    }

    // MARK: - Room Lifecycle

    private func buildRooms() {
        // Log the full compatibility user agent being applied
        addDebug("UA mode: full Safari compatibility override")
        addDebug("UA: \(WebViewFactory.safariCompatibilityUserAgent())")

        FileLogger.shared.info("buildRooms: creating \(accounts.count) rooms")
        for account in accounts {
            FileLogger.shared.debug("  Creating room for: \(account.displayName) (id: \(account.id))")
            let wv = WebViewFactory.makeWebView(for: account, uiDelegate: self, navigationDelegate: self)
            rooms[account.id] = wv
        }
        FileLogger.shared.info("buildRooms complete: \(rooms.count) rooms")

        // Asynchronously log the actual user agent for the first room
        if let firstWV = rooms.first?.value {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                firstWV.evaluateJavaScript("navigator.userAgent") { result, _ in
                    guard let self = self, let ua = result as? String else { return }
                    Task { @MainActor in
                        self.addDebug("Actual UA: \(ua)")
                        FileLogger.shared.info("Actual user agent: \(ua)")
                    }
                }
            }
        }
    }

    // MARK: - Navigation

    func loadService(_ service: GoogleService) {
        guard let id = activeAccountId, let wv = rooms[id] else {
            FileLogger.shared.warning("loadService: no active account or web view for service=\(service.title)")
            return
        }
        let name = displayName(for: id)
        FileLogger.shared.info("loadService: \(service.title) for \(name) (id: \(id))")

        currentService = service
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            accounts[idx].lastService = service
            saveAccounts()
            FileLogger.shared.debug("Persisted lastService=\(service.title) for \(name)")
        }
        let url = service.url.absoluteString
        FileLogger.shared.debug("Loading URL: \(url)")
        wv.load(URLRequest(url: service.url))
        addDebug("\(service.title) loaded in \(displayName(for: id))")
    }

    func reload() {
        guard let wv = activeWebView else {
            FileLogger.shared.warning("reload called but no active web view")
            return
        }
        let url = wv.url?.absoluteString ?? "?"
        FileLogger.shared.info("Reloading: \(url)")
        wv.reload()
    }

    func goBack() {
        guard let wv = activeWebView else {
            FileLogger.shared.warning("goBack called but no active web view")
            return
        }
        FileLogger.shared.info("goBack: canGoBack=\(wv.canGoBack), current=\(wv.url?.absoluteString ?? "?")")
        wv.goBack()
    }

    func goForward() {
        guard let wv = activeWebView else {
            FileLogger.shared.warning("goForward called but no active web view")
            return
        }
        FileLogger.shared.info("goForward: canGoForward=\(wv.canGoForward), current=\(wv.url?.absoluteString ?? "?")")
        wv.goForward()
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
        FileLogger.shared.info("startBadgeTimer: setting up 30s recurring timer + 5s initial check")

        badgeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            FileLogger.shared.debug("Badge timer fired (30s tick)")
            Task { @MainActor in
                self?.checkAllUnreadCounts()
            }
        }

        // Also check immediately after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            FileLogger.shared.debug("Initial 5s badge check firing")
            Task { @MainActor in
                self?.checkAllUnreadCounts()
            }
        }
    }

    func checkAllUnreadCounts() {
        FileLogger.shared.debug("checkAllUnreadCounts: checking \(rooms.count) rooms")
        let activeId = activeAccountId
        for (id, wv) in rooms {
            let isActive = id == activeId
            FileLogger.shared.debug("  Queueing check for room \(id) (active=\(isActive))")
            checkUnread(for: wv, accountId: id)
        }
        FileLogger.shared.debug("checkAllUnreadCounts: done queuing")
    }

    /// Check the unread count for a single web view and update its badge.
    private func checkUnread(for webView: WKWebView, accountId: UUID) {
        let name = displayName(for: accountId)
        let currentUrl = webView.url?.absoluteString ?? "nil"

        FileLogger.shared.debug("checkUnread: \(name) url=\(currentUrl)")

        webView.evaluateJavaScript("document.title") { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                FileLogger.shared.warning("checkUnread JS error for \(name): \(error.localizedDescription)")
                return
            }

            guard let title = result as? String else {
                FileLogger.shared.warning("checkUnread JS returned nil/non-string for \(name) (result type: \(type(of: result)))")
                return
            }

            FileLogger.shared.debug("checkUnread: \(name) document.title = '\(title)'")

            let count = Self.parseGmailUnreadCount(from: title)
            let old = self.lastKnownBadges[accountId] ?? 0

            FileLogger.shared.info("checkUnread: \(name) parsed=\(count) old=\(old)")

            Task { @MainActor in
                self.unreadBadges[accountId] = count
                self.lastKnownBadges[accountId] = count

                FileLogger.shared.debug("checkUnread: updated unreadBadges[\(accountId)] = \(count)")

                // Dock badge
                let total = self.unreadBadges.values.reduce(0, +)
                NSApplication.shared.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
                FileLogger.shared.debug("Dock badge updated: total=\(total)")

                // Notification for new mail
                if count > old, let acct = self.accounts.first(where: { $0.id == accountId }) {
                    FileLogger.shared.info("New mail notification for \(acct.displayName): \(count) unread")
                    self.postLocalNotification(for: acct, count: count)
                }
            }
        }
    }

    /// Parse Gmail's unread count from the page title.
    /// Gmail format: `"Inbox (3) - user@gmail.com - Gmail"`
    private static func parseGmailUnreadCount(from title: String) -> Int {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the first '(' and the following ')'
        guard let start = t.firstIndex(of: "("),
              let end = t.firstIndex(of: ")"),
              start < end
        else {
            let preview = t.prefix(80)
            FileLogger.shared.debug("parseGmailUnreadCount: no () pair in title='\(preview)'")
            return 0
        }

        let num = t[t.index(after: start) ..< end]
        let parsed = Int(num) ?? 0
        FileLogger.shared.debug("parseGmailUnreadCount: found '\(num)' → \(parsed) in title='\(t.prefix(80))'")
        return parsed
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { granted, error in
            if let error = error {
                FileLogger.shared.error("Notification permission error: \(error.localizedDescription)")
            }
            FileLogger.shared.info("Notification permission granted: \(granted)")
            print("Multitude notification permission: \(granted)")
        }
    }

    /// Proactively request camera and microphone permission at startup so the
    /// system prompt appears *before* Google Meet tries to use them. Without
    /// this, WKWebView's `getUserMedia()` may fail silently on modern macOS.
    private func requestMediaPermissions() {
        if #available(macOS 14, *) {
            let camera = AVCaptureDevice.authorizationStatus(for: .video)
            let mic = AVCaptureDevice.authorizationStatus(for: .audio)
            FileLogger.shared.info("Media permissions: camera=\(camera.rawValue) mic=\(mic.rawValue)")

            if camera == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    FileLogger.shared.info("Camera permission: \(granted)")
                }
            }
            if mic == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    FileLogger.shared.info("Microphone permission: \(granted)")
                }
            }
        } else {
            FileLogger.shared.debug("requestMediaPermissions: macOS < 14, skipping")
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
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                FileLogger.shared.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension MultitudeModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let room = name(for: webView)
        let url = webView.url?.absoluteString ?? "?"
        addDebug("[\(room)] Start: \(url)")
        FileLogger.shared.info("Nav START [\(room)] \(url)")
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let room = name(for: webView)
        let url = webView.url?.absoluteString ?? "?"
        addDebug("[\(room)] Redirect: \(url)")
        FileLogger.shared.info("Nav REDIRECT [\(room)] \(url)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let room = name(for: webView)
        let url = webView.url?.absoluteString ?? ""
        let title = webView.title ?? ""
        addDebug("[\(room)] Finish: \(url)")
        FileLogger.shared.info("Nav FINISH [\(room)] url='\(url)' title='\(title)'")

        if webView === activeWebView {
            currentURL = url
            pageTitle = webView.title ?? ""
            FileLogger.shared.debug("Active web view updated: url='\(url)' title='\(title)'")
        }

        // Check unread count as soon as a page finishes loading
        if let id = rooms.first(where: { $0.value === webView })?.key {
            FileLogger.shared.debug("Nav FINISH → triggering unread check for \(room)")
            checkUnread(for: webView, accountId: id)
        } else {
            FileLogger.shared.warning("Nav FINISH but no matching room found for webView")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let room = name(for: webView)
        let url = webView.url?.absoluteString ?? "?"
        addDebug("[\(room)] Error: \(error.localizedDescription)")
        FileLogger.shared.error("Nav FAIL [\(room)] \(url) error=\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let room = name(for: webView)
        let url = webView.url?.absoluteString ?? "?"
        addDebug("[\(room)] Provisional error: \(error.localizedDescription)")
        FileLogger.shared.error("Nav PROVISIONAL FAIL [\(room)] \(url) error=\(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let room = name(for: webView)
        addDebug("[\(room)] Process terminated")
        FileLogger.shared.warning("Web content process terminated [\(room)]")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        let url = navigationAction.request.url?.absoluteString ?? "?"
        FileLogger.shared.debug("Nav POLICY allow: \(url)")
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
        FileLogger.shared.info("Media permission granted: type=\(type.rawValue) host=\(origin.host) [\(room)]")
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
            FileLogger.shared.info("Popup redirected in-room: \(url.absoluteString) [\(room)]")
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
        FileLogger.shared.debug("JS Alert [\(room)]: \(message.prefix(200))")
        completionHandler()
    }
}
