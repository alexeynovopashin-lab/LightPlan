import Foundation

/// Даты: то, что в вебе собирает `Intl` (`dMon`, `dMonShort`, `monthTitle`…).
///
/// Порядок частей и знаки между ними — свойство языка («21 августа»,
/// «August 21», «8月21日», «21 de agosto»), поэтому дату собирает платформа,
/// а не сложение «число + месяц». Три русские мелочи веб приводит к прежнему
/// виду, и здесь то же самое: хвост « г.» у года, месяц тремя знаками без
/// точки и имя месяца с прописной в заголовке.
///
/// Момент — `Date`, день читается в `timeZone`: веб читает его местным.
public struct DateText: Sendable {

    public let language: String
    public let timeZone: TimeZone

    public init(language: String, timeZone: TimeZone = .current) {
        self.language = language
        self.timeZone = timeZone
    }

    private var locale: Locale { Locale(identifier: language) }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = locale
        return c
    }

    /// Часть даты с полем, к которому она относится: нужна там, где число и
    /// месяц стоят по разным строкам вёрстки и склеить их нельзя даже в одном
    /// языке.
    typealias Field = AttributeScopes.FoundationAttributes.DateFieldAttribute.Field

    struct Part: Sendable {
        let field: Field?
        let text: String
    }

    private func style() -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
    }

    private func parts(_ f: Date.FormatStyle, _ d: Date) -> [Part] {
        let attributed = f.attributed.format(d)
        return attributed.runs.map { run in
            Part(field: run.attributes[AttributeScopes.FoundationAttributes.DateFieldAttribute.self],
                 text: String(attributed[run.range].characters))
        }
    }

    // MARK: - Виды

    private var dm: Date.FormatStyle { style().day(.defaultDigits).month(.wide) }
    private var dmS: Date.FormatStyle { style().day(.defaultDigits).month(.abbreviated) }
    private var dmy: Date.FormatStyle { style().day(.defaultDigits).month(.wide).year(.defaultDigits) }
    private var dmyS: Date.FormatStyle { style().day(.defaultDigits).month(.abbreviated).year(.defaultDigits) }
    private var monthOnly: Date.FormatStyle { style().month(.wide) }
    private var weekdayShort: Date.FormatStyle { style().weekday(.abbreviated) }
    private var weekdayLong: Date.FormatStyle { style().weekday(.wide) }
    private var numeric: Date.FormatStyle { style().day(.twoDigits).month(.twoDigits).year(.defaultDigits) }

    /// Русский `Intl` дописывает к году « г.» — у нас его никогда не было.
    /// Пробел перед «г» обязателен: без него правило съедало «г» в «авг.».
    private static func tidy(_ s: String) -> String {
        var t = s
        while t.last?.isWhitespace == true { t.removeLast() }
        guard t.hasSuffix("г.") else { return s }
        var head = t.dropLast(2)
        guard let last = head.last, last.isWhitespace else { return s }
        while head.last?.isWhitespace == true { head.removeLast() }
        return String(head)
    }

    private static func cap(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    /// Месяц тремя знаками — не сокращение языка, а наша типографика: короткий
    /// месяц стоит в ячейках заданной ширины. Точка в конце отбрасывается.
    private static func abbr3(_ s: String) -> String {
        var t = s
        while t.last?.isWhitespace == true { t.removeLast() }
        if t.last == "." { t.removeLast() }
        while t.last?.isWhitespace == true { t.removeLast() }
        return String(t.prefix(3))
    }

    private func part(_ f: Date.FormatStyle, _ d: Date, _ field: Field) -> String {
        parts(f, d).first(where: { $0.field == field })?.text ?? ""
    }

    private func fromParts(_ f: Date.FormatStyle, _ d: Date, month fix: (String) -> String) -> String {
        parts(f, d).map { $0.field == .month ? fix($0.text) : $0.text }.joined()
    }

    // MARK: - Публичное

    /// «22.08.2026» · «08/22/2026» · «2026/08/22»
    public func dNum(_ d: Date) -> String { numeric.format(d) }
    /// «21 августа» · «August 21» · «8月21日»
    public func dMon(_ d: Date) -> String { Self.tidy(dm.format(d)) }
    /// «21 авг» — короткий месяц для плотных мест
    public func dMonShort(_ d: Date) -> String { Self.tidy(fromParts(dmS, d, month: Self.abbr3)) }
    /// «21 августа 2026»
    public func dMonYear(_ d: Date) -> String { Self.tidy(dmy.format(d)) }
    /// «21 авг 2026»
    public func dMonShortYear(_ d: Date) -> String { Self.tidy(fromParts(dmyS, d, month: Self.abbr3)) }
    /// «Август» — имя месяца само по себе, заголовком
    public func monthTitle(_ d: Date) -> String { Self.cap(Self.tidy(monthOnly.format(d))) }

    /// «августа» — месяц внутри даты, набранный отдельной строкой. В японском
    /// и китайском месяц в дате — число без знака 月, и «8» месяцем не читается:
    /// там берётся месяц целиком.
    public func monthOfDate(_ d: Date) -> String {
        let v = part(dm, d, .month)
        return !v.isEmpty && v.allSatisfy(\.isNumber) ? monthOnly.format(d) : v
    }

    /// «ВС» — прописными, как в шапке недели
    public func wdShort(_ d: Date) -> String { Self.abbr3(weekdayShort.format(d)).uppercased() }
    /// «воскресенье»
    public func wdFull(_ d: Date) -> String { weekdayLong.format(d) }
    /// «авг» — короткий месяц сам по себе
    public func monShortOfDate(_ d: Date) -> String { Self.abbr3(part(dmS, d, .month)) }

    /// Имя месяца по номеру 0…11: в годовой сетке месяц приходит числом.
    /// Год берётся любой невисокосный — имена месяцев от него не зависят.
    public func monthTitleN(_ m: Int) -> String {
        monthTitle(Self.carrier(year: 2001, month: m, day: 1, in: timeZone))
    }

    /// «МАЙ» для сетки выбора месяца: именительный, не родительный.
    public func monAbbrUpperN(_ m: Int) -> String { Self.abbr3(monthTitleN(m)).uppercased() }

    /// Шапка календаря: семь дней с понедельника. Неделя у нас начинается с
    /// понедельника во всех языках — это свойство наших сеток, а не языка.
    /// 2001-01-01 — понедельник.
    public func weekdayRow() -> [String] {
        (0..<7).map { i in
            Self.cap(Self.abbr3(weekdayShort.format(Self.carrier(year: 2001, month: 0, day: 1 + i, in: timeZone))))
        }
    }

    /// День на местную полночь: как `new Date(y, m, d)` в вебе. `month` — 0…11.
    static func carrier(year: Int, month: Int, day: Int, in tz: TimeZone) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c.date(from: DateComponents(year: year, month: month + 1, day: day)) ?? Date(timeIntervalSince1970: 0)
    }
}
