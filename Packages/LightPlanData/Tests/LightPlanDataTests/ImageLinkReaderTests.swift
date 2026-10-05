import Testing
import Foundation
@testable import LightPlanData

private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + [UInt8](repeating: 1, count: 40))
private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 2, count: 40))
private let webp = Data("RIFF".utf8) + Data(count: 4) + Data("WEBP".utf8) + Data(count: 30)
private let heic = Data(count: 4) + Data("ftypheic".utf8) + Data(count: 30)
private let gif = Data("GIF89a".utf8) + Data(count: 40)
private let html = Data(("<html><script>x()</script></html>" + String(repeating: " ", count: 40)).utf8)

// MARK: - распознавание по байтам

struct ImagePictureTests {
    @Test func fourFormatsAndNothingElse() {
        #expect(ImagePicture.mime(of: jpeg) == "image/jpeg")
        #expect(ImagePicture.mime(of: png) == "image/png")
        #expect(ImagePicture.mime(of: webp) == "image/webp")
        #expect(ImagePicture.mime(of: heic) == "image/heic")
        #expect(ImagePicture.mime(of: gif) == nil)
        #expect(ImagePicture.mime(of: html) == nil)
        #expect(ImagePicture.mime(of: Data()) == nil)
        #expect(ImagePicture.mime(of: Data([0xFF, 0xD8])) == nil)
    }
}

// MARK: - прямой путь (URLProtocol вместо сети)

private final class Stub: URLProtocol, @unchecked Sendable {
    struct Scenario {
        var status = 200
        var headers: [String: String] = ["Content-Type": "image/jpeg"]
        var chunks: [Data] = [jpeg]
        var error: URLError?
        var hang = false
        /// Куски приходят по одному с паузой в фоне: видно, оборвала ли загрузку читалка.
        var paced = false
    }
    nonisolated(unsafe) static var scenario = Scenario()
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var delivered = 0
    private let flag = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let s = Self.scenario
        if s.hang { return }
        if let e = s.error { client?.urlProtocol(self, didFailWithError: e); return }
        let r = HTTPURLResponse(url: request.url!, statusCode: s.status, httpVersion: "HTTP/1.1", headerFields: s.headers)!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        if s.paced {
            Self.delivered = 0
            DispatchQueue.global().async { [self] in
                for c in s.chunks {
                    flag.lock(); let done = stopped; flag.unlock()
                    if done { return }
                    client?.urlProtocol(self, didLoad: c); Self.delivered += 1
                    Thread.sleep(forTimeInterval: 0.01)
                }
                client?.urlProtocolDidFinishLoading(self)
            }
            return
        }
        for c in s.chunks { client?.urlProtocol(self, didLoad: c) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { flag.lock(); stopped = true; flag.unlock() }
}

@Suite(.serialized) struct DirectImageFetcherTests {
    private let url = URL(string: "https://example.test/p/photo.jpg")!
    private func fetcher(max: Int = 1_000, timeout: TimeInterval = 5) -> DirectImageFetcher {
        DirectImageFetcher(timeout: timeout, maxBytes: max, protocolClasses: [Stub.self])
    }
    private func run(_ s: Stub.Scenario, max: Int = 1_000) async throws -> Data {
        Stub.scenario = s
        return try await fetcher(max: max).fetch(url)
    }
    private func fails(_ s: Stub.Scenario, with f: ImageLinkFailure, max: Int = 1_000) async {
        await #expect(throws: f) { try await run(s, max: max) }
    }

    @Test func goodPicturesComeBackAsTheyAre() async throws {
        for body in [jpeg, png, webp, heic] {
            #expect(try await run(.init(chunks: [body])) == body)
        }
    }

    @Test func pictureInPiecesIsAssembled() async throws {
        let parts = [jpeg.prefix(10), jpeg.dropFirst(10).prefix(20), jpeg.dropFirst(30)].map { Data($0) }
        #expect(try await run(.init(chunks: parts)) == jpeg)
    }

    @Test func wrongTypeIsNotAnImage() async {
        await fails(.init(headers: ["Content-Type": "text/html"], chunks: [html]), with: .notImage)
        await fails(.init(headers: ["Content-Type": "image/svg+xml"], chunks: [Data("<svg onload=x()/>".utf8) + Data(count: 40)]), with: .notImage)
        await fails(.init(headers: ["Content-Type": "application/octet-stream"], chunks: [jpeg]), with: .notImage)
        await fails(.init(headers: ["Content-Type": "image/jpeg"], chunks: [html]), with: .notImage)   // заголовок врёт
        await fails(.init(headers: ["Content-Type": "image/gif"], chunks: [gif]), with: .notImage)     // не из четырёх
    }

    @Test func tooLargeByHeaderAndByStream() async {
        // по заголовку: тело не читаем
        await fails(.init(headers: ["Content-Type": "image/jpeg", "Content-Length": "5000"], chunks: [jpeg]), with: .tooLarge, max: 1_000)
        // без Content-Length: режем по ходу чтения
        await fails(.init(chunks: [jpeg, Data(count: 600), Data(count: 600)]), with: .tooLarge, max: 1_000)
        // заголовок врёт малым числом
        await fails(.init(headers: ["Content-Type": "image/jpeg", "Content-Length": "10"], chunks: [jpeg, Data(count: 600), Data(count: 600)]), with: .tooLarge, max: 1_000)
    }

