import Foundation
import Security

/// Связь с ядром Event OS (31.13; `docs/core_requirements_2026-11-19.md` CORE-01, CORE-02, вопрос 4.7).
/// 31.14: в сборке стоит `HTTPCoreClient` с одним домом — ru (Yandex Cloud Function, `CoreAddress.ru`). Дома world пока нет:
/// для номеров не из РФ и СНГ адреса нет, вызов — «нет связи» без сети, очередь (`CoreQueue`) молча ждёт. Снимки и тесты —
/// `AbsentCoreClient` (в сеть не ходит).
/// Слово «ядро» в интерфейсе не показывается (Алексей 23.11): человек видит «Мои данные».

/// Дом записи по стране номера (Алексей 22.11 «Да, по стране номера»): +7 и СНГ — Яндекс, остальные — Cloudflare.
public enum CoreHome: String, Codable, Sendable, Equatable {
    case ru, world

    /// Страны СНГ и +7 (Россия, Казахстан). Список — вывод исполнителя из «+7 и СНГ», не слова Алексея.
    public static let ruCountries: Set<String> = ["RU", "KZ", "BY", "AM", "AZ", "KG", "MD", "TJ", "TM", "UZ"]

    public static func of(country iso: String) -> CoreHome {
        ruCountries.contains(iso.uppercased()) ? .ru : .world
    }
}

/// Что телефон говорит о себе при регистрации (`POST /v1/devices`). Город — никогда; имя — только если человек его ввёл.
public struct CoreRegistration: Sendable, Equatable {
    public var appId: String
    public var country: String
    public var appVersion: String
    public var name: String?
    public init(appId: String, country: String, appVersion: String, name: String?) {
        self.appId = appId; self.country = country; self.appVersion = appVersion; self.name = name
    }
}

/// Пропуск устройства (ответ `201` на регистрацию). Хранится в Keychain, на сервере — только его хеш.
public struct CoreDevice: Codable, Sendable, Equatable {
    public var deviceId: String
    public var pass: String
    public var idState: String
    public var home: CoreHome
    /// ID, под которым устройство зарегистрировано: смена номера — `PATCH`.
    public var appId: String
    public init(deviceId: String, pass: String, idState: String, home: CoreHome, appId: String) {
        self.deviceId = deviceId; self.pass = pass; self.idState = idState; self.home = home; self.appId = appId
    }
}

public enum CoreFailure: Error, Equatable, Sendable {
    /// Ядра нет, нет сети, `503` — повторить позже, человеку не говорить.
    case unavailable
    /// `401 bad_pass`: пропуск не годен (стёрт на сервере) — забыть его.
    case badPass
    /// `400 bad_id`: номер не мобильный.
    case badId
    /// `429`.
    case rateLimited
    /// Прочий отказ (`413`, `415`, `422`, `409`…): код ответа.
    case rejected(Int)
}

/// Вызовы ядра по договору CORE-01/02 и 4.7. Тесты подставляют подделку, приложение — `HTTPCoreClient` (31.14).
public protocol CoreClient: Sendable {
    func register(_ r: CoreRegistration) async throws -> CoreDevice
    /// Смена номера в «Профиле»: ядро переносит аватарку на новый ID.
    func move(_ device: CoreDevice, to appId: String, at: Date) async throws
    func putAvatar(_ jpeg: Data, device: CoreDevice) async throws
    func deleteAvatar(device: CoreDevice) async throws
    /// `DELETE /v1/me`: стирает пропуск(а), аватарку и всё, что ядро знает о человеке. Повтор — `204`.
    func deleteMe(device: CoreDevice) async throws
}

/// Сервера нет: ни одного запроса в сеть, каждый вызов — «нет связи». Очередь ждёт, ошибок на экране нет (тесты, снимки).
public struct AbsentCoreClient: CoreClient {
    public init() {}
    public func register(_ r: CoreRegistration) async throws -> CoreDevice { throw CoreFailure.unavailable }
    public func move(_ device: CoreDevice, to appId: String, at: Date) async throws { throw CoreFailure.unavailable }
    public func putAvatar(_ jpeg: Data, device: CoreDevice) async throws { throw CoreFailure.unavailable }
    public func deleteAvatar(device: CoreDevice) async throws { throw CoreFailure.unavailable }
    public func deleteMe(device: CoreDevice) async throws { throw CoreFailure.unavailable }
}

