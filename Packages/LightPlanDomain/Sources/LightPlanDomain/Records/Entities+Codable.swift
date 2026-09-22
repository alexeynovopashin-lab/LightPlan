import Foundation
import LightPlanCore

/// Ключи снимка — из комментариев `Entities.swift` (итерация 12, тот же
/// приём, что у `Session+Codable.swift`).
extension Org: Codable {
    enum CodingKeys: String, CodingKey { case id, name, person, phone, req, reqFiles, docs, telLog, mt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "")
        person = try c.decodeIfPresent(String.self, forKey: .person) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        requisites = try c.decodeIfPresent(String.self, forKey: .req) ?? ""
        requisiteFiles = try c.decodeIfPresent([Attachment].self, forKey: .reqFiles) ?? []
        docs = try c.decodeIfPresent([Attachment].self, forKey: .docs) ?? []
        telLog = try c.decodeIfPresent([TelLogEntry].self, forKey: .telLog) ?? []
        modifiedAt = try c.decodeIfPresent(Int64.self, forKey: .mt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(person, forKey: .person)
        try c.encode(phone, forKey: .phone)
        try c.encode(requisites, forKey: .req)
        try c.encode(requisiteFiles, forKey: .reqFiles)
        try c.encode(docs, forKey: .docs)
        try c.encode(telLog, forKey: .telLog)
        try c.encodeIfPresent(modifiedAt, forKey: .mt)
    }
}

extension Block: Codable {
    enum CodingKeys: String, CodingKey { case id, k, note, from, allDay, days, min, dur, tzFrom, tzTo, mt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let fromString = try c.decodeIfPresent(String.self, forKey: .from),
              let from = CivilDate(snapshotString: fromString) else {
            throw DecodingError.dataCorruptedError(forKey: .from, in: c, debugDescription: "день блока не разобрался")
        }
        self.init(id: try c.decode(String.self, forKey: .id),
                  kind: try c.decodeLenient(BlockKind.self, forKey: .k, default: .busy),
                  from: from)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 1
        start = try c.decodeIfPresent(Int.self, forKey: .min)
        duration = try c.decodeIfPresent(Int.self, forKey: .dur)
        zoneFrom = try c.decodeIfPresent(Double.self, forKey: .tzFrom)
        zoneTo = try c.decodeIfPresent(Double.self, forKey: .tzTo)
        modifiedAt = try c.decodeIfPresent(Int64.self, forKey: .mt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .k)
        try c.encode(note, forKey: .note)
        try c.encode(from.snapshotString, forKey: .from)
        try c.encode(allDay, forKey: .allDay)
        try c.encode(days, forKey: .days)
        try c.encodeIfPresent(start, forKey: .min)
        try c.encodeIfPresent(duration, forKey: .dur)
        try c.encodeIfPresent(zoneFrom, forKey: .tzFrom)
        try c.encodeIfPresent(zoneTo, forKey: .tzTo)
        try c.encodeIfPresent(modifiedAt, forKey: .mt)
    }
}

extension Spot: Codable {
    enum CodingKeys: String, CodingKey { case id, name, address, town, sub, lat, lon, mt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  latitude: try c.decodeIfPresent(Double.self, forKey: .lat),
                  longitude: try c.decodeIfPresent(Double.self, forKey: .lon))
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        town = try c.decodeIfPresent(String.self, forKey: .town) ?? ""
        sub = try c.decodeIfPresent(String.self, forKey: .sub) ?? ""
        modifiedAt = try c.decodeIfPresent(Int64.self, forKey: .mt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(address, forKey: .address)
        try c.encode(town, forKey: .town)
        try c.encode(sub, forKey: .sub)
        try c.encodeIfPresent(latitude, forKey: .lat)
        try c.encodeIfPresent(longitude, forKey: .lon)
        try c.encodeIfPresent(modifiedAt, forKey: .mt)
    }
}

