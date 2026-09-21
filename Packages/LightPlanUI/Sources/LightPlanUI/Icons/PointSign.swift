import Foundation

/// Подбор знака точки дня по её названию — `ICONS.pointSign` из `icons.js`.
///
/// «Сборы невесты» → `rings`, «Церемония на пляже» → `arch`. Только имена:
/// рисовать знак — дело `Icon`. Файл не тянет SwiftUI, чтобы Домен мог
/// пользоваться им, когда понадобится, — граница слоёв разрешает Foundation.
///
/// Правила — 166 регулярок в четыре яруса, порядок значим. Их разбирает и
/// порядок ярусов задаёт веб; здесь только проигрывание. Шаблоны переписаны
/// генератором под ICU: `\b` в JS ASCII-шный, в ICU он понимает кириллицу,
/// поэтому границы слов там записаны явно.
public enum PointSign {

    /// Знак точки: название, при необходимости строка места и признак ссылки на студию.
    ///
    /// `all` — не пропускать правила, чей знак не нарисован: так проверка видит,
    /// что понял словарь, а не что стоит на экране. Нарисованы сейчас все.
    public static func name(for title: String, place: String? = nil, studio: Bool = false, all: Bool = false) -> String {
        let n = pick(title, all: all)
        if let n, n.tier < IconLibrary.weakTier { return n.sign }
        if studio { return "studio" }
        let p = pick(place, all: all)
        if let p, p.tier < IconLibrary.weakTier { return p.sign }
        return (n ?? p)?.sign ?? "dot"
    }

    /// Первое сработавшее правило.
    static func pick(_ text: String?, all: Bool) -> (sign: String, tier: Int)? {
        let text = fold(text ?? "")
        if text.isEmpty { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for rule in rules {
            if !all, IconLibrary.common[rule.sign] == nil { continue }
            if rule.regex.firstMatch(in: text, options: [], range: range) != nil {
                return (rule.sign, rule.tier)
            }
        }
        return nil
    }

    /// Латинские диакритики снимаются перед разбором: malecón = malecon,
    /// château = chateau. Кириллица не трогается — «й» и «ё» собираются обратно.
    static func fold(_ s: String) -> String {
        let d = s.decomposedStringWithCanonicalMapping
        let stripped = combining.stringByReplacingMatches(
            in: d, options: [], range: NSRange(d.startIndex..., in: d), withTemplate: "$1")
        return stripped.precomposedStringWithCanonicalMapping
    }

    // MARK: - Скомпилированные правила

    private struct Rule: @unchecked Sendable {
        let regex: NSRegularExpression
        let sign: String
        let tier: Int
    }

    private static let combining = try! NSRegularExpression(pattern: "([A-Za-z])[\\u0300-\\u036f]+")

    /// Шаблоны компилируются один раз. Ошибка шаблона — ошибка сборки словаря,
    /// а не ситуация во время работы: `try!` намеренно, тест перебирает все.
    private static let rules: [Rule] = IconLibrary.pointWords.map {
        Rule(regex: try! NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]),
             sign: $0.sign, tier: $0.tier)
    }

    /// Число правил — для теста: сверяется с веб-эталоном.
    static var ruleCount: Int { rules.count }
}
