import Foundation
import AuthenticationServices
import LightPlanData
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Окно входа поставщика облака — системное `ASWebAuthenticationSession` (31.1): страница Яндекса в защищённом окне
/// Safari, с его входом в аккаунт (не «эфемерное» окно: кто уже вошёл в Яндекс в Safari, не вводит пароль ещё раз).
/// Возврат ловится по схеме `lightplan-oauth` прямо этим окном: в Info.plist схема не нужна, и чужое приложение её
/// не перехватит. Пароль приложение не видит — его вводят на странице Яндекса.
@MainActor
final class SystemCloudSignIn: NSObject, CloudSignInPresenting, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func run(_ request: CloudSignInRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let s = ASWebAuthenticationSession(url: request.url, callback: .customScheme(request.callbackScheme)) { url, error in
                if let url { cont.resume(returning: url); return }
                if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    cont.resume(throwing: CloudFailure.cancelled); return
                }
                cont.resume(throwing: error.map { _ in CloudFailure.cancelled } ?? CloudFailure.cancelled)
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            session = s
            if !s.start() { cont.resume(throwing: CloudFailure.cancelled) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first.map { UIWindow(windowScene: $0) } ?? ASPresentationAnchor()
            #else
            return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
            #endif
        }
    }
}
