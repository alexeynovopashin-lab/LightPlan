import Foundation

/// Настройка часов. Умолчание — «как в языке»: платформа знает, что `en-US`
/// ходит по двенадцати, а `ru` по двадцати четырём. Это привычка, а не язык,
/// поэтому выбор отдельный, как у валюты и градусов.
public enum ClockPreference: String, Sendable, CaseIterable, Codable {
    case auto
    case h24 = "24"
    case h12 = "12"
}

/// Часть времени для набора: «AM/PM» в вёрстке ставится мельче цифр.
public struct ClockPart: Sendable, Equatable {
    public let text: String
    public let isDayPeriod: Bool
}

/// Время суток, 24 или 12 с AM/PM: то же, что `fmt`, `hm24`, `fmtHTML` и
/// `range` в вебе. Внутри время — минуты от полуночи.
public struct ClockText: Sendable {

    public let language: String
    public let preference: ClockPreference

    public init(language: String, preference: ClockPreference = .auto) {
        self.language = language
        self.preference = preference
    }

    private var locale: Locale { Locale(identifier: language) }

    /// Двенадцать ли часов на экране.
    public var is12: Bool {
        switch preference {
        case .h12: return true
        case .h24: return false
        case .auto: return Self.localeIs12(locale)
        }
    }

    /// `j` — «часы, как принято в языке»: в шаблоне остаётся `a` там, где
    /// принято двенадцать.
    static func localeIs12(_ locale: Locale) -> Bool {
        let p = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        return p.contains("a")
    }

    /// Сутки замкнуты: `Math.round(((m % 1440) + 1440) % 1440)` веба. Арифметика
    /// та же, вплоть до того, что 1439.5 даёт 1440 и на экране «24:00»:
    /// запись веба, паритет дороже.
    static func norm(_ m: Double) -> Int {
        let wrapped = (fmod(m, 1440) + 1440).truncatingRemainder(dividingBy: 1440)
        return Int((wrapped + 0.5).rounded(.down))
    }

    private static func two(_ n: Int) -> String { (n < 10 ? "0" : "") + String(n) }

    private func clock24(_ m: Int) -> String { Self.two(m / 60) + ":" + Self.two(m % 60) }

    // MARK: - Виды

    /// «ЧЧ:ММ» по 24 часам при любом языке и любой настройке: строка для
    /// машины, а не для экрана.
    public func hm24(_ m: Double) -> String { clock24(Self.norm(m)) }

    /// Строка экрана. 24 часа набираем сами: платформа у части языков ставит
    /// «24:00» вместо «00:00» и не везде держит ведущий ноль, а он держит
    /// колонку. Двенадцать — за платформой, пробел перед AM/PM неразрывный.
    public func fmt(_ m: Double?) -> String {
        guard let m, !m.isNaN else { return "—" }
        let n = Self.norm(m)
        if !is12 { return clock24(n) }
        return timeParts(n).map(\.text).joined()
    }

    /// Время для крупных мест: цифры и отдельно обозначение половины суток.
    public func parts(_ m: Double?) -> [ClockPart] {
        guard let m, !m.isNaN else { return [ClockPart(text: "—", isDayPeriod: false)] }
        if !is12 { return [ClockPart(text: fmt(m), isDayPeriod: false)] }
        return timeParts(Self.norm(m))
    }

    /// Промежуток времени. У двенадцатичасовых часов «AM/PM» не повторяют
    /// дважды, если обе границы в одной половине суток: «7:01 – 8:18 PM».
    public func range(_ a: Double?, _ b: Double?) -> String {
        guard let a, let b else { return "—" }
        if !is12 { return fmt(a) + "\u{00A0}–\u{00A0}" + fmt(b) }
        let (na, nb) = (Self.norm(a), Self.norm(b))
        /// Границы совпали — платформа сворачивает промежуток в одно время, и
        /// веб получает его тем же видом, что `fmt`, а не интервальным.
        if na == nb { return fmt(a) }
        let f = DateIntervalFormatter()
        f.locale = locale
        f.calendar = Self.utc
        f.timeZone = Self.utcZone
        f.dateTemplate = "hmm"
        /// Русский промежуток платформа пишет длинным тире, веб — коротким, как
        /// и в 24-часовой ветке выше: тире у нас одно на все виды времени.
        return Self.nonBreaking(f.string(from: Self.atMin(na), to: Self.atMin(nb)))
            .replacingOccurrences(of: "—", with: "–")
    }

