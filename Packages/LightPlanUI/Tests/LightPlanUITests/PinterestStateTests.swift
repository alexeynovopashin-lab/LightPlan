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

/// Итерация 28м, шаг 3: Pinterest в папке мудборда на состоянии приложения — читалка подменена сценарием,
/// настоящая сеть не нужна. Смотрим на данные (кадры, файлы, состояние), не на строки с экрана.
@MainActor
struct PinterestStateTests {

    // MARK: оснастка

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


    /// Сценарий читалки: что отвечают доска, картинка и превью; сколько раз звали.
    final class Reader: PinterestReading, @unchecked Sendable {
        private let lock = NSLock()
        var boards: [String: Result<PinterestBoard, PinterestFailure>] = [:]
        var previewResult: Result<Data, PinterestFailure> = .success(pinTestPNG)
        var imageFailures: [String: PinterestFailure] = [:]
        /// После стольких удачных картинок все следующие падают с этой причиной (обрыв связи).
        var dropAfter: Int?
        var dropWith: PinterestFailure = .offline
        var delay: Duration = .zero
        private var _calls = 0, _images = 0, _previews = 0
        var calls: Int { lock.withLock { _calls } }
        var images: Int { lock.withLock { _images } }
        var previews: Int { lock.withLock { _previews } }

        func board(link: String) async throws -> PinterestBoard {
            lock.withLock { _calls += 1 }
            switch boards[link] ?? .failure(.boardNotFound) { case .success(let b): return b; case .failure(let f): throw f }
        }
        func image(at address: String) async throws -> Data {
            let n: Int = lock.withLock { _calls += 1; _images += 1; return _images }
            if delay != .zero { try await Task.sleep(for: delay) }
            if let f = imageFailures[address] { throw f }
            if let d = dropAfter, n > d { throw dropWith }
            return pinTestPNG
        }
        func preview(of page: String) async throws -> Data {
            lock.withLock { _calls += 1; _previews += 1 }
            switch previewResult { case .success(let d): return d; case .failure(let f): throw f }
        }
    }

    private func pins(_ r: ClosedRange<Int>) -> [PinterestPin] {
        r.map { PinterestPin(id: "\($0)", permalink: "https://www.pinterest.com/pin/\($0)/", image: "https://i.pinimg.com/736x/\($0).jpg") }
    }
    private func board(_ r: ClosedRange<Int>, name: String = "Коллектив", count: Int? = nil, truncated: Bool = false) -> PinterestBoard {
        PinterestBoard(name: name, pinCount: count ?? r.count, truncated: truncated, pins: pins(r))
    }