/// Адрес дома ядра. Яндекс не пропускает путь после адреса функции (`…/<id>/v1/health` → 400 «invalid functionID»,
/// замер ядра 23–24.11), поэтому раздел там выбирается параметром: `?op=health`, `?op=devices/me` — то же, что
/// `/v1/health`, `/v1/devices/me` (`Event_OS:server/yandex/adapter.mjs`). Другие дома (Cloudflare, локальный запуск) — путём.
public struct CoreAddress: Sendable, Equatable {
    public enum Routing: Sendable, Equatable { case op, path }
    public var url: URL
    public var routing: Routing
    public init(url: URL, routing: Routing) { self.url = url; self.routing = routing }

    /// Дом ru (31.14): Yandex Cloud Function, публичный адрес (не секрет), проверка ядра 27/27 от 24.11.
    public static let ru = CoreAddress(url: URL(string: "https://functions.yandexcloud.net/d4ehnv8imbagj1vn50dd")!, routing: .op)

    /// Сборка приложения: есть только дом ru. Дома world пока нет (Алексей 23.11 «Пока мы начнем работу только с РФ»):
    /// номера не из РФ и СНГ ждут в очереди без запросов в сеть и без сообщений.
    public static let live: @Sendable (CoreHome) -> CoreAddress? = { $0 == .ru ? .ru : nil }

    /// Адрес раздела: `op` — `health`, `devices`, `devices/me`, `me/avatar`, `me`.
    public func url(_ op: String) -> URL {
        switch routing {
        case .path:
            return url.appendingPathComponent("v1").appendingPathComponent(op)
        case .op:
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "op", value: op)]
            return c.url!
        }
    }
}

/// Ответ `GET /v1/health` (CORE-03): `api` — разделы, которые уже работают; приложение не зовёт то, чего там нет.
public struct CoreHealth: Sendable, Equatable, Decodable {
    public var ok: Bool
    public var core: String?
    public var home: CoreHome?
    public var api: [String]
    public init(ok: Bool, core: String?, home: CoreHome?, api: [String]) { self.ok = ok; self.core = core; self.home = home; self.api = api }
}

/// Последний удачный ответ health по каждому дому. Неудачный не запоминается: следующий проход спросит снова.
actor CoreHealthMemory {
    private var seen: [CoreHome: (CoreHealth, Date)] = [:]
    func get(_ home: CoreHome, now: Date, ttl: TimeInterval) -> CoreHealth? {
        guard let e = seen[home], now >= e.1, now.timeIntervalSince(e.1) < ttl else { return nil }
        return e.0
    }
    func put(_ home: CoreHome, _ h: CoreHealth, at: Date) { seen[home] = (h, at) }
}

/// Ядро по HTTP — договор сервера `Event_OS:server/core/routes.mjs` (срез 1, коммит 7795d0a).
/// Перед вызовом раздела — `health` дома: раздела нет в `api`, дом не тот или связи нет — `.unavailable` без вызова.
/// Пропуск — только в `X-Core-Pass`: любой `Authorization` шлюз Яндекса принимает за свой IAM-токен и отвечает 403.
public struct HTTPCoreClient: CoreClient {
    public static let passHeader = "X-Core-Pass"
    /// Сколько верить удачному health: проход очереди бывает при изменении и при возврате в приложение.
    public static let healthTTL: TimeInterval = 600

    let base: @Sendable (CoreHome) -> CoreAddress?
    let transport: any CloudTransport
    let clock: @Sendable () -> Date
    let memory = CoreHealthMemory()

