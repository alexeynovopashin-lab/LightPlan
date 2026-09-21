import Foundation

/// Валюты, которые предлагают настройки.
public let currencies = ["RUB", "USD", "EUR", "GBP", "JPY", "CNY"]

/// Число, деньги и градусы: `num`, `money`, `currencySign`, `tempShow` веба.
///
/// Валюта — своя настройка, а не следствие языка: русский фотограф с
/// английским интерфейсом зарабатывает в рублях. Отсюда два источника:
/// локаль берётся у языка, валюта — у настройки. Знак денег берёт платформа, а
/// не таблица: для рубля англичанин видит «₽», а язык, который не знает знака,
/// покажет код.
public struct NumberText: Sendable {

    public let language: String

    public init(language: String) { self.language = language }

    private var locale: Locale { Locale(identifier: language) }

    /// Число с разделителями разрядов; разделитель — свойство языка.
    /// `digits == nil` — до трёх знаков после запятой, как умолчание `Intl`.
    public func num(_ n: Double, digits: Int? = nil) -> String {
        let precision: NumberFormatStyleConfiguration.Precision = digits.map { .fractionLength($0) }
            ?? .fractionLength(0...3)
        return n.formatted(.number.locale(locale).precision(precision).rounded(rule: .toNearestOrAwayFromZero))
    }

    private func moneyStyle(_ cur: String) -> FloatingPointFormatStyle<Double>.Currency {
        .currency(code: cur).locale(locale).presentation(.narrow)
            .precision(.fractionLength(0)).rounded(rule: .toNearestOrAwayFromZero)
    }

    /// Сумма целыми: `Math.round` веба, а не банковское округление. У него же
    /// «−0»: −0,4 округляется в отрицательный нуль, и `Intl` пишет «-0 ₽».
    /// Запись веба, паритет дороже (DECISIONS, «Форматы текста в нативе»).
    public func money(_ n: Double, _ cur: String) -> String {
        var r = (n.isNaN ? 0 : n + 0.5).rounded(.down)
        if r == 0 && n < 0 { r = -0.0 }
        return r.formatted(moneyStyle(cur))
    }

    /// Знак валюты отдельно от суммы: им подписаны поля формы («Ставка, ₽/час»).
    public func currencySign(_ cur: String) -> String {
        let a = 0.0.formatted(moneyStyle(cur).attributed)
        let s = a.runs.compactMap { run -> String? in
            run.attributes[AttributeScopes.FoundationAttributes.NumberFormatAttributes.SymbolAttribute.self] == .currency
                ? String(a[run.range].characters) : nil
        }.joined()
        return s
    }
}

/// Градусы. Модель считает в Цельсии всегда — прогноз приходит в нём, и
/// переводить внутри значило бы держать две правды. Единицы живут на выходе.
public enum Temperature {
    public enum Unit: String, Sendable, Codable { case c, f }

    /// `Math.round` веба — половина вверх, а не от нуля: −2,5 → −2.
    public static func show(_ c: Double, in unit: Unit) -> Int {
        let v = unit == .f ? c * 9 / 5 + 32 : c
        return Int((v + 0.5).rounded(.down))
    }

    public static func label(_ unit: Unit) -> String { unit == .f ? "°F" : "°C" }
}
