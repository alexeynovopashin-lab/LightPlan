import SwiftUI
import QuartzCore

// MARK: - Автопрокрутка листа у краёв, пока строка в руке (27а.3)

/// Мост между листом карточки и списком порядка: лист говорит, где его окно и как далеко он
/// прокручен, список двигает его у краёв. Класс, а не значения в `@State`: прокрутка меняет эти
/// числа каждый кадр, и подписанные на них виды пересчитывались бы вхолостую.
@MainActor
final class CardScrollBridge {
    /// Окно листа в координатах экрана.
    var viewport: CGRect = .zero
    /// Прокрутка листа сейчас и самая дальняя.
    var offset: CGFloat = 0
    var maxOffset: CGFloat = 0
    /// Двигает лист на `y` (задаёт `CardScreen`).
    var scrollTo: (CGFloat) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var cardScroll: CardScrollBridge? = nil
}

/// Числа автопрокрутки. Зона и скорость — по маршруту на Карте (у него 22 pt от края и 6 pt на событие
/// жеста, то есть 360–720 pt/с при 60–120 Гц), но с поправкой на карточку: строка 56 pt и палец на
/// ручке стоит у её середины, поэтому зона шире — 72, примерно строка и четверть; скорость растёт
/// от нуля на границе зоны до 420 pt/с на самом краю окна, так что девять строк (572 pt) лист
/// проезжает за полторы секунды, а не за четверть.
enum CardAutoScroll {
    static let zone: CGFloat = 72
    static let maxSpeed: CGFloat = 420
    /// Период шага, с.
    static let tick: Double = 1.0 / 60

    /// Скорость листа, pt/с (вниз — плюс): палец на `y` в окне от `top` до `bottom`.
    static func velocity(y: CGFloat, top: CGFloat, bottom: CGFloat) -> CGFloat {
        let z = min(zone, (bottom - top) / 2)
        guard z > 0 else { return 0 }
        if y < top + z { return -maxSpeed * min(1, (top + z - y) / z) }
        if y > bottom - z { return maxSpeed * min(1, (y - (bottom - z)) / z) }
        return 0
    }

    /// Куда встанет прокрутка за `dt` с, не выходя за `0 ... max`.
    static func next(offset: CGFloat, velocity: CGFloat, dt: Double, max limit: CGFloat) -> CGFloat {
        min(max(offset + velocity * CGFloat(dt), 0), max(0, limit))
    }
}
