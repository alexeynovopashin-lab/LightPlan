import Foundation
import LightPlanCore

/// Прогноз якоря съёмки на её день, каким его запомнили (веб `wxSnap`): категория
/// неба и закатный балл. Лежит в `wxSeen` снимка настроек.
public struct SkySnap: Hashable, Sendable {
    public let quality: DayQuality
    /// 0–100; `nil` — часа заката в прогнозе нет.
    public let sunset: Int?

    public init(quality: DayQuality, sunset: Int?) {
        self.quality = quality
        self.sunset = sunset
    }
}

/// Тревога «прогноз переменился» (веб `wxGap`, `wxUp`, `wxShiftSay`). Число было
/// честным в час, когда его показали; молчать, когда оно сменилось, нечестно.
public enum WeatherShift {

    /// Баллу заката положено двадцать пунктов: ниже — дрожь самой модели.
    public static let shift = 20
    /// Тридцать пять — уже не «переменился», а «съёмку впору переносить».
    public static let hard = 35

    /// Насколько разошлись два прогноза: 0 — тот же самый, 2 — переменился,
    /// 3 — впору переносить. Нет одного из двух — разницы нет.
    public static func gap(_ a: SkySnap?, _ b: SkySnap?) -> Int {
        guard let a, let b else { return 0 }
        var w = 0
        if a.quality != b.quality { w = (isDead(a.quality) || isDead(b.quality)) ? 3 : 2 }
        if let x = a.sunset, let y = b.sunset {
            let d = abs(x - y)
            if d >= hard { w = 3 } else if d >= shift && w < 2 { w = 2 }
        }
        return w
    }

    /// Стало лучше: по баллу, если он разошёлся, иначе по ряду категорий.
    public static func isUp(_ a: SkySnap, _ b: SkySnap) -> Bool {
        if let x = a.sunset, let y = b.sunset, x != y { return y > x }
        return rank(b.quality) > rank(a.quality)
    }

    /// Слова про балл заката, а не про категорию неба: балл есть у обоих и
    /// разошёлся не меньше чем на 20.
    public static func saysScore(_ a: SkySnap, _ b: SkySnap) -> Bool {
        guard let x = a.sunset, let y = b.sunset else { return false }
        return abs(x - y) >= shift
    }

    /// Туман и дождь — небо, с которым съёмка меняется целиком.
    private static func isDead(_ q: DayQuality) -> Bool { q == .poor || q == .fog }

    /// Куда считать лучше: туман стоит над дождём, но ниже ровного неба.
    private static func rank(_ q: DayQuality) -> Int {
        switch q {
        case .poor: 0
        case .fog: 1
        case .plain: 2
        case .good: 3
        case .excellent: 4
        }
    }
}
