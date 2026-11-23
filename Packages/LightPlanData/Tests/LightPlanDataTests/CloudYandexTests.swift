import Foundation
import Testing
import LightPlanCore
@testable import LightPlanData

/// Поддельный Яндекс: окно входа (обмен кода с PKCE), `/v1/disk`, папки, загрузка и скачивание по выданным
/// ссылкам. Проверяет то, что проверил бы настоящий: отпечаток PKCE, заголовок `OAuth`, отозванный ключ, место.
final class FakeYandexDisk: CloudTransport, @unchecked Sendable {
    private let lock = NSLock()
    var files: [String: Data] = [:]       // путь `app:/…` → содержимое
    var dirs: Set<String> = []
    var validTokens: Set<String> = []
    var refreshes: [String: String] = [:] // ключ обновления → выдаёт этот доступ
    var codes: [String: String] = [:]     // код → отпечаток PKCE
    var freeBytes: Int64 = 10_000_000
    var offline = false
    var infoAllowed = true
    var log: [String] = []
    private var issued = 0

    func give(code: String, challenge: String) { lock.withLock { codes[code] = challenge } }
    func revokeAll() { lock.withLock { validTokens.removeAll(); refreshes.removeAll() } }
    func file(_ p: String) -> Data? { lock.withLock { files[p] } }

