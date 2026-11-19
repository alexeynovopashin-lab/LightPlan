import Foundation
import LightPlanCore
import LightPlanDomain

/// Весь снимок веба — плоский объект под ключом `lightplan(.beta).v1`
/// (`saveAll`, `docs/17` § 6). Здесь так же плоско, не разложено на
/// «настройки» и «записи»: в файле веба это один объект, и повторять его
/// форму дешевле, чем придумывать своё разбиение.
///
/// Известные ключи получают свой тип. Остальные (`shots`, `boards`, `zones`,
/// `notif`, `me`, `packs`, …) веб пишет и читает сам, у Swift для них пока
/// нет типа — итерации 20, 28, 30 дадут. До той поры они лежат в `extra`
/// как есть и переживают чтение-запись без потерь: правило итерации 12 —
/// «импорт ничего не удаляет».
public struct Snapshot: Sendable, Hashable {
    public var sessions: [Session] = []
    public var orgs: [Org] = []
    /// Частные клиенты (шаг К1 «Клиенты»): только у нас, веб при пересохранении раздел выбрасывает — тогда проход
    /// `clientsAssembled` повторится и соберёт их заново из записей.
    public var clients: [Client] = []
    /// Разовый проход по уже записанным съёмкам сделан (справка `clients_reference.md` § 3.8).
    public var clientsAssembled: Bool = false
    public var blocks: [Block] = []
    public var spots: [Spot] = []
    public var studios: [Studio] = []
    public var trashed: [TrashedItem] = []
    /// «Мои» (итерация 28д): бумага без съёмки и без организации.
    public var myDocs: [Attachment] = []
    /// Корзина документов; корзина съёмок — `trashed`, другая.
    public var trashedDocs: [TrashedDoc] = []

    public var locLatitude: Double?
    public var locLongitude: Double?
    public var theme: String?
    public var clock: String?
    public var tempUnit: String?
    public var currency: Currency?
    public var timeStep: Int?
    public var travelMin: Int?
    public var pro: Bool = false
    /// Режим приложения: `simple`, `pro`, `astro` (30г.3). Веб его не знает и теряет при пересохранении, ключа может не быть;
    /// как тогда читается режим — `AppMode.read`.
    public var appMode: String?
    /// Выключенные переключатели «Астро» (30г.4): `moon`, `stars`, `azimuths`, `terms`, `milkyWay`. Веб ключа не знает и
    /// теряет его; нет ключа — как тогда читать, решает `AstroSwitches.read`.
    public var astroOff: [String]?
    public var ribbonMode: String?
    public var drumSlot: String?
    /// Сводка «Карты» свёрнута. По умолчанию — да (слово Алексея 01.10; у беты без сохранения развёрнута,
    /// намеренный отход). Явный выбор записывается и переживает перезапуск.
    public var mapFold: Bool = true
    public var mapLabels: Bool = false
    public var mapLayers: [String: Bool]?
    public var dayFold: Bool = false
    /// «Завершать вручную» (настройки «Съёмок», веб `manualEnd`): съёмка
    /// кончается нажатием «Завершить», а не записанным концом.
    public var manualEnd: Bool = false
    public var practice: String?
    public var genres: [Genre] = []
    public var genrePrefs: [Genre: GenrePrefs] = [:]
    public var defaultRate: Decimal = 0
    /// Пакеты по жанрам (веб `packs`, `genrePacks`). Строки без цены живут
    /// в редакторе и в файле, но при чтении отбрасываются, как у веба.
    public var packs: [Genre: [Pack]] = [:]
    public var delivery: DeliverySetting = .standard
    public var equipment: [String] = []
    /// Плеер по умолчанию (веб `musicApp`: `"yandex"`, `"spotify"`, `"apple"`, `"off"`). Строка как записана:
    /// незнакомое значение веб читает как «выкл», но пишет обратно как есть — и мы тоже.
    public var musicApp: String?
    /// С какого дня начинается неделя (только у нас, Алексей 28.10): `"sun"`, `"sat"`, `"auto"` (как в системе); нет ключа — понедельник,
    /// как у веба. Веб ключа не знает и при пересохранении выбрасывает — неделя снова с понедельника.
    public var weekStart: String?
    /// Вид экрана «Свет» (30з.2а, только у нас): `"flat"` — без блоков (вид 30з.1); нет ключа — с блоками. Веб ключа не знает.
    public var lightView: String?
    /// Библиотека плейлистов (веб `playlists`, до десяти). Пустой список в файл не пишется.
    public var playlists: [Playlist] = []
    public var cardOrder: [GenreGroup: [CardBlock]] = [:]
    public var cardOff: [GenreGroup: [CardBlock]] = [:]
    public var sync: String = "off"