    public init(base: @escaping @Sendable (CoreHome) -> CoreAddress? = CoreAddress.live,
                transport: any CloudTransport = URLSessionCloudTransport(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.base = base; self.transport = transport; self.clock = clock
    }

    func request(_ home: CoreHome, _ method: String, _ op: String, pass: String? = nil) throws -> URLRequest {
        guard let address = base(home) else { throw CoreFailure.unavailable }
        var r = URLRequest(url: address.url(op))
        r.httpMethod = method
        r.timeoutInterval = 20
        if let pass { r.setValue(pass, forHTTPHeaderField: Self.passHeader) }
        return r
    }

    func send(_ r: URLRequest) async throws -> (Data, Int) {
        let (data, resp): (Data, HTTPURLResponse)
        do { (data, resp) = try await transport.send(r) } catch { throw CoreFailure.unavailable }
        let code = resp.statusCode
        switch code {
        case 200..<300: return (data, code)
        case 400:
            // `bad_id` — номер не мобильный; прочие 400 (`bad_request`, `wrong_home`) — отказ с кодом.
            struct Err: Decodable { var error: String? }
            let e = try? JSONDecoder().decode(Err.self, from: data)
            throw e?.error == "bad_id" ? CoreFailure.badId : CoreFailure.rejected(400)
        case 401: throw CoreFailure.badPass
        case 429: throw CoreFailure.rateLimited
        case 500...: throw CoreFailure.unavailable
        default: throw CoreFailure.rejected(code)
        }
    }

    /// `GET health` дома (без пропуска). Любой отказ (не 2xx, 403 шлюза, не `ok`, чужой `home`, не разобралось) — `.unavailable`.
    public func health(_ home: CoreHome) async throws -> CoreHealth {
        let now = clock()
        if let h = await memory.get(home, now: now, ttl: Self.healthTTL) { return h }
        let data: Data
        do { (data, _) = try await send(try request(home, "GET", "health")) } catch { throw CoreFailure.unavailable }
        // Дом в ответе — не тот, к которому шли (адрес перепутан): такому ответу не верить и не запоминать.
        guard let h = try? JSONDecoder().decode(CoreHealth.self, from: data), h.ok, h.home == nil || h.home == home
        else { throw CoreFailure.unavailable }
        await memory.put(home, h, at: now)
        return h
    }

    /// Раздел работает в этом доме — иначе `.unavailable` (очередь ждёт, как без связи).
    func ensure(_ home: CoreHome, _ section: String) async throws {
        guard base(home) != nil else { throw CoreFailure.unavailable }
        let h = try await health(home)
        guard h.api.contains(section) else { throw CoreFailure.unavailable }
    }

    public func register(_ reg: CoreRegistration) async throws -> CoreDevice {
        let home = CoreHome.of(country: reg.country)
        try await ensure(home, "devices")
        var r = try request(home, "POST", "devices")
        var body: [String: String] = ["app": "lightplan", "appId": reg.appId, "country": reg.country, "appVersion": reg.appVersion]
        if let n = reg.name { body["name"] = n }
        r.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await send(r)
        struct Reply: Decodable { var deviceId: String; var pass: String; var idState: String?; var home: CoreHome? }
        guard let a = try? JSONDecoder().decode(Reply.self, from: data) else { throw CoreFailure.unavailable }
        return CoreDevice(deviceId: a.deviceId, pass: a.pass, idState: a.idState ?? "unconfirmed", home: a.home ?? home, appId: reg.appId)
    }

    public func move(_ device: CoreDevice, to appId: String, at: Date) async throws {
        try await ensure(device.home, "devices")
        var r = try request(device.home, "PATCH", "devices/me", pass: device.pass)
        let body = ["appId": appId, "previous": device.appId, "at": ISO8601DateFormatter().string(from: at)]
        r.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(r)
    }

    public func putAvatar(_ jpeg: Data, device: CoreDevice) async throws {
        try await ensure(device.home, "avatar")
        var r = try request(device.home, "PUT", "me/avatar", pass: device.pass)
        r.httpBody = jpeg
        r.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        _ = try await send(r)
    }

    public func deleteAvatar(device: CoreDevice) async throws {
        try await ensure(device.home, "avatar")
        _ = try await send(try request(device.home, "DELETE", "me/avatar", pass: device.pass))
    }

    /// `DELETE /v1/me` (шаг 3 сервера) в `api` отдельного имени не имеет: стирает устройства — значит, раздел `devices`.
    public func deleteMe(device: CoreDevice) async throws {
        try await ensure(device.home, "devices")
        _ = try await send(try request(device.home, "DELETE", "me", pass: device.pass))
    }
}

// MARK: - Пропуск

public protocol CorePassStore: Sendable {
    func load() -> CoreDevice?
    func save(_ device: CoreDevice)
    func clear()
}

/// Keychain, «только на этом устройстве, после первой разблокировки» — как ключ облака (`KeychainCloudTokenStore`).
/// Своя запись у каждой копии «LP …»: имя зависит от bundle id.
public struct KeychainCorePassStore: CorePassStore {
    let service: String
    let account = "core.pass"

    public init(service: String = "lightplan.core." + (Bundle.main.bundleIdentifier ?? "app")) { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> CoreDevice? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(CoreDevice.self, from: data)
    }

    public func save(_ device: CoreDevice) {
        guard let data = try? JSONEncoder().encode(device) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    public func clear() { SecItemDelete(query as CFDictionary) }
}

public final class InMemoryCorePassStore: CorePassStore, @unchecked Sendable {
    private let lock = NSLock()
    private var device: CoreDevice?
    public init(_ device: CoreDevice? = nil) { self.device = device }
    public func load() -> CoreDevice? { lock.withLock { device } }
    public func save(_ d: CoreDevice) { lock.withLock { device = d } }
    public func clear() { lock.withLock { device = nil } }
}
