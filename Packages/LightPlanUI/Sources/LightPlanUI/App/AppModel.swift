import Foundation
import Observation
import LightPlanCore
import LightPlanDomain
import LightPlanData
import LightPlanTimeline
import LightPlanMapCanvas

/// Хозяин приложения (итерация 19а): снимок на диске, настройки, место и
/// экран «Свет». Настройки меняются здесь и отсюда же доезжают до «Света»
/// присвоением — без пересоздания экрана и без перезапуска.
public enum AppTab: Hashable, Sendable { case light, map, planner, settings }

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
    /// Открытая вкладка. Живое приложение встаёт на «Свет»; снимок пары
    /// (итерация 19б) — на экран своего сценария.
    public var tab: AppTab = .light
    /// Глава настроек, открытая при запуске, — только снимок пары (19б).
    var startChapter: String?
    /// Открыта глава настроек — панель вкладок прячется, как у веба
    /// (раньше это делал `.toolbar(.hidden, for: .tabBar)` системной панели).
    var chapterOpen = false

    public let cityLookup: any CityLookup
    /// Поиск места по названию — путь «Место» листа «Где снимаем» (21в).
    public let placeSearch: any PlaceSearch
    /// Лист «Где снимаем» открыт: кнопка места в шапке «Света» и «Карты».
    public var placeSheetOpen = false
    /// Путь, на котором лист открывается (пара снимков открывает его сразу на
    /// «Месте» или «Геопозиции»); кнопка шапки — всегда развилка.
    var placeSheetStart: PlaceSheetForm.Way = .fork
    /// Слои карты — `mapLayers` снимка (меню слоёв — итерация 20б).
    public private(set) var mapLayers: MapLayers
    /// Поставщик холста (docs/17 § 10). Пока приложение бесплатное — MapLibre;
    /// выбор — глава «Карта и места». Веб такого ключа не знает, он лежит в
    /// снимке среди чужих (`extra`), как у других нативных полей.
    public private(set) var mapSource: MapCanvasSource
    public func setMapSource(_ s: MapCanvasSource) {
        guard mapSource != s else { return }
        mapSource = s
        snapshot.extra["mapSource"] = .string(s.rawValue)
        persist()
    }
    /// Названия улиц и мест на холсте (`mapLabels` снимка, тумблер веба).
    public var mapLabels: Bool { snapshot.mapLabels }
    public func setMapLabels(_ on: Bool) {
        guard snapshot.mapLabels != on else { return }
        snapshot.mapLabels = on
        persist()
    }
    /// Снимок пары веб / натив: без холста — у веба сеть закрыта, и карты нет.
    var mapOffline = false
    /// Записей в снимке — для строки «Карта и места» (сохранённые точки).
    public var spotCount: Int { snapshot.spots.count }
    /// Засветка места по атласу Лоренца — строка «Засветка» сводки карты.
    public let glow: GlowStore
    /// Датчик направления для живого компаса карты; `nil` — тесты и пары.
    let heading: (any HeadingSource)?
    /// Сводка карты свёрнута (`mapFold` снимка): кто свернул, не хочет видеть
    /// её и завтра — состояние переживает перезапуск, как у веба.
    public var mapFoldShut: Bool { snapshot.mapFold }
    /// Пункт меню слоёв: слой включён или выключен — и сразу в снимок.
    public func setMapLayer(_ key: MapLayers.Key, _ on: Bool) {
        guard mapLayers[key] != on else { return }
        mapLayers[key] = on
        snapshot.mapLayers = mapLayers.saved
        persist()
    }
    public func setMapFold(shut: Bool) {
        guard snapshot.mapFold != shut else { return }
        snapshot.mapFold = shut
        persist()
    }

    // MARK: - Сохранённые точки (итерация 20б)

    /// «Мои места» (`spots` снимка): булавки карты и закладка шапки.
    public var spots: [Spot] { snapshot.spots }

    /// Точка под головкой наблюдателя (`spotHere` веба) — допуск ~60 м.
    public var spotHere: Spot? {
        let c = place.coordinate
        return snapshot.spots.first { $0.coordinate.isSameSpot(as: c) }
    }

    /// Закладка шапки (`mapSave`): место под головкой уже сохранено — убрать,
    /// нет — записать первым в список. Новая точка возвращается: полоса имени
    /// открывается на ней. Имя — город от геокодера (`uniqueSpotName`), пока
    /// его нет — координаты, и геокодер ещё может назвать точку (`named`).
    @discardableResult
    public func toggleSpotHere(now: Date = Date()) -> Spot? {
        if let here = spotHere { removeSpot(id: here.id, now: now); return nil }
        let c = place.coordinate
        let name = place.isNameStale ? nil : place.name
        let city = name?.city ?? ""
        var sp = Spot(id: Self.newSpotId(now), name: Self.uniqueSpotName(city, in: snapshot.spots) ?? c.text,
                      latitude: Self.round5(c.latitude), longitude: Self.round5(c.longitude))
        sp.sub = name?.sub ?? ""
        sp.named = !city.isEmpty
        // Закладка — самый ручной способ завести место: координаты под
        // булавкой человек выбрал сам, и булавка сплошная.
        sp.pinned = true
        sp.modifiedAt = Self.ms(now)
        snapshot.spots.insert(sp, at: 0)
        persist()
        return sp
    }

    /// Имя из полосы (`commitSpotName`): пустое не пишется, набранное рукой
    /// геокодер больше не перебивает.
    public func renameSpot(id: String, to raw: String, now: Date = Date()) {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, let i = snapshot.spots.firstIndex(where: { $0.id == id }) else { return }
        snapshot.spots[i].name = v
        snapshot.spots[i].named = true
        snapshot.spots[i].modifiedAt = Self.ms(now)
        persist()
    }

    /// Корзина полосы и повторный тап закладки: ссылки съёмок на точку
    /// обнуляются (`unlinkSpot`), в `graves` ложится могила (`bury`) —
    /// слияние двух устройств иначе вернуло бы точку.
    public func removeSpot(id: String, now: Date = Date()) {
        guard let i = snapshot.spots.firstIndex(where: { $0.id == id }) else { return }
        for s in snapshot.sessions.indices {
            for r in snapshot.sessions[s].route.indices where snapshot.sessions[s].route[r].spotId == id {
                snapshot.sessions[s].route[r].spotId = nil
            }
        }
        var graves: [JSONValue] = []
        if case .array(let g)? = snapshot.extra["graves"] { graves = g }
        graves.removeAll { if case .object(let o) = $0, o["id"] == .string(id) { true } else { false } }
        graves.append(.object(["id": .string(id), "del": .number(Double(Self.ms(now)))]))
        snapshot.extra["graves"] = .array(graves)
        snapshot.spots.remove(at: i)
        persist()
    }

    /// `newSpotId` веба: «p» + время и четыре случайных знака в base36.
    static func newSpotId(_ now: Date) -> String {
        let tail = String((0..<4).map { _ in "0123456789abcdefghijklmnopqrstuvwxyz".randomElement()! })
        return "p" + String(ms(now), radix: 36) + tail
    }

    /// `uniqueSpotName` веба: имя занято — «Томск 2», «Томск 3»…; пустое — `nil`.
    static func uniqueSpotName(_ base: String, in spots: [Spot]) -> String? {
        guard !base.isEmpty else { return nil }
        var busy = false, top = 1
        for sp in spots {
            if sp.name == base { busy = true; continue }
            // `/^ (\d+)$/` веба: после пробела только цифры ASCII.
            let tail = sp.name.hasPrefix(base + " ") ? sp.name.dropFirst(base.count + 1) : ""
            guard !tail.isEmpty, tail.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(tail) else { continue }
            busy = true; top = max(top, n)
        }
        return busy ? "\(base) \(top + 1)" : base
    }

    /// `+LAT.toFixed(5)` веба.
    private static func round5(_ v: Double) -> Double { Double(JSNumber.fixed(v, 5)) ?? v }
    private static func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded(.down)) }

    /// «Съёмки» (итерация 21): одно состояние на месяц, неделю и день.
    /// Открывается на месяце и сегодняшнем дне при каждом запуске, как веб.
    public var planner: PlannerState
    /// Полоса «Вернуть» после удаления (итерация 22, веб `#undoBar`): висит
    /// над любой вкладкой, пока не выйдет срок или не вернут.
    public var undo: UndoOffer?
    /// Лист «Корзина» (веб `#binSheet`): из настроек, недели и карточки.
    public var binOpen = false
    /// Лист «Занять время» (веб `#blkSheet`) с заготовкой; `nil` — закрыт.
    public var blockSheet: BlockDraft?
    /// Сводка дня свёрнута (`dayFold` снимка) — единственное, что планировщик
    /// помнит между запусками.
    public var dayFold: Bool {
        get { snapshot.dayFold }
        set {
            guard newValue != snapshot.dayFold else { return }
            snapshot.dayFold = newValue
            persist()
        }
    }
    /// Записи и занятость снимка — планировщик их только читает (правка —
    /// итерации форм).
    public var sessions: [Session] { snapshot.sessions }
    public var blocks: [Block] { snapshot.blocks }
    public var orgs: [Org] { snapshot.orgs }
    /// Слой событий чужого календаря (веб `icsLayer`): без него события из
    /// подписки в планировщике не показываются.
    public var eventsLayer: Bool {
        if case .bool(let on)? = snapshot.extra["icsLayer"] { return on }
        return false
    }
    public var delivery: DeliverySetting { snapshot.delivery }
    public var genrePrefs: [Genre: GenrePrefs] { snapshot.genrePrefs }
    /// Часы приложения: у снимка пары — прибитые, как `page.clock` веба.
    public let now: @Sendable () -> Date

    // MARK: - Форма записи (итерация 23; правила — `AppModel+Form`)
    /// Открытая форма записи; `nil` — закрыта.
    public var form: EventForm?
    /// Форма поднята из черновика — над ней полоса «Черновик восстановлен».
    public var formIsDraft = false
    /// Строка под заголовком формы («черновик стёрт»).
    public var formNote: String?
    /// Последний жанр формы: новая форма открывается на нём (веб `shootType`).
    var lastFormGenre: Genre = .portrait
    var draftStore: any DraftStoring = DefaultsDraftStore()
    var draftTask: Task<Void, Never>?
    /// Последний зафиксированный номер владельца (веб `myTelSnap`): смена считается от него.
    var telSnap: String?

    /// Внутренний, а не закрытый: форма записи (`AppModel+Form`) правит список записей.
    var snapshot: Snapshot
    /// Снимок как есть — для тестов записи (могилы, ссылки маршрутов).
    var snapshotForTests: Snapshot { snapshot }
    private let store: Store?
    private let locator: any DeviceLocating

    init(snapshot: Snapshot, store: Store?, language: String, zone: TimeZone = .current,
         locator: any DeviceLocating, geocoder: any ReverseGeocoding, cityLookup: any CityLookup,
         placeSearch: any PlaceSearch = ApplePlaceSearch(),
         weatherSource: any WeatherSource, glowSource: any GlowTileSource = NoGlowSource(),
         headingSource: (any HeadingSource)? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.snapshot = snapshot
        self.store = store
        self.now = now
        self.language = language
        self.lexicon = Lexicon(language)
        self.locator = locator
        self.cityLookup = cityLookup
        self.placeSearch = placeSearch
        self.heading = headingSource
        let settings = AppSettings(snapshot: snapshot, zone: zone)
        self.settings = settings
        self.showStartSheet = !Self.met(snapshot)
        self.mapLayers = MapLayers(snapshot.mapLayers)
        if case .string(let raw)? = snapshot.extra["mapSource"], let src = MapCanvasSource(rawValue: raw) {
            self.mapSource = src
        } else {
            self.mapSource = .mapLibre
        }

        // Город по умолчанию. Место, выбранное руками в прошлый раз
        // (`loc` веба), на старте не читается: выбор руками живёт до
        // перезагрузки (решение 19 сентября).
        let resolved = DefaultCity.resolve(home: settings.home, device: nil, language: language, zone: zone)
        // Зоны, которые веб уже узнал (`zones` снимка): без них первая минута
        // «Света» считается по оценке пояса из долготы — Барнаул (+7) по
        // долготе +6, и экран открывался часом раньше «сейчас» (замер 19б).
        var zones = ZoneCache(entries: Self.savedZones(snapshot))
        if resolved.source == .capital {
            let cap = DefaultCity.capital(language: Lexicon.base(language), zone: zone)
            if let z = ZoneID(cap.zone) { zones.remember(z, at: cap.coordinate) }
        }
        let place = CurrentPlace(initial: resolved.coordinate,
                                 name: resolved.name.map { PlaceName(city: $0, sub: "") },
                                 zones: zones, namer: PlaceNamer(geocoder: geocoder), locator: locator)
        self.place = place
        self.citySource = resolved.source
        self.planner = PlannerState(today: Self.today(in: place.place, now: now()))

        let weather = WeatherStore(place: place.place, source: weatherSource)
        self.glow = GlowStore(place: place.place, source: glowSource)
        let timebar = TimebarState(place: place.place, date: Self.today(in: place.place, now: now()), weather: weather,
                                   language: language, ribbonMode: Self.ribbon(settings.ribbonMode),
                                   clockPreference: Self.clock(settings.clock), now: now)
        // Экран открывается на нынешней минуте, как веб (`viewMin` на старте
        // — «сейчас»), а не на солнечном полдне, которым машина времени
        // встаёт без минуты (найдено 19а, исправлено 19б).
        timebar.jumpToNow()
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
                        cityLookup: AppleCityLookup(locale: locale), placeSearch: ApplePlaceSearch(locale: locale),
                        weatherSource: OpenMeteoSource(),
                        glowSource: LorenzAtlas(), headingSource: CoreLocationHeading())
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

    /// Карту сдвинули пальцем — место приложения едет за точкой под
    /// головкой (`moveend` веба): свет, погода и прибор пересчитываются там.
    public func moveFromMap(latitude: Double, longitude: Double) {
        place.move(to: GeoCoordinate(latitude: latitude, longitude: longitude))
    }

    /// Лист «Где снимаем» ответил точкой (`gotoLocation` веба): место
    /// приложения, свет, погода, имя шапки и камера карты едут за ней. Как и
    /// сдвиг карты, выбор руками живёт до перезапуска (решение 19 сентября).
    public func movePlace(to c: GeoCoordinate) {
        place.move(to: c)
    }

    /// «Подставить моё место» листа: разрешение спрашивается здесь.
    @discardableResult
    public func locateHere() async -> DeviceFix {
        await place.useDeviceLocation()
        return place.lastDeviceResult ?? .unavailable
    }

    /// Разрешение на геоданные ещё не спрашивали — лист встаёт на путь
    /// координат и спрашивает сам (веб, `openLocSheet`).
    public var locationNeedsPermission: Bool { locator.needsPermission }

    /// Тумблер «Сохранить в моих местах» листа. Точка в 60 м от сохранённой —
    /// та же самая (`sameSpot`): ей обновляются имя и адрес, двойник не
    /// заводится. Новая встаёт первой; без имени её называют координаты.
    /// `fromHit` — координаты принёс поиск, а не рука: булавка полая.
    ///
    /// Веб в режиме места приложения этот тумблер не читает (ошибка эталона,
    /// справка 21в), здесь он делает то, что обещает.
    @discardableResult
    public func saveSpot(at c: GeoCoordinate, name raw: String, address rawAddr: String, fromHit: Bool,
                         now: Date = Date()) -> Spot {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let addr = rawAddr.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = snapshot.spots.firstIndex(where: { $0.coordinate.isSameSpot(as: c) }) {
            if !name.isEmpty { snapshot.spots[i].name = name; snapshot.spots[i].named = true }
            if !addr.isEmpty { snapshot.spots[i].address = addr }
            snapshot.spots[i].modifiedAt = Self.ms(now)
            persist()
            return snapshot.spots[i]
        }
        var sp = Spot(id: Self.newSpotId(now), name: name.isEmpty ? c.text : name,
                      latitude: Self.round5(c.latitude), longitude: Self.round5(c.longitude))
        sp.address = addr
        sp.named = !name.isEmpty
        sp.pinned = !fromHit
        sp.modifiedAt = Self.ms(now)
        snapshot.spots.insert(sp, at: 0)
        persist()
        return sp
    }

    /// Правка строки «Моих мест» в листе (карандаш): имя и адрес пишутся по
    /// мере набора. Пустое имя можно — строку тогда называют координаты
    /// (веб, `renderSpots`); полоса имени на карте пустое не пишет.
    public func editSpot(id: String, name raw: String? = nil, address rawAddr: String? = nil, now: Date = Date()) {
        guard let i = snapshot.spots.firstIndex(where: { $0.id == id }) else { return }
        if let raw {
            snapshot.spots[i].name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            snapshot.spots[i].named = true
        }
        if let rawAddr { snapshot.spots[i].address = rawAddr.trimmingCharacters(in: .whitespacesAndNewlines) }
        snapshot.spots[i].modifiedAt = Self.ms(now)
        persist()
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

    func persist() {
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
        glow.move(to: p)
        if !place.isNameStale {
            light.locationName = place.name?.city ?? place.coordinate.text
            light.locationSub = place.name?.sub ?? ""
        }
    }

    // MARK: - Перевод настроек в типы экранов

    static func clock(_ c: AppSettings.Clock) -> ClockPreference {
        ClockPreference(rawValue: c.rawValue) ?? .auto
    }

    static func ribbon(_ r: AppSettings.RibbonMode) -> RibbonMode {
        r == .lane ? .lane : .drum
    }

    private static func savedZones(_ s: Snapshot) -> [String: String] {
        guard case .object(let o)? = s.extra["zones"] else { return [:] }
        return o.compactMapValues { if case .string(let z) = $0 { z } else { nil } }
    }

    private static func met(_ s: Snapshot) -> Bool {
        if case .object(let me)? = s.extra["me"], case .bool(true)? = me["met"] { return true }
        return false
    }

    /// Сегодня по часам места приложения.
    public var today: CivilDate { Self.today(in: place.place, now: now()) }

    /// Минута «сейчас» в поясе места.
    public var nowMinute: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: place.place.zone.identifier) ?? .current
        let c = calendar.dateComponents([.hour, .minute], from: now())
        return c.hour! * 60 + c.minute!
    }

    /// Ступень сдачи записи сейчас (веб `deliveryState`): сутки считаются в
    /// поясе телефона, как у веба.
    public func deliveryStatus(_ s: Session) -> DeliveryStatus {
        Delivery.status(s, now: Moment(now()), zone: .current, setting: snapshot.delivery, prefs: snapshot.genrePrefs)
    }

    static func today(in place: Place, now: Date = Date()) -> CivilDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: place.zone.identifier) ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }
}

