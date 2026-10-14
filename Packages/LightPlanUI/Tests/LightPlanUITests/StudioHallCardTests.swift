import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг 29.11, пп. 5–6: студия и зал в строке места карточки; прошедшая точка
/// не «скоро». Часы — пустышка: момент задаётся строкой; студия в Томске
/// (по долготе без известного пояса — UTC+6), по нему и идут часы съёмки.
@MainActor
struct StudioHallCardTests {

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

    private let day = CivilDate(year: 2026, month: 9, day: 21)

    private func studio(halls: Bool = true) -> Studio {
        var st = Studio(id: "st1", name: "Томсон", latitude: 56.47, longitude: 84.97)
        if halls { st.halls = [Studio.Hall(id: "h1", name: "Эдисон"), Studio.Hall(id: "h2", name: "Тесла")] }
        return st
    }

    private func app(_ iso: String, session: Session, studios: [Studio]) -> AppModel {
        var snap = Snapshot()
        snap.sessions = [session]
        snap.studios = studios
        snap.practice = "ru"
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    /// Съёмка 15:15–16:15 с точкой «Фотостудия» в студии `st1`.
    private func shoot(hall: String?, point: (Int, Int)) -> Session {
        var s = Session(id: "p", kind: .shoot, day: day, start: 915, end: 975, duration: 60, genre: .portrait)
        s.studioId = "st1"; s.hallId = hall; s.place = "Томсон"
        s.route = [RoutePoint(start: point.0, end: point.1, name: "Фотостудия", placeText: "Томсон",
                              studioId: "st1", hallId: hall)]
        return s
    }

    private func placeTitle(_ a: AppModel) -> String? {
        let s = a.sessions[0]
        // Слово «Фотостудия» и имя склеены неразрывным пробелом.
        return a.cardPanes(s, phase: a.phase(of: s)).first { $0.kind == .place }?.title?
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: - Пункт 5

    @Test func placePaneNamesTheHallAsSecondWord() {
        let a = app("2026-09-21T10:00:00+06:00", session: shoot(hall: "h1", point: (915, 975)), studios: [studio()])
        #expect(placeTitle(a) == "Фотостудия Томсон. Зал Эдисон")
    }

    @Test func placePaneWithoutHallStaysStudioOnly() {
        let a = app("2026-09-21T10:00:00+06:00", session: shoot(hall: nil, point: (915, 975)), studios: [studio()])
        #expect(placeTitle(a) == "Фотостудия Томсон")
        // Зал, которого в студии уже нет, молчит, а не печатается пустым.
        let b = app("2026-09-21T10:00:00+06:00", session: shoot(hall: "gone", point: (915, 975)), studios: [studio()])
        #expect(placeTitle(b) == "Фотостудия Томсон")
    }

    // MARK: - Пункт 6

    private func tile(_ a: AppModel) -> DayTileText {
        let s = a.sessions[0]
        return DayTileText(s, phase: a.phase(of: s), app: a)
    }

    @Test func finishedPointBeforeTheShootShowsThePlanNotSoon() {
        // Точка 14:15–14:40, съёмка 15:15; сейчас 14:43 — точка кончилась, съёмка не началась.
        let a = app("2026-09-21T14:43:00+06:00", session: shoot(hall: nil, point: (855, 880)), studios: [studio()])
        let t = tile(a)
        #expect(!t.now.contains("Скоро"), "было «Скоро: Фотостудия» с отрицательным остатком")
        #expect(!t.now.contains("Сейчас"), "кончившаяся точка — не «Сейчас» (ревью GPT к f10a1e5)")
        #expect(!t.plainLeft.contains("через") && !t.plainLeft.contains("−"))
        #expect(t.now.contains("14:15") && t.now.contains("14:40"), "план дня: «14:15 – 14:40»")
    }

    @Test func runningPointBeforeTheShootIsNow() {
        // Точка 14:15–15:00, сейчас 14:43 — точка идёт.
        let a = app("2026-09-21T14:43:00+06:00", session: shoot(hall: nil, point: (855, 900)), studios: [studio()])
        let t = tile(a)
        #expect(t.now.replacingOccurrences(of: "\u{00A0}", with: " ") == "Сейчас: Фотостудия")
        #expect(!t.plainLeft.contains("через"))
    }

    @Test func futurePointIsStillSoon() {
        let a = app("2026-09-21T14:43:00+06:00", session: shoot(hall: nil, point: (915, 975)), studios: [studio()])
        let t = tile(a)
        #expect(t.now.replacingOccurrences(of: "\u{00A0}", with: " ") == "Скоро: Фотостудия")
        #expect(t.plainLeft.hasPrefix("через 32 мин"))
    }
}
