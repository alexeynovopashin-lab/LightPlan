import Foundation

/// Читалка под режимом «Сеть» (28л.6). Прямого пути к Pinterest у приложения нет — читает только наша функция
/// (`PinterestClient`), поэтому «Авто» для неё всегда «через сервер», как и было: зарубежное доступно или нет,
/// другого пути не существует. «Только напрямую» (слово Алексея: наш сервер для этих двух вещей не используется) —
/// читалка выключена честным отказом `serverOff`, запрос на сервер не уходит.
public struct PolicyPinterestReader: PinterestReading {
    let base: any PinterestReading
    let policy: @Sendable () async -> NetworkPolicy

    public init(_ base: any PinterestReading, policy: @escaping @Sendable () async -> NetworkPolicy) {
        self.base = base
        self.policy = policy
    }

    private func gate() async throws {
        if await policy().mode == .directOnly { throw PinterestFailure.serverOff }
    }

    public func board(link: String) async throws -> PinterestBoard {
        try await gate()
        return try await base.board(link: link)
    }

    public func image(at address: String) async throws -> Data {
        try await gate()
        return try await base.image(at: address)
    }

    public func preview(of page: String) async throws -> Data {
        try await gate()
        return try await base.preview(of: page)
    }
}