// MARK: - Корзина и занятость (итерация 22)

extension AppModel {
    /// Корзина, новые первыми (веб `trashed`).
    public var trashed: [TrashedItem] { snapshot.trashed }

    private var nowMs: Int64 { Self.ms(now()) }

    /// Убрать съёмку, встречу или событие в корзину (веб `removeSession`) и
    /// показать «Вернуть». Подпись — строка клиента или имя съёмки, как у веба
    /// (`rec.contact || typeName`).
    public func trashSession(id: String) {
        guard let rec = Bin.trash(id, in: &snapshot, now: nowMs) else { return }
        let words = PlannerWords(lexicon: lexicon, orgs: orgs)
        let name = rec.contact.isEmpty ? words.typeName(rec) : rec.contact
        undo = UndoOffer(what: .session(id: id), text: lexicon.t("day.inBin", ["name": name]))
        persist()
    }

    /// Вернуть из корзины — из листа или полосой. Полоса, которая держит эту
    /// запись, гаснет: ей больше нечего возвращать.
    public func restoreSession(id: String) {
        guard Bin.restore(id, in: &snapshot, now: nowMs) else { return }
        if undo?.what == .session(id: id) { undo = nil }
        persist()
    }

    /// «Очистить корзину» — после «Стереть». Полоса «Вернуть» съёмки гаснет:
    /// у веба она оставалась и молча ничего не делала.
    public func clearBin() {
        guard !snapshot.trashed.isEmpty else { return }
        Bin.clear(&snapshot, now: nowMs)
        if case .session? = undo?.what { undo = nil }
        persist()
    }