    @Test func overTheLimitTheDownloadIsCutNotFinished() async throws {
        await fails(.init(chunks: [jpeg] + Array(repeating: Data(count: 600), count: 60), paced: true), with: .tooLarge, max: 1_000)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(Stub.delivered <= 6, "доставлено кусков: \(Stub.delivered) из 61")   // порог 1000 байт — второй-третий кусок; с запасом на гонку
    }

    @Test func atTheLimitIsFine() async throws {
        let body = jpeg + Data(count: 100 - jpeg.count)
        #expect(try await run(.init(chunks: [body]), max: 100).count == 100)
    }

    @Test func statusesBecomeHonestReasons() async {
        for code in [404, 410, 403, 401] { await fails(.init(status: code, chunks: []), with: .notFound) }
        await fails(.init(status: 429, chunks: []), with: .busy)
        for code in [500, 502, 503] { await fails(.init(status: code, chunks: []), with: .unreachable) }
    }

    @Test func networkFailures() async {
        await fails(.init(error: URLError(.notConnectedToInternet)), with: .offline)
        await fails(.init(error: URLError(.timedOut)), with: .unreachable)
        await fails(.init(error: URLError(.networkConnectionLost)), with: .unreachable)
        await fails(.init(error: URLError(.cannotFindHost)), with: .unreachable)
        await fails(.init(error: URLError(.secureConnectionFailed)), with: .unreachable)
    }

    @Test func silenceEndsInUnreachableNotInHanging() async {
        Stub.scenario = .init(hang: true)
        let start = Date()
        await #expect(throws: ImageLinkFailure.unreachable) { try await fetcher(timeout: 0.4).fetch(url) }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func httpAddressIsNeverRequested() async {
        Stub.requests = 0
        await #expect(throws: ImageLinkFailure.badLink) { try await fetcher().fetch(URL(string: "http://example.test/a.jpg")!) }
        #expect(Stub.requests == 0)
    }
}

// MARK: - маршрут «напрямую / через сервер»

private final class Fake: ImageDirectFetching, ImageServerFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private let result: Result<Data, ImageLinkFailure>
    private let tag: String
    private let log: Log
    init(_ tag: String, _ result: Result<Data, ImageLinkFailure>, log: Log) { self.tag = tag; self.result = result; self.log = log }
    func fetch(_ url: URL) async throws -> Data { log.add(tag); return try result.get() }
    func picture(at address: String) async throws -> Data { log.add(tag); return try result.get() }
}
private final class Log: @unchecked Sendable {
    private let lock = NSLock(); private var v: [String] = []
    func add(_ s: String) { lock.lock(); v.append(s); lock.unlock() }
    var calls: [String] { lock.lock(); defer { lock.unlock() }; return v }
}

struct ImageLinkReaderRoutingTests {
    private let link = "https://example.test/p/photo.jpg"

    private func reader(direct: Result<Data, ImageLinkFailure>, server: Result<Data, ImageLinkFailure>?, mode: NetworkMode = .auto,
                        foreign: ForeignReach = .unknown, log: Log) -> ImageLinkReader {
        ImageLinkReader(direct: Fake("direct", direct, log: log), server: server.map { Fake("server", $0, log: log) },
                        policy: { NetworkPolicy(mode: mode, foreign: foreign) })
    }

    @Test func autoGoesDirectFirstAndStopsOnSuccess() async throws {
        let log = Log()
        #expect(try await reader(direct: .success(jpeg), server: .success(png), log: log).picture(at: link, viaServer: true) == jpeg)
        #expect(log.calls == ["direct"])
    }

    @Test func autoFallsBackToServerWhenDirectDoesNotOpen() async throws {
        let log = Log()
        #expect(try await reader(direct: .failure(.unreachable), server: .success(png), log: log).picture(at: link, viaServer: true) == png)
        #expect(log.calls == ["direct", "server"])
    }

    @Test func knownUnreachableForeignGoesServerFirst() async throws {
        let log = Log()
        #expect(try await reader(direct: .success(jpeg), server: .success(png), foreign: .unreachable, log: log).picture(at: link, viaServer: true) == png)
        #expect(log.calls == ["server"])
        let log2 = Log()   // и сервер не ответил: пробуем напрямую
        #expect(try await reader(direct: .success(jpeg), server: .failure(.unreachable), foreign: .unreachable, log: log2).picture(at: link, viaServer: true) == jpeg)
        #expect(log2.calls == ["server", "direct"])
    }

    @Test func definiteAnswersDoNotTryTheOtherWay() async {
        for f in [ImageLinkFailure.notFound, .notImage, .tooLarge, .offline, .busy, .badLink] {
            let log = Log()
            await #expect(throws: f) { try await reader(direct: .failure(f), server: .success(png), log: log).picture(at: link, viaServer: true) }
            #expect(log.calls == ["direct"], "\(f)")
        }
    }

