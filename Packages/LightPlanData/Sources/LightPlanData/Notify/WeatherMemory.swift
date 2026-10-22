import Foundation
import LightPlanCore
import LightPlanDomain

/// Память тревоги «прогноз переменился» в снимке (`card_reference.md`, «Где лежит память»): ключи `wxSeen` — каким
/// прогноз видел человек — и `wxTold` — о чём уже сказали баннер или уведомление. Значения — `{q, sc}`, ключ — `s.id`.
///
/// Пишет только по одной отметке: незнакомое в чужой отметке (поле, которого натив не знает) проходит насквозь,
/// а отметка, которую не удалось прочесть, не стирается молча.
public enum WeatherMemory {
    public static let seenKey = "wxSeen"
    public static let toldKey = "wxTold"

    private static func raw(_ key: String, in snap: Snapshot) -> [String: JSONValue] {
        if case .object(let o)? = snap.extra[key] { return o }
        return [:]
    }

    public static func decode(_ v: JSONValue?) -> SkySnap? {
        guard case .object(let o)? = v, case .string(let q)? = o["q"], let quality = DayQuality(rawValue: q) else { return nil }
        if case .number(let n)? = o["sc"] { return SkySnap(quality: quality, sunset: Int(n)) }
        return SkySnap(quality: quality, sunset: nil)
    }

    public static func encode(_ s: SkySnap) -> JSONValue {
        .object(["q": .string(s.quality.rawValue), "sc": s.sunset.map { .number(Double($0)) } ?? .null])
    }

    /// Прочитанные отметки ключа; непрочитанные пропущены.
    public static func read(_ key: String, in snap: Snapshot) -> [String: SkySnap] {
        raw(key, in: snap).compactMapValues { decode($0) }
    }

    /// Все id, у которых есть отметка в ключе, прочитанная или нет.
    public static func ids(_ key: String, in snap: Snapshot) -> Set<String> { Set(raw(key, in: snap).keys) }

    /// Поставить (`value`) или стереть (`nil`) отметки ключа; остальные не трогаются.
    public static func write(_ key: String, _ changes: [String: SkySnap?], in snap: inout Snapshot) {
        guard !changes.isEmpty else { return }
        var o = raw(key, in: snap)
        for (id, v) in changes { o[id] = v.map(encode) }
        snap.extra[key] = .object(o)
    }

    /// Применить обход: молчаливое знакомство — в `wxSeen`, отметки ушедших записей — из обоих ключей.
    /// `told` — то, что на самом деле сказано (баннер встал, уведомление принято системой): только оно идёт в `wxTold`.
    public static func apply(_ pass: WeatherWatch.Pass, told: [WeatherWatch.Say], in snap: inout Snapshot) {
        var seen: [String: SkySnap?] = pass.seed.mapValues { Optional($0) }
        var toldChanges: [String: SkySnap?] = [:]
        for id in pass.dead { seen[id] = .some(nil); toldChanges[id] = .some(nil) }
        for s in told { toldChanges[s.id] = s.now }
        write(seenKey, seen, in: &snap)
        write(toldKey, toldChanges, in: &snap)
    }
}