    /// «Убрать из календаря» у занятости — с полосой «Вернуть».
    public func removeBlock(id: String) {
        guard let (b, i) = Bin.removeBlock(id, in: &snapshot, now: nowMs) else { return }
        let label = b.note.isEmpty ? lexicon.t("blkKind." + b.kind.rawValue) : b.note
        undo = UndoOffer(what: .block(b, index: i), text: lexicon.t("blk.removed", ["name": label]))
        persist()
    }

    /// Нажали «Вернуть» на полосе.
    public func takeUndo() {
        guard let u = undo else { return }
        undo = nil
        switch u.what {
        case .session(let id):
            if Bin.restore(id, in: &snapshot, now: nowMs) { persist() }
        case .block(let b, let i):
            Bin.restoreBlock(b, at: i, in: &snapshot, now: nowMs)
            persist()
        }
    }

    /// Срок полосы вышел — гасим, только если это всё ещё тот же показ.
    public func expireUndo(_ token: UUID) {
        if undo?.token == token { undo = nil }
    }

    /// Сохранить занятость из листа «Занять время» (веб `#blkDone`): та же
    /// по знаку заменяется, новая добавляется в конец.
    public func saveBlock(_ b: Block) {
        var b = b
        b.modifiedAt = nowMs
        if let i = snapshot.blocks.firstIndex(where: { $0.id == b.id }) {
            snapshot.blocks[i] = b
        } else {
            snapshot.blocks.append(b)
        }
        persist()
    }

