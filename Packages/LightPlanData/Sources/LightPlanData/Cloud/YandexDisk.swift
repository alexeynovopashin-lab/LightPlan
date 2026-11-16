import Foundation

/// Регистрация приложения в Яндекс ID — та же, что у веба (`CLOUD_IDS.yandex`, `beta/index.html`): одна папка
/// приложения на Диске на веб и натив. ClientID в публичный репозиторий натива не кладём (он и не секрет — лежит
/// в открытом вебе, — но настройки сборки живут вне git, как ключи погоды и Pinterest): фаза сборки
/// `Tools/yandex_key.sh` кладёт `yandex_disk.plist` рядом с приложением из `~/.config/lightplan/yandex_client_id`.
/// Нет файла — нет ClientID — Яндекс в настройках честно «не настроен в этой сборке».
public struct YandexConfig: Sendable, Equatable {
    /// Адрес возврата из окна входа. Его нужно один раз добавить в регистрацию (Платформы → Веб-сервисы →
    /// Redirect URI, ниже адреса веба): иначе Яндекс молча вернёт на первый адрес списка — сайт веба.
    /// Зависит не от bundle id, поэтому одна регистрация служит и «Light Plan», и копиям «LP …».
    public static let redirect = "lightplan-oauth://yandex"
    public static let callbackScheme = "lightplan-oauth"

    public var clientID: String
    public var authorizeURL: URL
    public var tokenURL: URL
    public var apiURL: URL

    public init(clientID: String,
                authorizeURL: URL = URL(string: "https://oauth.yandex.ru/authorize")!,
                tokenURL: URL = URL(string: "https://oauth.yandex.ru/token")!,
                apiURL: URL = URL(string: "https://cloud-api.yandex.net/v1/disk")!) {
        self.clientID = clientID; self.authorizeURL = authorizeURL; self.tokenURL = tokenURL; self.apiURL = apiURL
    }

