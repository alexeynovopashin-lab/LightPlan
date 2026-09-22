import Foundation
import LightPlanCore
import LightPlanDomain

/// Эталон домена: `Fixtures/domain.json` собирает `Tools/parity/domain.js`
/// (`make domain`), вырезая таблицы и правила прямо из `beta/index.html`. Не
/// сошлось — ошибка переноса, пока не доказано обратное.
enum DomainOracle {
    static var url: URL {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        return u.appendingPathComponent("Fixtures/domain.json")
    }

    static let file: J = {
        do { return try JSONDecoder().decode(J.self, from: Data(contentsOf: url)) }
        catch { fatalError("нет или не читается \(url.path): \(error). Собрать: make domain") }
    }()

    // MARK: - Заглушки — те же, что в эталоне

    /// Место приложения (`LAT`, `LON`, `TZ` стенда).
    static let app = GeoPoint(latitude: file["meta"]["app"]["lat"].double!, longitude: file["meta"]["app"]["lon"].double!)
    static let appOffset = file["meta"]["app"]["tz"].double!

    /// Пояс: долгота / 15 по `Math.round`, у долготы 85.3 — 5.75.
    struct Zones: ZoneResolving {
        func utcOffsetHours(latitude: Double, longitude: Double, on day: CivilDate) -> Double {
            longitude == 85.3 ? 5.75 : Double(max(-12, min(14, jsRound(longitude / 15))))
        }
    }

    /// Дорога по месту назначения.
    static let travelTable: [(Double, Double, TravelTime)] = file["meta"]["travel"].array!.map { row in
        let r = row.array!
        let answer: TravelTime = r[2].isNull ? .unavailable : (r[2].string == "wait" ? .pending : .minutes(r[2].int!))
        return (r[0].double!, r[1].double!, answer)
    }
    static func travel(_ a: GeoPoint, _ b: GeoPoint) -> TravelTime {
        for t in travelTable where t.0 == b.latitude && t.1 == b.longitude { return t.2 }
        return .pending
    }

    /// Погода: плохо в дни, кратные 5 и 7.
    static func skyIsBad(_ d: CivilDate) -> Bool { d.day % 5 == 0 || d.day % 7 == 0 }

    static let spots: [Spot] = file["meta"]["spots"].array!.map(spot)
    static let studios: [Studio] = file["meta"]["studios"].array!.map(studio)

    // MARK: - Записи снимка веба → типы домена

    /// Запись в том виде, в каком её пишет `saveAll`, с умолчаниями веба
    /// (`|| ""`, `|| 0`, `|| []`). Незнакомые коды — `nil`, как их прочтёт
    /// читатель итерации 12.
    static func session(_ j: J) -> Session {
        var s = Session(id: j["id"].string ?? "", kind: RecordKind(rawValue: j["kind"].string ?? "shoot") ?? .shoot,
                        day: civil(j["date"].string!), start: j["min"].int ?? 0,
                        end: j["end"].int, duration: j["dur"].int, genre: j["type"].string.flatMap(Genre.init(rawValue:)))
        s.subGenre = j["sub"].string.flatMap(SubGenre.init(rawValue:))
        s.contact = j["contact"].string ?? ""
        s.place = j["place"].string ?? ""
        s.placeTown = j["placeTown"].string ?? ""
        s.placeAddress = j["placeAddr"].string ?? ""
        s.latitude = j["placeLat"].double
        s.longitude = j["placeLon"].double
        s.studioId = nonEmpty(j["studioId"].string)
        s.rentFrom = j["rentFrom"].int
        s.rentTo = j["rentTo"].int
        s.wishes = (j["wish"].array ?? []).compactMap { $0.string.flatMap(Wish.init(rawValue:)) }
        if j.has("deadlineChoice") {
            let d = j["deadlineChoice"]
            s.deadline = d.isNull ? .none : (d.int.map { .days($0) } ?? .auto)
        }
        s.delivered = j["delivered"].bool ?? false
        s.deliveredAt = j["deliveredAt"].string.flatMap(iso)
        s.pay = nonEmpty(j["pay"].string).flatMap(PayKind.init(rawValue:))
        s.rate = j["rate"].decimal
        s.units = j["units"].decimal ?? 0
        s.expense = j["expense"].decimal ?? 0
        s.prepay = j["prepay"].decimal ?? 0
        s.currency = j["currency"].string.flatMap(Currency.init(rawValue:))
        s.trip = j["trip"].bool ?? false
        s.tripManual = j["tripManual"].bool ?? false
        s.brief = j["brief"].string ?? ""
        s.docs = (j["docs"].array ?? []).map { d in
            Attachment(source: Attachment.Source(rawValue: d["k"].string ?? "doc") ?? .doc, path: d["path"].string,
                       name: d["name"].string, size: d["size"].int, url: d["url"].string,
                       kind: d["kind"].string.flatMap(DocKind.init(rawValue:)))
        }
        s.route = (j["route"].array ?? []).map { r in
            RoutePoint(start: r["t"].int, end: r["t2"].int, name: r["n"].string ?? "", placeText: r["p"].string ?? "",
                       spotId: nonEmpty(r["placeId"].string), studioId: nonEmpty(r["studioId"].string),
                       hallId: nonEmpty(r["hallId"].string), walk: r["walk"].bool ?? false)
        }
        s.doneAt = j["doneAt"].int
        if j.has("rep") {
            let r = j["rep"]
            s.repeatInfo = Repeat(group: r["g"].string!, rule: RepeatRule(rawValue: r["rule"].string!)!,
                                  index: r["i"].int ?? 1, count: r["n"].int ?? 1, monthly: r["monthly"].decimal,
                                  start: r["start"].string.map(civil),
                                  sums: (r["sums"].array ?? []).map { MonthSum(month: $0["k"].int!, sum: $0["sum"].decimal!, at: Int64($0["at"].int!)) })
        }
        return s
    }

