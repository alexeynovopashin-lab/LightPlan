import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 29б: корзина мудборда съёмки в хозяине приложения — убрать → в корзину, вернуть, очистить,
/// самоочистка по часам приложения (часы подменяются), у жанровых подборок корзины нет.
@MainActor
struct MoodboardBinStateTests {

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
    /// Часы, которые двигает тест.
    private final class Clock: @unchecked Sendable {
        var date: Date
        init(_ iso: String) { date = ISO8601DateFormatter().date(from: iso)! }
        func advance(days: Double = 0, seconds: Double = 0) { date = date.addingTimeInterval(days * 86_400 + seconds) }
    }

    private static let day = CivilDate(year: 2026, month: 10, day: 20)

    private func s(_ id: String) -> JSONValue {
        .object(["id": .string(id), "k": .string("img"), "im": .string(id), "tags": .array([])])
    }
    private func board(_ id: String, _ kind: String, _ items: [String], sid: String? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["id": .string(id), "kind": .string(kind), "genre": .string("wedding"),
                                      "items": .array(items.map { .string($0) })]
        if let sid { o["sid"] = .string(sid) }
        return .object(o)
    }

    /// Съёмка «w» 20 октября 10:00–23:00 с подборкой «sh» (a, b, c, d; d лежит и в жанровой «tpl»).
    private func model(clock: Clock) -> AppModel {
        var snap = Snapshot()
        snap.sessions = [Session(id: "w", kind: .shoot, day: Self.day, start: 600, end: 1380, duration: 780, genre: .wedding)]
        snap.extra["shots"] = .array(["a", "b", "c", "d"].map(s))
        snap.extra["boards"] = .array([board("sh", "shoot", ["a", "b", "c", "d"], sid: "w"), board("tpl", "tpl", ["d"])])
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { clock.date })
    }

    private func lib(_ app: AppModel) -> RefLibrary { app.mbLibrary() }
    private func binIds(_ app: AppModel) -> [String] { lib(app).board("sh")?.bin.map(\.id) ?? [] }

    @Test func removedFramesLandInBinWithTheClockOfTheApp() {
        let clock = Clock("2026-10-01T12:00:00+03:00")
        let app = model(clock: clock); app.openMbFolder(boardId: "sh")
        app.toggleMbPicking(); app.toggleMbPick("a"); app.toggleMbPick("d")
        app.mbRemovePicked()
        #expect(lib(app).board("sh")?.items == ["b", "c"])
        #expect(Set(binIds(app)) == ["a", "d"])
        #expect(lib(app).board("sh")?.bin.first?.at == Double(app.nowMs))
        #expect(lib(app).shot("a") != nil)                         // файл и кадр целы до срока
        #expect(lib(app).shot("d") != nil && lib(app).board("tpl")?.items == ["d"])
    }

    @Test func genreFolderGetsNoBin() {
        let app = model(clock: Clock("2026-10-01T12:00:00+03:00")); app.openMbFolder(boardId: "tpl")
        app.toggleMbPicking(); app.toggleMbPick("d")
        app.mbRemovePicked()
        #expect(lib(app).board("tpl")?.bin.isEmpty == true && lib(app).board("tpl")?.items.isEmpty == true)
        #expect(lib(app).board("sh")?.items.contains("d") == true && lib(app).shot("d") != nil)
    }

    @Test func restoreAndPurgeWorkOnTheFrozenList() {
        let app = model(clock: Clock("2026-10-01T12:00:00+03:00"))
        app.mbDiscard(["a", "b"], from: "sh")
        app.mbBinRestore(["a"], into: "sh")
        #expect(lib(app).board("sh")?.items == ["a", "c", "d"] && binIds(app) == ["b"])
        let asked = app.mbLibrary().binned("sh").filter { $0.id == "b" }   // о нём спросили «очистить»
        app.mbDiscard(["c"], from: "sh")                           // убрано уже после вопроса
        app.mbBinPurge(asked, of: "sh")                            // стирается то, о чём спросили
        #expect(binIds(app) == ["c"] && lib(app).shot("b") == nil && lib(app).shot("c") != nil)
    }

    @Test func sweepOnTheClockOfTheApp() {
        let clock = Clock("2026-10-01T12:00:00+03:00")
        let app = model(clock: clock)
        app.mbDiscard(["a", "d"], from: "sh")
        clock.advance(days: 7, seconds: -1)
        app.sweepMbBins()
        #expect(Set(binIds(app)) == ["a", "d"])                    // 7 суток без секунды
        clock.advance(seconds: 1)
        app.sweepMbBins()
        #expect(binIds(app).isEmpty)
        #expect(lib(app).shot("a") == nil)                         // одинокий — насовсем
        #expect(lib(app).shot("d") != nil && lib(app).board("tpl")?.items == ["d"])   // в жанре остался
    }

    @Test func shootEndModeFollowsTheShootClock() {
        let clock = Clock("2026-10-19T12:00:00+03:00")             // за день до съёмки
        let app = model(clock: clock)
        app.mbEdit { lib, now in lib.setBinMode(.shoot, of: "sh", now: now) }
        app.mbDiscard(["a"], from: "sh")
        clock.advance(days: 1, seconds: 3 * 3600)                  // 20 октября 15:00 — съёмка идёт
        app.sweepMbBins()
        #expect(binIds(app) == ["a"])
        clock.advance(seconds: 9 * 3600)                           // 21 октября 00:00 — после 23:00
        app.sweepMbBins()
        #expect(binIds(app).isEmpty && lib(app).shot("a") == nil)
    }

    @Test func journalSaysWhatHappened() {
        BinStoreLog.reset()
        let clock = Clock("2026-10-01T12:00:00+03:00")
        let app = model(clock: clock)
        app.mbDiscard(["a"], from: "sh")
        app.mbBinRestore(["a"], into: "sh")
        app.mbDiscard(["a"], from: "sh")
        clock.advance(days: 7)
        app.sweepMbBins()
        let j = BinStoreLog.journal
        #expect(j.count == 4)
        #expect(j[0].hasPrefix("discard board=sh bin=0→1 fund=4→4"))
        #expect(j[1].hasPrefix("restore board=sh bin=1→0 fund=4→4"))
        #expect(j[2].hasPrefix("discard board=sh bin=0→1 fund=4→4"))
        #expect(j[3].hasPrefix("sweep board=* bin=1→0 fund=4→3"))
    }
}