    /// Пробел перед AM/PM неразрывный: «7:52 PM» — одно слово, и перенос не
    /// должен оставлять «PM» одиноко на следующей строке. Платформа ставит
    /// узкий неразрывный (U+202F), веб — обычный, который сам заменяет на
    /// неразрывный; выходит один и тот же U+00A0.
    static func nonBreaking(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "\u{00A0}").replacingOccurrences(of: "\u{202F}", with: "\u{00A0}")
    }

    // MARK: - Двенадцать часов

    private static let utcZone = TimeZone(identifier: "UTC")!
    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utcZone
        return c
    }

    /// Дата-носитель: сам день неважен, важны часы и минуты. 2001-01-01 UTC;
    /// 1440 минут даёт полночь следующих суток, как `new Date(…, 24, 0)`.
    static func atMin(_ m: Int) -> Date {
        Date(timeIntervalSince1970: 978_307_200 + Double(m) * 60)
    }

    /// Двенадцатичасовое время частями по шаблону языка. Шаблон — то же
    /// `hmm`, что просит веб; куски режутся по полям шаблона, и каждое поле
    /// печатается своим форматтером, так что порядок и знаки — языковые.
    private func timeParts(_ m: Int) -> [ClockPart] {
        let date = Self.atMin(m)
        let f = DateFormatter()
        f.locale = locale
        f.calendar = Self.utc
        f.timeZone = Self.utcZone
        f.setLocalizedDateFormatFromTemplate("hmm")
        var out: [ClockPart] = []
        for token in Self.tokens(f.dateFormat) {
            let text: String
            switch token {
            case .literal(let s):
                text = s
            case .field(let run):
                let one = DateFormatter()
                one.locale = locale
                one.calendar = Self.utc
                one.timeZone = Self.utcZone
                /// `K` — часы 0–11, так японская платформа пишет полночь «午前0:00».
                /// Веб просит `hour12: true`, то есть 1–12, и печатает «午前12:00».
                /// Остальные языки в шаблоне `hmm` уже пользуются `h`.
                one.dateFormat = run.first == "K" ? String(repeating: "h", count: run.count) : run
                text = one.string(from: date)
            }
            let isPeriod: Bool = { if case .field(let r) = token { return "abB".contains(r.first!) } else { return false } }()
            out.append(ClockPart(text: Self.nonBreaking(text), isDayPeriod: isPeriod))
        }
        return out
    }

    enum Token: Equatable {
        case literal(String)
        case field(String)
    }

    /// Шаблон ICU → поля и то, что между ними. `'…'` — буквальный текст,
    /// `''` — апостроф.
    static func tokens(_ pattern: String) -> [Token] {
        var out: [Token] = []
        var lit = ""
        var run = ""
        func flushRun() { if !run.isEmpty { out.append(.field(run)); run = "" } }
        func flushLit() { if !lit.isEmpty { out.append(.literal(lit)); lit = "" } }
        let chars = Array(pattern)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "'" {
                flushRun()
                if i + 1 < chars.count, chars[i + 1] == "'" { lit.append("'"); i += 2; continue }
                i += 1
                while i < chars.count, chars[i] != "'" { lit.append(chars[i]); i += 1 }
                i += 1
                continue
            }
            if c.isASCII, c.isLetter {
                if !run.isEmpty, run.last != c { flushRun() }
                flushLit()
                run.append(c)
            } else {
                flushRun()
                lit.append(c)
            }
            i += 1
        }
        flushRun()
        flushLit()
        return out
    }
}