    static func block(_ j: J) -> Block {
        var b = Block(id: j["id"].string!, kind: BlockKind(rawValue: j["k"].string ?? "") ?? .busy, from: civil(j["from"].string!))
        b.note = j["note"].string ?? ""
        b.allDay = j["allDay"].bool ?? false
        b.days = j["days"].int ?? 1
        b.start = j["min"].int
        b.duration = j["dur"].int
        b.zoneFrom = j["tzFrom"].double
        b.zoneTo = j["tzTo"].double
        return b
    }

    static func spot(_ j: J) -> Spot {
        var s = Spot(id: j["id"].string!, name: j["name"].string ?? "", latitude: j["lat"].double, longitude: j["lon"].double)
        s.address = j["address"].string ?? ""
        s.town = j["town"].string ?? ""
        s.sub = j["sub"].string ?? ""
        return s
    }

    static func studio(_ j: J) -> Studio {
        var s = Studio(id: j["id"].string!, name: j["name"].string ?? "", latitude: j["lat"].double, longitude: j["lon"].double)
        s.address = j["address"].string ?? ""
        s.phone = j["tel"].string ?? ""
        s.town = j["town"].string ?? ""
        s.halls = (j["halls"].array ?? []).map { Studio.Hall(id: $0["id"].string!, name: $0["name"].string ?? "") }
        return s
    }

    static func civil(_ s: String) -> CivilDate {
        let p = s.split(separator: "-").map { Int($0)! }
        return CivilDate(year: p[0], month: p[1], day: p[2])
    }

    static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// `Math.round` веба: половина — вверх.
    static func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    /// Деньги рядом с числом веба: `Decimal` точнее двоичного, поэтому
    /// сравнение — до двенадцатого знака, а целые, которые видит человек, —
    /// строго (кроме самой половины, где двоичная дробь веба сама на волоске).
    static func sameMoney(_ a: Decimal, _ web: Double) -> Bool {
        let x = NSDecimalNumber(decimal: a).doubleValue
        guard abs(x - web) <= 1e-9 * max(1, abs(web)) else { return false }
        let frac = web - web.rounded(.down)
        if abs(frac - 0.5) < 1e-6 { return true }
        return jsRound(x) == jsRound(web)
    }
}

/// Значение JSON как есть: истина отличается от единицы, порядок массивов
/// сохранён. Словари таблиц эталон пишет парами, поэтому порядок ключей
/// объектов не нужен.
enum J: Decodable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([J])
    case object([String: J])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([J].self) { self = .array(a) }
        else { self = .object(try c.decode([String: J].self)) }
    }

    /// Нет ключа — `.null`, как `undefined` для `!= null` веба.
    subscript(_ key: String) -> J {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }
    subscript(_ i: Int) -> J {
        if case .array(let a) = self, a.indices.contains(i) { return a[i] }
        return .null
    }
    func has(_ key: String) -> Bool {
        if case .object(let o) = self { return o[key] != nil }
        return false
    }

    var isNull: Bool { if case .null = self { return true }; return false }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var double: Double? { if case .number(let n) = self { return n }; return nil }
    var int: Int? { double.map { Int($0) } }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var array: [J]? { if case .array(let a) = self { return a }; return nil }
    var strings: [String]? { array?.compactMap(\.string) }
    /// Число как `Decimal` без двоичного хвоста: по кратчайшей записи, той же,
    /// что напечатал JSON веба.
    var decimal: Decimal? { double.flatMap { Decimal(string: "\($0)") } }
}
