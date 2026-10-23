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
    public internal(set) var citySource: DefaultCity.Source
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
    /// Строка «Сборка» внизу «Настроек». Снимки пар «веб / натив» её не рисуют: у веба такой строки нет.
    var showsBuildLine = true
    /// Открыты статистика или поиск «Съёмок» (22) — они закрывают панель
    /// вкладок, как у веба (`z-index` 85 и 80 над 30 у `.tabbar`); год — нет.
    var plannerPageOpen = false

    public let cityLookup: any CityLookup
    /// Поиск места по названию — путь «Место» листа «Где снимаем» (21в).
    public let placeSearch: any PlaceSearch
    /// Лист «Где снимаем» открыт: кнопка места в шапке «Света» и «Карты».
    public var placeSheetOpen = false
    /// Слой AR: дуга солнца поверх камеры (29.8в). `nil` — закрыт. Вход — место и момент, откуда открыли — не помним.
    var sunAR: SunARTarget?
    /// Номер захода AR: ответ телефона, пришедший после закрытия экрана, ничего не меняет.
    @ObservationIgnored var sunARSession = 0
    /// Плашка перед входом в AR (29.8в.4): геолокации нет или выбранное место далеко от телефона. `nil` — плашки нет.
    var sunAREntry: SunAREntry?
    /// Телефон отвечает на «Использовать моё местоположение» (системное окно или поиск точки).
    var sunAREntryBusy = false
    /// Путь, на котором лист открывается (пара снимков открывает его сразу на
    /// «Месте» или «Геопозиции»); кнопка шапки — всегда развилка.
    var placeSheetStart: PlaceSheetForm.Way = .fork
    /// Точка маршрута формы, о чьём месте спрашивает лист (веб `locTarget === "stop"`);
    /// `nil` — лист про место приложения. Лист точки открывает сама форма: она
    /// лежит поверх всего, и лист оболочки встал бы под неё.
    var placeSheetStop: Int?
    /// Лист точки открывается на карточке её студии, раскрытой до залов
    /// (кнопка «Добавить зал» у студии без залов, 29.11).
    var placeSheetOpenCard = false
    /// Слои карты — `mapLayers` снимка (меню слоёв — итерация 20б).
    public private(set) var mapLayers: MapLayers
    /// Поставщик холста (docs/17 § 10). Пока приложение бесплатное — MapLibre;
    /// выбор — глава «Карта и места». Веб такого ключа не знает, он лежит в
    /// снимке среди чужих (`extra`), как у других нативных полей.
    public private(set) var mapSource: MapCanvasSource
    public func setMapSource(_ s: MapCanvasSource) {
        // Выбор запоминается и тогда, когда совпал с умолчанием: по нему автопереключение понимает, что решал человек.
        guard mapSource != s || !mapSourceChosen else { return }
        mapSource = s
        mapAutoApple = false
        snapshot.extra["mapSource"] = .string(s.rawValue)
        persist()
    }
    /// Запасная карта (28л.3). CARTO не отдала первую плитку за 4 с — на этот запуск показываем карту Apple.
    /// Только если холст не выбран руками: выбор в настройках (даже «OpenStreetMap») автопереключение не
    /// перебивает. В снимок не пишется — в следующий запуск CARTO получает новую попытку.
    public private(set) var mapAutoApple = false
    /// CARTO уже отдала плитку в этом запуске — сторожить дальше незачем.
    private var cartoAnswered = false
    /// Холст выбран руками: ключ `mapSource` в снимке появляется только от `setMapSource`.
    public var mapSourceChosen: Bool { snapshot.extra["mapSource"] != nil }
    /// Холст, который рисуется на самом деле.
    public var shownMapSource: MapCanvasSource { mapAutoApple && !mapSourceChosen ? .mapKit : mapSource }
    /// Надо ли следить за первой плиткой CARTO.
    public var mapFallbackArmed: Bool { mapSource == .mapLibre && !mapSourceChosen && !mapAutoApple && !cartoAnswered }
    public func cartoTileArrived() { cartoAnswered = true }
    public func cartoWentSilent() {
        guard mapFallbackArmed else { return }
        mapAutoApple = true
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
    /// Ответы маршрутизатора на куски черновика — на сеанс (`roadCache` веба).
    let roads = RoadBook()
    /// Записей в снимке — для строки «Карта и места» (сохранённые точки).
    public var spotCount: Int { snapshot.spots.count }
    /// Засветка места по атласу Лоренца — строка «Засветка» сводки карты.
    public let glow: GlowStore
    /// Откуда берутся плитки атласа: AR спрашивает засветку своего места (оно бывает местом телефона).
    let glowSource: any GlowTileSource
    /// Прогноз по точкам съёмки для карточки (веб `ptFetch`): свой, отдельный
    /// от прогноза места «Света».
    public let pointWeather: PointWeather
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
        let sp = insertSpotHere(now: now)
        persist()
        return sp
    }

    /// Новое место под головкой первым в списке — у закладки и у точки
    /// маршрута (`routeNewSpot` веба) один рецепт. Без записи на диск.
    /// Пока имя нового места в пути (0,9 с после сдвига карты и ответ
    /// геокодера), берётся прежнее — как `geoCity` веба; иначе точка,
    /// поставленная сразу после сдвига, получала координаты (Алексей 28.09).
    /// Но только если прежнее получено не дальше `nearNameKm`: у веба точка
    /// в Томске сразу после переезда из Москвы звалась бы «Москва».
    func insertSpotHere(now: Date) -> Spot {
        let c = place.coordinate
        let near = !place.isNameStale || place.nameOrigin.map { kmBetween($0, c) <= Self.nearNameKm } == true
        let name = near ? place.name : nil
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
        bury(id, now: now)
        snapshot.spots.remove(at: i)
        persist()
    }

    /// Могила удалённой записи (веб `bury`): слияние двух устройств иначе вернуло бы её.
    func bury(_ id: String, now: Date) {
        var graves: [JSONValue] = []
        if case .array(let g)? = snapshot.extra["graves"] { graves = g }
        graves.removeAll { if case .object(let o) = $0, o["id"] == .string(id) { true } else { false } }
        graves.append(.object(["id": .string(id), "del": .number(Double(Self.ms(now)))]))
        snapshot.extra["graves"] = .array(graves)
    }

    /// `newSpotId` веба: «p» + время и четыре случайных знака в base36.
    static func newSpotId(_ now: Date) -> String {
        let tail = String((0..<4).map { _ in "0123456789abcdefghijklmnopqrstuvwxyz".randomElement()! })
        return "p" + String(ms(now), radix: 36) + tail
    }

    static let nearNameKm = 5.0

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
    static func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded(.down)) }

    /// «Съёмки» (итерация 21): одно состояние на месяц, неделю и день.
    /// Открывается на месяце и сегодняшнем дне при каждом запуске, как веб.
    public var planner: PlannerState
    /// Полоса «Вернуть» после удаления (итерация 22, веб `#undoBar`): висит
    /// над любой вкладкой, пока не выйдет срок или не вернут.
    public var undo: UndoOffer?
    /// Лист «Корзина» (веб `#binSheet`): из настроек, недели и карточки.
    public var binOpen = false
    /// Полёт в корзину при стирании (29.7): круг, плашка-цель, звук. Один на приложение.
    @ObservationIgnored let binFlight = BinFlight()
    /// Полёт обложки в шапку папки мудборда (29.3в). Один на приложение.
    @ObservationIgnored let mbFly = MbFly()
    /// Свайп влево по строке съёмки (29.3г): открыта одна строка на всё приложение.
    @ObservationIgnored let rowSwipe = RowSwipe()
    /// Лист «Занять время» (веб `#blkSheet`) с заготовкой; `nil` — закрыт.
    public var blockSheet: BlockDraft?
    /// Открытая карточка — id записи (итерация 25, `AppModel+Card`).
    var cardId: String?
    /// Какая стопка над открытой карточкой (К5): соседи по дню или все долги. Ставится при открытии и
    /// держится, пока листают стопку: отмеченная «сдана» карточка не меняет режим, пока открыта.
    var cardStackMode: CardStackMode = .day
    /// Список всех долгов полосами, как в Wallet (К5, вид 2): открыт нажатием на стопку внизу карточки долга.
    var debtsListOpen = false
    /// Открытые свёртки карточки (маршрут, документы): держатся, пока открыта
    /// эта карточка (итерация 26; у веба закрывались при любой перерисовке).
    var cardFolds: Set<CardBlock> = []
    /// «Файл не открылся» — строка в самой карточке под документами (шаг 3, 27).
    var cardDocMessage: String?
    /// Полный экран референсов над карточкой (шаг 4, 27); `nil` — закрыт.
    var refsFull: RefsFullState?
    /// Мудборд (28, шаг 5а): галерея, полка, поле поиска и выбранный чип — состояние руки, в запись не идёт.
    var mb = MoodboardState()
    /// Режим сортировки мудборда и перенос подборок (29.3б): один на приложение, как `body.mb-sorting` веба.
    @ObservationIgnored let mbSort = MbSort()
    /// Организации (итерация 28, шаг 6): список, карточка, черновик новой.
    var org = OrgState()
    /// «Документы» (итерация 28д, шаг 3а): экран верхнего уровня и открытый в нём раздел.
    var docsNav = DocsNav()
    /// Реестр слоёв для жеста «назад» от левого края (28з).
    let edgeBack = EdgeBack()
    /// Опросник клиенту (28, шаг 9): лист, вставка, строка под полем.
    var quest = QuestState()
    /// Ответы клиентов, что ждут сохранения записи (шаг 8); файл — в папке приложения.
    var questDrafts = QuestDrafts()
    var questDraftStore: QuestDraftStore?
    /// Режим «ползунков» (веб `#cardOrder`): блоки свёрнуты в строки перестановки.
    /// Закрытие карточки и переход к другой выводят из режима (шаг 5а, 26).
    var cardTuning = false
    /// Сколько сжатий/разворотов блоков ещё идёт (27а.2): пока больше нуля, обёртки блоков обрезают по краю.
    var cardTuneMoves = 0
    /// Снимок «блок в руке» (`-LPShotDrag block:dy`, 27а.3): список порядка встаёт с поднятой строкой, как после жеста.
    var cardShotDrag: (block: CardBlock, dy: CGFloat)?
    /// Ночь места в сутки для строки «Звёзды» и дуги луны: окно Млечного Пути
    /// считается перебором суток шагом 5 минут, карточка же перерисовывается
    /// раз в минуту. Кэш вне наблюдения — запись в него из тела вида не
    /// будит перерисовку.
    @ObservationIgnored var nightCache: [String: StarNight] = [:]
    @ObservationIgnored var moonCache: [String: [ClosedRange<Int>]] = [:]
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
    /// Пояс телефона (веб `deviceZone`): с ним сверяется пояс места съёмки у
    /// часов плитки дня.
    let deviceZone: TimeZone

    // MARK: - Форма записи (итерация 23; правила — `AppModel+Form`)
    /// Открытая форма записи; `nil` — закрыта.
    public var form: EventForm?
    /// Форма поднята из черновика — над ней полоса «Черновик восстановлен».
    public var formIsDraft = false
    /// Строка под заголовком формы («черновик стёрт»).
    public var formNote: String?
    /// Вопрос «продолжить черновик или начать новую»: задан, когда в календаре выбрали день,
    /// не совпадающий с днём черновика с набранным текстом. Пока он не `nil`, форма закрыта (28о).
    public var draftAsk: DraftAsk?
    /// Форма открыта «новой» поверх живого черновика: пока в ней пусто, черновик на диске не трогаем.
    var formOverDraft = false
    /// Последний жанр формы: новая форма открывается на нём (веб `shootType`).
    var lastFormGenre: Genre = .portrait
    var draftStore: any DraftStoring = DefaultsDraftStore()
    /// Вид раздела «Документы», группировка, сортировка и свёрнутые группы — между запусками.
    var docsPrefsStore: any DraftStoring = DefaultsDraftStore(key: "lightplan.native.docsprefs")
    /// Шлюз студии для «Связать с бронью»; тестам подставляется свой.
    var bookingMatch: any BookingMatching = HTTPBookingMatch()
    /// Город формы, по которому уже спрашивали геокодер (веб `sessionPlace.townAt`).
    var formCityAsked: String?
    var draftTask: Task<Void, Never>?
    /// Последний зафиксированный номер владельца (веб `myTelSnap`): смена считается от него.
    var telSnap: String?

    /// Внутренний, а не закрытый: форма записи (`AppModel+Form`) правит список записей.
    var snapshot: Snapshot
    /// Снимок как есть — для тестов записи (могилы, ссылки маршрутов).
    var snapshotForTests: Snapshot { snapshot }
    private let store: Store?
    /// Файлы картинок мудборда (шаг 5г); `nil` — в тестах без диска и до `live()`.
    var refImages: RefImageStore?
    /// Читалка Pinterest (28м); `nil` — в этой сборке нет ключа, и Pinterest выключен с надписью.
    var pinterest: (any PinterestReading)?
    /// Читалка прямых ссылок на фото (28н.1): работает и без ключа (напрямую), с ключом — ещё и через наш сервер; `nil` — в тестах.
    var imageLinks: (any ImageLinkReading)?
    /// Режим «Сеть» и детектор доступности зарубежного (28л.6): общий для погоды и читалок; `nil` — в тестах и снимках.
    var netHub: NetworkPolicyHub?
    /// Режим «Авто» / «Только напрямую»: ключ `netMode` лежит в снимке среди чужих (`extra`), веб его не знает.
    public internal(set) var netMode: NetworkMode
    /// Что детектор думает о зарубежных адресах; экран «Сеть» пишет это словом.
    public internal(set) var foreignReach: ForeignReach = .unknown
    /// Идёт ручная проверка по кнопке «Проверить снова».
    public internal(set) var netChecking = false
    /// Система уведомлений для студийного часа (30а). `nil` — в тестах и снимках: расписание тогда не
    /// ставится никуда; настоящую даёт `live()`.
    @ObservationIgnored var alertCenter: (any NotificationCentering)?
    /// Что система сказала о праве уведомлять; тумблер «Студийный час» показывает его честно.
    public internal(set) var alertAuth: NotificationAuthorization = .notDetermined
    @ObservationIgnored var alertGen = 0
    @ObservationIgnored var alertForce = false
    /// Номер последнего нажатия на тумблер «Студийный час»: ответ на старое нажатие ничего не пишет.
    @ObservationIgnored var alertWish = 0
    /// Плашка перед системным окном (30а.2) стоит на экране.
    public internal(set) var studioAlertAsk = false
    /// Проверка «показывать ли плашку» после сохранения съёмки: тесты ждут её.
    @ObservationIgnored var alertOfferTask: Task<Void, Never>?
    @ObservationIgnored var alertChain: Task<Void, Never>?
    /// Отпечатки того, что последний раз поставили в систему: без правки данных система не опрашивается.
    @ObservationIgnored var alertApplied: [String]?
    @ObservationIgnored var alertPresenter = NotificationPresenter()
    /// «Прогноз переменился» (30.6): кто говорит из фона — `nil` в тестах без подставки и в снимках.
    @ObservationIgnored var wxPoster: (any InstantNotifying)?
    /// Когда обход последний раз ходил в сеть: возврат в приложение чаще получаса не спрашивает (веб `WX_WATCH_GAP`).
    @ObservationIgnored var wxWatchAt: Date?
    /// Обход в пути: тесты ждут его.
    @ObservationIgnored var wxWatchTask: Task<Void, Never>?
    /// Баннеры внутри приложения (веб `#notif`): очередь с потолком два и «И ещё N».
    public internal(set) var notices = NoticeQueue()
    /// Баннер стоит на экране (въехал и ещё не уехал).
    public internal(set) var noticeShown = false
    @ObservationIgnored var noticeTask: Task<Void, Never>?
    /// Сколько баннер стоит и пауза до следующего (веб 5,2 с и 0,4 с); тесты укорачивают.
    @ObservationIgnored var noticeTiming: (onScreen: Duration, step: Duration) = (.milliseconds(5200), .milliseconds(400))
    /// Плашка «Сообщать и когда приложение закрыто?» стоит на экране (30.6b).
    public internal(set) var weatherAlertAsk = false
    /// Баннер о прогнозе показан — когда очередь баннеров кончится, можно предложить плашку.
    @ObservationIgnored var wxOfferPending = false
    /// Проверка «показывать ли плашку» в пути: тесты ждут её.
    @ObservationIgnored var wxOfferTask: Task<Void, Never>?
    /// Где помнится «плашку о погоде уже показывали»: память телефона, одна на установку (`live()` даёт
    /// `.standard`); `nil` — тесты, помнится в `wxAskedMemory`. Не в снимке: веб пересобирает `notif` из своих
    /// пяти ключей и чужой флаг стёр бы.
    @ObservationIgnored var wxAskDefaults: UserDefaults?
    @ObservationIgnored var wxAskedMemory = false
    /// Окно на экране (`scenePhase == .active`): баннер говорит только тогда. Пишет `RootView`; тесты — сами.
    @ObservationIgnored public var sceneActive = true
    /// Зеркало съёмок в Календарь iPhone (30.1–3). `nil` — в тестах без подставки, в снимках и на Mac: ничего не пишется.
    @ObservationIgnored var calendarMirror: CalendarMirror?
    @ObservationIgnored var calendarStore: (any CalendarStoring)?
    @ObservationIgnored var calendarGen = 0
    @ObservationIgnored var calendarForce = false
    @ObservationIgnored var calendarChain: Task<Void, Never>?
    /// Слушает «база календарей изменилась» (30.4): подвинули событие в Календаре — запись узнает об этом без
    /// возврата в приложение.
    @ObservationIgnored var calendarWatch: Task<Void, Never>?
    /// Клетки поясов, которые уже спрашивали у геокодера в этом запуске: не ответили (нет сети) — не долбим снова.
    @ObservationIgnored var calendarZonesTried: Set<String> = []
    /// Сколько проходов подряд, начатых уведомлением базы, сами что-то записали в календарь: запись будит уведомление,
    /// и если календарь вечно переписывает своё (система нормализует поле по-своему), цепочка не гаснет. Три подряд —
    /// предел: дальше уведомления ждут возврата в приложение или правки данных.
    /// Тишина, после которой уведомление базы запускает проход (тест ставит короче).
    @ObservationIgnored var calendarSettle: Duration = .seconds(1)
    @ObservationIgnored var calendarWatchStreak = 0
    /// Когда кончился последний проход, записавший что-то по уведомлению: серия считается только подряд идущей.
    @ObservationIgnored var calendarWatchLast = Date.distantPast
    /// Дольше этого перерыва серия обнуляется: настоящая новая правка в Календаре не должна упираться в старый счётчик.
    @ObservationIgnored var calendarStreakWindow: TimeInterval = 10
    @ObservationIgnored var calendarPassWrote = false
    /// Что последний раз привели в Календарь: без правки данных проход молчит (кроме возврата в приложение).
    @ObservationIgnored var calendarApplied: [EventDraft]?
    /// Что система сказала о праве на календарь: тумблер «Съёмки в Календаре» показывает его честно.
    public internal(set) var calendarAuth: CalendarAuthorization = .notDetermined
    /// Человек включил зеркало (память телефона, не снимок).
    public internal(set) var calendarWanted = false
    /// Где календарь лежит сейчас: учётная запись и её имя.
    public internal(set) var calendarSourceId: String?
    public internal(set) var calendarSourceTitle: String?
    /// Учётные записи, где можно завести календарь.
    public internal(set) var calendarSources: [CalendarSource] = []
    /// Календарь удалили руками в Календаре iPhone: ждём ответа «завести заново?».
    public var calendarGoneAsk = false
    /// Последняя попытка завести календарь не удалась: учётная запись его не берёт.
    public internal(set) var calendarFailed = false
    /// Выключить не вышло: календарь или события остались в телефоне, зеркало осталось включённым.
    public internal(set) var calendarOffFailed = false
    // MARK: Чужие календари призраками (30.5)
    /// Читатель чужих календарей; `nil` там же, где нет и зеркала (тесты без подставки, снимки, Mac).
    @ObservationIgnored var ghostReader: GhostCalendars?
    @ObservationIgnored var ghostMemory: (any GhostMemory)?
    /// Окно дней, которое уже прочитано: пока выбранный день в нём, ничего не читается заново.
    @ObservationIgnored var ghostWindow: (from: CivilDate, to: CivilDate)?
    @ObservationIgnored var ghostLoad: Task<Void, Never>?
    @ObservationIgnored var ghostLoadGen = 0
    /// Склейка всплесков уведомлений базы: последнее уведомление запускает чтение через `calendarSettle`.
    @ObservationIgnored var ghostGen = 0
    @ObservationIgnored var ghostWatch: Task<Void, Never>?
    /// Призраки на прочитанное окно дней — только в памяти этого запуска: ни в снимок, ни в веб, ни в Календарь.
    public internal(set) var ghostList: [Ghost] = []
    /// Человек включил «Другие календари» (память телефона).
    public internal(set) var ghostWanted = false
    /// Календари для списка в настройках: все, кроме «Light Plan», и показывается ли каждый.
    public internal(set) var ghostChoices: [GhostCalendars.Choice] = []
    /// Спрашиваем, можно ли читать Календарь, прежде чем показать системный запрос.
    public var ghostAsk = false
    /// Лист призрака (или нескольких, если на ленте они схлопнулись в «+N»); `nil` — закрыт.
    public var ghostSheet: GhostSheetTarget?
    /// Дни недели, где список призраков раскрыт («Ещё N ⌄»): по дням, только в памяти запуска.
    public var ghostWeekOpen: Set<CivilDate> = []
    @ObservationIgnored var reachTask: Task<Void, Never>?
    /// Закачка доски идёт этой задачей; «Остановить» отменяет её.
    @ObservationIgnored var pinTask: Task<Void, Never>?
    let locator: any DeviceLocating

    // MARK: Слежение за местом (29.8в.12)

    @ObservationIgnored let placeMemory: any PlaceMemory
    /// Копия памяти места; запись уходит в память устройства сразу.
    var placeMemoryRecord: PlaceMemoryRecord { didSet { placeMemory.record = placeMemoryRecord } }
    /// «Следовать за мной» включено (даже если доступа к геопозиции нет — тогда вид честно говорит об этом).
    var following: Bool { didSet { light.placeFollowing = followingLive } }
    /// Слежение выключилось само: место выбрали руками.
    var followOffByChoice: Bool { didSet { light.placeFollowing = followingLive } }
    /// Сколько раз место выбирали руками: ответ «где я», запрошенный до выбора, его не перебивает (ревью GPT к 1fd6b27).
    @ObservationIgnored var handPicks = 0
    /// Доступ к геопозиции, сверенный последним (на старте и при возврате на экран).
    var locationAccess: LocationAccess { didSet { light.placeFollowing = followingLive } }

    init(snapshot: Snapshot, store: Store?, language: String, zone: TimeZone = .current,
         locator: any DeviceLocating, geocoder: any ReverseGeocoding, cityLookup: any CityLookup,
         placeSearch: any PlaceSearch = ApplePlaceSearch(),
         weatherSource: any WeatherSource, glowSource: any GlowTileSource = NoGlowSource(),
         headingSource: (any HeadingSource)? = nil,
         weatherReachability: (any NetworkReachability)? = nil,
         placeMemory: (any PlaceMemory)? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.snapshot = snapshot
        self.store = store
        self.now = now
        self.deviceZone = zone
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
        self.netMode = Self.netMode(of: snapshot)

        // Место на старте (29.8в.12). Решение 19 сентября «выбор руками живёт до перезагрузки» отменено словом
        // Алексея 18.10 (выбрал Томск, перезапустил — Москва): место приложения помнится между запусками.
        // Слежение включено и доступ дан — последняя точка телефона (свежая придёт следом); иначе последнее
        // место приложения; памяти нет — «Мой город», затем место телефона, если доступ был, затем столица.
        let memory = placeMemory ?? InMemoryPlaceMemory()
        self.placeMemory = memory
        let rec = memory.record
        self.placeMemoryRecord = rec
        self.following = rec.following
        self.followOffByChoice = rec.offByChoice
        let access = locator.access
        self.locationAccess = access
        let live = rec.following && access == .granted
        // Следим: место приложения и есть место телефона; запомненное место берётся с именем и поясом, если
        // оно в 500 м от последней точки телефона, иначе — голая точка (имя даст геокодер).
        let saved: PlaceMemoryRecord.Saved? = if live, let ph = rec.phone {
            rec.place.flatMap { PlaceFollow.shouldMove(from: $0.coordinate, to: ph.coordinate) ? nil : $0 }
                ?? .init(latitude: ph.latitude, longitude: ph.longitude, name: nil, sub: nil, zone: nil)
        } else { rec.place }
        let fromMemory: DefaultCity.Resolved? = saved.map {
            DefaultCity.Resolved(coordinate: $0.coordinate, name: $0.name, source: live ? .device : .saved)
        }
        let resolved = fromMemory ?? DefaultCity.resolve(home: settings.home, device: nil, language: language, zone: zone)
        // Зоны, которые веб уже узнал (`zones` снимка): без них первая минута
        // «Света» считается по оценке пояса из долготы — Барнаул (+7) по
        // долготе +6, и экран открывался часом раньше «сейчас» (замер 19б).
        var zones = ZoneCache(entries: Self.savedZones(snapshot))
        if resolved.source == .capital {
            let cap = DefaultCity.capital(language: Lexicon.base(language), zone: zone)
            if let z = ZoneID(cap.zone) { zones.remember(z, at: cap.coordinate) }
        }
        if let saved, let raw = saved.zone, let z = ZoneID(raw) { zones.remember(z, at: saved.coordinate) }
        let place = CurrentPlace(initial: resolved.coordinate,
                                 name: resolved.name.map { PlaceName(city: $0, sub: fromMemory == nil ? "" : saved?.sub ?? "") },
                                 zones: zones, namer: PlaceNamer(geocoder: geocoder), locator: locator)
        self.place = place
        self.citySource = resolved.source
        self.planner = PlannerState(today: Self.today(in: place.place, now: now()))

        let weather = WeatherStore(place: place.place, source: weatherSource, reachability: weatherReachability)
        self.pointWeather = PointWeather(source: weatherSource)
        self.glow = GlowStore(place: place.place, source: glowSource)
        self.glowSource = glowSource
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
        light.placeFollowing = live
        // Строка под именем запомненного места — сразу: тот же ответ геокодера наблюдателя не будит (равное значение).
        light.locationSub = place.name?.sub ?? ""

        watchPlace()
        // Следим и доступ уже дан — свежая точка телефона (без системного окна); слежение за смещением — с ней.
        // Не следим, но памяти нет и доступ есть — место телефона вместо столицы, как было. Новых запросов
        // разрешения на старте нет.
        if live {
            Task { await self.followFreshFix() }
            startWatchingIfFollowing()
        } else if resolved.source == .capital, access == .granted {
            Task { await self.useDeviceLocationIfNoCity() }
        } else if resolved.source == .settings || resolved.source == .saved {
            // Имя и настоящая зона для города настроек и запомненного места — от геокодера.
            if let n = resolved.name {
                place.move(to: resolved.coordinate, knownName: PlaceName(city: n, sub: saved?.sub ?? ""))
            } else {
                place.move(to: resolved.coordinate)
            }
        }
    }

    /// Снимок на старте. `fresh` — файла данных ещё нет. Тестовая копия ветки на свежей установке
    /// получает засев (город Алексея и его студия лежат в нём); данные, которые уже есть,
    /// и основное приложение засев не видят. Не разобрался файл — пустой снимок в памяти,
    /// файл не трогаем, пока человек сам что-нибудь не поменяет.
    static func startSnapshot(store: Store, fresh: Bool, bundleID: String?, now: Date = Date()) async -> Snapshot {
        var snapshot = (try? await store.load()) ?? Snapshot()
        if fresh, bundleID != "Novopashin.LightPlan", let seed = TestSeed.snapshot(now: now) {
            snapshot = seed
            try? await store.saveNow(seed)
        }
        return snapshot
    }

    /// Живое приложение: снимок из папки приложения, Apple для места и имени,
    /// Open-Meteo для погоды.
    public static func live() async -> AppModel {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true))
            .map { $0.appendingPathComponent("LightPlan", isDirectory: true) }
        let store = dir.map { Store(directory: $0) }
        var snapshot = Snapshot()
        // Тестовый засев (Алексей, 29.09): у копии ветки при первом запуске, пока файла данных
        // ещё нет, — записи сезона из прототипа; потом это обычные данные, их не обнуляем.
        // Основное приложение «Light Plan» (`Novopashin.LightPlan`) не засеивается.
        let seeded = dir.map { !FileManager.default.fileExists(atPath: $0.appendingPathComponent("light-plan.json").path) }
            ?? false
        if let store {
            snapshot = await Self.startSnapshot(store: store, fresh: seeded, bundleID: Bundle.main.bundleIdentifier)
        }
        // Клиенты из уже записанных съёмок — один раз на файл данных (шаг К1, справка `clients_reference.md` § 3.8).
        let assembled = Self.assembleClients(into: &snapshot, language: AppLanguage.current, now: Date())
        // Годовщина пары из свадьбы — в снимок (К6, § 2.4): экраны считают её сами, запись — для облака.
        let settled = Self.settleAnniversaries(in: &snapshot, now: Date())
        if assembled || settled {
            try? await store?.saveNow(snapshot)
        }
        // Пустая жанровая папка на каждый включённый жанр — один раз, пишется сразу (веб `mbSeeded`).
        if RefLibrary.seedGenreFolders(in: &snapshot.extra, genres: Moodboard.enabledGenres(snapshot.genres).map(\.rawValue),
                                       newId: { UUID().uuidString.lowercased() },
                                       now: Date().timeIntervalSince1970 * 1000) {
            try? await store?.saveNow(snapshot)
        }
        let language = AppLanguage.current
        let locale = Locale(identifier: language)
        let hub = NetworkPolicyHub(mode: Self.netMode(of: snapshot), detector: .live())
        var clock: @Sendable () -> Date = { Date() }
        #if DEBUG
        // Переезд во времени для замеров (К6, `-LPTravelTo <ISO 8601>`): часы приложения идут с этого момента, и запросы к
        // системе уведомлений переводятся на тот же сдвиг (`SystemNotificationCenter.debugShift`) — поздравление «завтра в
        // 10:00» приходит в настоящую минуту, когда часы приложения показывают 10:00. Расписание и текст — те же, что у людей.
        if let text = UserDefaults.standard.string(forKey: "LPTravelTo"), let to = ISO8601DateFormatter().date(from: text) {
            let shift = to.timeIntervalSinceNow
            clock = { Date().addingTimeInterval(shift) }
            SystemNotificationCenter.debugShift = shift
        }
        #endif
        let model = AppModel(snapshot: snapshot, store: store, language: language,
                        locator: CoreLocationProvider(), geocoder: AppleReverseGeocoder(locale: locale),
                        cityLookup: AppleCityLookup(locale: locale), placeSearch: ApplePlaceSearch(locale: locale),
                        weatherSource: RoutedWeatherSource.live(config: WeatherProxyConfig.load(), hub: hub),
                        glowSource: LorenzAtlas(), headingSource: CoreLocationHeading(),
                        weatherReachability: SystemReachability(),
                        // Место и слежение — в памяти телефона (29.8в.12); тесты и снимки пар живут в памяти запуска.
                        placeMemory: DevicePlaceMemory(), now: clock)
        // Картинки мудборда — рядом со снимком, в папке вложений (`docs/17` § 6).
        model.refImages = dir.map { RefImageStore(directory: $0.appendingPathComponent("attachments", isDirectory: true)) }
        model.pinterest = PinterestClient.live(config: PinterestConfig.load())
            .map { PolicyPinterestReader($0) { await hub.policy() } }
        model.imageLinks = ImageLinkReader(direct: DirectImageFetcher(), server: PinterestClient.live(config: PinterestConfig.load())) { await hub.policy() }
        model.attachNetwork(hub)
        model.wxAskDefaults = .standard  // «плашку о погоде уже показывали» — на этой установке (30.6b)
        model.attachAlerts()        // студийный час по расписанию, пока приложение закрыто (30а)
        model.attachCalendar()      // съёмки в Календаре iPhone, если человек включил (30.1)
        model.debugCalendarProbe()  // замер на настоящем календаре симулятора (`-LPCalendarProbe`, Debug)
        // Ответы клиентов, что ждут сохранения записи: лежат рядом со снимком; давнее (30 дней) стирается.
        if let dir {
            let qs = QuestDraftStore(directory: dir)
            var drafts = qs.load()
            if drafts.prune(now: Date()) { qs.save(drafts) }
            model.questDraftStore = qs
            model.questDrafts = drafts
        }
        return model
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
        if before.manualEnd, !settings.manualEnd { clearFinishMarks() }
        persist()

        light.proMode = settings.pro
        light.fahrenheit = settings.tempUnit == .f
        if settings.clock != before.clock { light.clockPreference = Self.clock(settings.clock) }
        if settings.ribbonMode != before.ribbonMode { light.timebar.setRibbonMode(Self.ribbon(settings.ribbonMode)) }
        // Пока место следует за телефоном, «Мой город» — запасной: свет стоит там, где телефон (29.8в.12).
        if settings.home != before.home, let c = settings.home.coordinate, !followingLive {
            place.move(to: c, knownName: PlaceName(city: settings.home.name, sub: ""))
            citySource = .settings
        }
    }

    /// Карту сдвинули пальцем — место приложения едет за точкой под
    /// головкой (`moveend` веба): свет, погода и прибор пересчитываются там.
    /// Сдвиг пальцем — выбор руками: слежение выключается само (29.8в.12).
    public func moveFromMap(latitude: Double, longitude: Double) {
        choseByHand()
        place.move(to: GeoCoordinate(latitude: latitude, longitude: longitude))
        citySource = .saved
        remember()
    }

    /// Лист «Где снимаем» ответил точкой (`gotoLocation` веба): место
    /// приложения, свет, погода, имя шапки и камера карты едут за ней. Выбор
    /// руками выключает слежение и помнится после перезапуска (29.8в.12;
    /// решение 19 сентября «живёт до перезапуска» отменено словом Алексея 18.10).
    public func movePlace(to c: GeoCoordinate) {
        choseByHand()
        place.move(to: c)
        citySource = .saved
        remember()
    }

    /// «Я здесь» листа и «Моё место» карты: разрешение спрашивается здесь. Место встаёт на точку телефона
    /// сразу, без порога; слежение не трогается — это разовый ответ «где я».
    /// Пока телефон отвечал, место выбрали руками (лист сам спрашивает при первом открытии) — ответ запоминается,
    /// но место не двигает (ревью GPT к 1fd6b27).
    @discardableResult
    public func locateHere() async -> DeviceFix {
        let picks = handPicks
        let r = await locator.currentFix()
        place.noteDeviceResult(r)
        refreshLocationAccess()
        if case .fix(let c) = r, picks != handPicks {
            phoneArrived(c)          // следить уже не за чем: выбор руками выключил слежение
            return r
        }
        if case .fix(let c) = r {
            // «Я здесь» ставит место на телефон всегда, следим или нет; точка запоминается для строки под кнопкой.
            citySource = .device
            place.move(to: c)
            phoneArrived(c)
            startWatchingIfFollowing()
        }
        return r
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

    /// `after` идёт, когда снимок записан на диск и запись подтверждена (без диска — сразу): так стирают файлы кадров, что ушли
    /// из данных, — оборвись приложение раньше, в данных остался бы кадр без картинки (ревью GPT к a2549e7).
    func persist(then after: (@Sendable () -> Void)? = nil) {
        syncAlerts()      // расписание студийного часа — функция данных (30а)
        syncCalendarMirror()    // и событие в Календаре iPhone — тоже (30.2)
        guard let store else { after?(); return }
        let snap = snapshot, prev = saving
        saving = Task {
            await prev?.value
            // С `after` — запись сразу и с ответом: не записалась (диск полон, нет прав) — `after` не идёт,
            // файлы остаются, а снимок уходит обычной отложенной записью ещё раз (ревью GPT к 5d9f57e).
            if let after, (try? await store.saveNow(snap)) != nil { after(); return }
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
        light.placeFollowing = followingLive
        remember()
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

    var nowMs: Int64 { Self.ms(now()) }

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
        announceBusy(restored: id)
        persist()
    }

    /// Съёмка вернулась на занятое время («Занято», «Выходной»): возврат не отменяем, но плашка называет,
    /// чем занято (слово Алексея 01.10). Плашка без кнопки — вернуть уже нечего.
    func announceBusy(restored id: String) {
        guard let s = snapshot.sessions.first(where: { $0.id == id }),
              let hit = SaveGuard.restoredHit(s, blocks: snapshot.blocks, context: clashContext) else { return }
        let facts = PlannerFacts(app: self, dark: false)
        let name = facts.blockLabel(snapshot.blocks[hit.blockIndex])
        let when = hit.allDay ? "" : facts.range(hit.from.map(Double.init), hit.to.map(Double.init))
        undo = UndoOffer(what: .notice, text: lexicon.t("bin.busyBack", ["name": name, "when": when]).trimmingCharacters(in: .whitespaces))
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
            if Bin.restore(id, in: &snapshot, now: nowMs) { announceBusy(restored: id); persist() }
        case .notice:
            break
        case .block(let b, let i):
            Bin.restoreBlock(b, at: i, in: &snapshot, now: nowMs)
            persist()
        case .route(let ids):
            // Место могли удалить за эти секунды — возвращаем только живые.
            let live = Set(snapshot.spots.map(\.id))
            setMapRoute(ids.filter(live.contains))
        case .merge(let m):
            mbEdit { lib, now in lib.undoMerge(m, now: now) }
        case .docAdded(let id):
            discardDoc(id)
        case .docTrashed(let id):
            restoreDoc(id, keepOffer: true)
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
