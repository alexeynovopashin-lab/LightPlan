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
    public var blocks: [Block] = []
    public var spots: [Spot] = []
    public var studios: [Studio] = []
    public var trashed: [TrashedItem] = []

    public var locLatitude: Double?
    public var locLongitude: Double?
    public var theme: String?
    public var clock: String?
    public var tempUnit: String?
    public var currency: Currency?
    public var timeStep: Int?
    public var travelMin: Int?
    public var pro: Bool = false
    public var ribbonMode: String?
    public var drumSlot: String?
    public var mapFold: Bool = false
    public var mapLabels: Bool = false
    public var mapLayers: [String: Bool]?
    public var dayFold: Bool = false
    public var practice: String?
    public var genres: [Genre] = []
    public var genrePrefs: [Genre: GenrePrefs] = [:]
    public var defaultRate: Decimal = 0
    public var delivery: DeliverySetting = .standard
    public var equipment: [String] = []
    public var cardOrder: [GenreGroup: [CardBlock]] = [:]
    public var cardOff: [GenreGroup: [CardBlock]] = [:]
    public var sync: String = "off"

    /// Ключи, которым Swift пока не дал типа (см. заголовок).
    public var extra: [String: JSONValue] = [:]

    public init() {}
}

extension Snapshot: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case sessions, orgs, blocks, spots, studios, trashed
        case loc, theme, clock, tempUnit, currency, timeStep, travelMin
        case pro, ribbonMode, drumSlot, mapFold, mapLabels, mapLayers, dayFold
        case practice, genres, genrePrefs, defaultRate, delivery, equipment
        case cardOrder, cardOff, sync
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        orgs = try c.decodeIfPresent([Org].self, forKey: .orgs) ?? []
        blocks = try c.decodeIfPresent([Block].self, forKey: .blocks) ?? []
        spots = try c.decodeIfPresent([Spot].self, forKey: .spots) ?? []
        studios = try c.decodeIfPresent([Studio].self, forKey: .studios) ?? []
        trashed = try c.decodeIfPresent([TrashedItem].self, forKey: .trashed) ?? []

        let loc = try c.decodeIfPresent([String: Double].self, forKey: .loc)
        locLatitude = loc?["lat"]
        locLongitude = loc?["lon"]
        theme = try c.decodeIfPresent(String.self, forKey: .theme)
        clock = try c.decodeIfPresent(String.self, forKey: .clock)
        tempUnit = try c.decodeIfPresent(String.self, forKey: .tempUnit)
        currency = try c.decodeLenient(Currency.self, forKey: .currency)
        timeStep = try c.decodeIfPresent(Int.self, forKey: .timeStep)
        travelMin = try c.decodeIfPresent(Int.self, forKey: .travelMin)
        pro = try c.decodeIfPresent(Bool.self, forKey: .pro) ?? false
        ribbonMode = try c.decodeIfPresent(String.self, forKey: .ribbonMode)
        drumSlot = try c.decodeIfPresent(String.self, forKey: .drumSlot)
        mapFold = try c.decodeIfPresent(Bool.self, forKey: .mapFold) ?? false
        mapLabels = try c.decodeIfPresent(Bool.self, forKey: .mapLabels) ?? false
        mapLayers = try c.decodeIfPresent([String: Bool].self, forKey: .mapLayers)
        dayFold = try c.decodeIfPresent(Bool.self, forKey: .dayFold) ?? false
        practice = try c.decodeIfPresent(String.self, forKey: .practice)
        genres = try c.decodeLenientArray(Genre.self, forKey: .genres)
        genrePrefs = try c.decodeLenientDictionary(keyedBy: Genre.self, valueType: GenrePrefs.self, forKey: .genrePrefs)
        defaultRate = try c.decodeIfPresent(Decimal.self, forKey: .defaultRate) ?? 0
        delivery = try c.decodeIfPresent(DeliverySetting.self, forKey: .delivery) ?? .standard
        equipment = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
        cardOrder = try c.decodeLenientDictionaryOfArrays(keyedBy: GenreGroup.self, elementType: CardBlock.self, forKey: .cardOrder)
        cardOff = try c.decodeLenientDictionaryOfArrays(keyedBy: GenreGroup.self, elementType: CardBlock.self, forKey: .cardOff)
        sync = try c.decodeIfPresent(String.self, forKey: .sync) ?? "off"

        let dyn = try decoder.container(keyedBy: DynamicKey.self)
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        var rest: [String: JSONValue] = [:]
        for key in dyn.allKeys where !known.contains(key.stringValue) {
            rest[key.stringValue] = try dyn.decode(JSONValue.self, forKey: key)
        }
        extra = rest
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(orgs, forKey: .orgs)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(spots, forKey: .spots)
        try c.encode(studios, forKey: .studios)
        try c.encode(trashed, forKey: .trashed)

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
        try c.encodeIfPresent(ribbonMode, forKey: .ribbonMode)
        try c.encodeIfPresent(drumSlot, forKey: .drumSlot)
        try c.encode(mapFold, forKey: .mapFold)
        try c.encode(mapLabels, forKey: .mapLabels)
        try c.encodeIfPresent(mapLayers, forKey: .mapLayers)
        try c.encode(dayFold, forKey: .dayFold)
        try c.encodeIfPresent(practice, forKey: .practice)
        try c.encodeLenientArray(genres, forKey: .genres)
        try c.encodeLenientDictionary(genrePrefs, forKey: .genrePrefs)
        try c.encode(defaultRate, forKey: .defaultRate)
        try c.encode(delivery, forKey: .delivery)
        try c.encode(equipment, forKey: .equipment)
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
