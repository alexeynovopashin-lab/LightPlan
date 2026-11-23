import Foundation
import Security

/// Связь с ядром Event OS (31.13; `docs/core_requirements_2026-11-19.md` CORE-01, CORE-02, вопрос 4.7).
/// Сервера ядра ещё нет: в сборке стоит `AbsentCoreClient`, который в сеть не ходит и отвечает «нет связи», —
/// очередь (`CoreQueue`) молча ждёт. Когда ядро появится, на его место встаёт `HTTPCoreClient` с адресами двух домов.
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

/// Вызовы ядра по договору CORE-01/02 и 4.7. Тесты подставляют подделку, приложение — `AbsentCoreClient`, пока сервера нет.
public protocol CoreClient: Sendable {
    func register(_ r: CoreRegistration) async throws -> CoreDevice
    /// Смена номера в «Профиле»: ядро переносит аватарку на новый ID.
    func move(_ device: CoreDevice, to appId: String, at: Date) async throws
    func putAvatar(_ jpeg: Data, device: CoreDevice) async throws
    func deleteAvatar(device: CoreDevice) async throws
    /// `DELETE /v1/me`: стирает пропуск(а), аватарку и всё, что ядро знает о человеке. Повтор — `204`.
    func deleteMe(device: CoreDevice) async throws
}

/// Сервера нет: ни одного запроса в сеть, каждый вызов — «нет связи». Очередь ждёт, ошибок на экране нет.
public struct AbsentCoreClient: CoreClient {
    public init() {}
    public func register(_ r: CoreRegistration) async throws -> CoreDevice { throw CoreFailure.unavailable }
    public func move(_ device: CoreDevice, to appId: String, at: Date) async throws { throw CoreFailure.unavailable }
    public func putAvatar(_ jpeg: Data, device: CoreDevice) async throws { throw CoreFailure.unavailable }
    public func deleteAvatar(device: CoreDevice) async throws { throw CoreFailure.unavailable }
    public func deleteMe(device: CoreDevice) async throws { throw CoreFailure.unavailable }
}

/// Ядро по HTTP — договор из `docs/core_requirements_2026-11-19.md` (предложение, сервер его ещё не принял).
/// Адрес дома — снаружи: `nil` для дома значит «этого дома нет», вызов — `.unavailable` без сети.
public struct HTTPCoreClient: CoreClient {
    let base: @Sendable (CoreHome) -> URL?
    let transport: any CloudTransport

    public init(base: @escaping @Sendable (CoreHome) -> URL?, transport: any CloudTransport = URLSessionCloudTransport()) {
        self.base = base; self.transport = transport
    }

    func request(_ home: CoreHome, _ method: String, _ path: String, pass: String? = nil) throws -> URLRequest {
        guard let root = base(home) else { throw CoreFailure.unavailable }
        var r = URLRequest(url: root.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = 20
        if let pass { r.setValue("Bearer " + pass, forHTTPHeaderField: "Authorization") }
        return r
    }

    func send(_ r: URLRequest) async throws -> (Data, Int) {
        let (data, resp): (Data, HTTPURLResponse)
        do { (data, resp) = try await transport.send(r) } catch { throw CoreFailure.unavailable }
        let code = resp.statusCode
        switch code {
        case 200..<300: return (data, code)
        case 400: throw CoreFailure.badId
        case 401: throw CoreFailure.badPass
        case 429: throw CoreFailure.rateLimited
        case 500...: throw CoreFailure.unavailable
        default: throw CoreFailure.rejected(code)
        }
    }

    public func register(_ reg: CoreRegistration) async throws -> CoreDevice {
        let home = CoreHome.of(country: reg.country)
        var r = try request(home, "POST", "v1/devices")
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
        var r = try request(device.home, "PATCH", "v1/devices/me", pass: device.pass)
        let body = ["appId": appId, "previous": device.appId, "at": ISO8601DateFormatter().string(from: at)]
        r.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(r)
    }

    public func putAvatar(_ jpeg: Data, device: CoreDevice) async throws {
        var r = try request(device.home, "PUT", "v1/me/avatar", pass: device.pass)
        r.httpBody = jpeg
        r.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        _ = try await send(r)
    }

    public func deleteAvatar(device: CoreDevice) async throws {
        _ = try await send(try request(device.home, "DELETE", "v1/me/avatar", pass: device.pass))
    }

    public func deleteMe(device: CoreDevice) async throws {
        _ = try await send(try request(device.home, "DELETE", "v1/me", pass: device.pass))
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
