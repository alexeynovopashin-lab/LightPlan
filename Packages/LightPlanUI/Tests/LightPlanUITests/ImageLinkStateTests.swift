import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

private let pinTestPNG: Data = {
    let ctx = CGContext(data: nil, width: 4, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}()

/// Итерация 28н.1: прямые ссылки на фото в папке мудборда — читалка подменена сценарием. Смотрим на данные
/// (кадры, файлы, состояние), не на строки с экрана.
@MainActor
struct ImageLinkStateTests {

    private struct NoWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup { func cities(matching query: String) async throws -> [CityHit] { [] } }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    final class Reader: ImageLinkReading, @unchecked Sendable {
        private let lock = NSLock()
        var result: Result<Data, ImageLinkFailure> = .success(pinTestPNG)
        var delay: Duration = .zero
        private var _asked: [(String, Bool)] = []
        var asked: [(link: String, viaServer: Bool)] { lock.withLock { _asked.map { (link: $0.0, viaServer: $0.1) } } }
        func picture(at link: String, viaServer: Bool) async throws -> Data {
            lock.withLock { _asked.append((link, viaServer)) }
            if delay != .zero { try await Task.sleep(for: delay) }
            return try result.get()
        }
    }

    private func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("img-" + UUID().uuidString) }

    private func model(_ dir: URL, reader: (any ImageLinkReading)?) -> AppModel {
        var snap = Snapshot()
        snap.extra["boards"] = .array([
            .object(["id": .string("x"), "kind": .string("tpl"), "genre": .string("wedding"), "items": .array([])]),
        ])
        let now = ISO8601DateFormatter().date(from: "2026-10-05T09:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), now: { now })
        app.refImages = RefImageStore(directory: dir)
        app.imageLinks = reader
        app.openMbFolder(boardId: "x")
        return app
    }
    private func frames(_ app: AppModel) -> [RefFrame] {
        let lib = app.mbLibrary()
        return (lib.board("x")?.items ?? []).compactMap { lib.shot($0) }
    }
    private func files(_ dir: URL) -> Int { RefImageStore(directory: dir).names().count }
    private func until(_ what: String = "", _ ok: () -> Bool) async {
        for _ in 0..<400 { if ok() { return }; try? await Task.sleep(for: .milliseconds(10)) }
        Issue.record("не дождались: \(what)")
    }
    private let link = "https://photos.example.com/set/portrait.jpg"

    // MARK: картинка по расширению

    @Test func imageLinkBecomesATileThenGetsItsPicture() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        app.mbAddLink(link)
        #expect(frames(app).count == 1 && frames(app)[0].kind == .link && frames(app)[0].url == link)
        await until("картинка") { frames(app).first?.im != nil }
        let f = frames(app)[0]
        #expect(f.kind == .link && f.url == link && f.w == 4 && f.h == 6 && f.isViewable)
        #expect(RefImageStore(directory: dir).exists(f.im!) && files(dir) == 1)
        #expect(app.mb.pinNote == nil)
        #expect(r.asked.count == 1 && r.asked[0].viaServer == true)
    }

    @Test func httpLinkIsAskedAsHttps() async {
        let r = Reader(), app = model(tmp(), reader: r)
        app.mbAddLink("http://photos.example.com/a.png")
        await until { !r.asked.isEmpty }
        #expect(r.asked[0].link == "https://photos.example.com/a.png")
    }

    @Test func failureKeepsTheTileSaysWhyAndRetryBringsThePicture() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.result = .failure(.unreachable)
        app.mbAddLink(link)
        await until("надпись") { app.mb.pinNote != nil }
        #expect(app.mb.pinNote == .image(.unreachable, retryFrame: frames(app)[0].id))
        #expect(frames(app).count == 1 && frames(app)[0].im == nil && files(dir) == 0)
        #expect(app.imageLinkText(.unreachable) == app.lexicon.t("img.unreachable"))
        r.result = .success(pinTestPNG)
        app.retryImageNote()
        await until("картинка после повтора") { frames(app).first?.im != nil }
        #expect(app.mb.pinNote == nil && files(dir) == 1 && r.asked.count == 2)
    }

    @Test(arguments: [ImageLinkFailure.notFound, .notImage, .tooLarge, .offline, .serverOff, .busy, .badLink])
    func everyFailureIsAnHonestNoteAndNeverAFakePicture(f: ImageLinkFailure) async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.result = .failure(f)
        app.mbAddLink(link)
        await until("надпись") { app.mb.pinNote != nil }
        guard case .image(let why, _)? = app.mb.pinNote else { Issue.record("нет строки"); return }
        #expect(why == f)
        #expect(!app.imageLinkText(f).isEmpty && app.imageLinkText(f) != "img.\(f)")
        #expect(frames(app)[0].im == nil && files(dir) == 0)
    }

    @Test func serverOffNamesTheSettingAndOtherNotesDoNot() {
        let app = model(tmp(), reader: nil)
        #expect(app.imageLinkText(.serverOff).contains("«Авто»"))
        #expect(!app.imageLinkText(.unreachable).contains("Авто"))
    }

    @Test func bytesThatAreNotADecodablePictureAreRefused() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.result = .success(Data([0xFF, 0xD8, 0xFF, 0xE0] + [UInt8](repeating: 0, count: 40)))   // по байтам JPEG, а не раскрывается
        app.mbAddLink(link)
        await until("надпись") { app.mb.pinNote != nil }
        #expect(app.mb.pinNote == .image(.notImage, retryFrame: frames(app)[0].id))
        #expect(frames(app)[0].im == nil && files(dir) == 0)
    }

    @Test func sameLinkTwiceAddsOneTileAndOneRequest() async {
        let r = Reader(), app = model(tmp(), reader: r)
        app.mbAddLink(link)
        await until { frames(app).first?.im != nil }
        let again = app.mbAddLink(link)
        #expect(again == .duplicate && frames(app).count == 1 && r.asked.count == 1)
    }

    @Test func tileRemovedWhileLoadingLeavesNoFile() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.delay = .milliseconds(150)
        app.mbAddLink(link)
        let id = frames(app)[0].id
        app.mbEdit { lib, _ in lib.dropShot(id) }
        try? await Task.sleep(for: .milliseconds(400))
        #expect(frames(app).isEmpty && files(dir) == 0 && r.asked.count == 1)
    }

    // MARK: адрес без расширения и не картинка

    @Test func noExtensionIsProbedQuietlyAndNeverViaOurServer() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        app.mbAddLink("https://images.example.com/photo-123?w=800")
        await until("картинка") { frames(app).first?.im != nil }
        #expect(r.asked.count == 1 && r.asked[0].viaServer == false && app.mb.pinNote == nil && files(dir) == 1)
    }

    @Test(arguments: [ImageLinkFailure.notImage, .unreachable, .offline, .notFound])
    func noExtensionFailureIsSilentAndTheTileStaysAPlainLink(f: ImageLinkFailure) async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.result = .failure(f)
        app.mbAddLink("https://blog.example.com/post-title")
        await until { !r.asked.isEmpty }
        try? await Task.sleep(for: .milliseconds(80))
        #expect(app.mb.pinNote == nil && frames(app).count == 1 && frames(app)[0].im == nil && files(dir) == 0)
    }

    @Test(arguments: ["https://example.com/", "https://example.com/blog/", "https://example.com/page.html", "https://example.com/doc.pdf",
                      "https://www.pinterest.com/pin/5/", "https://pin.it/abc"])
    func notAnImageNeverCallsTheImageReader(link: String) async {
        let r = Reader(), app = model(tmp(), reader: r)
        app.mbAddLink(link)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(r.asked.isEmpty)
    }

    @Test func withoutAReaderTheLinkIsJustATile() {
        let app = model(tmp(), reader: nil)
        app.mbAddLink(link)
        #expect(frames(app).count == 1 && frames(app)[0].im == nil && app.mb.pinNote == nil)
    }
}