    public static func load(bundle: Bundle = .main) -> YandexConfig? {
        guard let file = bundle.url(forResource: "yandex_disk", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: file) as? [String: Any] else { return nil }
        let id = (dict["LPYandexClientID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return id.isEmpty ? nil : YandexConfig(clientID: id)
    }
}

/// Яндекс.Диск через REST API, права — только папка приложения (`cloud_api:disk.app_folder`): остальной Диск
/// приложению не виден. Вход — код подтверждения с PKCE, без секрета; ключ живёт около года и обновляется
/// `refresh_token`. Заголовок у Яндекса свой: `OAuth <ключ>`, а не `Bearer` (веб, `CLOUD_YANDEX.head`).
public struct YandexDisk: CloudProvider {
    public let kind = CloudKind.yandex
    let config: YandexConfig
    let transport: any CloudTransport
    let now: @Sendable () -> Date

    public init(config: YandexConfig, transport: any CloudTransport = URLSessionCloudTransport(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config; self.transport = transport; self.now = now
    }

    // MARK: Вход

    public func signIn() throws -> CloudSignInRequest {
        let verifier = PKCE.verifier()
        let state = UUID().uuidString
        var c = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: YandexConfig.redirect),
            .init(name: "code_challenge", value: PKCE.challenge(verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            // Окно согласия каждый раз: видно, какой аккаунт подключается, и можно сменить (веб — так же).
            .init(name: "force_confirm", value: "yes"),
        ]
        return CloudSignInRequest(url: c.url!, callbackScheme: YandexConfig.callbackScheme, verifier: verifier, state: state)
    }

    public func finishSignIn(_ callback: URL, request: CloudSignInRequest) async throws -> CloudToken {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ n: String) -> String? { items.first { $0.name == n }?.value }
        if let err = q("error") {
            // `access_denied` — человек нажал «Отмена» на странице Яндекса.
            if err == "access_denied" { throw CloudFailure.cancelled }
            throw CloudFailure.server(code: 400, message: q("error_description") ?? err)
        }
        guard q("state") == request.state, let code = q("code"), !code.isEmpty else {
            throw CloudFailure.server(code: 400, message: "no code")
        }
        return try await tokenRequest([
            "grant_type": "authorization_code", "code": code,
            "client_id": config.clientID, "code_verifier": request.verifier,
        ], keepRefresh: nil)
    }

    public func refresh(_ token: CloudToken) async throws -> CloudToken {
        guard let r = token.refresh else { throw CloudFailure.revoked }
        do {
            return try await tokenRequest(["grant_type": "refresh_token", "refresh_token": r, "client_id": config.clientID],
                                          keepRefresh: r)
        } catch CloudFailure.server(let code, _) where (400..<500).contains(code) {
            // `invalid_grant`: доступ отозван в Яндекс ID или ключ обновления истёк.
            throw CloudFailure.revoked
        }
    }

    private struct TokenReply: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double?
    }
    private struct ErrorReply: Decodable {
        let error: String?
        let error_description: String?
        let message: String?
        let description: String?
    }

    private func tokenRequest(_ form: [String: String], keepRefresh: String?) async throws -> CloudToken {
        var req = URLRequest(url: config.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formBody(form)
        let (data, resp) = try await transport.send(req)
        guard resp.statusCode == 200, let t = try? JSONDecoder().decode(TokenReply.self, from: data) else {
            throw CloudFailure.server(code: resp.statusCode == 200 ? 0 : resp.statusCode, message: Self.message(data))
        }
        return CloudToken(kind: .yandex, access: t.access_token, refresh: t.refresh_token ?? keepRefresh,
                          expires: t.expires_in.map { now().addingTimeInterval($0) })
    }

    static func formBody(_ form: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }

    /// Яндекс объясняет причину сам — берём её, а не общую фразу (веб, `CLOUD_YANDEX.upload`).
    static func message(_ data: Data) -> String? {
        guard let e = try? JSONDecoder().decode(ErrorReply.self, from: data) else { return nil }
        return e.error_description ?? e.description ?? e.message ?? e.error
    }

    // MARK: Диск

    /// `app:/` — корень папки приложения («Приложения/<имя приложения>» на Диске человека).
    static func diskPath(_ rel: String) -> String { "app:/" + rel }

    private func api(_ path: String, query: [String: String] = [:], method: String = "GET", token: CloudToken) -> URLRequest {
        var c = URLComponents(url: config.apiURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.setValue("OAuth " + token.access, forHTTPHeaderField: "Authorization")
        return req
    }

    /// Ответ Диска в причину: 401 — ключ отозван, 507 — нет места (`InsufficientStorageError`), прочее — код и слово Яндекса.
    static func check(_ data: Data, _ resp: HTTPURLResponse, allow: Set<Int> = []) throws {
        let code = resp.statusCode
        if (200..<300).contains(code) || allow.contains(code) { return }
        switch code {
        case 401: throw CloudFailure.revoked
        case 507: throw CloudFailure.noSpace
        default: throw CloudFailure.server(code: code, message: message(data))
        }
    }

    public func account(_ token: CloudToken) async throws -> CloudAccount {
        let (data, resp) = try await transport.send(api("", query: ["fields": "total_space,used_space,user"], token: token))
        // 403 — у регистрации нет права «информация о Диске»: подключение есть, имени нет.
        if resp.statusCode == 403 { return CloudAccount() }
        try Self.check(data, resp)
        struct Disk: Decodable {
            struct User: Decodable { let login: String?; let display_name: String? }
            let total_space: Int64?; let used_space: Int64?; let user: User?
        }
        let d = try? JSONDecoder().decode(Disk.self, from: data)
        let free = d.flatMap { d in d.total_space.flatMap { t in d.used_space.map { t - $0 } } }
        return CloudAccount(login: d?.user?.login, name: d?.user?.display_name, freeBytes: free)
    }

    public func ensureFolder(_ path: String, token: CloudToken) async throws {
        let (data, resp) = try await transport.send(api("resources", query: ["path": Self.diskPath(path)], method: "PUT", token: token))
        // 409 — папка уже есть.
        try Self.check(data, resp, allow: [409])
    }

    public func upload(_ body: Data, to path: String, token: CloudToken) async throws {
        let (data, resp) = try await transport.send(api("resources/upload",
                                                        query: ["path": Self.diskPath(path), "overwrite": "true"], token: token))
        try Self.check(data, resp)
        struct Link: Decodable { let href: String? }
        guard let href = (try? JSONDecoder().decode(Link.self, from: data))?.href, let url = URL(string: href) else {
            throw CloudFailure.server(code: resp.statusCode, message: Self.message(data))
        }
        var put = URLRequest(url: url)
        put.httpMethod = "PUT"
        put.httpBody = body
        let (d2, r2) = try await transport.send(put)
        // Адрес загрузки ключа не просит; его 401 был бы не про наш ключ — общий код.
        if r2.statusCode == 507 || r2.statusCode == 413 { throw CloudFailure.noSpace }
        guard (200..<300).contains(r2.statusCode) else { throw CloudFailure.server(code: r2.statusCode, message: Self.message(d2)) }
    }

    public func download(_ path: String, token: CloudToken) async throws -> Data? {
        let (data, resp) = try await transport.send(api("resources/download", query: ["path": Self.diskPath(path)], token: token))
        if resp.statusCode == 404 { return nil }
        try Self.check(data, resp)
        struct Link: Decodable { let href: String? }
        guard let href = (try? JSONDecoder().decode(Link.self, from: data))?.href, let url = URL(string: href) else {
            throw CloudFailure.server(code: resp.statusCode, message: Self.message(data))
        }
        let (body, r2) = try await transport.send(URLRequest(url: url))
        if r2.statusCode == 404 { return nil }
        guard (200..<300).contains(r2.statusCode) else { throw CloudFailure.server(code: r2.statusCode, message: nil) }
        return body
    }

    private struct Resource: Decodable {
        let name: String?
        let size: Int64?
        let modified: String?
        let type: String?
        struct Embedded: Decodable { let items: [Resource]?; let total: Int? }
        let _embedded: Embedded?
    }

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    public func item(_ path: String, token: CloudToken) async throws -> CloudItem? {
        let (data, resp) = try await transport.send(api("resources", query: ["path": Self.diskPath(path),
                                                                             "fields": "name,size,modified,type"], token: token))
        if resp.statusCode == 404 { return nil }
        try Self.check(data, resp)
        guard let r = try? JSONDecoder().decode(Resource.self, from: data), let name = r.name else { return nil }
        return CloudItem(name: name, size: r.size ?? 0, modified: Self.date(r.modified))
    }

    /// Перечень папки страницами по 200; папки нет — пусто (веб `list`: «соседей пока нет — не беда»).
    public func list(_ folder: String, token: CloudToken) async throws -> [CloudItem] {
        var out: [CloudItem] = []
        var offset = 0
        let page = 200
        while true {
            let (data, resp) = try await transport.send(api("resources", query: [
                "path": Self.diskPath(folder), "limit": String(page), "offset": String(offset),
                "fields": "_embedded.items.name,_embedded.items.size,_embedded.items.modified,_embedded.items.type,_embedded.total",
            ], token: token))
            if resp.statusCode == 404 { return out }
            try Self.check(data, resp)
            let items = (try? JSONDecoder().decode(Resource.self, from: data))?._embedded?.items ?? []
            out += items.compactMap { r in
                guard let n = r.name, r.type != "dir" else { return nil }
                return CloudItem(name: n, size: r.size ?? 0, modified: Self.date(r.modified))
            }
            if items.count < page { return out }
            offset += page
        }
    }
}