    private func reply(_ code: Int, _ json: Any? = nil, _ url: URL) -> (Data, HTTPURLResponse) {
        let data = json.map { (try? JSONSerialization.data(withJSONObject: $0)) ?? Data() } ?? Data()
        return (data, HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try lock.withLock { try handle(request) }
    }

    private func handle(_ r: URLRequest) throws -> (Data, HTTPURLResponse) {
        if offline { throw CloudFailure.offline }
        let url = r.url!
        let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        func q(_ n: String) -> String? { c.queryItems?.first { $0.name == n }?.value }
        log.append((r.httpMethod ?? "GET") + " " + url.path)

        if url.host == "oauth.test", url.path == "/token" {
            let form = Dictionary(uniqueKeysWithValues: String(decoding: r.httpBody ?? Data(), as: UTF8.self)
                .split(separator: "&").map { kv -> (String, String) in
                    let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
                    return (p[0], (p.count > 1 ? p[1] : "").removingPercentEncoding ?? "")
                })
            #expect(form["client_secret"] == nil, "секрет приложения не уходит никогда")
            #expect(form["client_id"] == "test-client")
            switch form["grant_type"] {
            case "authorization_code":
                guard let ch = codes.removeValue(forKey: form["code"] ?? ""),
                      let v = form["code_verifier"], PKCE.challenge(v) == ch else {
                    return reply(400, ["error": "invalid_grant", "error_description": "Code has expired"], url)
                }
            case "refresh_token":
                guard refreshes[form["refresh_token"] ?? ""] != nil else {
                    return reply(400, ["error": "invalid_grant", "error_description": "Refresh token expired"], url)
                }
            default: return reply(400, ["error": "unsupported_grant_type"], url)
            }
            issued += 1
            let access = "acc\(issued)", refresh = "ref\(issued)"
            validTokens.insert(access); refreshes[refresh] = access
            return reply(200, ["access_token": access, "refresh_token": refresh, "expires_in": 31_536_000, "token_type": "bearer"], url)
        }

        if url.host == "upload.test" {
            let p = q("p")!
            let size = Int64(r.httpBody?.count ?? 0)
            if size > freeBytes { return reply(507, ["error": "InsufficientStorageError"], url) }
            freeBytes -= size
            files[p] = r.httpBody ?? Data()
            return reply(201, nil, url)
        }
        if url.host == "download.test" {
            guard let d = files[q("p")!] else { return reply(404, nil, url) }
            return (d, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        // Диск: ключ обязателен и только в виде `OAuth <ключ>`.
        let auth = r.value(forHTTPHeaderField: "Authorization") ?? ""
        guard auth.hasPrefix("OAuth "), validTokens.contains(String(auth.dropFirst(6))) else {
            return reply(401, ["error": "UnauthorizedError", "message": "Не авторизован."], url)
        }
        let path = q("path") ?? ""
        switch (r.httpMethod ?? "GET", url.path) {
        case ("GET", "/v1/disk"), ("GET", "/v1/disk/"):
            if !infoAllowed { return reply(403, ["error": "ForbiddenError"], url) }
            return reply(200, ["total_space": 20_000_000, "used_space": 20_000_000 - freeBytes,
                               "user": ["login": "alexey.photo", "display_name": "Алексей"]], url)
        case ("PUT", "/v1/disk/resources"):
            if dirs.contains(path) { return reply(409, ["error": "DiskPathPointsToExistentDirectoryError"], url) }
            dirs.insert(path); return reply(201, [:], url)
        case ("GET", "/v1/disk/resources/upload"):
            let parent = (path as NSString).deletingLastPathComponent
            if parent != "app:" && !dirs.contains(parent) { return reply(409, ["error": "DiskPathDoesntExistsError"], url) }
            if freeBytes <= 0 { return reply(507, ["error": "InsufficientStorageError"], url) }
            var u = URLComponents(string: "https://upload.test/put")!
            u.queryItems = [.init(name: "p", value: path)]
            return reply(200, ["href": u.url!.absoluteString, "method": "PUT"], url)
        case ("GET", "/v1/disk/resources/download"):
            guard files[path] != nil else { return reply(404, ["error": "DiskNotFoundError"], url) }
            var u = URLComponents(string: "https://download.test/get")!
            u.queryItems = [.init(name: "p", value: path)]
            return reply(200, ["href": u.url!.absoluteString], url)
        case ("GET", "/v1/disk/resources"):
            if let d = files[path] {
                return reply(200, ["name": (path as NSString).lastPathComponent, "size": d.count,
                                   "modified": "2026-11-16T10:20:00+00:00", "type": "file"], url)
            }
            guard dirs.contains(path) else { return reply(404, ["error": "DiskNotFoundError"], url) }
            let all = files.keys.filter { ($0 as NSString).deletingLastPathComponent == path }.sorted()
            let offset = Int(q("offset") ?? "0") ?? 0, limit = Int(q("limit") ?? "20") ?? 20
            let page = all.dropFirst(offset).prefix(limit).map { ["name": ($0 as NSString).lastPathComponent,
                                                                   "size": files[$0]!.count, "type": "file"] as [String: Any] }
            return reply(200, ["_embedded": ["items": page, "total": all.count]], url)
        default:
            return reply(405, nil, url)
        }
    }
}

@Suite("Облако: Яндекс.Диск (31.1)")
struct CloudYandexTests {
    static let config = YandexConfig(clientID: "test-client",
                                     authorizeURL: URL(string: "https://oauth.test/authorize")!,
                                     tokenURL: URL(string: "https://oauth.test/token")!,
                                     apiURL: URL(string: "https://disk.test/v1/disk")!)

    /// Окно входа «нажали Разрешить»: Яндекс запомнил отпечаток и вернул код на адрес приложения.
    static func connect(_ disk: FakeYandexDisk, _ tokens: InMemoryCloudTokenStore) async throws -> YandexDisk {
        let ya = YandexDisk(config: config, transport: disk)
        let req = try ya.signIn()
        let items = URLComponents(url: req.url, resolvingAgainstBaseURL: false)!.queryItems!
        func q(_ n: String) -> String? { items.first { $0.name == n }?.value }
        #expect(q("redirect_uri") == "lightplan-oauth://yandex")
        #expect(q("code_challenge_method") == "S256")
        #expect(q("response_type") == "code")
        #expect(req.callbackScheme == "lightplan-oauth")
        disk.give(code: "c1", challenge: q("code_challenge")!)
        let back = URL(string: "lightplan-oauth://yandex?code=c1&state=\(q("state")!)")!
        tokens.save(try await ya.finishSignIn(back, request: req))
        return ya
    }

    static func images(_ files: [String: Data]) -> RefImageStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-\(UUID().uuidString)")
        let s = RefImageStore(directory: dir)
        for (n, d) in files { s.save(d, as: n) }
        return s
    }

    static func copy(_ title: String) throws -> Data {
        var snap = Snapshot()
        snap.extra["probe"] = .string(title)
        return try JSONEncoder().encode(BackupFile(snapshot: snap))
    }

    @Test("Круг: подключить → выгрузить → забрать на «другой телефон» → отключить")
    func roundTrip() async throws {
        let disk = FakeYandexDisk()
        let tokens = InMemoryCloudTokenStore()
        let ya = try await Self.connect(disk, tokens)
        let backup = CloudBackup(provider: ya, tokens: tokens)

        let acc = try await backup.account()
        #expect(acc.label == "Алексей")

        let pics = Self.images(["a.jpg": Data(repeating: 1, count: 1200), "b.png": Data(repeating: 2, count: 800)])
        let first = try await backup.push(copy: try Self.copy("one"), images: pics)
        #expect(first == .init(images: 2, alreadyThere: 0))
        #expect(disk.file("app:/light-plan-iphone.json") != nil)
        #expect(disk.file("app:/iphone-images/a.jpg")?.count == 1200)

        // Второй раз уезжает только новое.
        pics.save(Data(repeating: 3, count: 50), as: "c.jpg")
        let second = try await backup.push(copy: try Self.copy("two"), images: pics)
        #expect(second == .init(images: 1, alreadyThere: 2))

        // Обратно — в пустой телефон.
        let other = Self.images([:])
        let item = try await backup.remoteCopy()
        #expect(item?.name == "light-plan-iphone.json")
        let raw = try await backup.pullCopy()
        let snap = try ImportedFile.decode(raw)
        #expect(snap.extra["probe"] == .string("two"))
        #expect(try await backup.pullImages(into: other) == 3)
        #expect(other.read("a.jpg") == pics.read("a.jpg"))
        #expect(try await backup.pullImages(into: other) == 0, "уже лежащие не качаются второй раз")

        // Отключить — забыть ключ; Диск дальше недоступен без входа.
        tokens.clear()
        await #expect(throws: CloudFailure.revoked) { try await backup.remoteCopy() }
        #expect(disk.file("app:/light-plan-iphone.json") != nil, "копия на Диске остаётся")
    }

    @Test("Своя аватарка едет рядом с копией и возвращается (31.13, «Да, класть»)")
    func avatarRidesWithTheCopy() async throws {
        let disk = FakeYandexDisk()
        let tokens = InMemoryCloudTokenStore()
        let backup = CloudBackup(provider: try await Self.connect(disk, tokens), tokens: tokens)
        _ = try await backup.push(copy: try Self.copy("one"), images: nil)
        #expect(disk.file("app:/iphone-avatar.jpg") == nil, "нет фото — файла нет")
        #expect(try await backup.pullAvatar() == nil)
        let face = Data(repeating: 7, count: 900)
        _ = try await backup.push(copy: try Self.copy("two"), images: nil, avatar: face)
        #expect(disk.file("app:/iphone-avatar.jpg") == face)
        #expect(try await backup.pullAvatar() == face)
    }

    @Test("Ключ отозван в Яндекс ID: одно обновление, потом «подключите заново», ключ забыт")
    func revokedToken() async throws {
        let disk = FakeYandexDisk()
        let tokens = InMemoryCloudTokenStore()
        let ya = try await Self.connect(disk, tokens)
        let backup = CloudBackup(provider: ya, tokens: tokens)
        disk.revokeAll()
        await #expect(throws: CloudFailure.revoked) { try await backup.push(copy: try Self.copy("x"), images: nil) }
        #expect(tokens.load() == nil)
        #expect(disk.log.contains("POST /token"), "сначала пробуем обновить ключ")
    }

    @Test("Доступ протух, а обновление живо — молча обновляем и продолжаем")
    func expiredAccessRefreshes() async throws {
        let disk = FakeYandexDisk()
        let tokens = InMemoryCloudTokenStore()
        let ya = try await Self.connect(disk, tokens)
        let old = tokens.load()!
        disk.validTokens.remove(old.access)
        let backup = CloudBackup(provider: ya, tokens: tokens)
        _ = try await backup.push(copy: try Self.copy("x"), images: nil)
        #expect(tokens.load()?.access != old.access)
        #expect(disk.file("app:/light-plan-iphone.json") != nil)
    }

    @Test("Нет сети, нет места, нет копии, чужой файл — свои причины")
    func honestFailures() async throws {
        let disk = FakeYandexDisk()
        let tokens = InMemoryCloudTokenStore()
        let ya = try await Self.connect(disk, tokens)
        let backup = CloudBackup(provider: ya, tokens: tokens)

        await #expect(throws: CloudFailure.noCopy) { try await backup.pullCopy() }
        #expect(try await backup.remoteCopy() == nil)

        disk.freeBytes = 100
        await #expect(throws: CloudFailure.noSpace) {
            try await backup.push(copy: try Self.copy("x"), images: Self.images(["a.jpg": Data(count: 5000)]))
        }
        // Место неизвестно (нет права «информация о Диске») — узнаём от самой загрузки.
        disk.infoAllowed = false
        await #expect(throws: CloudFailure.noSpace) {
            try await backup.push(copy: try Self.copy("x"), images: Self.images(["a.jpg": Data(count: 5000)]))
        }
        #expect(try await backup.account() == CloudAccount())

        disk.freeBytes = 10_000_000
        disk.files["app:/light-plan-iphone.json"] = Data("{\"hello\":1}".utf8)
        await #expect(throws: CloudFailure.badCopy) { try await backup.pullCopy() }

        disk.offline = true
        await #expect(throws: CloudFailure.offline) { try await backup.remoteCopy() }
        #expect(tokens.load() != nil, "без сети ключ не забывается")
    }

