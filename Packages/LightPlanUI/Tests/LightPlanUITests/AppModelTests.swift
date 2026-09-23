import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanTimeline

/// Итерация 19а: настройки доезжают до «Света» без перезапуска, город по
/// умолчанию, язык из iOS, знакомство один раз.
@MainActor
struct AppModelTests {

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

    private final class Locator: DeviceLocating {
        let authorized: Bool
        let fix: DeviceFix
        private(set) var asked = 0
        init(authorized: Bool, fix: DeviceFix = .unavailable) { self.authorized = authorized; self.fix = fix }
        var isAlreadyAuthorized: Bool { authorized }
        func currentFix() async -> DeviceFix { asked += 1; return fix }
    }

    private let barnaul = TimeZone(identifier: "Asia/Barnaul")!
    private let phone = GeoCoordinate(latitude: 53.3481, longitude: 83.7798)
    private let tomsk = CityHit(name: "Томск", area: "Томская область, Россия", countryCode: "ru",
                                coordinate: GeoCoordinate(latitude: 56.4846, longitude: 84.9476))

    private func model(_ snapshot: Snapshot = Snapshot(), store: Store? = nil,
                       locator: Locator = Locator(authorized: false)) -> AppModel {
        AppModel(snapshot: snapshot, store: store, language: "ru", zone: barnaul, locator: locator,
                 geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
    }

    // MARK: - «Готово, когда»: смена доезжает до «Света» без перезапуска

    @Test func settingsReachLightScreenInPlace() {
        let app = model()
        let light = app.light
        let minute = light.timebar.machine.viewMinute
        let before = light.telemetry

        app.update { $0.pro = true; $0.tempUnit = .f; $0.clock = .h12; $0.ribbonMode = .lane; $0.timeStep = 30 }

        #expect(app.light === light)                        // экран тот же, не пересоздан
        #expect(light.timebar.machine.viewMinute == minute)  // выбранная минута на месте
        #expect(light.proMode)
        #expect(light.fahrenheit)
        #expect(light.clockPreference == .h12)
        #expect(light.timebar.machine.ribbonMode == .lane)
        let after = light.telemetry
        #expect(after.readout?.time != before.readout?.time)
        #expect(after.readout?.time.hasSuffix("M") == true)  // «12:22 PM»
        #expect(after.header.temperature != before.header.temperature)
    }

    // MARK: - Город по умолчанию на старте

    @Test func capitalWhenNoCityAndNoAccess() {
        let locator = Locator(authorized: false, fix: .fix(phone))
        let app = model(locator: locator)
        #expect(app.citySource == .capital)
        #expect(app.light.locationName == "Москва")
        #expect(app.light.timebar.place.zone.identifier == "Europe/Moscow")
        #expect(locator.asked == 0)                          // разрешения не спрашивали
    }

    @Test func deviceWhenAccessAlreadyGiven() async {
        let app = model(locator: Locator(authorized: true, fix: .fix(phone)))
        for _ in 0..<50 where app.citySource != .device { await Task.yield() }
        #expect(app.citySource == .device)
        #expect(app.place.coordinate == phone)
    }

    @Test func settingsCityWinsOverDevice() {
        var snap = Snapshot()
        var s = AppSettings(snapshot: snap)
        s.takeCity(tomsk)
        s.apply(to: &snap)
        let locator = Locator(authorized: true, fix: .fix(phone))
        let app = model(snap, locator: locator)
        #expect(app.citySource == .settings)
        #expect(app.light.locationName == "Томск")
        #expect(app.place.coordinate == tomsk.coordinate)
        #expect(locator.asked == 0)
    }

    // MARK: - Город из настроек двигает свет, набранное имя — нет

    @Test func pickedCityMovesLightTypedNameDoesNot() async {
        let app = model()
        let start = app.place.coordinate
        app.typeCity("Томск")
        #expect(app.place.coordinate == start)
        app.takeCity(tomsk)
        #expect(app.place.coordinate == tomsk.coordinate)
        for _ in 0..<50 where app.light.timebar.place.latitude != tomsk.coordinate.latitude { await Task.yield() }
        #expect(app.light.timebar.place.latitude == tomsk.coordinate.latitude)
        #expect(app.light.locationName == "Томск")
        #expect(app.settings.practice == .ru)
    }

    private struct TomskGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: "Томск", region: "Томская область", country: "Россия", zoneIdentifier: "Asia/Tomsk")
        }
    }

    /// Оценка по долготе даёт Томску +6; настоящий пояс +7 приходит с именем
    /// от геокодера и обязан доехать до таймбара — иначе восход и закат
    /// стоят на час раньше (замечено на симуляторе, 23 сентября 2026).
    @Test func realZoneFromGeocoderReachesTimebar() async {
        let app = AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: barnaul,
                           locator: Locator(authorized: false), geocoder: TomskGeocoder(),
                           cityLookup: NoCities(), weatherSource: NoWeather())
        app.takeCity(tomsk)
        await app.place.settled()
        for _ in 0..<100 where app.light.timebar.place.zone.identifier != "Asia/Tomsk" { await Task.yield() }
        #expect(app.place.zone.identifier == "Asia/Tomsk")
        #expect(app.light.timebar.place.zone.identifier == "Asia/Tomsk")
        #expect(app.light.weather.place.zone.identifier == "Asia/Tomsk")
        // Сутки — Томска в его поясе, а не столицы, с которой приложение стартовало.
        let expected = SolarDay(date: app.light.timebar.machine.selectedDate, place: app.place.place)
        #expect(app.light.timebar.solarDay.rise == expected.rise)
        #expect(app.light.timebar.solarDay.set == expected.set)
    }

    // MARK: - Знакомство один раз, настройки переживают перезапуск

    @Test func startSheetOnceAndSettingsSurviveRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-19a-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir, debounce: .milliseconds(1))
        let first = model(store: store)
        #expect(first.showStartSheet)
        first.takeCity(tomsk)
        first.update { $0.theme = .light; $0.pro = true }
        first.finishStart()
        await first.flush()

        let second = model(try await store.load(), store: store)
        #expect(!second.showStartSheet)
        #expect(second.settings.theme == .light)
        #expect(second.settings.pro)
        #expect(second.citySource == .settings)
        #expect(second.light.locationName == "Томск")
    }

    // MARK: - Язык из iOS

    @Test(arguments: [
        ("ru-RU", "RU", "ru"),
        ("ru", nil, "ru"),
        ("en-US", "US", "en-US"),
        ("en-GB", "GB", "en-GB"),
        ("en", "RU", "en-GB"),        // говор по региону телефона, а не по языку
        ("en-GB", "US", "en-US"),
        ("es-MX", "MX", "es"),
        ("zh-Hans-CN", "CN", "zh"),
        ("ja-JP", "JP", "ja"),
        ("de-DE", "DE", "en-GB"),      // языка нет в словаре — английский
    ] as [(String, String?, String)])
    func languageFromIOS(preferred: String, region: String?, expected: String) {
        #expect(AppLanguage.code(preferred: preferred, region: region) == expected)
    }
}
