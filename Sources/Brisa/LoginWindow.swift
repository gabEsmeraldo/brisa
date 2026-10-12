import AppKit

/// Opens LG's sign-in in the user's default browser. LG finishes by redirecting to
/// `lgaccount.lgsmartthinq:/?code=…`; Info.plist registers that scheme, so macOS hands
/// the URL back to Brisa (see `AppDelegate.application(_:open:)`).
/// The password stays between the user and LG.
@MainActor
enum LoginWindow {
    static func present(url: URL) {
        NSWorkspace.shared.open(url)
    }
}
