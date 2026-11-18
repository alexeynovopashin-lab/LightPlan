import Testing
import Foundation
@testable import LightPlanCore

/// 31.6 «Рассвет — остальные места» (Алексей 18.11: «закаты и рассветы равнозначны по значению»), ядро. Томск 18.11.2026 (+7).
/// Только API, что было и на `c7b1256b`: на старом коде набор падает проверками, не сборкой. Новое API — в `DawnRestCoreNewTests`.
struct DawnRestCoreTests {

    static let tomsk = Place(latitude: 56.49, longitude: 84.95, zone: ZoneID(fixedOffsetHours: 7))
    static let date = CivilDate(year: 2026, month: 11, day: 18)
    static var sun: SolarDay { SolarDay(date: date, place: tomsk) }

    /// П. 18: утренний синий час — «Синий час, ещё», вечерний золотой — «Золотой час, ещё»; на `c7b1256b` — «До рассвета» и «До заката».
    @Test("«что дальше»: утром синий час и золотой, вечером золотой и синий — по границам «Подробно»")
    func nextLightLadderIsSymmetric() throws {
        let s = Self.sun
        let civilA = try #require(s.civilA), blueA = try #require(s.blueA), goldenA = try #require(s.goldenA)
        let goldenB = try #require(s.goldenB), blueB = try #require(s.blueB), civilB = try #require(s.civilB)
        func at(_ t: Minutes) -> NextLight { s.nextLight(at: t) }
        // Ночь — до утреннего синего часа (−6°).
        #expect(at(civilA - 30).key.rawValue == "toBlue")
        #expect(at(civilA - 30).minutes == 30)
        // Утренний синий час (−6°…−4°): «Синий час, ещё» до −4°.
        #expect(at(civilA + 5) == NextLight(key: .blueLeft, minutes: blueA - civilA - 5))
        // Утренний золотой час (−4°…+6°) — с −4°, ещё до восхода: «Золотой час, ещё» до +6°.
        #expect(at(blueA + 5) == NextLight(key: .goldenLeft, minutes: goldenA - blueA - 5))
        // День — до вечернего золотого часа.
        #expect(at(720) == NextLight(key: .toGolden, minutes: goldenB - 720))
        // Вечерний золотой час (+6°…−4°): «Золотой час, ещё» до −4°, и до заката, и после.
        #expect(at(goldenB + 5) == NextLight(key: .goldenLeft, minutes: blueB - goldenB - 5))
        #expect(at(try #require(s.set) + 5).key == .goldenLeft)
        // Вечерний синий час (−4°…−6°).
        #expect(at(blueB + 5) == NextLight(key: .blueLeft, minutes: civilB - blueB - 5))
        // Ночь после вечера — до утреннего синего часа (эти сутки + 24 ч).
        #expect(at(civilB + 10).key.rawValue == "toBlue")
        #expect(at(civilB + 10).minutes == civilA + 1440 - civilB - 10)
    }

    /// Веб-порт остаётся для сверки: тот же день, слова веба.
    @Test("сверка с вебом не тронута: веб утром до восхода говорит «До рассвета», вечером до заката — «До заката»")
    func webLadderIsKept() throws {
        let s = Self.sun
        let civilA = try #require(s.civilA), goldenB = try #require(s.goldenB)
        #expect(s.webNextLight(at: civilA + 5).key == .toDawn)
        #expect(s.webNextLight(at: goldenB + 5).key == .toSunset)
    }

    /// Зимой за полярным кругом солнце не поднимается до +6°: золотой час — весь день от −4° до −4°.
    @Test("нет +6° за день — золотой час весь день, без «До золотого часа»")
    func noSixDegreesIsAGoldenDay() throws {
        let s = SolarDay(date: CivilDate(year: 2026, month: 12, day: 10), place: Place(latitude: 66.0, longitude: 25.7, zone: ZoneID(fixedOffsetHours: 2)))
        #expect(s.polar == .normal && s.goldenA == nil && s.goldenB == nil)
        let blueA = try #require(s.blueA), blueB = try #require(s.blueB)
        #expect(s.nextLight(at: s.solarNoon) == NextLight(key: .goldenLeft, minutes: blueB - s.solarNoon))
        #expect(s.nextLight(at: blueA - 1).key == .blueLeft)
    }

    /// П. 17: после восхода до конца утреннего золотого часа AR пишет «после рассвета N», не «до заката N».
    @Test("AR: сразу после восхода строка — не «до заката»")
    func arAfterSunriseIsNotUntilSunset() throws {
        let s = Self.sun
        let rise = try #require(s.rise), set = try #require(s.set)
        #expect(SunTrack.note(at: rise + 20, solar: s) != .untilSunset(set - rise - 20))
        // После утреннего золотого часа — до заката, как было.
        let after = try #require(s.goldenA) + 10
        #expect(SunTrack.note(at: after, solar: s) == .untilSunset(set - after))
    }
}
