import Foundation
import LightPlanData

/// Тестовый засев прототипа (Алексей, 29.09): записи сезона, лежат в пакете
/// (`Resources/test_seed.json`); копия ветки берёт их при первом запуске.
enum TestSeed {
    /// Запись `sd_today_wed` (27: маршрут и референсы «сегодня») переносится на день первого
    /// запуска по часам Томска — чтобы лента точек показывала прошедшие и текущую, а не «после».
    static func snapshot(now: Date = Date()) -> Snapshot? {
        guard let url = Bundle.module.url(forResource: "test_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: rebased(data, now: now))
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
        sessions[at]["date"] = iso.string(from: cal.startOfDay(for: now))
        root["sessions"] = sessions
        return (try? JSONSerialization.data(withJSONObject: root)) ?? data
    }
}