extension Studio: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, address, tel, town, lat, lon, halls, key, tomcohId, hourMin, mt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  latitude: try c.decodeIfPresent(Double.self, forKey: .lat),
                  longitude: try c.decodeIfPresent(Double.self, forKey: .lon))
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .tel) ?? ""
        town = try c.decodeIfPresent(String.self, forKey: .town) ?? ""
        halls = try c.decodeIfPresent([Hall].self, forKey: .halls) ?? []
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        catalogId = try c.decodeIfPresent(String.self, forKey: .tomcohId)
        hourMinutes = try c.decodeIfPresent(Int.self, forKey: .hourMin)
        modifiedAt = try c.decodeIfPresent(Int64.self, forKey: .mt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(address, forKey: .address)
        try c.encode(phone, forKey: .tel)
        try c.encode(town, forKey: .town)
        try c.encodeIfPresent(latitude, forKey: .lat)
        try c.encodeIfPresent(longitude, forKey: .lon)
        try c.encode(halls, forKey: .halls)
        try c.encode(key, forKey: .key)
        try c.encodeIfPresent(catalogId, forKey: .tomcohId)
        try c.encodeIfPresent(hourMinutes, forKey: .hourMin)
        try c.encodeIfPresent(modifiedAt, forKey: .mt)
    }
}

extension Studio.Hall: Codable {
    enum CodingKeys: String, CodingKey { case id, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
    }
}

/// `rec`, `at`, `del`.
extension TrashedItem: Codable {
    enum CodingKeys: String, CodingKey { case rec, at, del }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(record: try c.decode(Session.self, forKey: .rec),
                  index: try c.decodeIfPresent(Int.self, forKey: .at) ?? 0,
                  deletedAt: try c.decodeIfPresent(Int64.self, forKey: .del) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(record, forKey: .rec)
        try c.encode(index, forKey: .at)
        try c.encode(deletedAt, forKey: .del)
    }
}

/// `g`, `rule`, `i`, `n`, `monthly`, `start`, `sums`, `stop`.
extension Repeat: Codable {
    enum CodingKeys: String, CodingKey { case g, rule, i, n, monthly, start, sums, stop }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `.month` — оборонительное умолчание для порченого кода правила,
        // у веба такого умолчания нет: цепочка повтора без разбора кода
        // потеряла бы больше, чем неверная периодичность одной группы.
        self.init(group: try c.decode(String.self, forKey: .g),
                  rule: try c.decodeLenient(RepeatRule.self, forKey: .rule, default: .month),
                  index: try c.decodeIfPresent(Int.self, forKey: .i) ?? 0,
                  count: try c.decodeIfPresent(Int.self, forKey: .n) ?? 1,
                  monthly: try c.decodeIfPresent(Decimal.self, forKey: .monthly),
                  start: try c.decodeIfPresent(String.self, forKey: .start).flatMap { CivilDate(snapshotString: $0) },
                  sums: try c.decodeIfPresent([MonthSum].self, forKey: .sums) ?? [])
        stopped = try c.decodeIfPresent(Bool.self, forKey: .stop) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(group, forKey: .g)
        try c.encode(rule.rawValue, forKey: .rule)
        try c.encode(index, forKey: .i)
        try c.encode(count, forKey: .n)
        try c.encodeIfPresent(monthly, forKey: .monthly)
        try c.encodeIfPresent(start?.snapshotString, forKey: .start)
        try c.encode(sums, forKey: .sums)
        try c.encode(stopped, forKey: .stop)
    }
}

/// `k`, `sum`, `at`.
extension MonthSum: Codable {
    enum CodingKeys: String, CodingKey { case k, sum, at }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(month: try c.decode(Int.self, forKey: .k),
                  sum: try c.decode(Decimal.self, forKey: .sum),
                  at: try c.decodeIfPresent(Int64.self, forKey: .at) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(month, forKey: .k)
        try c.encode(sum, forKey: .sum)
        try c.encode(at, forKey: .at)
    }
}
