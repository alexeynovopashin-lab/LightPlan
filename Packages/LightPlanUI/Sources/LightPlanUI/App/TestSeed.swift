import Foundation
import LightPlanData

/// Тестовый засев прототипа (Алексей, 29.09): записи сезона, лежат в пакете
/// (`Resources/test_seed.json`); копия ветки берёт их при первом запуске.
enum TestSeed {
    static func snapshot() -> Snapshot? {
        guard let url = Bundle.module.url(forResource: "test_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
