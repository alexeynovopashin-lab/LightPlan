import Foundation

/// Слово о длине тени. Ключ словаря — `shadow.<rawValue>`.
public enum ShadowWord: String, Sendable {
    case none, veryShort, short, long, veryLong
}

/// Подпись ближайшего светового события. Ключ словаря — `next.<rawValue>`.
public enum NextLightKey: String, Sendable {
    case polarDay, polarNight, toDawn, goldenLeft, toGolden, toSunset, blueLeft
}

/// Ближайшее «хорошее» световое событие: подпись и сколько минут до него.
/// `minutes` — `nil` в полярные сутки и полярную ночь: события нет.
public struct NextLight: Sendable, Equatable {
    public let key: NextLightKey
    public let minutes: Minutes?

    public init(key: NextLightKey, minutes: Minutes?) {
        self.key = key
        self.minutes = minutes
    }
}

extension SolarDay {

    /// Состояние света в минуту `t` этих суток. То же, что `stateAt(t)` веба.
    public func state(at t: Minutes) -> LightState {
        LightState(elevation: elevation(at: t), morning: t < solarNoon)
    }

    /// Слово о тени. Порт `shadowWord`.
    public func shadowWord(at t: Minutes) -> ShadowWord {
        let e = elevation(at: t)
        if e < 0 { return .none }
        if e > 45 { return .veryShort }
        if e > 25 { return .short }
        if e > 10 { return .long }
        return .veryLong
    }

    /// Ближайшее световое событие относительно минуты `t`. Порт `nextLight`.
    ///
    /// **Наследство веба, перенесено как есть.** Вебовский `nextLight`
    /// сравнивает `t` с полями `SUN`, которые бывают `null`, а у JS `null` в
    /// сравнении и в вычитании — это `0`. Там, где солнце за день не доходит до
    /// 6° (`goldenA == nil`) или не уходит ниже −6° (`civilB == nil`), проверка
    /// читается как `t < 0`. Здесь `nil` в этих местах тоже читается нулём.
    /// Замер по сетке стенда: 11 суток из 240 (Антарктида и 66.6° в
    /// июньские дни), и для `t ≥ 0` это ровно «пропустить отсутствующую ветку»:
    /// нет золотого часа — сразу к закату, нет синего — сразу к рассвету.
    /// Поведение разумное, править нечего; но перенесено оно буквально, а не по
    /// смыслу, и расходиться с вебом здесь нельзя.
    public func nextLight(at t: Minutes) -> NextLight {
        switch polar {
        case .day: return NextLight(key: .polarDay, minutes: nil)
        case .night: return NextLight(key: .polarNight, minutes: nil)
        case .normal: break
        }
        func js(_ v: Minutes?) -> Minutes { v ?? 0 }
        if t < js(rise) { return NextLight(key: .toDawn, minutes: js(rise) - t) }
        if t < js(goldenA) { return NextLight(key: .goldenLeft, minutes: js(goldenA) - t) }
        if t < js(goldenB) { return NextLight(key: .toGolden, minutes: js(goldenB) - t) }
        if t < js(set) { return NextLight(key: .toSunset, minutes: js(set) - t) }
        if t < js(civilB) { return NextLight(key: .blueLeft, minutes: js(civilB) - t) }
        return NextLight(key: .toDawn, minutes: js(rise) + 1440 - t)
    }
}
