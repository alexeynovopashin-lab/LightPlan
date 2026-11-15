import Foundation
import LightPlanData

/// Тестовый засев прототипа (Алексей, 29.09): записи сезона, лежат в пакете
/// (`Resources/test_seed.json`); копия ветки берёт их при первом запуске.
enum TestSeed {
    /// Запись `sd_today_wed` (27: маршрут и референсы «сегодня») переносится на день первого
    /// запуска по часам Томска — чтобы лента точек показывала прошедшие и текущую, а не «после».
    static func snapshot(now: Date = Date()) -> Snapshot? {
        guard let data = rawData() else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: rebased(data, now: now))
    }

    /// Файл засева как есть (тесты читают его же, не через `snapshot`).
    static func rawData() -> Data? {
        Bundle.module.url(forResource: "test_seed", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }

    static func rebased(_ data: Data, now: Date) -> Data {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var sessions = root["sessions"] as? [[String: Any]],
              let at = sessions.firstIndex(where: { $0["id"] as? String == "sd_today_wed" }),
              let zone = TimeZone(identifier: "Asia/Tomsk") else { return data }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let today = cal.startOfDay(for: now)
        // 30и.12: свадьба «сегодня» идёт с 08:00 до 02:00 — любая другая запись засева, выпавшая на этот день
        // (в ноябре это был «День города» 12:00–18:00, форма свадьбы писала «Время пересекается»), уезжает на
        // следующий. Пара «clash» (25.09), которая нарочно пересекается сама с собой, остаётся парой: оба её конца едут вместе.
        for i in sessions.indices where i != at {
            guard let text = sessions[i]["date"] as? String, let d = iso.date(from: text),
                  cal.isDate(d, inSameDayAs: today), let next = cal.date(byAdding: .day, value: 1, to: d) else { continue }
            sessions[i]["date"] = iso.string(from: next)
        }
        sessions[at]["date"] = iso.string(from: today)
        root["sessions"] = sessions
        return (try? JSONSerialization.data(withJSONObject: root)) ?? data
    }
}
