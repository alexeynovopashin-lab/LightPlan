import Foundation
import Observation
import LightPlanCore
import LightPlanData
import LightPlanTimeline

/// Хозяин приложения (итерация 19а): снимок на диске, настройки, место и
/// экран «Свет». Настройки меняются здесь и отсюда же доезжают до «Света»
/// присвоением — без пересоздания экрана и без перезапуска.
@MainActor
@Observable
public final class AppModel {

    public private(set) var settings: AppSettings
    /// Код словаря этого запуска — из iOS (`AppLanguage`).
    public let language: String
    public let lexicon: Lexicon
    public let place: CurrentPlace
    public let light: LightScreenModel
    /// Откуда взят город, по которому живёт «Свет» после запуска.
    public private(set) var citySource: DefaultCity.Source
    /// Лист «Откуда вы работаете» — первый запуск, пока знакомство не пройдено.
    public var showStartSheet: Bool

    public let cityLookup: any CityLookup
    /// Записей в снимке — для строки «Карта и места» (сохранённые точки).
    public var spotCount: Int { snapshot.spots.count }

    private var snapshot: Snapshot
    private let store: Store?
    private let locator: any DeviceLocating

    init(snapshot: Snapshot, store: Store?, language: String, zone: TimeZone = .current,
         locator: any DeviceLocating, geocoder: any ReverseGeocoding, cityLookup: any CityLookup,
         weatherSource: any WeatherSource) {
        self.snapshot = snapshot
        self.store = store
        self.language = language
        self.lexicon = Lexicon(language)
        self.locator = locator
        self.cityLookup = cityLookup
        let settings = AppSettings(snapshot: snapshot, zone: zone)
        self.settings = settings
        self.showStartSheet = !Self.met(snapshot)

        // Город по умолчанию. Место, выбранное руками в прошлый раз
        // (`loc` веба), на старте не читается: выбор руками живёт до
        // перезагрузки (решение 19 сентября).
        let resolved = DefaultCity.resolve(home: settings.home, device: nil, language: language, zone: zone)
        var zones = ZoneCache()
        if resolved.source == .capital {
            let cap = DefaultCity.capital(language: Lexicon.base(language), zone: zone)
            if let z = ZoneID(cap.zone) { zones.remember(z, at: cap.coordinate) }
        }
        let place = CurrentPlace(initial: resolved.coordinate,
                                 name: resolved.name.map { PlaceName(city: $0, sub: "") },
                                 zones: zones, namer: PlaceNamer(geocoder: geocoder), locator: locator)
        self.place = place
        self.citySource = resolved.source

        let weather = WeatherStore(place: place.place, source: weatherSource)
        let timebar = TimebarState(place: place.place, date: Self.today(in: place.place), weather: weather,
                                   language: language, ribbonMode: Self.ribbon(settings.ribbonMode),
                                   clockPreference: Self.clock(settings.clock))
        self.light = LightScreenModel(timebar: timebar, weather: weather, language: language,
                                      locationName: resolved.name ?? place.coordinate.text,
                                      clockPreference: Self.clock(settings.clock))
        light.proMode = settings.pro
        light.fahrenheit = settings.tempUnit == .f

        watchPlace()
        // Нет своего города, но доступ к геолокации уже дан — берём место
        // телефона. Новых запросов разрешения здесь нет: если доступа нет,
        // остаётся столица.
        if resolved.source == .capital, locator.isAlreadyAuthorized {
            Task { await self.useDeviceLocationIfNoCity() }
        } else {
            // Имя и настоящая зона для города настроек — от геокодера.
            if resolved.source == .settings { place.move(to: resolved.coordinate, knownName: PlaceName(city: resolved.name ?? "", sub: "")) }
        }
    }

