import Testing
import Foundation
@testable import LightPlanData

/// Итерация 28м, шаг 3: клиент читалки Pinterest — запрос, ключ, коды ответа → честные причины.
struct PinterestReaderTests {

    private let base = URL(string: "https://example.test/fn")!

    private func client(status: Int = 200, body: String = "", headers: [String: String] = [:],
                        capture: Capture? = nil, error: URLError? = nil) -> PinterestClient {
        PinterestClient(config: PinterestConfig(url: base, key: "K-TEST")) { req in
            capture?.set(req)
            if let error { throw error }
            let r = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (Data(body.utf8), r)
        }
    }

    final class Capture: @unchecked Sendable {
        private let lock = NSLock(); private var r: URLRequest?
        func set(_ x: URLRequest) { lock.lock(); r = x; lock.unlock() }
        var request: URLRequest? { lock.lock(); defer { lock.unlock() }; return r }
    }

    // MARK: запрос

    @Test func requestCarriesKeyAndEncodesTheWholeValue() async throws {
        let cap = Capture()
        _ = try? await client(body: "{\"pins\":[]}", capture: cap).board(link: "https://pin.it/a?b=1&c=2#x")
        let r = try #require(cap.request)
        #expect(r.value(forHTTPHeaderField: "X-LP-Key") == "K-TEST")
        let q = try #require(r.url?.absoluteString)
        #expect(q == "https://example.test/fn?board=https%3A%2F%2Fpin.it%2Fa%3Fb%3D1%26c%3D2%23x")
        #expect(r.timeoutInterval == 15)
    }

    @Test func modesUseTheirParameters() async throws {
        let cap = Capture()
        _ = try? await client(body: "x", capture: cap).image(at: "https://i.pinimg.com/736x/a.jpg")
        #expect(cap.request?.url?.query?.hasPrefix("img=") == true)
        _ = try? await client(body: "x", capture: cap).preview(of: "https://www.pinterest.com/pin/1/")
        #expect(cap.request?.url?.query?.hasPrefix("url=") == true)
    }

    // MARK: ответ

    @Test func boardAnswerParses() async throws {
        let body = #"{"name":"Коллектив","pinCount":150,"truncated":true,"pins":[{"id":"1","permalink":"https://www.pinterest.com/pin/1/","image":"https://i.pinimg.com/736x/a.jpg"},{"id":"","permalink":"x","image":"y"}]}"#
        let b = try await client(body: body).board(link: "https://pin.it/a")
        #expect(b.name == "Коллектив" && b.pinCount == 150 && b.truncated && b.pins.count == 1)
    }

    @Test func boardWithoutTruncatedFlagComparesCounts() async throws {
        let body = #"{"name":"","pinCount":3,"pins":[{"id":"1","permalink":"p","image":"i"}]}"#
        let b = try await client(body: body).board(link: "x")
        #expect(b.truncated)
    }

    @Test func garbageBoardIsBadAnswer() async {
        await #expect(throws: PinterestFailure.badAnswer) { try await client(body: "<html>").board(link: "x") }
    }

    @Test func emptyPictureIsBadAnswer() async {
        await #expect(throws: PinterestFailure.badAnswer) { try await client(body: "").image(at: "x") }
    }

    // MARK: коды → причины

    @Test(arguments: [
        (400, "bad url", PinterestFailure.badLink), (403, "forbidden", .rejected),
        (404, "board not found", .boardNotFound), (404, "no og:image", .notFound), (404, "not found", .notFound),
        (413, "too large", .notFound), (429, "rate", .busy), (502, "upstream", .serverDown),
        (500, "internal", .serverDown), (503, "", .serverDown),
    ])
    func statusMapsToReason(status: Int, reason: String, want: PinterestFailure) async {
        let body = #"{"error":"\#(reason)","reason":"\#(reason)"}"#
        await #expect(throws: want) { try await client(status: status, body: body).board(link: "x") }
    }

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, PinterestFailure.offline), (.networkConnectionLost, .offline),
        (.dnsLookupFailed, .offline), (.timedOut, .timeout), (.cannotConnectToHost, .serverDown), (.secureConnectionFailed, .serverDown),
    ])
    func transportErrorMapsToReason(code: URLError.Code, want: PinterestFailure) async {
        await #expect(throws: want) { try await client(error: URLError(code)).image(at: "x") }
    }

    @Test func cancellationIsNotAFailure() async {
        await #expect(throws: CancellationError.self) { try await client(error: URLError(.cancelled)).image(at: "x") }
    }

    // MARK: медленная сеть — настоящая сессия, зависший ответ

    final class Hang: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {}      // не отвечает никогда
        override func stopLoading() {}
    }

    @Test func slowServerEndsInTimeoutNotInSilence() async throws {
        let t = PinterestTimeouts(page: 0.4, image: 0.4)
        let c = PinterestClient(config: PinterestConfig(url: base, key: "k"), timeouts: t,
                                transport: PinterestClient.liveTransport(timeouts: t, protocolClasses: [Hang.self]))
        let start = Date()
        await #expect(throws: PinterestFailure.timeout) { try await c.image(at: "https://i.pinimg.com/a.jpg") }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    // MARK: ключ в сборке

    @Test func noPlistMeansNoConfig() {
        #expect(PinterestConfig.load(bundle: Bundle(for: Capture.self)) == nil)
        #expect(PinterestClient.live(config: nil) == nil)
    }
}
