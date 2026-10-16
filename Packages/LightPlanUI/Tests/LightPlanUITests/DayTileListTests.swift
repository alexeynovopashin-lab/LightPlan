import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг 29.11в: плитка дня без ленты. Вид выбирает `DayTilePoints.of` — по числу точек на нити, а строки
/// списка читают слова `DayRowText`. Круг одной точки посреди пустой ленты больше не рисуется.
@MainActor
struct DayTileListTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
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

    private func app() -> AppModel {
        var snap = Snapshot()
        var st = Studio(id: "st1", name: "Томсон", latitude: 56.47, longitude: 84.97)
        st.halls = [Studio.Hall(id: "h1", name: "Эдисон")]
        snap.studios = [st]
        snap.practice = "ru"
        let now = ISO8601DateFormatter().date(from: "2026-10-15T12:15:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func shoot(_ route: [RoutePoint]) -> Session {
        var s = Session(id: "dt", kind: .shoot, day: CivilDate(year: 2026, month: 10, day: 15), start: 720, end: 750,
                        duration: 30, genre: .portrait)
        s.route = route
        return s
    }

    private let studioPoint = RoutePoint(start: 720, end: 750, name: "Фотостудия", placeText: "Томсон, зал Эдисон",
                                         studioId: "st1", hallId: "h1")
    private let walk = RoutePoint(start: 840, end: 900, name: "Прогулка", placeText: "Лагерный сад")
    private let prep = RoutePoint(start: 600, end: 660, name: "Сборы", placeText: "Дом невесты")

    private func list(_ p: DayTilePoints) -> [RoutePoint]? { if case .list(let r) = p { return r } else { return nil } }
    private func isLane(_ p: DayTilePoints) -> Bool { if case .lane = p { return true } else { return false } }

    // MARK: - Какой вид

    @Test func oneTimedPointIsAListNotALane() {
        let p = DayTilePoints.of(shoot([studioPoint]), golden: nil)
        #expect(list(p)?.map(\.name) == ["Фотостудия"], "одна точка без «Золотого» — строка списка")
        #expect(!isLane(p), "круг одной точки на пустой ленте не рисуется")
    }

    @Test func twoOrMoreTimedPointsKeepTheLane() {
        let two = DayTilePoints.of(shoot([studioPoint, walk]), golden: nil)
        #expect(isLane(two), "две точки — нить есть")
        let three = DayTilePoints.of(shoot([prep, studioPoint, walk]), golden: nil)
        #expect(isLane(three) && list(three) == nil)
        if case .lane(let r) = three { #expect(r.map(\.name) == ["Сборы", "Фотостудия", "Прогулка"], "лента получает те же точки, что и раньше") }
    }

    @Test func goldenIsAPointOnTheThread() {
        // Одна своя точка и «Золотой» рядом — две точки на нити: лента, как была.
        #expect(isLane(DayTilePoints.of(shoot([studioPoint]), golden: 1040)))
        // «Золотого» нет — список.
        #expect(!isLane(DayTilePoints.of(shoot([studioPoint]), golden: nil)))
    }

    @Test func noPointsMeansNothingUnderTheText() {
        #expect(DayTilePoints.of(shoot([]), golden: nil) == .none)
    }

    @Test func listHasOneRowPerPointTimedFirst() {
        let untimed = RoutePoint(start: nil, name: "Прогулка", placeText: "Лагерный сад")
        // Точка без часа стоит в списке после точки с часом, хоть записана раньше.
        let mixed = list(DayTilePoints.of(shoot([untimed, studioPoint]), golden: nil))
        #expect(mixed?.map(\.name) == ["Фотостудия", "Прогулка"])
        #expect(mixed?.map(\.start) == [720, nil])
        // Одни точки без часа — тоже строки (ленты на них не построить).
        let only = list(DayTilePoints.of(shoot([untimed, RoutePoint(start: nil, name: "Свет")]), golden: nil))
        #expect(only?.count == 2, "строк столько, сколько именованных точек")
        // Пустое имя — не точка.
        #expect(DayTilePoints.of(shoot([RoutePoint(start: nil, name: "")]), golden: nil) == .none)
    }

    @Test func nonShootHasNoRows() {
        var meet = shoot([studioPoint])
        meet.kind = .meet
        #expect(DayTilePoints.of(meet, golden: nil) == .none)
    }

    // MARK: - Слова строки

    @Test func rowSaysNameTimeAndPlace() {
        let a = app()
        let f = PlannerFacts(app: a, dark: true)
        let x = DayRowText(studioPoint, app: a, f: f)
        #expect(x.name == "Фотостудия" && x.time == "12:00" && x.place == "Томсон, зал Эдисон")
    }

    @Test func rowWithoutPlaceOrTimeStaysShort() {
        let a = app()
        let f = PlannerFacts(app: a, dark: true)
        let bare = DayRowText(RoutePoint(start: 720, end: 750, name: "Фотостудия"), app: a, f: f)
        #expect(bare.place.isEmpty, "без зала и адреса строки места нет")
        let untimed = DayRowText(RoutePoint(start: nil, name: "Прогулка", placeText: "Лагерный сад"), app: a, f: f)
        #expect(untimed.time == nil && untimed.place == "Лагерный сад")
    }

    @Test func studioPointWithoutTextNamesStudioAndHall() {
        let a = app()
        let f = PlannerFacts(app: a, dark: true)
        let p = RoutePoint(start: 720, end: 750, name: "Фотостудия", studioId: "st1", hallId: "h1")
        #expect(DayRowText(p, app: a, f: f).place == a.studioSpotName("st1", hallId: "h1"))
        #expect(DayRowText(p, app: a, f: f).place.contains("Эдисон"))
    }

    @Test func longNameIsKeptWhole() {
        let a = app()
        let long = "Свадебная фотосессия с родителями невесты и жениха на набережной"
        let x = DayRowText(RoutePoint(start: 720, name: long), app: a, f: PlannerFacts(app: a, dark: true))
        #expect(x.name == long, "перенос делает вид, слова не режутся")
    }
}
