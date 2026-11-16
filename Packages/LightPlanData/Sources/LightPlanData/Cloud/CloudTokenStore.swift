import Foundation
import Security

/// Где лежит ключ доступа к облаку. Один на установку: облако одно (DECISIONS «Облако фотографа»).
public protocol CloudTokenStore: Sendable {
    func load() -> CloudToken?
    func save(_ token: CloudToken)
    func clear()
}

/// Keychain телефона (решение 24.09: «ключи доступа к облакам — в Keychain»). Запись «только на этом устройстве,
/// после первой разблокировки»: в резервную копию iPhone ключ не уезжает, а фоновая выгрузка его прочтёт.
/// Имя записи зависит от bundle id — у каждой копии «LP …» своё подключение, как и свои данные.
public struct KeychainCloudTokenStore: CloudTokenStore {
    let service: String
    let account = "cloud.token"

    public init(service: String = "lightplan.cloud." + (Bundle.main.bundleIdentifier ?? "app")) {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> CloudToken? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(CloudToken.self, from: data)
    }

    public func save(_ token: CloudToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    public func clear() { SecItemDelete(query as CFDictionary) }
}

/// Ключ в памяти запуска — тестам и снимкам экранов.
public final class InMemoryCloudTokenStore: CloudTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: CloudToken?
    public init(_ token: CloudToken? = nil) { self.token = token }
    public func load() -> CloudToken? { lock.withLock { token } }
    public func save(_ token: CloudToken) { lock.withLock { self.token = token } }
    public func clear() { lock.withLock { token = nil } }
}

/// Не секретное о подключении — на устройстве (`UserDefaults`), как `lightplan.cloud.synced` веба: какой поставщик,
/// чьё имя показать, когда последний раз выгружали. В данные съёмок не идёт: восстановление из копии не должно
/// выбрасывать подключение (веб, «Токен хранится отдельно от данных»).
public struct CloudRecord: Codable, Sendable, Equatable {
    public var kind: CloudKind?
    public var account: String?
    public var lastUpload: Date?
    public init(kind: CloudKind? = nil, account: String? = nil, lastUpload: Date? = nil) {
        self.kind = kind; self.account = account; self.lastUpload = lastUpload
    }
}

public protocol CloudRecordStore: Sendable {
    func load() -> CloudRecord
    func save(_ record: CloudRecord)
}

public struct DefaultsCloudRecordStore: CloudRecordStore {
    let key: String
    public init(key: String = "lightplan.native.cloud.record") { self.key = key }
    public func load() -> CloudRecord {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(CloudRecord.self, from: $0) } ?? CloudRecord()
    }
    public func save(_ record: CloudRecord) {
        UserDefaults.standard.set(try? JSONEncoder().encode(record), forKey: key)
    }
}

public final class InMemoryCloudRecordStore: CloudRecordStore, @unchecked Sendable {
    private let lock = NSLock()
    private var record: CloudRecord
    public init(_ record: CloudRecord = CloudRecord()) { self.record = record }
    public func load() -> CloudRecord { lock.withLock { record } }
    public func save(_ record: CloudRecord) { lock.withLock { self.record = record } }
}
