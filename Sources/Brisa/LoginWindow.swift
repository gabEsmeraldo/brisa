import AppKit
import AuthenticationServices

/// Runs LG's sign-in in the system web authentication sheet (Safari engine), so
/// Google/Apple sign-in and popups work, and catches the `lgaccount.lgsmartthinq:/` redirect.
/// The password stays between the user and LG.
@MainActor
final class LoginWindow: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = LoginWindow()
    private var session: ASWebAuthenticationSession?

    func present(url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: LegacyThinQ.redirectScheme) { [weak self] callback, error in
            Task { @MainActor in
                self?.session = nil
                if let callback {
                    completion(.success(callback))
                } else if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                    completion(.failure(error))
                }
            }
        }
        session.presentationContextProvider = self
        // Reuse Safari's cookies so an existing Google session carries over.
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        NSApp.activate(ignoringOtherApps: true)
        if !session.start() { completion(.failure(LegacyThinQ.Failure.badResponse)) }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSWindow()
        }
    }
}
