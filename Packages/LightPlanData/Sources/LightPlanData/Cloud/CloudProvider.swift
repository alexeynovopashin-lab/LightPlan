import Foundation

/// Облако фотографа в нативе (итерация 31): **дополнительная копия и шлюз выгрузки**, не главное хранилище
/// (DECISIONS «Курс на серверы: облако — костыль PWA», 23.08). Главные данные — файл на телефоне (`Store`);
/// облако получает его копию и картинки мудборда и умеет отдать их обратно.
///
/// Поставщиков три, как у веба (DECISIONS «Облако фотографа — три поставщика под одним интерфейсом»); в 31.1
/// работает Яндекс, Google и Dropbox честно показаны «скоро» (`CloudKind.ready`).
public enum CloudKind: String, Sendable, CaseIterable, Codable {
    case yandex, google, dropbox

    /// Есть ли у этого поставщика реализация в этой сборке. Google и Dropbox — позже (план, итерация 31).
    public var ready: Bool { self == .yandex }
}

/// Ключ доступа, каким его отдал поставщик. Живёт в Keychain (`CloudTokenStore`), не в данных съёмок и не в
/// `UserDefaults`: копия данных уезжает в облако, и ключ к облаку в ней был бы лишним.
public struct CloudToken: Codable, Sendable, Equatable {
    public var kind: CloudKind
    public var access: String
    public var refresh: String?
    /// Когда ключ перестанет действовать (`expires_in` от выдачи); `nil` — поставщик не сказал.
    public var expires: Date?

    public init(kind: CloudKind, access: String, refresh: String?, expires: Date?) {
        self.kind = kind; self.access = access; self.refresh = refresh; self.expires = expires
    }

    /// Пора обновить: срок известен и до него меньше суток.
    public func stale(now: Date) -> Bool {
        guard let expires else { return false }
        return expires.timeIntervalSince(now) < 24 * 3600
    }
}

/// Что известно об аккаунте: имя для строки «Подключение» и место на Диске для честного «нет места».
/// Всё необязательно: без права «информация о Диске» Яндекс может не отдать ни того, ни другого.
public struct CloudAccount: Sendable, Equatable {
    public var login: String?
    public var name: String?
    public var freeBytes: Int64?

    public init(login: String? = nil, name: String? = nil, freeBytes: Int64? = nil) {
        self.login = login; self.name = name; self.freeBytes = freeBytes
    }

    /// Строка для человека: имя, иначе логин; пусто — `nil`.
    public var label: String? {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        let l = (login ?? "").trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? nil : l
    }
}

/// Почему не вышло — по этому выбирается честная строка под кнопками (правило «без имитации»).
public enum CloudFailure: Error, Equatable, Sendable {
    /// В этой сборке нет ClientID (`~/.config/lightplan/yandex_client_id` не нашёлся при сборке).
    case notConfigured
    /// Человек закрыл окно входа или отказал в доступе.
    case cancelled
    /// Ключ отозван или протух, обновить не вышло: подключиться заново.
    case revoked
    /// У телефона нет сети (или Яндекс недоступен).
    case offline
    /// На Диске нет места.
    case noSpace
    /// Копии в облаке ещё нет.
    case noCopy
    /// Файл с Диска — не копия Light Plan.
    case badCopy
    /// Поставщик ответил иначе, чем ждали: код ответа и его собственное объяснение, если было.
    case server(code: Int, message: String?)
}

/// Файл на Диске: имя и размер — по ним выгрузка картинок решает, что уже лежит.
public struct CloudItem: Sendable, Equatable {
    public var name: String
    public var size: Int64
    public var modified: Date?
    public init(name: String, size: Int64, modified: Date? = nil) { self.name = name; self.size = size; self.modified = modified }
}

/// Что умеет поставщик. Пути относительные (`light-plan-iphone.json`, `iphone-images/a.jpg`): как их разложить
/// у себя — дело поставщика (у Яндекса — `app:/…`, папка приложения).
public protocol CloudProvider: Sendable {
    var kind: CloudKind { get }
    /// Адрес окна входа и проверочная пара PKCE, которой его ответ меняется на ключ.
    func signIn() throws -> CloudSignInRequest
    /// Ответ окна входа (адрес возврата) — в ключ.
    func finishSignIn(_ callback: URL, request: CloudSignInRequest) async throws -> CloudToken
    /// Обновить ключ без окна; не вышло — `.revoked`.
    func refresh(_ token: CloudToken) async throws -> CloudToken
    func account(_ token: CloudToken) async throws -> CloudAccount
    func ensureFolder(_ path: String, token: CloudToken) async throws
    func upload(_ data: Data, to path: String, token: CloudToken) async throws
    /// Содержимое файла; файла нет — `nil`.
    func download(_ path: String, token: CloudToken) async throws -> Data?
    /// Сведения о файле; нет — `nil`.
    func item(_ path: String, token: CloudToken) async throws -> CloudItem?
    /// Файлы папки; папки нет — пустой список.
    func list(_ folder: String, token: CloudToken) async throws -> [CloudItem]
}

/// Окно входа: адрес, куда его открыть, схема возврата и одноразовая пара PKCE.
public struct CloudSignInRequest: Sendable, Equatable {
    public var url: URL
    public var callbackScheme: String
    public var verifier: String
    public var state: String
    public init(url: URL, callbackScheme: String, verifier: String, state: String) {
        self.url = url; self.callbackScheme = callbackScheme; self.verifier = verifier; self.state = state
    }
}
