import Foundation

/// Закатный балл — сердце продукта (порт `sunsetScore`, `scoreCat`, `deriveQ`
/// беты). Три яруса облаков и влажность в час заката; аэрозоль — поправка
/// поверх, не слагаемое (§ 4.6, 5.1 плана).
public enum SunsetScore {
    /// Колокол Гаусса, пик в `c`, ширина `w` (веб `bell`).
    static func bell(_ x: Double, _ c: Double, _ w: Double) -> Double {
        let z = (x - c) / w
        return exp(-z * z)
    }

    /// Низкий ярус (0–2 км) — блокиратор: закрывает горизонт, свет не
    /// пробьётся выше. Средний (2–7 км) — текстура: объём, лиловый и
    /// оранжевый. Верхний (>7 км) — экран: перистые держат afterglow. Влажность
    /// — дымка (рассеяние Ми), гасит чистый цвет. Аэрозоль красит уже имеющийся
    /// свет: до 0.35 взвесь работает светофильтром, выше — гасит.
    ///
    /// Порядок операций как в JS: `Math.round`, затем зажим в 0…100 — не
    /// наоборот, число выходит за оба края по дороге.
    public static func score(low: Double, mid: Double, high: Double, humidity: Double, air: AirSample? = nil) -> Int {
        let hi = bell(high, 50, 30)
        let mdBell = bell(mid, 45, 30)
        let canvas = 30 + hi * 45 + mdBell * 25
        let gap = low <= 20 ? 1.0 : low >= 70 ? 0.05 : 1 - (low - 20) / 50 * 0.95
        var s = canvas * gap
        if humidity > 70 { s -= (humidity - 70) * 0.6 }
        if let aod = air?.aod, aod.isFinite {
            if aod <= 0.35 {
                s += 10 * bell(aod * 100, 15, 14)
            } else {
                s *= max(0.5, 1 - (aod - 0.35) * 0.8)
            }
        }
        let rounded = Sky.jsRound(s)
        return Int(min(100, max(0, rounded)))
    }

    /// Категория из балла (веб `scoreCat`); тумана среди них нет — он
    /// перебивает категорию раньше, чем считается балл.
    public static func category(_ score: Int) -> DayQuality {
        score >= 75 ? .excellent : score >= 50 ? .good : score >= 28 ? .plain : .poor
    }

    /// Качество дня без ярусов — полярный день/ночь, откат без прогноза
    /// (веб `deriveQ`).
    public static func deriveQuality(cloud: Double, code: Int, precipitation: Double, fogMorning: Bool) -> DayQuality {
        if fogMorning { return .fog }
        if precipitation > 0.5 || code >= 51 { return .poor }
        if cloud < 25 { return .excellent }
        if cloud < 55 { return .good }
        return .plain
    }
}
