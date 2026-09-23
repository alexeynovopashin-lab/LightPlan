import Testing
import Foundation
@testable import LightPlanData
import LightPlanDomain
import LightPlanCore

/// Итерация 19а: настройки в снимке и город по умолчанию.
struct SettingsTests {

    // MARK: - Чтение по правилам веба

    @Test func emptySnapshotGivesWebDefaults() {
        let s = AppSettings(snapshot: Snapshot(), zone: TimeZone(identifier: "Asia/Barnaul")!)
        #expect(s.pro == false)
        #expect(s.theme == .dark)
        #expect(s.ribbonMode == .drum)
        #expect(s.drumSlot == .paper)
        #expect(s.timeStep == 5)
        #expect(s.travelMin == 40)
        #expect(s.tempUnit == .c)
        #expect(s.clock == .auto)
        #expect(s.currency == .rub)
        #expect(s.practice == .ru)          // Барнаул в списке российских поясов веба
        #expect(s.practicePicked == false)
        #expect(s.home.isEmpty)
    }

    @Test func strangeValuesFallBackLikeTheWeb() {
        var snap = Snapshot()
        snap.theme = "sepia"; snap.timeStep = 7; snap.travelMin = 0; snap.tempUnit = "k"
        snap.drumSlot = "glass"; snap.ribbonMode = "tape"; snap.clock = "36"
        let s = AppSettings(snapshot: snap)
        #expect(s.theme == .dark)
        #expect(s.timeStep == 5)
        #expect(s.travelMin == 40)          // `+saved.travelMin || 40`
        #expect(s.tempUnit == .c)
        #expect(s.drumSlot == .paper)
        #expect(s.ribbonMode == .drum)
        #expect(s.clock == .auto)
    }

    @Test func roundTripKeepsForeignKeysOfMe() {
        var snap = Snapshot()
        snap.extra["me"] = .object(["phone": .string("+7 900 000-00-00"), "met": .bool(true)])
        var s = AppSettings(snapshot: snap)
        s.pro = true; s.theme = .auto; s.drumSlot = .window; s.timeStep = 30; s.travelMin = 90
        s.tempUnit = .f; s.clock = .h12; s.currency = .eur; s.practice = .eu; s.practicePicked = true
        s.takeCity(CityHit(name: "томск", area: "Томская область, Россия", countryCode: "ru",
                           coordinate: GeoCoordinate(latitude: 56.4846, longitude: 84.9476)))
        s.apply(to: &snap)
        let back = AppSettings(snapshot: snap)
        #expect(back == s)
        #expect(back.home.name == "Томск")    // `cityCap`
        guard case .object(let me)? = snap.extra["me"] else { Issue.record("me пропал"); return }
        #expect(me["phone"] == .string("+7 900 000-00-00"))
        #expect(me["met"] == .bool(true))
        #expect(me["cityAt"] == .string("Томск"))
    }

    @Test func guessedPracticeIsNotWrittenAsAChoice() {
        var snap = Snapshot()
        AppSettings(snapshot: snap, zone: TimeZone(identifier: "Europe/Berlin")!).apply(to: &snap)
        #expect(snap.practice == nil)
        #expect(AppSettings(snapshot: snap, zone: TimeZone(identifier: "America/Chicago")!).practice == .us)
    }

    @Test func cityCountryMovesPracticeOnlyUntilPicked() {
        let madrid = CityHit(name: "Madrid", area: "España", countryCode: "es",
                             coordinate: GeoCoordinate(latitude: 40.4, longitude: -3.7))
        var guessed = AppSettings(snapshot: Snapshot(), zone: TimeZone(identifier: "Europe/Moscow")!)
        guessed.takeCity(madrid)
        #expect(guessed.practice == .eu)
        var picked = guessed
        picked.practice = .ru; picked.practicePicked = true
        picked.takeCity(madrid)
        #expect(picked.practice == .ru)
    }

    @Test func coordinatesOfAnotherNameAreIgnored() {
        var snap = Snapshot()
        snap.extra["me"] = .object(["city": .string("Барнаул"), "cityAt": .string("Томск"),
                                    "cityLat": .number(56.48), "cityLon": .number(84.95)])
        let home = AppSettings(snapshot: snap).home
        #expect(home.name == "Барнаул")
        #expect(home.coordinate == nil)
    }

    // MARK: - Город по умолчанию: три случая плана

    private let tomsk = GeoCoordinate(latitude: 56.4846, longitude: 84.9476)
    private let barnaulPhone = GeoCoordinate(latitude: 53.3481, longitude: 83.7798)
    private let barnaulZone = TimeZone(identifier: "Asia/Barnaul")!

    @Test func settingsCityWins() {
        let home = HomeCity(name: "Томск", coordinate: tomsk, countryCode: "ru")
        let r = DefaultCity.resolve(home: home, device: barnaulPhone, language: "ru", zone: barnaulZone)
        #expect(r.source == .settings)
        #expect(r.coordinate == tomsk)
        #expect(r.name == "Томск")
    }

    @Test func deviceWhenNoCityButAccessGiven() {
        // Город набран руками, координат нет — он не в счёт.
        let r = DefaultCity.resolve(home: HomeCity(name: "Томск"), device: barnaulPhone,
                                    language: "ru", zone: barnaulZone)
        #expect(r.source == .device)
        #expect(r.coordinate == barnaulPhone)
    }

    @Test func capitalWhenNoCityAndNoAccess() {
        let r = DefaultCity.resolve(home: HomeCity(), device: nil, language: "ru", zone: barnaulZone)
        #expect(r.source == .capital)
        #expect(r.name == "Москва")
    }

    // MARK: - Столица по поясу: примеры Алексея

    /// Январь: без летнего времени, смещения стоят ровно как в примерах.
    private let winter = Date(timeIntervalSince1970: 1_768_000_000)

    @Test(arguments: [
        ("es", "Europe/Athens", "Madrid"),            // «в GMT+2 поставим Мадрид»
        ("es", "America/Chicago", "Mexico City"),     // «для UTC-6 Мехико»
        ("en-GB", "Europe/London", "London"),
        ("en-US", "America/Los_Angeles", "Washington"),
        ("en", "Asia/Tokyo", "Canberra"),
        ("ru", "Asia/Barnaul", "Moscow"),              // не Бишкек: русский там второй язык
        ("ru", "Europe/Kaliningrad", "Moscow"),        // +2: Москва и Минск на +3, ничья — Москва
        ("ja", "Europe/Paris", "Tokyo"),
        ("zh-Hans", "Asia/Shanghai", "Beijing"),
        ("pt-BR", "America/Sao_Paulo", "Washington"),  // незнакомый язык — английский
    ])
    func capitalByZone(language: String, zone: String, expected: String) {
        let base = String(language.prefix { $0 != "-" }).lowercased()
        let c = DefaultCity.capital(language: base, zone: TimeZone(identifier: zone)!, now: winter)
        #expect(c.name(in: "en") == expected)
    }
}
