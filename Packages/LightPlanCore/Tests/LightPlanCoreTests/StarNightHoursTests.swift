import Testing
import Foundation
@testable import LightPlanCore

/// 31.6в (Алексей 18.11: «1Б, но надо учитывать работу приложения во всех городах, местах»): часы ночи «Звёзд» без названного
/// времени — окно Млечного Пути, нет окна — темнота ниже −18°, не темнеет — пусто. Места и даты — из просьбы оркестратора.
struct StarNightHoursTests {

    static func place(_ lat: Double, _ lon: Double, _ zone: String) -> Place { Place(latitude: lat, longitude: lon, zone: ZoneID(zone)!) }
    static let tomsk = place(56.49, 84.95, "Asia/Tomsk"), moscow = place(55.75, 37.62, "Europe/Moscow")
    static let almaty = place(43.24, 76.89, "Asia/Almaty"), yerevan = place(40.18, 44.51, "Asia/Yerevan")
    static let petersburg = place(59.94, 30.31, "Europe/Moscow"), tromso = place(69.65, 18.96, "Europe/Oslo")
    static let quito = place(-0.18, -78.47, "America/Guayaquil"), sydney = place(-33.87, 151.21, "Australia/Sydney")
    static let kyiv = place(50.45, 30.52, "Europe/Kiev")
    static func day(_ y: Int, _ m: Int, _ d: Int) -> CivilDate { CivilDate(year: y, month: m, day: d) }

    /// Темнота ночи D — вечерний переход −18° D и утренний D+1, с точностью до двух минут (шаг поиска — минута).
    static func expectDarkMatchesTheSun(_ p: Place, _ d: CivilDate, _ name: String) throws {
        let dark = try #require(StarNightHours.dark(date: d, place: p), "\(name): темнота есть")
        let b = try #require(SolarDay(date: d, place: p).astroB), a = try #require(SolarDay(date: d.adding(days: 1), place: p).astroA)
        #expect(abs(dark.lowerBound - b) <= 2 && abs(dark.upperBound - (a + 1440)) <= 2, "\(name): \(dark) против \(b)…\(a + 1440)")
    }

    @Test("Томск и Москва зимой: окна нет (ядро ниже 10°), облака — часов темноты, ~12 ч")
    func winterNorthHasDarknessOnly() throws {
        for (p, n) in [(Self.tomsk, "Томск"), (Self.moscow, "Москва")] {
            let d = Self.day(2026, 12, 21)
            #expect(StarNightHours.milkyWay(date: d, place: p).isEmpty, "\(n): окна нет")
            try Self.expectDarkMatchesTheSun(p, d, n)
            let h = StarNightHours.hours(date: d, place: p)
            #expect(h == [StarNightHours.dark(date: d, place: p)!], "\(n)")
            #expect((12...12.6).contains((h[0].upperBound - h[0].lowerBound) / 60), "\(n): \(h)")
        }
    }

    @Test("Алматы и Ереван в июле (новолуние): окно Млечного Пути, сшитое через полночь, внутри темноты")
    func southSummerHasTheWindow() throws {
        let d = Self.day(2027, 7, 4)
        for (p, n) in [(Self.almaty, "Алматы"), (Self.yerevan, "Ереван")] {
            let w = StarNightHours.hours(date: d, place: p)
            let dark = try #require(StarNightHours.dark(date: d, place: p))
            #expect(w.count == 1, "\(n): одно окно через полночь — \(w)")
            #expect(w.allSatisfy { dark.contains($0.lowerBound) && dark.contains($0.upperBound) }, "\(n): окно внутри темноты")
            #expect(w[0].upperBound > 1440, "\(n): окно заходит за полночь")
            #expect(w[0].lowerBound > 1200, "\(n): утро самой D (хвост прошлой ночи) не берётся")
        }
    }

    @Test("Петербург в июне и Тромсё в июне (полярный день): не темнеет — часов нет, облака не придумываются")
    func whiteNightsHaveNoHours() {
        #expect(StarNightHours.hours(date: Self.day(2027, 6, 21), place: Self.petersburg).isEmpty)
        #expect(StarNightHours.hours(date: Self.day(2027, 6, 21), place: Self.tromso).isEmpty)
    }

    @Test("Тромсё в декабре (полярная ночь): темнота 16:56–06:28, 13,5 ч — как время «Звёзд» формы, не сутки")
    func polarNightIsNotTwentyFourHours() throws {
        let d = Self.day(2026, 12, 21)
        try Self.expectDarkMatchesTheSun(Self.tromso, d, "Тромсё")
        let h = try #require(StarNightHours.hours(date: d, place: Self.tromso).first)
        #expect((13...14).contains((h.upperBound - h.lowerBound) / 60), "\(h)")
    }

    @Test("Кито (экватор) и Сидней (юг): ночь через полночь; Сидней в декабре — без окна, темнота ~6 ч")
    func equatorAndSouth() throws {
        for (p, n) in [(Self.quito, "Кито"), (Self.sydney, "Сидней")] {
            let w = StarNightHours.hours(date: Self.day(2027, 7, 4), place: p)
            #expect(!w.isEmpty && w[0].upperBound > 1440, "\(n) 4.07: окно через полночь — \(w)")
            try Self.expectDarkMatchesTheSun(p, Self.day(2026, 12, 21), n)
        }
        #expect(StarNightHours.milkyWay(date: Self.day(2026, 12, 21), place: Self.sydney).isEmpty)
        let h = try #require(StarNightHours.hours(date: Self.day(2026, 12, 21), place: Self.sydney).first)
        #expect((5.5...6.5).contains((h.upperBound - h.lowerBound) / 60), "\(h)")
    }

    /// Темнота после полуночи: переход −18° у D лежит за полночью (или его нет), время «Звёзд» формы (`LightGoal`) его не
    /// берёт, а темно — Киев 27.05, Томск 29.04.
    @Test("темнота после полуночи считается: Киев 27.05 и Томск 29.04")
    func darknessAfterMidnightCounts() throws {
        for (p, d, n) in [(Self.kyiv, Self.day(2027, 5, 27), "Киев"), (Self.tomsk, Self.day(2027, 4, 29), "Томск")] {
            let b = SolarDay(date: d, place: p).astroB
            #expect(b == nil || b! >= 1440, "\(n): переход −18° у D после полуночи (\(String(describing: b))) — время «Звёзд» формы его не берёт")
            let h = try #require(StarNightHours.dark(date: d, place: p), "\(n)")
            #expect(h.lowerBound > 1440 && h.upperBound - h.lowerBound >= 30, "\(n): \(h)")
        }
    }

    @Test("солнце ниже −18° весь промежуток (у полюса зимой) — 12 часов вокруг самого низкого солнца")
    func alwaysDarkTakesTwelveHours() throws {
        let h = try #require(StarNightHours.dark(date: Self.day(2026, 12, 21), place: Self.place(89.9, 0, "UTC")))
        #expect(h.upperBound - h.lowerBound == 720)
    }
}
