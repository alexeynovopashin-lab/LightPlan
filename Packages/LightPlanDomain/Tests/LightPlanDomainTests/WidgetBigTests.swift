import Testing
import Foundation
import LightPlanCore
@testable import LightPlanDomain

/// 30и.13: правила большого виджета (Б2) — слова оценки, призрак светила, запасные слова.
struct WidgetBigTests {
    @Test func scoreWordsFollowTheThresholdsOfTheLightScreen() {
        let w = WidgetFeed.Words()
        #expect(BigWidget.scoreWord(75, w) == "красивый" && BigWidget.scoreWord(74, w) == "с цветом")
        #expect(BigWidget.scoreWord(50, w) == "с цветом" && BigWidget.scoreWord(49, w) == "спокойный")
        #expect(BigWidget.scoreWord(28, w) == "спокойный" && BigWidget.scoreWord(27, w) == "серый")
        #expect(BigWidget.scoreLine(34, w) == "спокойный · 34 / 100")
        #expect(BigWidget.scoreLine(nil, w) == nil, "оценки нет — строки нет, числа не выдумываются")
    }

    @Test func theAppsWordWinsOverTheFallback() {
        var w = WidgetFeed.Words()
        w.table["score.calm"] = "calm"
        #expect(BigWidget.scoreWord(30, w) == "calm")
        #expect(BigWidget.phaseWord(.astroNight, w) == "НОЧЬ" && BigWidget.phaseWord(.evening, w) == "ВЕЧЕРЕЕТ")
    }

    @Test func aBodyBelowTheHorizonIsAGhostNotAGapAndFadesDeep() {
        #expect(BigWidget.ghostOpacity(elevation: 5) == 0, "над горизонтом призрака нет")
        #expect(BigWidget.ghostOpacity(elevation: -3) == 1, "на −3° пятно в полную плотность (как `DomeGeometry.deepOf`)")
        #expect(BigWidget.ghostOpacity(elevation: -1.5) == 0.5, "на полпути гаснущего диска — половина")
        #expect(abs(BigWidget.ghostOpacity(elevation: -30) - 2.0 / 3.0) < 1e-9, "глубокой ночью не ниже пола 2/3")
    }
    // MARK: Три вида большого (30и.14)

    private static let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private static func tsk(_ h: Int, _ m: Int = 0, day d: Int = 24) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private static func shoot(_ id: String, _ from: Date, _ to: Date, stops: [WidgetFeed.Stop] = []) -> WidgetFeed.Shoot {
        .init(id: id, start: Moment(from).milliseconds, end: Moment(to).milliseconds, title: "Свадьба", stops: stops, genre: "wedding", names: "Анна+Игорь")
    }
    private static func stop(_ at: Date, _ name: String) -> WidgetFeed.Stop { .init(at: Moment(at).milliseconds, name: name, place: "", sign: "feast") }

    @Test func theThreeStatesFollowTheShootAndItsRoute() {
        let route = [Self.stop(Self.tsk(12), "Пара в студии"), Self.stop(Self.tsk(14), "Обед")]
        let wedding = Self.shoot("w", Self.tsk(12), Self.tsk(0, 30, day: 25), stops: route)
        let photo = Self.shoot("p", Self.tsk(16), Self.tsk(18))
        func state(_ shoots: [WidgetFeed.Shoot], at now: Date) -> BigWidget.State { BigWidget.state(WidgetFeed(place: Self.tomsk, shoots: shoots).frame(at: now)) }
        #expect(state([], at: Self.tsk(14)) == .idle, "съёмок нет")
        #expect(state([wedding], at: Self.tsk(9)) == .idle, "съёмка сегодня впереди — съёмка не идёт")
        #expect(state([wedding], at: Self.tsk(13)) == .route, "идёт, маршрут есть")
        #expect(state([photo], at: Self.tsk(17)) == .photo, "идёт, маршрута нет")
        #expect(state([wedding], at: Self.tsk(1, day: 25)) == .idle, "кончилась")
        // Сломанная свадьба Алексея 16.11: 00:00–00:35, точки с 08:00 — съёмка идёт, маршрут всё равно есть.
        let broken = Self.shoot("b", Self.tsk(0), Self.tsk(0, 35), stops: [Self.stop(Self.tsk(8), "Сборы"), Self.stop(Self.tsk(10), "Выезд")])
        #expect(state([broken], at: Self.tsk(0, 10)) == .route)
    }

    @Test func theRouteWindowKeepsOnePastPointAboveTheCurrentOne() {
        #expect(BigWidget.routeWindow(count: 6, current: 0, rows: 6) == 0..<6, "помещается всё")
        #expect(BigWidget.routeWindow(count: 6, current: 1, rows: 4) == 0..<4, "одна прошедшая сверху, дальше — будущие")
        #expect(BigWidget.routeWindow(count: 6, current: 3, rows: 4) == 2..<6)
        #expect(BigWidget.routeWindow(count: 6, current: 5, rows: 4) == 2..<6, "последняя точка: окно не выходит за список")
        #expect(BigWidget.routeWindow(count: 6, current: nil, rows: 4) == 0..<4, "первая точка впереди — с начала")
        #expect(BigWidget.routeWindow(count: 2, current: 1, rows: 6) == 0..<2)
        #expect(BigWidget.routeWindow(count: 0, current: nil, rows: 6).isEmpty)
    }
}
