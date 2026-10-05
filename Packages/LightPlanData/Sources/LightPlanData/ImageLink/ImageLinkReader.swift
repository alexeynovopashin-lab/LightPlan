import Foundation

/// Почему картинка по прямой ссылке не легла в мудборд (итерация 28н.1): по этому выбирается честная надпись.
public enum ImageLinkFailure: Error, Equatable, Sendable {
    /// У телефона нет сети: пробовать другой путь незачем.
    case offline
    /// Хост (или наш сервер) не ответил вовремя, сбросил соединение, не нашёлся: другой путь может сработать.
    case unreachable
    /// Хост ответил «нет такого» (404, 410, закрыто 403/401).
    case notFound
    /// Пришло не то, что обещано: страница, SVG, GIF, мусор под заголовком картинки.
    case notImage
    /// Больше предела (напрямую 15 МБ; через наш сервер 2,5 МБ — потолок ответа платформы).
    case tooLarge
    /// Адрес не годится (не https после правки, наш сервер отказал адресу).
    case badLink
    /// Слишком часто (429 у нашего сервера).
    case busy
    /// Напрямую не открылось, а наш сервер человек выключил («Только напрямую», 28л.6).
    case serverOff
}

/// Какая это картинка по первым байтам: только JPEG, PNG, WebP и HEIC (как у функции, `picfetch.js`). Заголовку ответа не верим.
public enum ImagePicture {
    public static let directMaxBytes = 15 * 1024 * 1024

    /// MIME-тип по байтам или `nil`, если это не одна из четырёх.
    public static func mime(of d: Data) -> String? {
        let b = [UInt8](d.prefix(12))
        guard b.count >= 12 else { return nil }
        if b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "image/jpeg" }
        if Array(b[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] { return "image/png" }
        if Array(b[0..<4]) == Array("RIFF".utf8), Array(b[8..<12]) == Array("WEBP".utf8) { return "image/webp" }
        if Array(b[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            if ["heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1"].contains(brand) { return "image/heic" }
        }
        return nil
    }
}

/// Прямой путь: телефон сам идёт на адрес картинки.
public protocol ImageDirectFetching: Sendable {
    /// Байты картинки или `ImageLinkFailure`.
    func fetch(_ url: URL) async throws -> Data
}

/// Путь через наш сервер (`lightplanogreader`, режим `?pic=`).
public protocol ImageServerFetching: Sendable {
    func picture(at address: String) async throws -> Data
}

/// Читалка прямых ссылок для приложения; тесты подставляют сценарий.
public protocol ImageLinkReading: Sendable {
    /// `viaServer == false` — только напрямую (тихая проверка адреса без расширения: чужие страницы нашему серверу не носим).
    func picture(at link: String, viaServer: Bool) async throws -> Data
}

/// Маршрут: «Авто» — напрямую, а если не открылось, то через наш сервер (и наоборот, если зарубежное уже известно как недоступное);
/// «Только напрямую» (28л.6) — наш сервер не трогаем, при отказе честная причина. Дальше по маршруту идут только при `unreachable`:
/// «нет такой», «не картинка», «слишком большая», «нет сети» второй путь не изменит.
public struct ImageLinkReader: ImageLinkReading {
    let direct: any ImageDirectFetching
    let server: (any ImageServerFetching)?
    let policy: @Sendable () async -> NetworkPolicy

    public init(direct: any ImageDirectFetching, server: (any ImageServerFetching)?, policy: @escaping @Sendable () async -> NetworkPolicy) {
        self.direct = direct; self.server = server; self.policy = policy
    }

    private enum Route { case direct, server }

    public func picture(at link: String, viaServer: Bool) async throws -> Data {
        guard let secure = PinterestLinkSecure.url(link), let url = URL(string: secure) else { throw ImageLinkFailure.badLink }
        let p = await policy()
        let serverUsable = viaServer && server != nil && p.mode != .directOnly
        let routes: [Route] = serverUsable && p.foreign == .unreachable ? [.server, .direct] : serverUsable ? [.direct, .server] : [.direct]
        var last = ImageLinkFailure.unreachable
        for route in routes {
            do {
                switch route {
                case .direct: return try await direct.fetch(url)
                case .server: return try await server!.picture(at: secure)
                }
            } catch let f as ImageLinkFailure {
                guard f == .unreachable else { throw f }
                last = f
            }
        }
        if viaServer && p.mode == .directOnly { throw ImageLinkFailure.serverOff }
        throw last
    }
}

/// `https`-адрес из того, что вставил человек (как `PinterestLink.secure`, но Data не знает Domain-правил ссылок).
enum PinterestLinkSecure {
    static func url(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return nil }
        if s.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) == nil { s = "https://" + s }
        if s.lowercased().hasPrefix("http://") { s = "https://" + s.dropFirst(7) }
        guard let u = URL(string: s), u.scheme?.lowercased() == "https", let h = u.host, h.contains(".") else { return nil }
        return s
    }
}

