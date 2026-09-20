import SwiftUI

/// Песочница итерации 4: два пути холста карты рядом, на одном месте.
/// Ни записей, ни погоды, ни настоящего прибора здесь нет — проверяется
/// единственное: спорит холст с разметкой прибора или нет.
@main
struct MapCanvasSpikeApp: App {
    var body: some Scene {
        WindowGroup { SpikeScreen() }
    }
}

/// Путь холста. Третий путь плана («свой рендер») снят § 22 архитектуры.
enum CanvasPath: String, CaseIterable, Identifiable {
    case mapKit = "MapKit"
    case mapLibre = "MapLibre"
    var id: String { rawValue }
}

enum Place: String, CaseIterable, Identifiable {
    case city = "Город"
    case nature = "Природа"
    var id: String { rawValue }

    /// Томск — город всех замеров веба. Природа — Таловские чаши под Томском:
    /// та же широта, но ни застройки, ни дорожной сетки.
    var lat: Double { self == .city ? 56.4847 : 56.2350 }
    var lon: Double { self == .city ? 84.9482 : 84.9840 }
    /// Зум MapLibre. Зум MapKit задаётся расстоянием, см. `MapKitCanvas`.
    var zoom: Double { self == .city ? 14 : 12 }
}