    /// Живое приложение: снимок из папки приложения, Apple для места и имени,
    /// Open-Meteo для погоды.
    public static func live() async -> AppModel {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true))
            .map { $0.appendingPathComponent("LightPlan", isDirectory: true) }
        let store = dir.map { Store(directory: $0) }
        var snapshot = Snapshot()
        if let store {
            // Не разобрался файл — пустой снимок в памяти, файл не трогаем,
            // пока человек сам что-нибудь не поменяет.
            snapshot = (try? await store.load()) ?? Snapshot()
        }
        let language = AppLanguage.current
        let locale = Locale(identifier: language)
        return AppModel(snapshot: snapshot, store: store, language: language,
                        locator: CoreLocationProvider(), geocoder: AppleReverseGeocoder(locale: locale),
                        cityLookup: AppleCityLookup(locale: locale), weatherSource: OpenMeteoSource())
    }

    // MARK: - Правка настроек

    /// Одна правка — одна запись на диск (дебаунс у `Store`) и одна раздача
    /// экранам. Город меняет место «Света» только с координатами из
    /// справочника: набранное руками имя свет не двигает.
    public func update(_ change: (inout AppSettings) -> Void) {
        let before = settings
        change(&settings)
        guard settings != before else { return }
        settings.apply(to: &snapshot)
        persist()

        light.proMode = settings.pro
        light.fahrenheit = settings.tempUnit == .f
        if settings.clock != before.clock { light.clockPreference = Self.clock(settings.clock) }
        if settings.ribbonMode != before.ribbonMode { light.timebar.setRibbonMode(Self.ribbon(settings.ribbonMode)) }
        if settings.home != before.home, let c = settings.home.coordinate {
            place.move(to: c, knownName: PlaceName(city: settings.home.name, sub: ""))
            citySource = .settings
        }
    }

    /// Выбор из подсказки справочника (`takeCity`).
    public func takeCity(_ hit: CityHit) { update { $0.takeCity(hit) } }

    /// Имя набрано руками, подсказку не выбрали: имя пишется, координаты —
    /// нет, свет стоит, где стоял (веб, `cityHints`: «набранное руками —
    /// уже ответ, справочник только уточняет»).
    public func typeCity(_ name: String) {
        update { s in
            guard s.home.name != name else { return }
            s.home = HomeCity(name: name, coordinate: nil, countryCode: nil)
        }
    }

    /// Лист знакомства закрыт — второй раз не спрашиваем, даже если поле
    /// осталось пустым: молчание тоже ответ (веб, `closeStartSheet`).
    public func finishStart() {
        showStartSheet = false
        var me: [String: JSONValue] = [:]
        if case .object(let o)? = snapshot.extra["me"] { me = o }
        me["met"] = .bool(true)
        snapshot.extra["me"] = .object(me)
        if !settings.home.isEmpty { settings.home.name = HomeCity.cap(settings.home.name) }
        settings.apply(to: &snapshot)
        persist()
    }

    /// Дописать отложенную запись сейчас: приложение уходит в фон или в
    /// настройки iPhone, где смена языка его перезапустит.
    public func flush() async {
        await saving?.value
        await store?.flush()
    }

    /// Правки уходят в `Store` цепочкой: каждая ждёт предыдущую, а `flush`
    /// ждёт последнюю. Без цепочки `flush` успевал раньше, чем задача с
    /// правкой доходила до актора, и дописывать было нечего — правка терялась
    /// (поймано тестом `startSheetOnceAndSettingsSurviveRestart`).
    private var saving: Task<Void, Never>?

    private func persist() {
        guard let store else { return }
        let snap = snapshot, prev = saving
        saving = Task {
            await prev?.value
            await store.save(snap)
        }
    }

    // MARK: - Место

    private func useDeviceLocationIfNoCity() async {
        await place.useDeviceLocation()
        if case .fix? = place.lastDeviceResult, settings.home.coordinate == nil { citySource = .device }
    }

    /// Место сменилось (город из настроек, геолокация, ответ геокодера с
    /// зоной) — таймбар и погода переезжают, шапка берёт имя.
    private func watchPlace() {
        withObservationTracking {
            _ = place.place
            _ = place.name
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.placeChanged()
                self.watchPlace()
            }
        }
    }

    private func placeChanged() {
        let p = place.place
        if light.timebar.place != p {
            light.timebar.setPlace(p)
            light.weather.move(to: p)
        }
        if !place.isNameStale { light.locationName = place.name?.city ?? place.coordinate.text }
    }

    // MARK: - Перевод настроек в типы экранов

    static func clock(_ c: AppSettings.Clock) -> ClockPreference {
        ClockPreference(rawValue: c.rawValue) ?? .auto
    }

    static func ribbon(_ r: AppSettings.RibbonMode) -> RibbonMode {
        r == .lane ? .lane : .drum
    }

    private static func met(_ s: Snapshot) -> Bool {
        if case .object(let me)? = s.extra["me"], case .bool(true)? = me["met"] { return true }
        return false
    }

    static func today(in place: Place) -> CivilDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: place.zone.identifier) ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }
}
