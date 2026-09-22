import Foundation

/// Категория дня — одно слово на мок и на настоящий прогноз (веб `QUAL`,
/// `scoreCat`, `deriveQ`). `.fog` не встречается у `SunsetScore.category(_:)` —
/// туман перебивает категорию раньше, чем считается закатный балл.
public enum DayQuality: String, Sendable, Equatable, CaseIterable {
    case excellent, good, plain, poor, fog

    /// Облачность мока для этой категории (веб `QUAL_C.cloud`) — ориентир для
    /// детерминированной выдумки офлайн, не измеренная величина.
    public var mockCloud: Double {
        switch self {
        case .excellent: return 12
        case .fog: return 30
        case .good: return 45
        case .plain: return 60
        case .poor: return 92
        }
    }
}
