import SwiftUI
import WebKit

/// SwiftUI bridge for `WKWebView`.
///
/// Swaps the displayed web view when `activeWebView` changes.
/// Web views are kept alive in `MultitudeModel` — they are never recreated
/// or reloaded during a room switch.
struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView?

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let webView = webView else {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        // Avoid re-adding if it's already the subview
        guard nsView.subviews.first !== webView else { return }

        nsView.subviews.forEach { $0.removeFromSuperview() }
        webView.translatesAutoresizingMaskIntoConstraints = false
        nsView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: nsView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
        ])
    }
}