    private func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("pin-" + UUID().uuidString) }

    /// Две жанровые папки «x» и «y», обе пустые; открыта «x».
    private func model(_ dir: URL, reader: Reader?) -> AppModel {
        var snap = Snapshot()
        snap.extra["boards"] = .array([
            .object(["id": .string("x"), "kind": .string("tpl"), "genre": .string("wedding"), "items": .array([])]),
            .object(["id": .string("y"), "kind": .string("tpl"), "genre": .string("wedding"), "items": .array([]), "name": .string("Вторая")]),
        ])
        let now = ISO8601DateFormatter().date(from: "2026-10-03T09:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), now: { now })
        app.refImages = RefImageStore(directory: dir)
        app.pinterest = reader
        app.openMbFolder(boardId: "x")
        return app
    }

    private func frames(_ app: AppModel, _ id: String = "x") -> [RefFrame] {
        let lib = app.mbLibrary()
        return (lib.board(id)?.items ?? []).compactMap { lib.shot($0) }
    }
    private func files(_ dir: URL) -> Int { RefImageStore(directory: dir).names().count }

    /// Ждём, пока условие станет правдой (задачи без ручки — превью одного пина).
    private func until(_ what: String = "", _ ok: () -> Bool) async {
        for _ in 0..<400 { if ok() { return }; try? await Task.sleep(for: .milliseconds(10)) }
        Issue.record("не дождались: \(what)")
    }
    private func ask(_ app: AppModel, link: String) async {
        app.mbAddLink(link)
        await app.pinTask?.value
    }
    private func add(_ app: AppModel) async {
        app.confirmPinBoard()
        await app.pinTask?.value
    }

    // MARK: ссылка не Pinterest

    @Test func foreignLinkStaysATextTileAndNeverCallsTheReader() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        app.mbAddLink("https://example.com/a/b/")
        #expect(frames(app).count == 1 && frames(app)[0].im == nil && frames(app)[0].kind == .link)
        #expect(r.calls == 0 && app.mb.pin == nil && app.mb.pinNote == nil)
    }

    // MARK: нет ключа в сборке

    @Test(arguments: ["https://www.pinterest.com/pin/5/", "https://www.pinterest.com/u/b/", "https://pin.it/abc"])
    func withoutKeyTheLinkIsATileAndTheNoteIsHonest(link: String) {
        let dir = tmp(), app = model(dir, reader: nil)
        app.mbAddLink(link)
        #expect(frames(app).count == 1 && frames(app)[0].im == nil)
        #expect(app.mb.pinNote == .failure(.notConfigured, retryFrame: nil))
        #expect(app.mb.pin == nil && app.mb.sheet == nil)
        #expect(app.pinterestUnavailable() == .notConfigured)
    }

    // MARK: один пин

    @Test func singlePinGetsItsPicture() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        app.mbAddLink("https://www.pinterest.com/pin/115264071708018540/")
        #expect(frames(app).count == 1)
        await until("картинка") { frames(app).first?.im != nil }
        let f = frames(app)[0]
        #expect(f.kind == .link && f.w == 4 && f.h == 6 && f.isViewable)
        #expect(RefImageStore(directory: dir).exists(f.im!) && files(dir) == 1)
        #expect(app.mb.pinNote == nil && r.previews == 1)
    }

    @Test func samePinTwiceAddsOneTile() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        app.mbAddLink("https://www.pinterest.com/pin/9/")
        await until { frames(app).first?.im != nil }
        let again = app.mbAddLink("https://ru.pinterest.com/pin/9/?invite=zz")
        #expect(again == .duplicate && frames(app).count == 1 && r.previews == 1)
    }

    @Test func singlePinOfflineKeepsTheTileThenRetryBringsThePicture() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.previewResult = .failure(.offline)
        app.mbAddLink("https://www.pinterest.com/pin/5/")
        let id = frames(app)[0].id
        await until { app.mb.pinNote != nil }
        #expect(app.mb.pinNote == .failure(.offline, retryFrame: id))
        #expect(frames(app)[0].im == nil && files(dir) == 0)            // картинку не придумали
        r.previewResult = .success(pinTestPNG)
        app.retryPinNote()
        await until { frames(app).first?.im != nil }
        #expect(app.mb.pinNote == nil && files(dir) == 1)
    }

    @Test func pinWithoutPictureStaysATile() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.previewResult = .failure(.notFound)
        app.mbAddLink("https://www.pinterest.com/pin/5/")
        await until { app.mb.pinNote != nil }
        #expect(frames(app).count == 1 && frames(app)[0].im == nil && files(dir) == 0)
    }

    @Test func frameRemovedWhileThePreviewTravelsLeavesNoFile() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.delay = .milliseconds(60)
        let p = Reader(); p.previewResult = .success(pinTestPNG)
        let slow = SlowPreview(inner: p)
        app.pinterest = slow
        app.mbAddLink("https://www.pinterest.com/pin/5/")
        let id = frames(app)[0].id
        app.mbEdit { lib, _ in lib.dropWithShots("x") ; _ = id }
        await until { slow.finished }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(files(dir) == 0)
    }
    private final class SlowPreview: PinterestReading, @unchecked Sendable {
        let inner: Reader
        private let lock = NSLock(); private var _done = false
        var finished: Bool { lock.withLock { _done } }
        init(inner: Reader) { self.inner = inner }
        func board(link: String) async throws -> PinterestBoard { try await inner.board(link: link) }
        func image(at address: String) async throws -> Data { try await inner.image(at: address) }
        func preview(of page: String) async throws -> Data {
            try await Task.sleep(for: .milliseconds(80)); defer { lock.withLock { _done = true } }
            return try await inner.preview(of: page)
        }
    }

    // MARK: короткая ссылка

    @Test func shortLinkThatIsABoardOpensTheBoardSheet() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://pin.it/3qVvzLDZl"] = .success(board(1...6))
        await ask(app, link: "pin.it/3qVvzLDZl")
        #expect(app.mb.sheet == .pinBoard && app.mb.pin?.phase == .ask && app.mb.pin?.all.count == 6)
        #expect(frames(app).isEmpty)                                    // до «Добавить» в папке ничего нет
    }

    @Test func shortLinkThatIsAPinBecomesATileWithPicture() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://pin.it/pinpin"] = .failure(.badLink)
        await ask(app, link: "https://pin.it/pinpin")
        await until { frames(app).first?.im != nil }
        #expect(frames(app).count == 1 && frames(app)[0].url == "https://pin.it/pinpin")
        #expect(app.mb.pin == nil && app.mb.sheet == nil)
    }

    // MARK: доска

    @Test(arguments: [1, 6, 100])
    func boardOfNPinsLandsWholeWithOneFilePerFrame(n: Int) async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...n))
        await ask(app, link: "https://www.pinterest.com/u/b/")
        #expect(app.mb.pin?.phase == .ask && app.mb.pin?.truncated == false)
        await add(app)
        let fs = frames(app)
        #expect(fs.count == n && Set(fs.compactMap(\.im)).count == n && files(dir) == n)
        #expect(app.mb.pin?.phase == .ended && app.mb.pin?.added == n && app.mb.pin?.pending.isEmpty == true)
        #expect(fs.allSatisfy { $0.kind == .link && $0.isViewable && $0.url?.contains("/pin/") == true })
    }

    @Test func boardOf150IsCappedAtTheFirst100AndSaysSo() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://www.pinterest.com/u/big/"] = .success(board(1...100, count: 150, truncated: true))
        await ask(app, link: "https://www.pinterest.com/u/big/")
        #expect(app.mb.pin?.truncated == true && app.mb.pin?.pinCount == 150 && app.mb.pin?.all.count == 100)
        await add(app)
        #expect(frames(app).count == 100 && files(dir) == 100)
    }

    @Test func clientNeverTakesMoreThanTheCeilingEvenIfAnswerIsLonger() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...130, count: 130))
        await ask(app, link: "https://www.pinterest.com/u/b/")
        #expect(app.mb.pin?.all.count == 100 && app.mb.pin?.truncated == true)
    }

    @Test func importingTheSameBoardAgainAddsNothingAndLeavesNoFiles() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...6))
        await ask(app, link: "https://www.pinterest.com/u/b/"); await add(app)
        app.closePinFlow()
        let imagesBefore = r.images
        await ask(app, link: "https://www.pinterest.com/u/b/")
        #expect(app.mb.pin?.all.isEmpty == true && app.mb.pin?.already == 6)
        #expect(frames(app).count == 6 && files(dir) == 6 && r.images == imagesBefore)   // ни трафика, ни файлов
    }

    @Test func theSamePictureInTwoBoardsAddsThePinOnceToAFolderButTwiceToTwoFolders() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://www.pinterest.com/u/a/"] = .success(board(1...4))
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(3...6))       // 3 и 4 — те же пины
        await ask(app, link: "https://www.pinterest.com/u/a/"); await add(app); app.closePinFlow()
        await ask(app, link: "https://www.pinterest.com/u/b/")
        #expect(app.mb.pin?.already == 2 && app.mb.pin?.all.map(\.id) == ["5", "6"])
        await add(app); app.closePinFlow()
        #expect(frames(app).count == 6 && files(dir) == 6)
        // В другую папку те же пины — отдельные кадры с отдельными файлами.
        app.closeMbFolder(); app.openMbFolder(boardId: "y")
        await ask(app, link: "https://www.pinterest.com/u/a/"); await add(app)
        #expect(frames(app, "y").count == 4 && files(dir) == 10)
        #expect(Set(app.mbLibrary().imageNames).count == 10)
    }

    @Test func boardNotFoundIsSaidNotSwallowed() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        await ask(app, link: "https://www.pinterest.com/u/none/")
        #expect(app.mb.pin?.phase == .failed(.boardNotFound) && frames(app).isEmpty)
    }

    @Test func boardOfflineIsSaidAndRetryWorks() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://www.pinterest.com/u/b/"] = .failure(.offline)
        await ask(app, link: "https://www.pinterest.com/u/b/")
        #expect(app.mb.pin?.phase == .failed(.offline))
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...3))
        app.loadPinBoard(); await app.pinTask?.value
        #expect(app.mb.pin?.phase == .ask && app.mb.pin?.all.count == 3)
    }

    @Test func pinWithoutPictureInsideABoardIsCountedNotHidden() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...6))
        r.imageFailures["https://i.pinimg.com/736x/4.jpg"] = .notFound
        await ask(app, link: "https://www.pinterest.com/u/b/"); await add(app)
        #expect(frames(app).count == 5 && app.mb.pin?.failed == 1 && app.mb.pin?.pending.map(\.id) == ["4"])
        #expect(files(dir) == 5)
    }

    @Test func networkDropInTheMiddleKeepsWhatCameAndRetryFinishesWithoutDuplicates() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...60))
        r.dropAfter = 25
        await ask(app, link: "https://www.pinterest.com/u/b/"); await add(app)
        let f1 = app.mb.pin!
        #expect(f1.phase == .ended && f1.interrupted == .offline && !f1.stopped)
        #expect(frames(app).count == f1.added && files(dir) == f1.added && f1.added >= 20 && f1.added < 60)
        #expect(f1.added + f1.pending.count == 60)
        r.dropAfter = nil
        await add(app)                                                   // «Повторить»
        #expect(frames(app).count == 60 && files(dir) == 60 && app.mb.pin?.pending.isEmpty == true)
        #expect(Set(frames(app).compactMap(\.url)).count == 60)
    }

    @Test func stopInTheMiddleKeepsWhatCameAndLeavesNoHalfFinishedFrames() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.delay = .milliseconds(15)
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...80))
        await ask(app, link: "https://www.pinterest.com/u/b/")
        app.confirmPinBoard()
        await until("часть пришла") { frames(app).count >= 6 }
        app.stopPinImport()
        await app.pinTask?.value
        let f = app.mb.pin!
        #expect(f.phase == .ended && f.stopped && f.failed == 0)
        let fs = frames(app)
        #expect(fs.count == f.added && fs.count < 80 && files(dir) == fs.count)       // кадров и файлов поровну: полуфабрикатов нет
        #expect(fs.allSatisfy { RefImageStore(directory: dir).exists($0.im ?? "") })
        r.delay = .zero
        await add(app)
        #expect(frames(app).count == 80 && files(dir) == 80)
    }

    @Test func leavingTheFolderDuringImportDoesNotLoseTheBoard() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.delay = .milliseconds(10)
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...30))
        await ask(app, link: "https://www.pinterest.com/u/b/")
        app.confirmPinBoard()
        app.closeMbFolder()                                              // смена экрана посреди закачки
        #expect(app.mbLibrary().board("x") != nil)                       // пустая подборка не ушла под ногами у закачки
        await app.pinTask?.value
        #expect(frames(app).count == 30 && files(dir) == 30)
    }

    @Test func closingTheFolderBeforeConfirmingDropsTheBoardAndFetchesNothing() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...6))
        await ask(app, link: "https://www.pinterest.com/u/b/")
        app.closeMbFolder()
        #expect(app.mb.pin == nil && app.mb.sheet == nil && r.images == 0 && files(dir) == 0)
    }

    @Test func swipingTheSheetAwayKeepsARunningImportButDropsAnUnconfirmedOne() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.delay = .milliseconds(10)
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...20))
        await ask(app, link: "https://www.pinterest.com/u/b/")
        app.pinSheetClosed()
        #expect(app.mb.pin == nil)
        await ask(app, link: "https://www.pinterest.com/u/b/")
        app.confirmPinBoard()
        app.pinSheetClosed()
        #expect(app.mb.pin?.phase == .running)
        await app.pinTask?.value
        #expect(frames(app).count == 20)
    }

    @Test func folderDeletedDuringImportLeavesNoOrphanFiles() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        r.delay = .milliseconds(10)
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...20))
        await ask(app, link: "https://www.pinterest.com/u/b/")
        app.confirmPinBoard()
        await until("первая пачка") { frames(app).count >= 6 }
        app.mbDeleteBoard("x")
        await app.pinTask?.value
        #expect(files(dir) == 0 && app.mbLibrary().shots.isEmpty)
    }

    @Test func boardWithRealisticPinsAcrossFolderTagGetsTheSectionTag() async {
        let dir = tmp(), r = Reader(), app = model(dir, reader: r)
        app.mb.folderTag = "portrait"
        r.boards["https://www.pinterest.com/u/b/"] = .success(board(1...3))
        await ask(app, link: "https://www.pinterest.com/u/b/"); await add(app)
        #expect(frames(app).allSatisfy { $0.tags == ["portrait"] })
    }
}
