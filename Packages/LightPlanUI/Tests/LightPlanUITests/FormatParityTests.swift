import Testing
import Foundation
@testable import LightPlanUI

/// Итерация 14: даты, часы, число, деньги, градусы. Эталон — `Fixtures/format.json`:
/// слой веба (`Intl`) прогнан узлом по всем дням 2026-го и по языкам экрана.
/// Расхождение — либо ошибка порта, либо разница ICU узла и платформы; какая
/// именно, решает замер, а не догадка (DECISIONS, «Форматы текста в нативе»).
struct FormatParityTests {

    static let utc = TimeZone(identifier: "UTC")!
    static let langs = ["ru", "en-GB", "en-US", "es", "ja", "zh"]

    static func day(_ iso: String) -> Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        return DateText.carrier(year: p[0], month: p[1] - 1, day: p[2], in: utc)
    }

    // MARK: - Даты

    /// Порт `tools/datecheck.js`: русский экран не должен измениться ни в
    /// одном символе. Слова — прежние массивы, которые слой `Intl` заменил;
    /// 2 376 проверок = 12 месяцев × (28 дней × 7 видов + 2).
    @Test func russianScreenUnchangedSinceIntl() {
        let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
        let monthsN = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
        let monS = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
        let wd = ["ВС", "ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ"]
        let wdFull = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]
        let d = DateText(language: "ru", timeZone: Self.utc)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.utc
        var t = Tally("datecheck")
        for mo in 0..<12 {
            for n in 1...28 {
                let date = DateText.carrier(year: 2026, month: mo, day: n, in: Self.utc)
                let w = cal.component(.weekday, from: date) - 1
                let at = "\(n).\(mo + 1)"
                t.check("dMon", d.dMon(date), "\(n) \(months[mo])", at)
                t.check("dMonShort", d.dMonShort(date), "\(n) \(monS[mo])", at)
                t.check("dMonShortYear", d.dMonShortYear(date), "\(n) \(months[mo].prefix(3)) 2026", at)
                t.check("monthOfDate", d.monthOfDate(date), months[mo], at)
                t.check("monShortOfDate", d.monShortOfDate(date), monS[mo], at)
                t.check("wdShort", d.wdShort(date), wd[w], at)
                t.check("wdFull", d.wdFull(date), wdFull[w], at)
            }
            t.check("monthTitleN", d.monthTitleN(mo), monthsN[mo], "\(mo)")
            t.check("monAbbrUpperN", d.monAbbrUpperN(mo), String(monthsN[mo].prefix(3)).uppercased(), "\(mo)")
        }
        #expect(t.checked == 2376)
        #expect(t.total == 0, Comment(rawValue: t.report))
    }

    @Test func datesMatchWebInEveryLanguage() throws {
        let f = try TextFixtures.load("format.json", as: TextFixtures.FormatFile.self)
        var t = Tally("даты")
        for code in Self.langs {
            let d = DateText(language: code, timeZone: Self.utc)
            let want = try #require(f.langs[code]).dates
            let fns: [(String, (Date) -> String)] = [
                ("dNum", d.dNum), ("dMon", d.dMon), ("dMonShort", d.dMonShort), ("dMonYear", d.dMonYear),
                ("dMonShortYear", d.dMonShortYear), ("monthTitle", d.monthTitle), ("monthOfDate", d.monthOfDate),
                ("wdShort", d.wdShort), ("wdFull", d.wdFull), ("monShortOfDate", d.monShortOfDate),
            ]
            for (name, fn) in fns {
                let exp = try #require(want[name])
                for (i, iso) in f.days.enumerated() { t.check("\(code) \(name)", fn(Self.day(iso)), exp[i], iso) }
            }
            let months = try #require(f.langs[code]).months
            for m in 0..<12 {
                t.check("\(code) monthTitleN", d.monthTitleN(m), months.title[m], "\(m)")
                t.check("\(code) monAbbrUpperN", d.monAbbrUpperN(m), months.abbr[m], "\(m)")
            }
            let row = d.weekdayRow().map { "<span>\($0)</span>" }.joined()
            t.check("\(code) wdRow", row, try #require(f.langs[code]).wdRow, "шапка")
        }
        print(t.report)
        #expect(t.total == 0, Comment(rawValue: t.report))
    }

    // MARK: - Часы

    static func html(_ parts: [ClockPart]) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        return parts.map { $0.isDayPeriod ? "<i class=\"mer\">\(esc($0.text))</i>" : esc($0.text) }.joined()
    }

    /// Виды пробела сворачиваются в один. Регулярка веба заменяет на
    /// неразрывный только обычный пробел, а узел отдаёт перед AM/PM то
    /// обычный (`fmt`, и выходит U+00A0), то узкий U+202F (`fmtHTML`, `range`,
    /// и он остаётся как есть): один и тот же вид у веба даёт разные коды
    /// пробела. Это свойство эталона, а не приложения; Swift держит одно
    /// правило — перед AM/PM всегда U+00A0 (`ClockText.nonBreaking`). Текст,
    /// цифры, знаки и порядок частей сверяются строго.
    static func squash(_ s: String) -> String {
        String(s.map { " \u{00A0}\u{202F}\u{2009}".contains($0) ? " " : $0 })
    }

    @Test func clockMatchesWebInEveryLanguageAndPreference() throws {
        let f = try TextFixtures.load("format.json", as: TextFixtures.FormatFile.self)
        var t = Tally("часы")
        var dashSpacing = 0
        let prefs: [(String, ClockPreference)] = [("auto", .auto), ("24", .h24), ("12", .h12)]
        for code in Self.langs {
            for (key, pref) in prefs {
                let c = ClockText(language: code, preference: pref)
                let want = try #require(f.langs[code]?.clock[key])
                let g = "\(code)/\(key)"
                t.check("\(g) is12", String(c.is12), String(want.is12), "")
                for (i, m) in f.minutes.enumerated() {
                    t.check("\(g) fmt", c.fmt(m), want.fmt[i], "\(String(describing: m))")
                    t.check("\(g) hm24", m.map { c.hm24($0) } ?? want.hm24[i], want.hm24[i], "\(String(describing: m))")
                    t.check("\(g) fmtHTML", Self.squash(Self.html(c.parts(m))), Self.squash(want.fmtHTML[i]), "\(String(describing: m))")
                }
                var k = 0
                for a in f.rangeEnds {
                    for b in f.rangeEnds {
                        let got = Self.squash(c.range(a, b)), exp = Self.squash(want.range[k])
                        /// Известное расхождение данных: русский промежуток через полдень
                        /// веб (CLDR узла) пишет «12:00 AM – 12:00 PM», платформа — без
                        /// пробелов вокруг тире. Другое расхождение сюда не попадёт.
                        if got != exp, code == "ru", key == "12", Self.tight(exp) == got {
                            dashSpacing += 1
                        } else {
                            t.check("\(g) range", got, exp, "\(String(describing: a))–\(String(describing: b))")
                        }
                        k += 1
                    }
                }
            }
        }
        print(t.report + ", из известных (тире без пробелов, ru/12): \(dashSpacing)")
        #expect(t.total == 0, Comment(rawValue: t.report))
        #expect(dashSpacing == 40, "известных расхождений ждали 40, а их \(dashSpacing) — исключение изменилось")
    }

    /// Пробелы вокруг короткого тире убраны.
    static func tight(_ s: String) -> String {
        s.replacingOccurrences(of: " – ", with: "–")
    }

    // MARK: - Число, деньги, градусы

    @Test func numbersAndMoneyMatchWeb() throws {
        let f = try TextFixtures.load("format.json", as: TextFixtures.FormatFile.self)
        #expect(currencies == f.currencies)
        var t = Tally("число и деньги")
        for code in Self.langs {
            let n = NumberText(language: code)
            let want = try #require(f.langs[code])
            for (i, x) in f.numIn.enumerated() {
                t.check("\(code) num", n.num(x), want.number.plain[i], "\(x)")
                t.check("\(code) num0", n.num(x, digits: 0), want.number.d0[i], "\(x)")
                t.check("\(code) num2", n.num(x, digits: 2), want.number.d2[i], "\(x)")
            }
            for cur in f.currencies {
                let exp = try #require(want.money[cur])
                for (i, x) in f.moneyIn.enumerated() { t.check("\(code) money \(cur)", n.money(x, cur), exp[i], "\(x)") }
                t.check("\(code) sign", n.currencySign(cur), try #require(want.sign[cur]), cur)
            }
        }
        print(t.report)
        #expect(t.total == 0, Comment(rawValue: t.report))
    }

    @Test func temperatureRoundsHalfUpLikeWeb() throws {
        let f = try TextFixtures.load("format.json", as: TextFixtures.FormatFile.self)
        var t = Tally("градусы")
        for (i, c) in f.tempIn.enumerated() {
            t.check("c", String(Temperature.show(c, in: .c)), String(f.temp.c[i]), "\(c)")
            t.check("f", String(Temperature.show(c, in: .f)), String(f.temp.f[i]), "\(c)")
        }
        #expect(t.total == 0, Comment(rawValue: t.report))
        #expect(Temperature.label(.c) == "°C" && Temperature.label(.f) == "°F")
    }
}
