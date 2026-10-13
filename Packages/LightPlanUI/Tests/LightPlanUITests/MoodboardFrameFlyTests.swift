import Testing
import Foundation
import CoreGraphics
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// 29.3в: драг кадров в папке (`MbFrameDrag`) и полёт обложки в шапку (`MbFly`) — порядок, исходы жеста, запись,
/// фазы полёта и подчистка клона. Числа — `mbGridDrag` и `openBoardWithFly` беты.
@MainActor
struct MoodboardFrameFlyTests {

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

    /// Жанровая подборка «tpl» из пяти кадров (в фонде), без вторых папок жанра.
    private func model() -> AppModel {
        var snap = Snapshot()
        snap.extra["shots"] = .array(["a", "b", "c", "d", "e"].map { .object(["id": .string($0), "k": .string("img"), "im": .string($0)]) })
        snap.extra["boards"] = .array([.object(["id": .string("tpl"), "kind": .string("tpl"), "genre": .string("wedding"),
                                                "items": .array(["a", "b", "c", "d", "e"].map { .string($0) })])])
        let now = ISO8601DateFormatter().date(from: "2026-10-13T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    /// Раскладка беты из замера: колонка 172, кадры 258,6 / 386,5 / 215 / 301,8 / 258,6 и «+».
    private func drag(_ items: [String] = ["a", "b", "c", "d", "e"]) -> MbFrameDrag {
        let d = MbFrameDrag()
        d.still = { true }
        let h: [String: Double] = ["a": 258.6, "b": 386.5, "c": 215, "d": 301.8, "e": 258.6]
        d.cells = { order in MbFrameDragRules.layout(ids: order + ["+add"], heights: order.map { h[$0]! } + [172], column: 172).cells }
        return d
    }

    // MARK: драг

    /// Подняли «a», повели к середине «c» — две перестановки, запись нового порядка в момент отпускания.
    @Test func dragAcrossColumnWritesOrderOnRelease() {
        let d = drag()
        let items = ["a", "b", "c", "d", "e"]
        let c0 = d.cells(items)[0], c2 = d.cells(items)[2]
        #expect(d.begin(id: "a", items: items, at: CGPoint(x: c0.midX, y: c0.midY)))
        #expect(d.swallows, "подъём — не тап")
        for i in 1...20 {
            let t = Double(i) / 20
            d.move(to: CGPoint(x: c0.midX + (c2.midX - c0.midX) * t, y: c0.midY + (c2.midY - c0.midY) * t))
        }
        #expect(d.order == ["b", "c", "a", "d", "e"])
        var written: [[String]] = []
        let out = d.drop { written.append($0) }
        #expect(out == .reordered(["b", "c", "a", "d", "e"]))
        #expect(written == [["b", "c", "a", "d", "e"]])
        #expect(d.settling)
    }

    /// Подержали и отпустили, не двигая (дрожь пальца меньше 2 pt) — лист кадра, порядок не пишется.
    @Test func holdWithoutMoveOpensSheetNotReorder() {
        let d = drag()
        let items = ["a", "b", "c", "d", "e"]
        let c = d.cells(items)[1]
        #expect(d.begin(id: "b", items: items, at: CGPoint(x: c.midX, y: c.midY)))
        d.move(to: CGPoint(x: c.midX + 0.8, y: c.midY - 0.7))
        #expect(!d.moved)
        var written = 0
        #expect(d.drop { _ in written += 1 } == .menu("b"))
        #expect(written == 0)
    }

    /// Повели и вернули на своё место — не лист и не запись.
    @Test func dragBackHomeIsSame() {
        let d = drag()
        let items = ["a", "b", "c", "d", "e"]
        let c = d.cells(items)[0]
        #expect(d.begin(id: "a", items: items, at: CGPoint(x: c.midX, y: c.midY)))
        d.move(to: CGPoint(x: c.midX + 20, y: c.midY + 10))
        var written = 0
        #expect(d.drop { _ in written += 1 } == .same)
        #expect(written == 0)
    }

    /// Пока кадр ложится, новый подъём не начинается; после посадки — снова можно.
    @Test func secondLiftWaitsForLanding() async {
        let d = drag()
        d.still = { false }
        let items = ["a", "b", "c", "d", "e"]
        let c = d.cells(items)[0]
        #expect(d.begin(id: "a", items: items, at: CGPoint(x: c.midX, y: c.midY)))
        d.drop { _ in }
        #expect(!d.begin(id: "b", items: items, at: .zero))
        try? await Task.sleep(for: .milliseconds(450))
        #expect(!d.active)
        #expect(d.begin(id: "b", items: items, at: CGPoint(x: c.midX, y: c.midY + 300)))
    }

    /// Новый порядок доходит до подборки (`mbEdit` → `RefLibrary.reorder`) и папки.
    @Test func reorderReachesFolder() {
        let app = model()
        app.openMbFolder(boardId: "tpl")
        #expect(app.mbReorderFrames(["c", "a", "b", "d", "e"], of: "tpl"))
        #expect(app.mbFolderScene(app.mbLibrary())?.list.map(\.id) == ["c", "a", "b", "d", "e"])
        #expect(!app.mbReorderFrames(["c", "a", "b", "d"], of: "tpl"), "неполный порядок не пишется")
    }

    /// Кривые беты: подъём 0,22 с, соседи 0,22 с, посадка 0,3 с.
    @Test func motionNumbersAreTheBetas() {
        #expect(MbFrameMotion.landDuration == 0.3)
        #expect(MbFrameDragRules.liftScale == 1.06)
    }

    // MARK: полёт

    private func fly(still: Bool) -> MbFly {
        let f = MbFly()
        f.still = { still }
        f.sources["tpl"] = CGRect(x: 154.7, y: 293, width: 120.7, height: 120.7)
        return f
    }

    @Test func timelineIsTheBetas() {
        #expect(MbFlyTimeline.flight == 0.43)
        #expect(MbFlyTimeline.fade == 0.14)
        #expect(MbFlyTimeline.sweep == 0.9)
        #expect(MbFlyTimeline.radiusFrom == 12 && MbFlyTimeline.radiusTo == 14)
    }

    /// Рамка клона — прямая от плитки к шапке (`left/top/width/height` веба), скругление 12 → 14.
    @Test func cloneRectIsStraightLine() {
        let a = CGRect(x: 154.7, y: 293, width: 120.7, height: 120.7), b = CGRect(x: 24, y: 62, width: 58, height: 58)
        #expect(MbFly.rect(from: a, to: b, k: 0) == a)
        #expect(MbFly.rect(from: a, to: b, k: 1) == b)
        let m = MbFly.rect(from: a, to: b, k: 0.5)
        #expect(abs(m.minX - 89.35) < 0.01 && abs(m.width - 89.35) < 0.01)
        #expect(MbFly.rect(from: a, to: nil, k: 0.7) == a, "шапка ещё не разложена — клон на плитке")
        #expect(MbFly.radius(k: 0.5) == 13)
    }

    /// «Уменьшение движения»: папка открывается сразу, клона нет (веб `reduced` → `openMbFolder`).
    @Test func reduceMotionOpensWithoutFlight() {
        let f = fly(still: true)
        var opened = 0
        f.launch(board: "tpl", genre: "wedding") { opened += 1 }
        #expect(opened == 1)
        #expect(f.board == nil && !f.hidesHero("tpl"))
        #expect(MbFlyLog.journal.filter { $0.flight == f.id }.map(\.phase) == ["calm"])
    }

    /// Плитки нет на экране (вход не с плитки) — без полёта.
    @Test func noSourceOpensWithoutFlight() {
        let f = fly(still: false)
        var opened = 0
        f.launch(board: "other", genre: nil) { opened += 1 }
        #expect(opened == 1 && f.board == nil)
    }

    /// Полёт целиком: старт, полёт, посадка, гашение; шапка спрятана, пока клон летит, и видна после.
    @Test func flightRunsLaunchFlyLandGone() async {
        let f = fly(still: false)
        var opened = 0
        f.launch(board: "tpl", genre: "wedding") { opened += 1 }
        #expect(opened == 1, "папка открывается в момент старта, как у веба")
        #expect(f.board == "tpl" && f.hidesHero("tpl"))
        f.hero("tpl", CGRect(x: 24, y: 62, width: 58, height: 58))
        #expect(f.target == CGRect(x: 24, y: 62, width: 58, height: 58))
        f.hero("other", .zero)
        #expect(f.target != .zero, "чужая шапка цель не меняет")
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(f.board == nil && !f.hidesHero("tpl"))
        let phases = MbFlyLog.journal.filter { $0.flight == f.id }.map(\.phase).filter { $0 != "hero" }
        #expect(phases == ["launch", "fly", "land", "gone"], "\(phases)")
    }

    /// Анимация не кончилась (вкладка в фоне, экран сменился) — клон снимает подчистка через 0,9 с от старта; у веба
    /// такой клон оставался лежать поверх папки.
    @Test func stalledCloneIsSweptAtNinetyHundredths() async {
        let f = fly(still: false)
        f.animate = { _, body, _ in body() }   // анимация без конца
        let t0 = ProcessInfo.processInfo.systemUptime
        f.launch(board: "tpl", genre: nil) {}
        try? await Task.sleep(for: .milliseconds(800))
        #expect(f.board == "tpl", "до подчистки клон на месте")
        try? await Task.sleep(for: .milliseconds(250))
        #expect(f.board == nil, "клон не снят к 1,05 с")
        let mine = MbFlyLog.journal.filter { $0.flight == f.id }
        #expect(mine.map(\.phase).filter { $0 != "hero" } == ["launch", "fly", "sweep"])
        if let s = mine.last { #expect(abs(s.at - t0 - MbFlyTimeline.sweep) < 0.05, "подчистка на \(s.at - t0) с") }
    }

    /// Второй тап поверх идущего полёта: подчистка первого не снимает клон второго.
    @Test func newerFlightOwnsTheClone() async {
        let f = fly(still: false)
        f.animate = { _, body, _ in body() }
        f.sources["two"] = CGRect(x: 10, y: 10, width: 100, height: 100)
        f.launch(board: "tpl", genre: nil) {}
        try? await Task.sleep(for: .milliseconds(600))
        f.launch(board: "two", genre: nil) {}
        try? await Task.sleep(for: .milliseconds(400))
        #expect(f.board == "two", "таймер первого полёта (0,9 с) второй не трогает")
        try? await Task.sleep(for: .milliseconds(600))
        #expect(f.board == nil)
    }
}
