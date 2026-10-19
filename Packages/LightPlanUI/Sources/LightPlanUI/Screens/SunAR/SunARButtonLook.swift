import SwiftUI

/// Вид кнопок AR (шаг 29.8в.9б): настоящее стекло и то, что возвращает значку читаемость без чёрной подложки.
///
/// До 29.8в.9б у кнопок стоял чёрный оттенок 0,7: над белым небом чистое стекло светлое, и белый значок на нём
/// терялся (1,02 : 1, замер 29.8в.4), а с оттенком кнопка выглядела чёрной плашкой. Теперь три рычага, от
/// лёгкого к тяжёлому: само стекло (`.regular` или `.clear`), оттенок не темнее `tint` и тонкая тень значка.
/// Какой набор остаётся — решает замер контраста на четырёх подложках (`Tools/ar_contrast.py`, цель ≥ 3 : 1).
struct SunARButtonLook: Equatable {
    var clear: Bool
    /// Доля чёрного оттенка стекла, `0` — оттенка нет.
    var tint: Double
    /// Тонкая тень значка и подписи кнопки.
    var shadow: Bool
    /// Чернила значка: белые всегда, системные (`.primary` — стекло само делает их тёмными на светлом) или чёрные
    /// (только для опыта).
    var ink: Ink = .white

    enum Ink: Equatable { case white, adaptive, black }

    /// Выбранный вид. Менять только вместе с замером и записью в отчёте.
    static let standard = SunARButtonLook(clear: false, tint: 0, shadow: false, ink: .adaptive)

    static let current: SunARButtonLook = {
        #if DEBUG
        // `-LPSunARButtonGlass regular|clear[.tNN][.s]`: вариант стекла для замера (NN — процент чёрного, `.s` — тень
        // значка, `.p` — системные чернила, `.k` — чёрные); `black70` — прежний вид 29.8в.4. Только отладка: у людей стоит `standard`.
        if let spec = UserDefaults.standard.string(forKey: "LPSunARButtonGlass") { return parse(spec) ?? standard }
        #endif
        return standard
    }()

    var inkColor: Color {
        switch ink {
        case .white: return SunARInk.light
        case .adaptive: return Color.primary
        case .black: return Color.black
        }
    }

    var glass: Glass {
        var g: Glass = clear ? .clear : .regular
        if tint > 0 { g = g.tint(Color.black.opacity(tint)) }
        return g
    }

    /// Строка вида для `-LPSunARButtonGlass`, например `clear.t20.s`.
    static func parse(_ spec: String) -> SunARButtonLook? {
        if spec == "standard" { return standard }
        if spec == "black70" { return SunARButtonLook(clear: false, tint: 0.7, shadow: false) }
        var parts = spec.split(separator: ".").map(String.init)
        guard let base = parts.first, base == "regular" || base == "clear" else { return nil }
        parts.removeFirst()
        var look = SunARButtonLook(clear: base == "clear", tint: 0, shadow: false)
        for p in parts {
            if p == "s" { look.shadow = true }
            else if p == "p" { look.ink = .adaptive }
            else if p == "k" { look.ink = .black }
            else if p.hasPrefix("t"), let n = Double(p.dropFirst()) { look.tint = n / 100 }
            else { return nil }
        }
        return look
    }
}

extension View {
    /// Тень значка на стеклянной кнопке (если вид её включает): тёмный контур на светлом небе, где белый значок тонет.
    @ViewBuilder func arInkShadow() -> some View {
        if SunARInk.look.shadow {
            self.shadow(color: Color.black.opacity(0.45), radius: 1.2, x: 0, y: 0.5)
        } else {
            self
        }
    }
}
