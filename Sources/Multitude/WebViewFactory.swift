import WebKit

// MARK: - WebView Factory

/// Creates `WKWebView` instances with fully isolated persistent data stores.
///
/// Each account gets its own store via `WKWebsiteDataStore(forIdentifier:)`,
/// which is the macOS 14+ API for creating separate on-disk storage containers.
/// This is the foundation of Multitude's account isolation — no cookie sharing,
/// no localStorage bleed, no server-side session joining.
enum WebViewFactory {
    static func makeWebView(
        for account: MultitudeAccount,
        uiDelegate: WKUIDelegate,
        navigationDelegate: WKNavigationDelegate
    ) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // ── Isolated persistent data store ──────────────────────────────
        //
        // Each account gets its own WKWebsiteDataStore identified by a unique
        // UUID. This creates a separate SQLite database, cache directory, and
        // cookie jar on disk — completely independent from every other account.
        //
        // The store persists across app launches because macOS backs it by the
        // store identifier UUID in the app's container.
        //
        // Must be set on the configuration BEFORE creating the WKWebView.
        // ─────────────────────────────────────────────────────────────────
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.storeIdentifier)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.uiDelegate = uiDelegate
        webView.navigationDelegate = navigationDelegate

        // ── Google compatibility user agent ─────────────────────────────
        //
        // Google Calendar still redirects WKWebView to its supported-browser
        // help page even when `applicationNameForUserAgent` appends a Safari
        // suffix. That means Calendar is either checking the raw request UA
        // more strictly or applying WKWebView/embedded-browser heuristics.
        //
        // This is intentionally a full Safari compatibility UA. It is more
        // invasive than `applicationNameForUserAgent` and should be treated as
        // a product/policy decision: without it, Calendar currently fails in
        // WKWebView; with it, test whether Calendar proceeds.
        //
        // Must be set before any navigation starts.
        webView.customUserAgent = safariCompatibilityUserAgent()
        return webView
    }

    static func safariCompatibilityUserAgent() -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) \(defaultSafariSuffix() ?? "Version/18.6 Safari/605.1.15")"
    }

    /// Builds the Safari version suffix for the user agent.
    ///
    /// Real Safari's user agent looks like:
    ///   AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.x Safari/605.1.15
    ///                                        ^^^^^^^^         ^^^^^^^^
    ///                                   Safari marketing    AppleWebKit token
    ///                                   version (26.5)      (always 605.1.15)
    ///
    /// The `Safari/` value MUST match the `AppleWebKit/` token (always `605.1.15`).
    /// The `Version/` value intentionally uses a conservative Safari 18 token
    /// instead of the installed Safari version. Some macOS 26 / Safari 26 builds
    /// currently trigger Google's Calendar supported-browser redirect even though
    /// Safari itself works. Safari 18.x is broadly accepted by Google's parser.
    ///
    /// Google checks both parts. Using the wrong Safari/ value (like the internal
    /// WebKit build number `21624.2.5`) triggers the "browser not supported" warning.
    static func defaultSafariSuffix() -> String? {
        // The AppleWebKit token is frozen at 605.1.15 for modern Safari.
        // Calendar rejects the internal WebKit build number here.
        return "Version/18.6 Safari/605.1.15"
    }
}
