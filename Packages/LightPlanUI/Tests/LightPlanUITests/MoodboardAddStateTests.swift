import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 28, шаг 5г: «Фото» и «Ссылка» в открытой папке; файл ложится при добавлении и уходит,
/// когда кадр покидает последнюю подборку.
@MainActor
struct MoodboardAddStateTests {

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
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func png(_ w: Int, _ h: Int) -> Data {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// Две жанровые папки: «x» пустая, «y» держит кадр «k» с файлом; открыта «x».
    private func model(dir: URL, store: Store? = nil) -> AppModel {
        var snap = Snapshot()
        snap.extra["shots"] = .array([.object(["id": .string("k"), "k": .string("img"), "im": .string("k")])])
        snap.extra["boards"] = .array([
            .object(["id": .string("x"), "kind": .string("tpl"), "genre": .string("wedding"), "items": .array([])]),
            .object(["id": .string("y"), "kind": .string("tpl"), "genre": .string("wedding"), "items": .array([.string("k")]),
                     "name": .string("Вторая")]),
        ])
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: store, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), now: { now })
        app.refImages = RefImageStore(directory: dir)
        app.openMbFolder(boardId: "x")
        return app
    }

    private func temp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lp-mbadd-" + UUID().uuidString, isDirectory: true)
    }

    @Test func photoSavedAsFileAndFrameInOpenFolder() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = model(dir: dir)
        let ids = app.mbAddPhotos([png(30, 20), png(10, 40)], to: "x")
        #expect(ids.count == 2)
        let lib = app.mbLibrary()
        #expect(lib.board("x")?.items == ids)
        let f = lib.shot(ids[0])
        #expect(f?.kind == .img && f?.im == ids[0] && f?.w == 30 && f?.h == 20 && f?.mt != nil)
        #expect(RefImageStore(directory: dir).names().sorted() == ids.sorted())
    }

    @Test func notAnImageIsNotSaved() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = model(dir: dir)
        #expect(app.mbAddPhotos([Data([1, 2, 3])], to: "x").isEmpty)
        #expect(app.mbLibrary().board("x")?.items.isEmpty == true)
        #expect(RefImageStore(directory: dir).names().isEmpty)
    }

    @Test func fileGoesWhenFrameLeavesLastBoard() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = model(dir: dir)
        let store = RefImageStore(directory: dir)
        let id = app.mbAddPhotos([png(4, 3)], to: "x")[0]
        #expect(store.exists(id))
        // кладём в «y» ещё раз: из «x» уйдёт, из «y» — нет
        app.mbPut(id, into: "y")
        app.mb.pick = MbPick(); app.mb.pick?.toggle(id)
        app.mbRemovePicked()
        #expect(store.exists(id), "кадр ещё лежит в «y»")
        // удалить «y» целиком: k и новый кадр нигде не лежат — файлы уходят
        store.save(Data([1]), as: "k")
        app.mbDeleteBoard("y")
        #expect(!store.exists(id) && !store.exists("k"))
        #expect(app.mbLibrary().shots.isEmpty)
    }

    @Test func linkAddedAndJunkKeepsSheet() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = model(dir: dir)
        app.openMbAddLink()
        #expect(app.mbAddLink("abc") == .invalid && app.mb.sheet == .addLink)
        #expect(app.mbAddLink("site.com/p") != .invalid && app.mb.sheet == nil)
        let items = app.mbLibrary().board("x")?.items ?? []
        #expect(items.count == 1 && app.mbLibrary().shot(items[0])?.url == "https://site.com/p")
        app.openMbAddLink()
        #expect(app.mbAddLink("https://SITE.com/p") == .duplicate && app.mb.sheet == nil)
        #expect(app.mbLibrary().board("x")?.items.count == 1)
    }

    @Test func photoButtonClosesSheetAndAsksPicker() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = model(dir: dir)
        app.openMbAddWhat()
        #expect(app.mb.sheet == .addWhat)
        app.requestMbPhotoPicker()
        #expect(app.mb.sheet == nil && app.mb.photoPicker)
    }

    /// Ревью GPT к a2549e7 (2): чтение фото долгое — кадры идут в папку, что была открыта при выборе,
    /// а не в ту, что открыта, когда чтение кончилось.
    @Test func photosGoToTheFolderChosenNotTheOneOpenNow() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = model(dir: dir)                 // открыта «x»
        app.openMbFolder(boardId: "y")            // пока грузились фото, перешли в «y»
        let ids = app.mbAddPhotos([png(5, 5)], to: "x", tag: "couple")
        #expect(app.mbLibrary().board("x")?.items == ids && app.mbLibrary().board("y")?.items == ["k"])
        #expect(app.mbLibrary().shot(ids[0])?.tags == ["couple"])
        app.mb.folder = nil                       // папку закрыли — подборка есть, кадры всё равно в неё
        #expect(app.mbAddPhotos([png(5, 5)], to: "x").count == 1)
        #expect(app.mbAddPhotos([png(5, 5)], to: "gone").isEmpty)         // подборки нет — ни кадра, ни файла
        #expect(RefImageStore(directory: dir).names().count == 2)
    }

    /// Ревью GPT к a2549e7 (1): файл уходит, когда снимок без кадра уже на диске, не раньше.
    @Test func fileGoesOnlyAfterSnapshotIsSaved() async {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir, debounce: .milliseconds(1))
        let app = model(dir: dir.appendingPathComponent("img", isDirectory: true), store: store)
        let images = RefImageStore(directory: dir.appendingPathComponent("img", isDirectory: true))
        images.save(Data([1]), as: "k")
        app.mbDeleteBoard("y")                    // «k» лежал только в «y»
        #expect(images.exists("k"), "снимок ещё не записан — файл держится")
        await app.flush()
        #expect(!images.exists("k"))
        let onDisk = (try? String(contentsOf: dir.appendingPathComponent("light-plan.json"), encoding: .utf8)) ?? ""
        #expect(!onDisk.isEmpty && !onDisk.contains("\"im\":\"k\""))
    }
}
