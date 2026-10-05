import Foundation
import CryptoKit

/// Читалка Pinterest в Yandex Cloud (`lightplanogreader`, итерация 28м): адрес известен всем, ключ — нет.
/// Ключ не лежит в репозитории (он публичный): фаза сборки `Tools/og_key.sh` кладёт его в
/// `pinterest_reader.plist` рядом с приложением из `~/.config/lightplan/og_key`. Нет файла — нет ключа —
/// Pinterest в приложении выключен с честной надписью, без падений (`PinterestConfig.load` вернёт `nil`).
public struct PinterestConfig: Sendable, Equatable {
    public static let defaultURL = URL(string: "https://functions.yandexcloud.net/d4e9gcsechraduu4pvnm")!

    public let url: URL
    public let key: String

    public init(url: URL = Self.defaultURL, key: String) {
        self.url = url
        self.key = key
    }

    public static func load(bundle: Bundle = .main) -> PinterestConfig? {
        guard let file = bundle.url(forResource: "pinterest_reader", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: file) as? [String: Any] else { return nil }
        let key = (dict["LPPinterestKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { return nil }
        let url = (dict["LPPinterestURL"] as? String).flatMap(URL.init(string:)) ?? defaultURL
        return PinterestConfig(url: url, key: key)
    }
}

/// Пин доски, как его отдаёт читалка.
public struct PinterestPin: Sendable, Equatable, Hashable {
    public let id: String
    public let permalink: String
    public let image: String
    public init(id: String, permalink: String, image: String) { self.id = id; self.permalink = permalink; self.image = image }
}

public struct PinterestBoard: Sendable, Equatable {
    public let name: String
    /// Сколько пинов на доске у Pinterest; в `pins` их не больше потолка читалки.
    public let pinCount: Int
    public let truncated: Bool
    public let pins: [PinterestPin]
    public init(name: String, pinCount: Int, truncated: Bool, pins: [PinterestPin]) {
        self.name = name; self.pinCount = pinCount; self.truncated = truncated; self.pins = pins
    }
}

/// Почему не вышло — по этому выбирается честная надпись (правило «без имитации»).
public enum PinterestFailure: Error, Equatable, Sendable {
    /// В этой сборке нет ключа.
    case notConfigured
    /// Человек выбрал «Только напрямую» (28л.6): читалка — наш сервер, приложение само Pinterest не читает.
    case serverOff
    /// Нет сети у телефона.
    case offline
    /// Читалка или Pinterest не ответили вовремя.
    case timeout
    /// Читалка ответила сбоем (502/5xx) — Pinterest отказал или упал.
    case serverDown
    /// Читалка просит подождать (429).
    case busy
    /// Читалка не приняла ключ (403).
    case rejected
    /// Доски нет, закрыта или удалена.
    case boardNotFound
    /// У пина нет картинки или её не отдали.
    case notFound
    /// Читалка не считает адрес Pinterest-адресом.
    case badLink
    /// Ответ пришёл, но это не то, что обещано.
    case badAnswer

    /// Сбой, из-за которого незачем продолжать очередь: следующие запросы упадут так же.
    public var isSystemic: Bool {
        switch self {
        case .notConfigured, .serverOff, .offline, .rejected, .busy: return true
        default: return false
        }
    }

    /// Один повтор имеет смысл (временный сбой), а не «нет такого».
    public var isTransient: Bool {
        switch self {
        case .timeout, .serverDown, .badAnswer: return true
        default: return false
        }
    }
}

/// Читалка за протоколом: приложение говорит с нашей функцией, тесты — со сценарием.
/// Режим 28л.6 держит обёртка `PolicyPinterestReader`; сама доступность читалки — ответ функции (`PinterestFailure`).
public protocol PinterestReading: Sendable {
    /// Список пинов доски; ссылка — доска или короткая `pin.it`.
    func board(link: String) async throws -> PinterestBoard
    /// Байты картинки пина по адресу из списка доски (`?img=`).
    func image(at address: String) async throws -> Data
    /// Байты картинки одного пина по ссылке на его страницу (`?url=`); короткую `pin.it` читалка раскрывает сама.
    func preview(of page: String) async throws -> Data
}

public struct PinterestTimeouts: Sendable, Equatable {
    public var page: TimeInterval
    public var image: TimeInterval
    public init(page: TimeInterval = 15, image: TimeInterval = 15) { self.page = page; self.image = image }
}

public typealias PinterestTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

public struct PinterestClient: PinterestReading {
    let config: PinterestConfig
    let timeouts: PinterestTimeouts
    let transport: PinterestTransport
    let genericPictures: Set<String>

    /// Картинка-заглушка Pinterest: на мёртвую или недописанную `pin.it/<код>` читалка отвечает `200` и отдаёт её
    /// (страница-посадка Pinterest с красной «P» на мозаике, 921 610 байт, одна и та же для любого кода; измерено 04.10.2026,
    /// два разных несуществующих кода — один и тот же sha256). Это не картинка пина: показывать её плиткой — имитация.
    /// Настоящий несуществующий `/pin/<номер>/` даёт честный 404. Если Pinterest сменит заглушку, фильтр перестанет её
    /// ловить, и плитка получит чужую картинку — тогда добавить новый отпечаток сюда.
    public static let genericPictureHashes: Set<String> = ["32a37cba60d1045235db6f18b41fd487beb96c35064d34a6ce0110a80728240c"]

    static func fingerprint(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    public init(config: PinterestConfig, timeouts: PinterestTimeouts = PinterestTimeouts(), transport: PinterestTransport? = nil,
                genericPictures: Set<String> = PinterestClient.genericPictureHashes) {
        self.config = config
        self.timeouts = timeouts
        self.genericPictures = genericPictures
        self.transport = transport ?? Self.liveTransport(timeouts: timeouts)
    }

    /// Боевая сборка; `nil` — в этой сборке нет ключа.
    public static func live(config: PinterestConfig?) -> PinterestClient? { config.map { PinterestClient(config: $0) } }

    /// Своя сессия: ждать ответа не дольше срока и целиком не дольше него (медленная сеть не висит минутами).
    static func liveTransport(timeouts: PinterestTimeouts, protocolClasses: [AnyClass]? = nil) -> PinterestTransport {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = max(timeouts.page, timeouts.image)
        c.timeoutIntervalForResource = max(timeouts.page, timeouts.image)
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let protocolClasses { c.protocolClasses = protocolClasses }
        let session = URLSession(configuration: c)
        return { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw PinterestFailure.badAnswer }
            return (data, http)
        }
    }

    // MARK: PinterestReading

    public func board(link: String) async throws -> PinterestBoard {
        let (data, _) = try await get(mode: "board", value: link, timeout: timeouts.page)
        guard let raw = try? JSONDecoder().decode(BoardAnswer.self, from: data) else { throw PinterestFailure.badAnswer }
        let pins = raw.pins.filter { !$0.id.isEmpty && !$0.image.isEmpty }
            .map { PinterestPin(id: $0.id, permalink: $0.permalink, image: $0.image) }
        let count = max(raw.pinCount ?? pins.count, pins.count)
        return PinterestBoard(name: raw.name ?? "", pinCount: count, truncated: raw.truncated ?? (count > pins.count), pins: pins)
    }

    public func image(at address: String) async throws -> Data {
        let (data, _) = try await get(mode: "img", value: address, timeout: timeouts.image)
        guard !data.isEmpty else { throw PinterestFailure.badAnswer }
        return data
    }

    public func preview(of page: String) async throws -> Data {
        let (data, _) = try await get(mode: "url", value: page, timeout: timeouts.page)
        guard !data.isEmpty else { throw PinterestFailure.badAnswer }
        if genericPictures.contains(Self.fingerprint(data)) { throw PinterestFailure.notFound }
        return data
    }

    // MARK: запрос

    private struct BoardAnswer: Decodable {
        struct Pin: Decodable { let id: String; let permalink: String; let image: String }
        let name: String?
        let pinCount: Int?
        let truncated: Bool?
        let pins: [Pin]
    }

    static func request(base: URL, mode: String, value: String, key: String, timeout: TimeInterval) -> URLRequest? {
        // Значение кодируется целиком: `&`, `?`, `#`, `+` внутри адреса пина не должны стать частью нашего запроса.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let v = value.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: base.absoluteString + "?\(mode)=" + v) else { return nil }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = "GET"
        r.setValue(key, forHTTPHeaderField: "X-LP-Key")
        return r
    }

    private func get(mode: String, value: String, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        guard let req = Self.request(base: config.url, mode: mode, value: value, key: config.key, timeout: timeout) else {
            throw PinterestFailure.badLink
        }
        let data: Data, http: HTTPURLResponse
        do {
            (data, http) = try await transport(req)
        } catch {
            throw Self.failure(for: error)
        }
        if (200..<300).contains(http.statusCode) { return (data, http) }
        throw Self.failure(status: http.statusCode, body: data)
    }

    static func failure(for error: Error) -> Error {
        if error is CancellationError { return error }
        if let f = error as? PinterestFailure { return f }
        guard let e = error as? URLError else { return PinterestFailure.serverDown }
        switch e.code {
        case .cancelled: return CancellationError()
        case .timedOut: return PinterestFailure.timeout
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .networkConnectionLost,
             .cannotFindHost, .dnsLookupFailed: return PinterestFailure.offline
        default: return PinterestFailure.serverDown
        }
    }

    static func failure(status: Int, body: Data) -> PinterestFailure {
        let reason = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["reason"] as? String ?? ""
        switch status {
        case 400: return .badLink
        case 403: return .rejected
        case 404: return reason == "board not found" ? .boardNotFound : .notFound
        case 413: return .notFound
        case 429: return .busy
        default: return .serverDown
        }
    }
}
