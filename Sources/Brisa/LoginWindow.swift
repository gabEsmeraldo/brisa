import AppKit
import WebKit

/// Shows LG's own sign-in page and catches the `lgaccount.lgsmartthinq:/` redirect.
/// The password (or QR / social sign-in) stays between the user and LG.
@MainActor
final class LoginWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var completion: ((URL?) -> Void)?

    func present(url: URL, completion: @escaping (URL?) -> Void) {
        self.completion = completion
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 720), configuration: config)
        web.navigationDelegate = self
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        web.load(URLRequest(url: url))

        let w = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = L("Sign in to LG")
        w.contentView = web
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, url.scheme == LegacyThinQ.redirectScheme {
            decisionHandler(.cancel)
            finish(url)
            return
        }
        decisionHandler(.allow)
    }

    func windowWillClose(_ notification: Notification) { finish(nil) }

    private func finish(_ url: URL?) {
        guard let completion else { return }
        self.completion = nil
        completion(url)
        window?.delegate = nil
        window?.close()
        window = nil
    }
}