// MARK: - прямой путь

/// Скачивает картинку с адреса: смотрит на заголовок раньше тела (страницу или огромный файл не качаем), держит потолок
/// по ходу чтения (Content-Length может не быть или врать), проверяет тип по байтам.
public struct DirectImageFetcher: ImageDirectFetching {
    let timeout: TimeInterval
    let maxBytes: Int
    let protocolClasses: [AnyClass]?

    public init(timeout: TimeInterval = 8, maxBytes: Int = ImagePicture.directMaxBytes, protocolClasses: [AnyClass]? = nil) {
        self.timeout = timeout; self.maxBytes = maxBytes; self.protocolClasses = protocolClasses
    }

    public func fetch(_ url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw ImageLinkFailure.badLink }
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = max(timeout * 3, 30)
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let protocolClasses { c.protocolClasses = protocolClasses }
        let download = PictureDownload(maxBytes: maxBytes)
        let session = URLSession(configuration: c, delegate: download, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("image/jpeg,image/png,image/webp,image/heic,image/*;q=0.5", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: req)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                download.start(cont)
                task.resume()
            }
        } onCancel: { task.cancel() }
    }
}

final class PictureDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private var buffer = Data()
    private var verdict: ImageLinkFailure?
    private var cont: CheckedContinuation<Data, Error>?

    init(maxBytes: Int) { self.maxBytes = maxBytes }

    func start(_ c: CheckedContinuation<Data, Error>) { lock.lock(); cont = c; lock.unlock() }

    private func decide(_ f: ImageLinkFailure) { lock.lock(); if verdict == nil { verdict = f }; lock.unlock() }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Переход только на https: ответ-переход без тела не картинка.
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { decide(.unreachable); completionHandler(.cancel); return }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        switch http.statusCode {
        case 200..<300:
            if !type.hasPrefix("image/") || type.hasPrefix("image/svg") { decide(.notImage); completionHandler(.cancel); return }
            if http.expectedContentLength > Int64(maxBytes) { decide(.tooLarge); completionHandler(.cancel); return }
            completionHandler(.allow)
        case 401, 403, 404, 410: decide(.notFound); completionHandler(.cancel)
        case 429: decide(.busy); completionHandler(.cancel)
        default: decide(.unreachable); completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffer.append(data)
        let over = buffer.count > maxBytes
        if over, verdict == nil { verdict = .tooLarge }
        lock.unlock()
        if over { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let c = cont; cont = nil
        let v = verdict
        let body = buffer
        lock.unlock()
        guard let c else { return }
        if let v { c.resume(throwing: v); return }
        if let e = error as? URLError {
            switch e.code {
            case .cancelled: c.resume(throwing: CancellationError())
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: c.resume(throwing: ImageLinkFailure.offline)
            default: c.resume(throwing: ImageLinkFailure.unreachable)
            }
            return
        }
        if error != nil { c.resume(throwing: ImageLinkFailure.unreachable); return }
        guard ImagePicture.mime(of: body) != nil else { c.resume(throwing: ImageLinkFailure.notImage); return }
        c.resume(returning: body)
    }
}

// MARK: - путь через наш сервер

extension PinterestClient: ImageServerFetching {
    /// `?pic=<адрес>`: функция сама проверяет адрес, переходы, размер (≤ 2,5 МБ) и тип; клиент ещё раз сверяет байты.
    public func picture(at address: String) async throws -> Data {
        guard let req = Self.request(base: config.url, mode: "pic", value: address, key: config.key, timeout: timeouts.image) else {
            throw ImageLinkFailure.badLink
        }
        let data: Data, http: HTTPURLResponse
        do { (data, http) = try await transport(req) } catch {
            if error is CancellationError { throw error }
            if let e = error as? URLError {
                switch e.code {
                case .cancelled: throw CancellationError()
                case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .networkConnectionLost: throw ImageLinkFailure.offline
                default: throw ImageLinkFailure.unreachable
                }
            }
            throw ImageLinkFailure.unreachable
        }
        guard (200..<300).contains(http.statusCode) else { throw Self.pictureFailure(status: http.statusCode, body: data) }
        guard ImagePicture.mime(of: data) != nil else { throw ImageLinkFailure.notImage }
        return data
    }

    static func pictureFailure(status: Int, body: Data) -> ImageLinkFailure {
        let reason = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["reason"] as? String ?? ""
        switch status {
        // 400 «bad request» — функция в облаке ещё без режима `?pic=` (выкладка позже приложения): это не вина адреса.
        case 400: return reason == "host not allowed" || reason == "bad url" ? .badLink : .unreachable
        case 404: return reason == "not an image" ? .notImage : .notFound
        case 413: return .tooLarge
        case 429: return .busy
        default: return .unreachable   // 403 (ключ не принят), 5xx: картинка с нашего сервера не пришла
        }
    }
}
