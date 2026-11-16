import Foundation
import CryptoKit

/// Сеть облака одной функцией: тесты подставляют поддельный Диск (`FakeYandexDisk` в тестах), приложение — `URLSession`.
public protocol CloudTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Настоящая сеть. Отказ сети (нет связи, таймаут, хост не найден) — `CloudFailure.offline`, а не сырой `URLError`:
/// экрану нужна причина, а не код.
public struct URLSessionCloudTransport: CloudTransport {
    let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, resp) = try await session.data(for: request)
            guard let http = resp as? HTTPURLResponse else { throw CloudFailure.server(code: 0, message: nil) }
            return (data, http)
        } catch let e as URLError {
            switch e.code {
            case .cancelled: throw CloudFailure.cancelled
            default: throw CloudFailure.offline
            }
        }
    }
}

/// Одноразовая пара PKCE (RFC 7636): проверочная строка остаётся в телефоне, наружу уходит только её отпечаток
/// SHA-256. Так вход обходится без секрета приложения — секрету в открытом исходнике негде спрятаться
/// (DECISIONS «Облако фотографа», абзац про Dropbox; Яндекс: «если передается code_verifier, секретный ключ
/// передавать не требуется»).
public enum PKCE {
    /// 64 случайных байта в base64url — 86 знаков, в пределах 43…128 по RFC.
    public static func verifier() -> String {
        var g = SystemRandomNumberGenerator()
        let bytes = (0..<64).map { _ in UInt8.random(in: .min ... .max, using: &g) }
        return base64url(Data(bytes))
    }

    public static func challenge(_ verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