    /// Открыть лист «Занять время» (веб `openBlockSheet`). С тулбара — весь
    /// выбранный день; из меню часа — два часа с этого часа, «выходной»;
    /// занятость — на правку.
    public func openBlockSheet(editing id: String) {
        guard let b = snapshot.blocks.first(where: { $0.id == id }) else { return }
        var d = b
        // Веб `b.min || 600` превращал занятость с полуночи в 10:00.
        d.start = b.start ?? 600
        d.duration = b.duration ?? 120
        d.days = max(1, b.days)
        blockSheet = BlockDraft(block: d, editing: true)
    }

    public func openBlockSheet(day: CivilDate, at minute: Int? = nil) {
        var b = Block(id: Self.newBlockId(nowMs), kind: .off, from: day)
        b.allDay = minute == nil
        b.days = 1
        b.start = minute ?? 600
        b.duration = 120
        blockSheet = BlockDraft(block: b, editing: false)
    }

    /// Знак новой занятости (веб `newBlockId`): «b», время в base36 и три
    /// случайных знака.
    static func newBlockId(_ ms: Int64) -> String {
        let abc = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return "b" + String(ms, radix: 36) + String((0..<3).map { _ in abc.randomElement()! })
    }

    /// Раздел настроек «Сдача материала» (веб `#delvSeg`, `#delvDays`).
    /// Срок «единого» помнится, когда режим уходит и возвращается.
    public func setDelivery(mode: DeliveryMode? = nil, days: Int? = nil) {
        var d = snapshot.delivery
        if let mode { d.mode = mode }
        if let days { d.days = days }
        guard d != snapshot.delivery else { return }
        snapshot.delivery = d
        persist()
    }
}

/// Атлас без сети: тесты и снимки пар (у веба в паре сеть закрыта, и строки
/// засветки нет).
struct NoGlowSource: GlowTileSource {
    func tile(tx: Int, ty: Int) async throws -> Data { throw URLError(.notConnectedToInternet) }
}
