import Testing
import Foundation
@testable import LightPlanUI
import LightPlanData
import LightPlanCore
import LightPlanDomain

/// Тестовый засев копии ветки (Алексей, 29.09): лежит в пакете и читается как снимок.
struct TestSeedTests {
    @Test func seedDecodesAsSnapshot() throws {
        let snap = try #require(TestSeed.snapshot())
        #expect(snap.sessions.count == 24)
        #expect(snap.sessions.contains { $0.id == "sd_sep_inter" })
    }
}

/// Запись «сегодня» тестового засева (27): маршрут и «Референсы» открыты в любое время суток,
/// а не только пока свадьба идёт по записанным рамкам.
@MainActor
struct TestSeedTodayTests {
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

    /// Засев, перенесённый на 29.09 по Томску; часы приложения — `iso`.
    private func app(_ iso: String) throws -> AppModel {
        let launch = ISO8601DateFormatter().date(from: "2026-09-29T12:00:00+07:00")!
        let snap = try #require(TestSeed.snapshot(now: launch))
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Tomsk")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    /// (фаза, есть ли «Маршрут», есть ли «Референсы») записи `sd_today_wed` в момент `iso`.
    private func look(_ iso: String) throws -> (EventPhase, Bool, Bool) {
        let a = try app(iso)
        let s = try #require(a.sessions.first { $0.id == "sd_today_wed" })
        let ph = a.phase(of: s)
        let shown = a.cardBlocks(s, phase: ph)
        return (ph, shown.contains(.route), shown.contains(.refs))
    }

    @Test func routeAndRefsOpenAtAnyTimeOfDay() throws {
        for t in ["00:30", "07:00", "12:00", "21:00", "22:12", "23:59"] {
            let (ph, route, refs) = try look("2026-09-29T\(t):00+07:00")
            #expect(route, "маршрут скрыт в \(t), фаза \(ph)")
            #expect(refs, "«Референсы» скрыты в \(t), фаза \(ph)")
        }
    }

    /// «Заполнить»: в форме столько же строк, сколько точек в записи. Веб (`loadRoute`) ставит
    /// первой строкой место записи, если оно не начало первой точки, — засев держит их согласованными.
    @Test func fillFormShowsExactlyTheRoutePoints() throws {
        let snap = try #require(TestSeed.snapshot())
        let s = try #require(snap.sessions.first { $0.id == "sd_today_wed" })
        #expect(s.route.count == 12)
        #expect(EventForm.editing(s).route.count == s.route.count)
    }
}
