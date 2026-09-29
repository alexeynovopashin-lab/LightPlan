import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 25, шаг 4: стопка карточек дня (веб `dayStack` + `renderStack`) —
/// кто в ней, в каком порядке, что пишет край и куда ведёт тап. Записи —
/// посев сезона (`Fixtures/shots/seed_planner.json`), телефон в Барнауле.
@MainActor
struct CardStackTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        struct Silent: Error {}
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer { throw Silent() }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func app(_ iso: String = "2026-09-23T13:00:00+07:00",
                     edit: (inout Snapshot) -> Void = { _ in }) -> AppModel {
        var snap = CardPhaseTests.seed
        edit(&snap)
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func rec(_ app: AppModel, _ id: String) -> Session { app.sessions.first { $0.id == id }! }
    private func ids(_ app: AppModel, _ id: String) -> [String] { app.stack(of: rec(app, id)).map(\.id) }

    /// Копия записи посева с другим id, днём и часами.
    private func copy(_ snap: Snapshot, _ id: String, as newId: String, day: CivilDate? = nil,
                      start: Int, end: Int, kind: RecordKind? = nil) -> Session {
        var s = snap.sessions.first { $0.id == id }!
        s.id = newId
        if let day { s.day = day }
        s.start = start
        s.end = end
        if let kind { s.kind = kind }
        return s
    }

    private static let sep26 = CivilDate(year: 2026, month: 9, day: 26)

    // MARK: - Кто в стопке

    /// 23.09: портрет «прямо сейчас» и встреча вечером. Встреча — край над
    /// портретом, портрет — над встречей; сама карточка в стопку не входит.
    @Test func neighboursOfTheDayWithoutTheCardItself() {
        let a = app()
        #expect(ids(a, "sd_sep_now") == ["sd_sep_meet"])
        #expect(ids(a, "sd_sep_meet") == ["sd_sep_now"])
        // Свадьба 24.09 — одна в своём дне: стопки нет.
        #expect(ids(a, "sd_sep_wed").isEmpty)
    }

    /// Порядок — по началу, ближний к листу край — последняя съёмка дня; при
    /// равном начале ближе та, что записана позже (веб `b.i − a.i`). Правило
    /// «свадьба первой» на стопку не влияет.
    @Test func orderIsLatestNearestTiesByLaterRecord() {
        let a = app { snap in
            snap.sessions.append(copy(snap, "sd_sep_wed", as: "t_wed", day: Self.sep26, start: 600, end: 700))
            snap.sessions.append(copy(snap, "sd_sep_clash_b", as: "t_late", start: 1080, end: 1140))
            snap.sessions.append(copy(snap, "sd_sep_clash_b", as: "t_tie", start: 900, end: 960))
        }
        // clash_b (15:00, индекс 12) и t_tie (15:00, записан последним) — t_tie ближе.
        #expect(ids(a, "sd_sep_clash_a") == ["t_late", "t_tie", "sd_sep_clash_b", "t_wed"])
    }

    /// Съёмка через полночь лежит в обоих днях (`partOfDay`): свадьба 25.09
    /// с 19:10 до 03:10 — край и у карточки 26-го.
    @Test func shootAcrossMidnightIsInTheNextDayStack() {
        let a = app { snap in
            snap.sessions.append(copy(snap, "sd_sep_wed", as: "t_night", day: Self.sep26.adding(days: -1),
                                      start: 1150, end: 1630))
        }
        #expect(ids(a, "sd_sep_clash_a").contains("t_night"))
        // Кончилась ровно в полночь — в следующий день не заходит.
        let b = app { snap in
            snap.sessions.append(copy(snap, "sd_sep_wed", as: "t_eve", day: Self.sep26.adding(days: -1),
                                      start: 1150, end: 1440))
        }
        #expect(!ids(b, "sd_sep_clash_a").contains("t_eve"))
    }

    /// Событие чужого календаря в стопке и при выключенном слое событий: веб
    /// берёт `onDay` без `shownRec`.
    @Test func calendarEventIsInTheStackEvenWithLayerOff() {
        let a = app { snap in
            snap.sessions.append(copy(snap, "sd_sep_clash_b", as: "t_ev", start: 600, end: 660, kind: .event))
        }
        #expect(!a.eventsLayer)   // слоя нет в посеве — выключен
        #expect(ids(a, "sd_sep_clash_a").contains("t_ev"))
    }

    // MARK: - Край

    /// 26.09: «Олег Дан» 14:00–15:30 и «Семья Ким» 15:00–16:30 — время
    /// соседа терракотой, имя клиента крупно, жанр словом.
    @Test func edgeOfOverlappingNeighbour() {
        let a = app()
        let x = PeekText(rec(a, "sd_sep_clash_b"), card: rec(a, "sd_sep_clash_a"), app: a)
        #expect(x.genre == "Семья")
        #expect(x.name == "Семья Ким")
        #expect(x.time == "15:00 – 16:30")
        #expect(x.over)
    }

    /// Встреча вечером у портрета днём: «Встреча», имена пары, без пересечения.
    @Test func edgeOfMeeting() {
        let a = app()
        let x = PeekText(rec(a, "sd_sep_meet"), card: rec(a, "sd_sep_now"), app: a)
        #expect(x.genre == "Встреча")
        #expect(x.time == "19:00 – 20:00")
        #expect(!x.over)
    }

    /// Встык — не пересечение: конец одной в начало другой (`<`, не `≤`).
    @Test func edgeTouchingIsNotOverlap() {
        let a = app { snap in
            snap.sessions.append(copy(snap, "sd_sep_clash_b", as: "t_next", start: 930, end: 990))
        }
        #expect(!PeekText(rec(a, "t_next"), card: rec(a, "sd_sep_clash_a"), app: a).over)
    }

    /// Через полночь (ревью GPT к 4224ce1): минуты соседа — на шкале дня
    /// карточки. Веб сравнивает `s.min` без дат — ошибка эталона, не переносим.
    @Test func edgeOverlapAcrossMidnightOnTheCardDayScale() {
        let a = app { snap in
            // 25.09 23:00 – 26.09 02:00.
            snap.sessions.append(copy(snap, "sd_sep_wed", as: "t_night", day: Self.sep26.adding(days: -1),
                                      start: 1380, end: 1560))
            // 26.09 00:30 – 01:30 — внутри ночной съёмки.
            snap.sessions.append(copy(snap, "sd_sep_clash_b", as: "t_small", start: 30, end: 90))
            // 26.09 23:10 – 23:50 — на минуты вчерашних 23:00 без даты похоже, но не пересекается.
            snap.sessions.append(copy(snap, "sd_sep_clash_b", as: "t_late", start: 1390, end: 1430))
        }
        #expect(PeekText(rec(a, "t_night"), card: rec(a, "t_small"), app: a).over)
        #expect(!PeekText(rec(a, "t_night"), card: rec(a, "t_late"), app: a).over)
    }

    // MARK: - Наложение в карточке (веб `renderClash`)

    /// 26.09 «Олег Дан» 14:00–15:30 и «Семья Ким» 15:00–16:30: в карточке —
    /// первое наложение словами формы, до и во время съёмки.
    @Test func clashLineBeforeAndDuring() {
        for iso in ["2026-09-26T12:00:00+07:00", "2026-09-26T14:30:00+07:00"] {
            let a = app(iso)
            let s = rec(a, "sd_sep_clash_a")
            let w = a.cardClash(s, phase: a.phase(of: s))
            #expect(w?.title == "Время пересекается")
            #expect(w?.message.contains("Семья Ким") == true)
        }
    }

    /// После съёмки молчит; у записи без наложений строки нет.
    @Test func clashLineSilentAfterAndAlone() {
        let a = app("2026-09-26T17:00:00+07:00")
        let s = rec(a, "sd_sep_clash_a")
        #expect(a.phase(of: s) == .after)
        #expect(a.cardClash(s, phase: .after) == nil)
        let b = app()
        let wed = rec(b, "sd_sep_wed")
        #expect(b.cardClash(wed, phase: b.phase(of: wed)) == nil)
    }

    /// Наложений два — «И ещё 1.» в конце (веб `card.clashMore`).
    @Test func clashLineCountsTheRest() {
        let a = app("2026-09-26T12:00:00+07:00") { snap in
            snap.sessions.append(copy(snap, "sd_sep_clash_b", as: "t_third", start: 870, end: 900))
        }
        let s = rec(a, "sd_sep_clash_a")
        #expect(a.cardClash(s, phase: .before)?.message.hasSuffix("И ещё 1.") == true)
    }

    // MARK: - Тап

    /// Тап по краю открывает соседа листом; прежняя карточка уходит в стопку.
    @Test func tapOnEdgeSwapsTheCard() {
        let a = app()
        a.openCard(id: "sd_sep_now")
        let next = a.stack(of: a.card!)[0]
        a.openCard(id: next.id)
        #expect(a.card?.id == "sd_sep_meet")
        #expect(a.stack(of: a.card!).map(\.id) == ["sd_sep_now"])
    }

    /// Геометрия краёв (веб `renderStack`): ступень ширины растёт до четвёртого.
    @Test func edgeInsetStopsGrowingAtTheFourth() {
        #expect((0...5).map { CardStack<EmptyView>.inset($0) } == [10, 20, 30, 40, 40, 40])
    }
}