    @Test func directOnlyNeverTouchesOurServerAndSaysSo() async throws {
        let log = Log()
        #expect(try await reader(direct: .success(jpeg), server: .success(png), mode: .directOnly, foreign: .unreachable, log: log).picture(at: link, viaServer: true) == jpeg)
        #expect(log.calls == ["direct"])
        let log2 = Log()
        await #expect(throws: ImageLinkFailure.serverOff) {
            try await reader(direct: .failure(.unreachable), server: .success(png), mode: .directOnly, log: log2).picture(at: link, viaServer: true)
        }
        #expect(log2.calls == ["direct"])
        let log3 = Log()   // нет сети — это «нет связи», а не «сервер выключен»
        await #expect(throws: ImageLinkFailure.offline) {
            try await reader(direct: .failure(.offline), server: nil, mode: .directOnly, log: log3).picture(at: link, viaServer: true)
        }
    }

    @Test func quietProbeNeverGoesToOurServer() async {
        let log = Log()
        await #expect(throws: ImageLinkFailure.unreachable) {
            try await reader(direct: .failure(.unreachable), server: .success(png), log: log).picture(at: "https://example.test/blog/post", viaServer: false)
        }
        #expect(log.calls == ["direct"])
    }

    @Test func noServerKeyMeansDirectOnlyAndHonestFailure() async {
        let log = Log()
        await #expect(throws: ImageLinkFailure.unreachable) { try await reader(direct: .failure(.unreachable), server: nil, log: log).picture(at: link, viaServer: true) }
        #expect(log.calls == ["direct"])
    }

    @Test func linkIsMadeHttpsOrRefused() async throws {
        let log = Log()
        let r = reader(direct: .success(jpeg), server: nil, log: log)
        #expect(try await r.picture(at: "http://example.test/a.jpg", viaServer: true) == jpeg)
        #expect(try await r.picture(at: "example.test/a.jpg", viaServer: true) == jpeg)
        for bad in ["", "not a link", "abc", "ftp://example.test/a.jpg"] {
            await #expect(throws: ImageLinkFailure.badLink) { try await r.picture(at: bad, viaServer: true) }
        }
    }
}

// MARK: - путь через сервер: запрос и ответы

struct ServerPictureTests {
    private let base = URL(string: "https://example.test/fn")!
    final class Cap: @unchecked Sendable {
        private let l = NSLock(); private var r: URLRequest?
        func set(_ x: URLRequest) { l.lock(); r = x; l.unlock() }
        var request: URLRequest? { l.lock(); defer { l.unlock() }; return r }
    }
    private func client(status: Int = 200, body: Data = jpeg, error: URLError? = nil, cap: Cap? = nil) -> PinterestClient {
        PinterestClient(config: PinterestConfig(url: base, key: "K-TEST")) { req in
            cap?.set(req)
            if let error { throw error }
            return (body, HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func requestUsesPicModeAndKeyAndEncodesTheAddress() async throws {
        let cap = Cap()
        let out = try await client(cap: cap).picture(at: "https://img.example.test/a.jpg?w=1&h=2#x")
        #expect(out == jpeg)
        let r = try #require(cap.request)
        #expect(r.value(forHTTPHeaderField: "X-LP-Key") == "K-TEST")
        #expect(r.url?.absoluteString == "https://example.test/fn?pic=https%3A%2F%2Fimg.example.test%2Fa.jpg%3Fw%3D1%26h%3D2%23x")
    }

    @Test func answersBecomeReasons() async {
        func reason(_ status: Int, _ body: String = "") async -> ImageLinkFailure? {
            do { _ = try await client(status: status, body: Data(body.utf8)).picture(at: "https://a.test/p.jpg"); return nil } catch { return error as? ImageLinkFailure }
        }
        #expect(await reason(400, #"{"reason":"host not allowed"}"#) == .badLink)
        #expect(await reason(400, #"{"reason":"bad url"}"#) == .badLink)
        #expect(await reason(400, #"{"reason":"bad request"}"#) == .unreachable)   // старая функция без ?pic=
        #expect(await reason(404, #"{"reason":"not an image"}"#) == .notImage)
        #expect(await reason(404, #"{"reason":"not found"}"#) == .notFound)
        #expect(await reason(413, #"{"reason":"too large"}"#) == .tooLarge)
        #expect(await reason(429) == .busy)
        #expect(await reason(403) == .unreachable)
        #expect(await reason(502) == .unreachable)
    }

    @Test func goodStatusWithNonImageBodyIsRefused() async {
        await #expect(throws: ImageLinkFailure.notImage) { try await client(body: html).picture(at: "https://a.test/p.jpg") }
        await #expect(throws: ImageLinkFailure.notImage) { try await client(body: gif).picture(at: "https://a.test/p.jpg") }
    }

    @Test func networkFailures() async {
        await #expect(throws: ImageLinkFailure.offline) { try await client(error: URLError(.notConnectedToInternet)).picture(at: "https://a.test/p.jpg") }
        await #expect(throws: ImageLinkFailure.unreachable) { try await client(error: URLError(.timedOut)).picture(at: "https://a.test/p.jpg") }
    }
}