    /// Ключи, которым Swift пока не дал типа (см. заголовок).
    public var extra: [String: JSONValue] = [:]

    public init() {}
}

extension Snapshot {
    /// Бумаги снимка как одно целое для правил `DocLibrary`. Запись обратно трогает только то, что
    /// правила меняют: съёмки, организации, «Мои», корзину документов; корзина съёмок остаётся.
    public var docLibrary: DocLibrary {
        get {
            DocLibrary(sessions: sessions, orgs: orgs, myDocs: myDocs, trashedDocs: trashedDocs,
                       trashedSessionIds: Set(trashed.map(\.record.id)))
        }
        set {
            sessions = newValue.sessions
            orgs = newValue.orgs
            myDocs = newValue.myDocs
            trashedDocs = newValue.trashedDocs
        }
    }
}

extension Snapshot: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case sessions, orgs, clients, clientsAssembled, blocks, spots, studios, trashed, myDocs, trashedDocs
        case loc, theme, clock, tempUnit, currency, timeStep, travelMin
        case pro, appMode, astroOff, ribbonMode, drumSlot, mapFold, mapLabels, mapLayers, dayFold, manualEnd
        case practice, genres, genrePrefs, defaultRate, packs, delivery, equipment, musicApp, playlists, weekStart, lightView
        case cardOrder, cardOff, sync
    }

    /// Элемент списка плейлистов, не разобравшийся — `nil`, а не отказ всего снимка.
    private struct LossyPlaylist: Decodable {
        let value: Playlist?
        init(from decoder: Decoder) throws { value = try? Playlist(from: decoder) }
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    /// Строгое чтение — как всегда: одна неразобранная запись роняет весь снимок (`StoreError.corrupted`). Щадящее
    /// (31.11) — только когда строгое уже упало и `Store` читает свой файл: в `userInfo` лежит `SnapshotSalvage`,
    /// неразобранная запись раздела выпадает (счёт в `dropped`), неразобранное поле берёт значение «нет ключа»
    /// (`fields`), раздел не массивом — в `lostSections`, и тогда снимок не годится (решает `ImportedFile.salvage`).
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let salvage = decoder.userInfo[SnapshotSalvage.key] as? SnapshotSalvage

        func records<T: Decodable>(_ key: CodingKeys) throws -> [T] {
            guard let salvage else { return try c.decodeIfPresent([T].self, forKey: key) ?? [] }
            guard c.contains(key), (try? c.decodeNil(forKey: key)) != true else { return [] }
            guard let items = try? c.decode([SalvagedItem<T>].self, forKey: key) else {
                salvage.lostSections.append(key.stringValue)
                return []
            }
            salvage.dropped += items.filter { $0.value == nil }.count
            return items.compactMap(\.value)
        }
        func soft<T>(_ fallback: @autoclosure () -> T, _ get: () throws -> T) throws -> T {
            guard let salvage else { return try get() }
            do { return try get() } catch { salvage.fields += 1; return fallback() }
        }

        sessions = try records(.sessions)
        orgs = try records(.orgs)
        clients = try records(.clients)
        clientsAssembled = try soft(false) { try c.decodeIfPresent(Bool.self, forKey: .clientsAssembled) ?? false }
        blocks = try records(.blocks)
        spots = try records(.spots)
        studios = try records(.studios)
        trashed = try records(.trashed)
        myDocs = try records(.myDocs)
        trashedDocs = try records(.trashedDocs)

        let loc = try soft(nil) { try c.decodeIfPresent([String: Double].self, forKey: .loc) }
        locLatitude = loc?["lat"]
        locLongitude = loc?["lon"]
        theme = try soft(nil) { try c.decodeIfPresent(String.self, forKey: .theme) }
        clock = try soft(nil) { try c.decodeIfPresent(String.self, forKey: .clock) }
        tempUnit = try soft(nil) { try c.decodeIfPresent(String.self, forKey: .tempUnit) }
        currency = try soft(nil) { try c.decodeLenient(Currency.self, forKey: .currency) }
        timeStep = try soft(nil) { try c.decodeIfPresent(Int.self, forKey: .timeStep) }
        travelMin = try soft(nil) { try c.decodeIfPresent(Int.self, forKey: .travelMin) }
        pro = try soft(false) { try c.decodeIfPresent(Bool.self, forKey: .pro) ?? false }
        appMode = try? c.decodeIfPresent(String.self, forKey: .appMode)
        astroOff = try? c.decodeIfPresent([String].self, forKey: .astroOff)
        ribbonMode = try soft(nil) { try c.decodeIfPresent(String.self, forKey: .ribbonMode) }
        drumSlot = try soft(nil) { try c.decodeIfPresent(String.self, forKey: .drumSlot) }
        mapFold = try soft(true) { try c.decodeIfPresent(Bool.self, forKey: .mapFold) ?? true }
        mapLabels = try soft(false) { try c.decodeIfPresent(Bool.self, forKey: .mapLabels) ?? false }
        mapLayers = try soft(nil) { try c.decodeIfPresent([String: Bool].self, forKey: .mapLayers) }
        dayFold = try soft(false) { try c.decodeIfPresent(Bool.self, forKey: .dayFold) ?? false }
        manualEnd = try soft(false) { try c.decodeIfPresent(Bool.self, forKey: .manualEnd) ?? false }
        practice = try soft(nil) { try c.decodeIfPresent(String.self, forKey: .practice) }
        genres = try soft([]) { try c.decodeLenientArray(Genre.self, forKey: .genres) }
        genrePrefs = try soft([:]) { try c.decodeLenientDictionary(keyedBy: Genre.self, valueType: GenrePrefs.self, forKey: .genrePrefs) }
        defaultRate = try soft(0) { try c.decodeIfPresent(Decimal.self, forKey: .defaultRate) ?? 0 }
        packs = Pack.genrePacks(from: try? c.decodeIfPresent(JSONValue.self, forKey: .packs))
        delivery = try soft(.standard) { try c.decodeIfPresent(DeliverySetting.self, forKey: .delivery) ?? .standard }
        equipment = try soft([]) { try c.decodeIfPresent([String].self, forKey: .equipment) ?? [] }
        musicApp = try? c.decodeIfPresent(String.self, forKey: .musicApp)
        weekStart = try? c.decodeIfPresent(String.self, forKey: .weekStart)
        lightView = try? c.decodeIfPresent(String.self, forKey: .lightView)
        // Запись без имени или без адреса веб при чтении отбрасывает молча; не массив — как пусто.
        let lossy = (try? c.decodeIfPresent([LossyPlaylist].self, forKey: .playlists)).flatMap { $0 } ?? []
        playlists = Music.clean(lossy.compactMap(\.value))
        cardOrder = try soft([:]) {
            try c.decodeLenientDictionaryOfArrays(keyedBy: GenreGroup.self, elementType: CardBlock.self, forKey: .cardOrder)
        }
        cardOff = try soft([:]) {
            try c.decodeLenientDictionaryOfArrays(keyedBy: GenreGroup.self, elementType: CardBlock.self, forKey: .cardOff)
        }
        sync = try soft("off") { try c.decodeIfPresent(String.self, forKey: .sync) ?? "off" }

        let dyn = try decoder.container(keyedBy: DynamicKey.self)
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        var rest: [String: JSONValue] = [:]
        for key in dyn.allKeys where !known.contains(key.stringValue) {
            rest[key.stringValue] = try soft(nil) { try dyn.decode(JSONValue.self, forKey: key) }
        }
        extra = rest
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(orgs, forKey: .orgs)
        // Пустого раздела и непройденного прохода в файле нет: файл без клиентов байт в байт как до К1.
        if !clients.isEmpty { try c.encode(clients, forKey: .clients) }
        if clientsAssembled { try c.encode(true, forKey: .clientsAssembled) }
        try c.encode(blocks, forKey: .blocks)
        try c.encode(spots, forKey: .spots)
        try c.encode(studios, forKey: .studios)
        try c.encode(trashed, forKey: .trashed)
        try c.encode(myDocs, forKey: .myDocs)
        try c.encode(trashedDocs, forKey: .trashedDocs)

        if let locLatitude, let locLongitude {
            try c.encode(["lat": locLatitude, "lon": locLongitude], forKey: .loc)
        }
        try c.encodeIfPresent(theme, forKey: .theme)
        try c.encodeIfPresent(clock, forKey: .clock)
        try c.encodeIfPresent(tempUnit, forKey: .tempUnit)
        try c.encodeLenient(currency, forKey: .currency)
        try c.encodeIfPresent(timeStep, forKey: .timeStep)
        try c.encodeIfPresent(travelMin, forKey: .travelMin)
        try c.encode(pro, forKey: .pro)
        try c.encodeIfPresent(appMode, forKey: .appMode)
        try c.encodeIfPresent(astroOff, forKey: .astroOff)
        try c.encodeIfPresent(ribbonMode, forKey: .ribbonMode)
        try c.encodeIfPresent(drumSlot, forKey: .drumSlot)
        try c.encode(mapFold, forKey: .mapFold)
        try c.encode(mapLabels, forKey: .mapLabels)
        try c.encodeIfPresent(mapLayers, forKey: .mapLayers)
        try c.encode(dayFold, forKey: .dayFold)
        try c.encode(manualEnd, forKey: .manualEnd)
        try c.encodeIfPresent(practice, forKey: .practice)
        try c.encodeLenientArray(genres, forKey: .genres)
        try c.encodeLenientDictionary(genrePrefs, forKey: .genrePrefs)
        try c.encode(defaultRate, forKey: .defaultRate)
        if !packs.isEmpty {
            try c.encode(Dictionary(uniqueKeysWithValues: packs.map { ($0.key.rawValue, $0.value) }), forKey: .packs)
        }
        try c.encode(delivery, forKey: .delivery)
        try c.encode(equipment, forKey: .equipment)
        try c.encodeIfPresent(musicApp, forKey: .musicApp)
        try c.encodeIfPresent(weekStart, forKey: .weekStart)
        try c.encodeIfPresent(lightView, forKey: .lightView)
        if !playlists.isEmpty { try c.encode(playlists, forKey: .playlists) }
        try c.encodeLenientDictionaryOfArrays(cardOrder, forKey: .cardOrder)
        try c.encodeLenientDictionaryOfArrays(cardOff, forKey: .cardOff)
        try c.encode(sync, forKey: .sync)

        var dyn = encoder.container(keyedBy: DynamicKey.self)
        for (k, v) in extra {
            guard let key = DynamicKey(stringValue: k) else { continue }
            try dyn.encode(v, forKey: key)
        }
    }
}

/// Счёт щадящего чтения (31.11, см. `Snapshot.init(from:)`): живёт одно чтение, потом читается `ImportedFile.salvage`.
final class SnapshotSalvage: @unchecked Sendable {
    static let key = CodingUserInfoKey(rawValue: "lightplan.snapshotSalvage")!
    /// Записей разделов (съёмки, организации, клиенты, …), которые не разобрались и выпали.
    var dropped = 0
    /// Полей настроек, которые не разобрались и взяли значение «нет ключа».
    var fields = 0
    /// Разделы, которые в файле есть, но не массив: их записи пропали бы целиком.
    var lostSections: [String] = []
}

/// Элемент раздела, не разобравшийся, — `nil` (как `LossyPlaylist`, но для любой записи).
private struct SalvagedItem<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
