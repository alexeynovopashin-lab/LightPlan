import Foundation

/// Своя аватарка фотографа (31.13, Алексей 19.11 «Только своя»). Квадрат JPEG 512 без EXIF лежит файлом рядом со
/// снимком данных (`avatar.jpg`); круг — только отрисовка. В снимок (`light-plan.json`) не попадает: веб её не знает.
public struct AvatarStore: Sendable {
    public static let fileName = "avatar.jpg"
    public let url: URL

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(Self.fileName)
    }

    public func read() -> Data? { try? Data(contentsOf: url) }

    @discardableResult
    public func save(_ jpeg: Data) -> Bool { (try? jpeg.write(to: url, options: .atomic)) != nil }

    /// Старое фото стирается сразу (Алексей 22.11 «Стирать сразу»).
    public func remove() { try? FileManager.default.removeItem(at: url) }
}

/// Заглушка, пока фото нет (Алексей 23.11): вместо диафрагмы — кошка, собака или человек из библиотеки значков.
/// Выбирается случайно один раз на установку и запоминается; на сервер не уходит.
public enum AvatarStub: String, Codable, Sendable, CaseIterable {
    case cat, dog, person
}

/// Что должно дойти до ядра. Ставится действием человека, снимается, когда ядро ответило; без связи — ждёт.
public struct CoreQueue: Codable, Sendable, Equatable {
    /// Текущее состояние фото (есть — выгрузить, нет — стереть) ещё не на сервере.
    public var avatar = false
    /// «Удалить мои данные» нажато, сервер ещё не подтвердил.
    public var forget = false
    public init(avatar: Bool = false, forget: Bool = false) { self.avatar = avatar; self.forget = forget }
    public var isEmpty: Bool { !avatar && !forget }
}

/// Память установки: заглушка и очередь. UserDefaults: в резервной копии iPhone может уехать — это не секрет.
public struct AvatarRecord: Codable, Sendable, Equatable {
    public var stub: AvatarStub?
    public var queue = CoreQueue()
    public init(stub: AvatarStub? = nil, queue: CoreQueue = CoreQueue()) { self.stub = stub; self.queue = queue }
}

public protocol AvatarRecordStore: Sendable {
    func load() -> AvatarRecord
    func save(_ record: AvatarRecord)
}

public struct DefaultsAvatarRecordStore: AvatarRecordStore {
    let key = "lightplan.native.avatar"
    public init() {}
    public func load() -> AvatarRecord {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(AvatarRecord.self, from: $0) } ?? AvatarRecord()
    }
    public func save(_ record: AvatarRecord) {
        UserDefaults.standard.set(try? JSONEncoder().encode(record), forKey: key)
    }
}

public final class InMemoryAvatarRecordStore: AvatarRecordStore, @unchecked Sendable {
    private let lock = NSLock()
    private var record: AvatarRecord
    public init(_ record: AvatarRecord = AvatarRecord()) { self.record = record }
    public func load() -> AvatarRecord { lock.withLock { record } }
    public func save(_ r: AvatarRecord) { lock.withLock { record = r } }
}

/// Один проход очереди. Порядок: сначала «забыть меня» (если нажато), потом смена номера, потом фото.
/// Регистрируется устройство только ради фото — то есть по действию человека и только с мобильным номером (CORE-01).
/// Любой сбой связи оставляет пункт в очереди и ничего не говорит человеку.
public enum CoreSync {
    public struct Input: Sendable {
        public var avatar: Data?
        public var appId: String
        public var country: String
        public var appVersion: String
        public var name: String?
        public var now: Date
        public init(avatar: Data?, appId: String, country: String, appVersion: String, name: String?, now: Date) {
            self.avatar = avatar; self.appId = appId; self.country = country; self.appVersion = appVersion; self.name = name; self.now = now
        }
    }

    public static func run(_ queue: CoreQueue, _ input: Input, client: any CoreClient, passes: any CorePassStore) async -> CoreQueue {
        var q = queue
        if q.forget {
            if let d = passes.load() {
                do { try await client.deleteMe(device: d) } catch CoreFailure.badPass {
                    // Пропуск уже не годен — ядро этого устройства не знает: стирать нечего.
                } catch { return q }
                passes.clear()
            }
            q.forget = false
        }
        // Номер сменили, а устройство записано под старым ID: ядро переносит аватарку (CORE-01, `PATCH`).
        if var d = passes.load(), !input.appId.isEmpty, d.appId != input.appId {
            do {
                try await client.move(d, to: input.appId, at: input.now)
                d.appId = input.appId
                passes.save(d)
            } catch CoreFailure.badPass { passes.clear() } catch { return q }
        }
        guard q.avatar else { return q }
        if let jpeg = input.avatar {
            for attempt in 0..<2 {
                guard let d = await device(input, passes: passes, client: client) else { return q }
                do {
                    try await client.putAvatar(jpeg, device: d)
                    q.avatar = false
                    return q
                } catch CoreFailure.badPass where attempt == 0 {
                    passes.clear()   // сервер забыл пропуск — зарегистрироваться заново, один раз
                } catch { return q }
            }
            return q
        }
        guard let d = passes.load() else { q.avatar = false; return q }   // фото не было на сервере
        do { try await client.deleteAvatar(device: d) } catch CoreFailure.badPass { passes.clear() } catch { return q }
        q.avatar = false
        return q
    }

    static func device(_ input: Input, passes: any CorePassStore, client: any CoreClient) async -> CoreDevice? {
        if let d = passes.load() { return d }
        guard !input.appId.isEmpty else { return nil }   // без мобильного номера не регистрируемся: фото ждёт
        let reg = CoreRegistration(appId: input.appId, country: input.country, appVersion: input.appVersion, name: input.name)
        guard let d = try? await client.register(reg) else { return nil }
        passes.save(d)
        return d
    }
}