    @Test("Окно входа: отказ, чужой state, нет кода")
    func signInAnswers() async throws {
        let disk = FakeYandexDisk()
        let ya = YandexDisk(config: Self.config, transport: disk)
        let req = try ya.signIn()
        await #expect(throws: CloudFailure.cancelled) {
            try await ya.finishSignIn(URL(string: "lightplan-oauth://yandex?error=access_denied&state=\(req.state)")!, request: req)
        }
        await #expect(throws: CloudFailure.self) {
            try await ya.finishSignIn(URL(string: "lightplan-oauth://yandex?code=zzz&state=other")!, request: req)
        }
        // Код с чужим отпечатком (верификатор не наш) Яндекс не обменяет.
        disk.give(code: "c9", challenge: PKCE.challenge("not-ours"))
        await #expect(throws: CloudFailure.self) {
            try await ya.finishSignIn(URL(string: "lightplan-oauth://yandex?code=c9&state=\(req.state)")!, request: req)
        }
    }

    @Test("PKCE: отпечаток = SHA-256 в base64url без «=» (число сверено с Python hashlib)")
    func pkceVector() {
        #expect(PKCE.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWNFXmXk") == "4IE7_rY7t8WQCj4aKTq8X6BrXmPToqQUf8ClTYerDbk")
        let v = PKCE.verifier()
        #expect((43...128).contains(v.count))
        #expect(v.allSatisfy { $0.isLetter || $0.isNumber || "-_".contains($0) })
    }

    @Test("ClientID — только из файла сборки; нет файла — Яндекс не настроен")
    func configFromBundle() {
        #expect(YandexConfig.load(bundle: Bundle(for: FakeYandexDisk.self)) == nil)
    }
}
