import Testing
import Foundation
@testable import LightPlanUI
import LightPlanMapCanvas
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
                       locator: Locator = Locator(authorized: false), memory: PlaceMemory? = nil,
                       modes: (any AppModeMemory)? = nil) -> AppModel {
        AppModel(snapshot: snapshot, store: store, language: "ru", zone: barnaul, locator: locator,
                 geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather(), placeMemory: memory,
                 modeMemory: modes)
    }

    // MARK: - «Готово, когда»: смена доезжает до «Света» без перезапуска

    @Test func settingsReachLightScreenInPlace() {
        let app = model()
        let light = app.light
        let minute = light.timebar.machine.viewMinute
        let before = light.telemetry

        app.update { $0.mode = .astro; $0.tempUnit = .f; $0.clock = .h12; $0.ribbonMode = .lane; $0.timeStep = 30 }

        #expect(app.light === light)                        // экран тот же, не пересоздан
        #expect(light.timebar.machine.viewMinute == minute)  // выбранная минута на месте
        #expect(light.proMode)
        #expect(light.fahrenheit)
        #expect(light.clockPreference == .h12)
        #expect(light.timebar.machine.ribbonMode == .lane)
        let after = light.telemetry
        #expect(after.readout?.time != before.readout?.time)
        #expect(after.readout?.time.hasSuffix("M") == true)  // «12:22 PM»
        // Источник погоды молчит (`NoWeather`): настоящего прогноза нет, значит нет и градусов — выдумка не показывается (28ж).
        #expect(after.header.weather == nil && before.header.weather == nil)
        #expect(after.forecastNote != nil)
    }

    // MARK: - 19б: «Свет» открывается на «сейчас», в поясе из снимка

    /// Барнаул из настроек, «сейчас» — 13:00 по Барнаулу.
    private func barnaulAt13(zones: Bool) -> AppModel {
        var snap = Snapshot()
        snap.extra["me"] = .object(["city": .string("Барнаул"), "cityLat": .number(53.3548),
                                    "cityLon": .number(83.7698), "met": .bool(true)])
        if zones { snap.extra["zones"] = .object(["53.5,84.0": .string("Asia/Barnaul")]) }
        let now = ISO8601DateFormatter().date(from: "2026-09-23T13:00:00+07:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: barnaul, locator: Locator(authorized: false),
                        geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather(), now: { now })
    }

    /// До 19б машина времени вставала на солнечный полдень (12:17 в этот
    /// день), а не на нынешнюю минуту, как веб (найдено 19а).
    @Test func lightOpensAtNowNotAtSolarNoon() {
        let app = barnaulAt13(zones: true)
        #expect(app.light.timebar.machine.viewMinute == 780)
        #expect(app.light.telemetry.readout?.time == "13:00")
        #expect(app.light.timebar.nowButtonVisible == false)
    }

    /// Зоны, которые веб уже узнал, лежат в снимке (`zones`). Без них пояс
    /// Барнаула оценивается по долготе (+6), и «сейчас» выходит 12:00 — так
    /// приложение и открывалось до 19б (снимок пары: 12:17 против 13:00).
    @Test func savedZoneBeatsLongitudeEstimate() {
        #expect(barnaulAt13(zones: false).light.timebar.machine.viewMinute == 720)
        #expect(barnaulAt13(zones: true).light.timebar.machine.viewMinute == 780)
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

    /// Город настроек сильнее телефона, только пока слежение выключено (29.8в.12: слежение включено по
    /// умолчанию, и тогда место — телефон, `PlaceFollowTests.phoneBeatsHomeCityWhileFollowing`).
    @Test func settingsCityWinsOverDeviceWhenNotFollowing() {
        var snap = Snapshot()
        var s = AppSettings(snapshot: snap)
        s.takeCity(tomsk)
        s.apply(to: &snap)
        let locator = Locator(authorized: true, fix: .fix(phone))
        var rec = PlaceMemoryRecord()
        rec.following = false
        let app = model(snap, locator: locator, memory: InMemoryPlaceMemory(rec))
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
        first.update { $0.theme = .light; $0.mode = .astro }
        first.finishStart()
        await first.flush()

        let second = model(try await store.load(), store: store)
        #expect(!second.showStartSheet)
        #expect(second.settings.theme == .light)
        #expect(second.settings.mode == .astro)
        #expect(second.citySource == .settings)
        #expect(second.light.locationName == "Томск")
    }

    // MARK: - Три режима (30г.3)

    private func webFile(_ json: String) throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }

    @Test func newPersonStartsInSimpleAndScreensKnowIt() {
        let modes = InMemoryAppModeMemory()
        let app = model(modes: modes)
        #expect(app.settings.mode == .simple)
        #expect(!app.light.proMode)
        #expect(modes.mode == .simple)
    }

    /// Просто → Про → Астро → Просто: экраны читают прежнюю галочку, в «Про» и «Астро» она включена, память и снимок идут следом.
    @Test func cycleReachesScreensMemoryAndSnapshot() {
        let modes = InMemoryAppModeMemory()
        let app = model(modes: modes)
        for (mode, flag) in [(AppMode.pro, true), (.astro, true), (.simple, false), (.pro, true)] {
            app.update { $0.mode = mode }
            #expect(app.settings.mode == mode)
            #expect(app.settings.pro == flag)
            #expect(app.light.proMode == flag)
            #expect(modes.mode == mode)
            #expect(app.snapshot.appMode == mode.rawValue)
            #expect(app.snapshot.pro == flag)
        }
    }

    /// «Про» пока выглядит как «Астро» без «Терминов», «Азимутов» и «Луны» (30г.4–6; Звёзды, Млечный Путь — 30г.7): смена между
    /// ними не трогает ничего, что читают экраны. Минута — глубокая ночь, где термины есть на куполе и в «Подробно»; градусы есть всегда.
    @Test func proLooksLikeAstroWithoutTermsAndAzimuths() {
        let app = model()
        app.light.pick(day: CivilDate(year: 2026, month: 12, day: 21), minute: 60)
        app.update { $0.mode = .pro }
        let pro = app.light.telemetry
        app.update { $0.mode = .astro; $0.astro[.terms] = false; $0.astro[.azimuths] = false; $0.astro[.moon] = false }
        #expect(app.light.telemetry == pro)
        #expect(app.light.proMode)
        #expect(!app.light.azimuths && !app.light.moon)
        app.update { $0.astro[.terms] = true }
        #expect(app.light.telemetry != pro)
        app.update { $0.astro[.terms] = false; $0.astro[.azimuths] = true }
        #expect(app.light.telemetry != pro)
    }

    /// «Азимуты» доезжают до «Света» (а через него — до «Карты» и AR, они читают `light.azimuths`): в «Просто» и «Про» градусов нет,
    /// в «Астро» — по переключателю; выключенный переживает уход в «Про» и обратно.
    @Test func azimuthsReachTheScreensInThreeModes() {
        let app = model()
        let azimuth = app.lexicon.t("pro.azimuth")
        func sunRows() -> [String] {
            app.light.telemetry.proGroups.first { $0.title == app.lexicon.t("pro.sunNow") }?.rows.map(\.label) ?? []
        }
        for (mode, shown) in [(AppMode.simple, false), (.pro, false), (.astro, true)] {
            app.update { $0.mode = mode }
            #expect(app.light.azimuths == shown, "\(mode)")
            #expect(sunRows().contains(azimuth) == shown, "\(mode)")
        }
        app.update { $0.astro[.azimuths] = false }
        #expect(!app.light.azimuths)
        #expect(!sunRows().contains(azimuth))
        #expect(app.snapshot.astroOff == ["azimuths"])
        app.update { $0.mode = .pro }
        app.update { $0.mode = .astro }
        #expect(!app.light.azimuths)
        // Переключатель «Азимуты» в настройках не приглушён; с 30г.7 работают все пять.
        #expect(AstroSwitchRows.working == Set(AstroSwitch.allCases))
    }

    /// Старт с выключенными «Азимутами» из файла: экраны сразу без градусов, не только после правки.
    @Test func azimuthsOffFromFileOnStart() throws {
        let app = model(try webFile(#"{"pro":true,"appMode":"astro","astroOff":["azimuths"]}"#))
        #expect(app.settings.mode == .astro)
        #expect(!app.light.azimuths)
        #expect(app.light.terms)
    }

    /// Старт из файла (30г.6): «Луна» доезжает до экранов сразу, не только после правки — в «Астро» с ней и без неё.
    @Test func moonFromFileOnStart() throws {
        let on = model(try webFile(#"{"pro":true,"appMode":"astro"}"#))
        #expect(on.settings.mode == .astro && on.light.moon)
        let off = model(try webFile(#"{"pro":true,"appMode":"astro","astroOff":["moon"]}"#))
        #expect(!off.light.moon && off.light.azimuths)
        #expect(!model(try webFile(#"{"pro":true,"appMode":"pro"}"#)).light.moon)
    }

    // MARK: - Пять переключателей «Астро» (30г.4)

    /// «Термины» доезжают до «Света»: в «Просто» и «Про» их нет, в «Астро» — по переключателю; слово купола глубокой ночью.
    @Test func termsReachTheLightScreenInThreeModes() {
        let app = model()
        app.light.pick(day: CivilDate(year: 2026, month: 12, day: 21), minute: 60)
        let night = app.lexicon.t("sun.night.label"), term = app.lexicon.t("sun.astroNight.label")
        for (mode, terms) in [(AppMode.simple, false), (.pro, false), (.astro, true)] {
            app.update { $0.mode = mode }
            #expect(app.light.terms == terms, "\(mode)")
            #expect(app.light.telemetry.readout?.phase == (terms ? term : night), "\(mode)")
        }
        app.update { $0.astro[.terms] = false }
        #expect(!app.light.terms)
        #expect(app.light.telemetry.readout?.phase == night)
        // Выключенный в «Астро» переключатель не включает термины в «Про» и не сбрасывается сменой режима.
        app.update { $0.mode = .pro }
        app.update { $0.mode = .astro }
        #expect(!app.light.terms)
        #expect(app.settings.astro[.terms] == false)
    }

    /// Первый вход в «Астро» и старые данные «Астро»: все пять включены, и это сразу в памяти и в снимке.
    @Test func firstAstroAndOldAstroHaveAllFiveOn() throws {
        let fresh = InMemoryAppModeMemory()
        let app = model(modes: fresh)
        app.update { $0.mode = .astro }
        #expect(app.settings.astro == .allOn)
        #expect(app.light.terms)
        #expect(fresh.astro == .allOn)
        let old = InMemoryAppModeMemory()
        let was = model(try webFile(#"{"pro":true}"#), modes: old)
        #expect(was.settings.mode == .astro)
        #expect(was.settings.astro == .allOn)
        #expect(was.light.terms)
        #expect(old.astro == .allOn)
        #expect(was.snapshot.astroOff == [])
    }

    /// Выключили «Термины», веб пересохранил файл (ключа нет): переключатель остаётся выключенным, снимок сразу вровень.
    @Test func webFileDoesNotResetTheSwitches() throws {
        let phone = InMemoryAppModeMemory()
        let first = model(modes: phone)
        first.update { $0.mode = .astro; $0.astro[.terms] = false }
        #expect(phone.astro == AstroSwitches(off: [.terms]))
        #expect(first.snapshot.astroOff == ["terms"])
        let app = model(try webFile(#"{"pro":true}"#), modes: phone)
        #expect(app.settings.mode == .astro)
        #expect(app.settings.astro[.terms] == false)
        #expect(!app.light.terms)
        #expect(app.snapshot.astroOff == ["terms"])
    }

    @Test func oldFileStaysInItsModeAfterUpdate() throws {
        let astro = InMemoryAppModeMemory()
        #expect(model(try webFile(#"{"pro":true}"#), modes: astro).settings.mode == .astro)
        #expect(astro.mode == .astro)
        let simple = InMemoryAppModeMemory()
        #expect(model(try webFile(#"{"pro":false}"#), modes: simple).settings.mode == .simple)
        #expect(simple.mode == .simple)
    }

    /// Файл, пересохранённый вебом (ключа нет), не сбрасывает выбор: ни «Про» в «Астро», ни «Астро» в «Просто».
    @Test func webFileDoesNotResetTheChoice() throws {
        for (chosen, flag) in [(AppMode.pro, true), (.astro, false), (.simple, true), (.pro, false)] {
            let app = model(try webFile("{\"pro\":\(flag)}"), modes: InMemoryAppModeMemory(chosen))
            #expect(app.settings.mode == chosen, "выбрано \(chosen), галочка веба \(flag)")
            #expect(app.light.proMode == chosen.webPro)
            // Снимок сразу вровень: следующая запись вернёт файлу ключ и верную галочку.
            #expect(app.snapshot.appMode == chosen.rawValue)
            #expect(app.snapshot.pro == chosen.webPro)
        }
    }

    /// Весь путь через диск: выбрали «Про», веб пересохранил файл, запуск, ещё запись, новый телефон с этим файлом.
    @Test func proSurvivesWebResaveThroughTheStore() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-30g3-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir, debounce: .milliseconds(1))
        let phone = InMemoryAppModeMemory()
        let first = model(store: store, modes: phone)
        first.update { $0.mode = .pro }
        await first.flush()
        #expect(try await store.load().appMode == "pro")

        // Веб пишет только свои ключи (`saveAll`): галочка на месте, ключа нет.
        var fromWeb = try await store.load()
        fromWeb.appMode = nil
        try await store.saveNow(fromWeb)

        let second = model(try await store.load(), store: store, modes: phone)
        #expect(second.settings.mode == .pro)
        second.update { $0.theme = .light }
        await second.flush()
        #expect(try await store.load().appMode == "pro")

        // Новый телефон с файлом, где ключ снова есть: режим едет с файлом и встаёт в память.
        let otherPhone = InMemoryAppModeMemory(.astro)
        #expect(model(try await store.load(), modes: otherPhone).settings.mode == .pro)
        #expect(otherPhone.mode == .pro)

        // Цена § 4: файл без ключа на новом телефоне без памяти — «Астро», выбор сделают заново.
        try await store.saveNow(fromWeb)
        #expect(model(try await store.load(), modes: InMemoryAppModeMemory()).settings.mode == .astro)
    }

    /// Глава «Карта и места» (20б): подписи и холст — после перезапуска те же.
    @Test func mapLabelsAndCanvasSurviveRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-20b-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir, debounce: .milliseconds(1))
        let first = model(store: store)
        #expect(!first.mapLabels && first.mapSource == .mapLibre)
        first.setMapLabels(true)
        first.setMapSource(.mapKit)
        await first.flush()

        let second = model(try await store.load(), store: store)
        #expect(second.mapLabels)
        #expect(second.mapSource == .mapKit)
    }

    // MARK: - Запасная карта (28л.3)

    @Test func silentCartoFallsBackToApple() {
        let app = model()
        #expect(app.mapFallbackArmed && app.shownMapSource == .mapLibre)
        app.cartoWentSilent()
        #expect(app.shownMapSource == .mapKit && app.mapAutoApple && !app.mapFallbackArmed)
        #expect(app.mapSource == .mapLibre)
    }

    @Test func answeredCartoStaysAndIsNotWatchedAgain() {
        let app = model()
        app.cartoTileArrived()
        #expect(!app.mapFallbackArmed)
        app.cartoWentSilent()
        #expect(app.shownMapSource == .mapLibre && !app.mapAutoApple)
    }

    @Test func handPickedCanvasIsNeverOverridden() {
        let app = model()
        app.setMapSource(.mapLibre)   // сам выбрал «OpenStreetMap» — выбор есть, хоть он и совпал с умолчанием
        #expect(app.mapSourceChosen && !app.mapFallbackArmed)
        app.cartoWentSilent()
        #expect(app.shownMapSource == .mapLibre && !app.mapAutoApple)

        let apple = model()
        apple.setMapSource(.mapKit)
        #expect(!apple.mapFallbackArmed && apple.shownMapSource == .mapKit)
    }

    @Test func pickingAfterAutoFallbackWins() {
        let app = model()
        app.cartoWentSilent()
        app.setMapSource(.mapLibre)
        #expect(app.shownMapSource == .mapLibre)
    }

    @Test func autoFallbackIsNotSaved() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-28l3-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir, debounce: .milliseconds(1))
        let first = model(store: store)
        first.cartoWentSilent()
        first.setMapLabels(true)
        await first.flush()
        let second = model(try await store.load(), store: store)
        #expect(second.mapLabels && !second.mapAutoApple && second.mapFallbackArmed)
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
