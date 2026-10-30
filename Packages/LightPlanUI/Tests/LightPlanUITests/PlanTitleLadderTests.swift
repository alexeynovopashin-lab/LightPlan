import Testing
import SwiftUI
import UIKit
@testable import LightPlanUI

/// Заголовок шапки «Съёмок» (слово Алексея 28.10: «проще сокращать месяц на мелких экранах»): лесенка слово целиком →
/// короткий месяц («23 сент.») → сжатие → место между кнопками; слово не пропадает ни на одном экране и ни на одном языке.
@MainActor
struct PlanTitleLadderTests {

    private static let utc = TimeZone(identifier: "UTC")!
    private static let langs = AppLanguage.codes
    private static func day(_ y: Int, _ m: Int, _ d: Int) -> Date { DateText.carrier(year: y, month: m - 1, day: d, in: utc) }

    /// Короткие формы месяца: русский — «сент.» с точкой (так сокращает язык), «мая» не трогается, английский без точки,
    /// японский и китайский не сокращаются (месяц там — число со знаком 月), многоточия нет нигде.
    @Test func shortMonthFormsFollowTheLanguage() {
        let ru = DateText(language: "ru", timeZone: Self.utc)
        #expect(ru.dMonAbbr(Self.day(2026, 9, 23)) == "23 сент.")
        #expect(ru.monthAbbr(Self.day(2027, 9, 1)) == "Сент.")
        #expect(ru.dMonAbbr(Self.day(2026, 5, 23)) == ru.dMon(Self.day(2026, 5, 23)), "«23 мая» уже короткое")
        #expect(ru.dMonAbbr(Self.day(2026, 8, 3)) == "3 авг.")
        let us = DateText(language: "en-US", timeZone: Self.utc)
        #expect(us.dMonAbbr(Self.day(2026, 9, 23)) == "Sep 23")
        #expect(us.monthAbbr(Self.day(2027, 9, 1)) == "Sep")
        let es = DateText(language: "es", timeZone: Self.utc)
        #expect(es.dMonAbbr(Self.day(2026, 9, 23)).hasPrefix("23 sep"))
        for code in ["ja", "zh"] {
            let d = DateText(language: code, timeZone: Self.utc)
            #expect(d.dMonAbbr(Self.day(2026, 9, 23)) == d.dMon(Self.day(2026, 9, 23)), "\(code): сокращать нечего")
            #expect(d.monthAbbr(Self.day(2027, 9, 1)).count <= d.monthTitle(Self.day(2027, 9, 1)).count)
        }
        for code in Self.langs {
            let d = DateText(language: code, timeZone: Self.utc)
            for m in 1...12 {
                let a = d.dMonAbbr(Self.day(2027, m, 23)), b = d.monthAbbr(Self.day(2027, m, 1))
                #expect(!a.contains("…") && !b.contains("…"), "\(code) \(m): многоточие в «\(a)» / «\(b)»")
                #expect(!a.isEmpty && !b.isEmpty)
                // Сокращённый вид никогда не длиннее полного.
                #expect(a.count <= d.dMon(Self.day(2027, m, 23)).count, "\(code) \(m): «\(a)» длиннее полного")
            }
        }
    }

    /// Экран дня (слово Алексея 30.10: «не надо писать сверху 29 октября, только Октябрь»): заголовок — название месяца в именительном
    /// падеже языка, без числа; чужой год дописывается; короткая ступень — сокращение месяца. Месяц, а не «дата»: день недели и число
    /// в заголовке не появляются ни на одном языке.
    @Test func dayTitleIsTheMonthNameOnly() {
        let ru = DateText(language: "ru", timeZone: Self.utc)
        let oct29 = Self.day(2026, 10, 29)
        let t = PlanTitleLayout.dayTitles(dates: ru, day: oct29, year: "")
        #expect(t.full == "Октябрь", "именительный, без «а» на конце: «\(t.full)»")
        #expect(t.short == "Окт.")
        #expect(PlanTitleLayout.dayTitles(dates: ru, day: oct29, year: " 2027").full == "Октябрь 2027")
        // Март и август: падеж именительный, не родительный («Март», не «марта»).
        #expect(PlanTitleLayout.dayTitles(dates: ru, day: Self.day(2026, 3, 8), year: "").full == "Март")
        #expect(PlanTitleLayout.dayTitles(dates: ru, day: Self.day(2026, 8, 31), year: "").full == "Август")
        let us = DateText(language: "en-US", timeZone: Self.utc)
        #expect(PlanTitleLayout.dayTitles(dates: us, day: oct29, year: "").full == "October")
        // Любой день месяца даёт один и тот же заголовок, на всех языках: число из него исключено.
        for code in Self.langs {
            let d = DateText(language: code, timeZone: Self.utc)
            for m in 1...12 {
                let first = PlanTitleLayout.dayTitles(dates: d, day: Self.day(2027, m, 1), year: "")
                let last = PlanTitleLayout.dayTitles(dates: d, day: Self.day(2027, m, 28), year: "")
                #expect(first.full == last.full && first.short == last.short, "\(code) \(m): заголовок зависит от числа («\(first.full)» / «\(last.full)»)")
                #expect(first.full == d.monthTitle(Self.day(2027, m, 1)), "\(code) \(m): не тот же месяц, что в заголовке «месяца»")
                #expect(!first.full.contains("28") && !first.short.contains("28"))
            }
        }
    }

    /// Заголовок шапки во всех трёх видах (слова Алексея 30.10: «Октябрь целиком», «увеличил шрифт», «все три вида»): кегль 22; слово на
    /// 440 / 430 / 393 / 375 pt стоит целиком — на оси, а если на оси не влез, в свободном месте между кнопками, — и не сокращается.
    /// Названия месяцев ru и en-US (день, неделя, месяц) и недели из двух месяцев («Окт – Ноя»).
    @Test func headerTitleKeepsTheWholeWordAtSize22() {
        #expect(PlanTitleLayout.titleFont == 22)
        let axis = PlanTitleLayout.insets(rightButtons: 3).leading
        var words: [String] = []
        for code in ["ru", "en-US"] {
            let d = DateText(language: code, timeZone: Self.utc)
            for m in 1...12 { words.append(PlanTitleLayout.dayTitles(dates: d, day: Self.day(2026, m, 15), year: "").full) }
        }
        words += ["Сен – Окт", "Окт – Ноя", "Дек – Янв", "Sep – Oct", "Nov – Dec"]
        for word in words {
            for w: CGFloat in [440, 430, 393, 375] {
                let st = PlanTitleLayout.choose(full: word, short: word, screenWidth: w, rightButtons: 3)
                let shown = PlanTitleLayout.width(word) * st.scale
                let room = w - 32 - st.leading - st.trailing
                #expect(!st.short, "\(word) \(Int(w)): сократился")
                #expect(st.scale >= PlanTitleLayout.invisibleSqueeze, "\(word) \(Int(w)): сжат до \(st.scale)")
                #expect(shown <= room + 0.5, "\(word) \(Int(w)): \(shown) не влезает в \(room)")
                if w >= 440 && PlanTitleLayout.width(word) < 112 { #expect(st.leading == axis, "\(word) \(Int(w)): ушёл с оси, хотя места на оси хватает") }
            }
        }
        // Октябрь: на 440 на оси, на 393 целиком между кнопками (на оси места 69 pt, слову на 22 pt нужно 89); без этого шага — «Окт.».
        let ru = DateText(language: "ru", timeZone: Self.utc)
        let t = PlanTitleLayout.dayTitles(dates: ru, day: Self.day(2026, 10, 29), year: "")
        let s440 = PlanTitleLayout.choose(full: t.full, short: t.short, screenWidth: 440, rightButtons: 3)
        let s393 = PlanTitleLayout.choose(full: t.full, short: t.short, screenWidth: 393, rightButtons: 3)
        #expect(s440.leading == axis && !s440.short)
        #expect(s393.leading > axis - 100 && s393.leading < axis && !s393.short, "393 pt: целиком между кнопками, сдвиг влево от оси")
        let old393 = PlanTitleLayout.choose(full: t.full, short: t.short, screenWidth: 393, rightButtons: 3, wholeFirst: false)
        #expect(old393.short, "без шага «целиком» на 393 pt «Окт.»")
        // Слово 22 pt шире 18 pt ровно в пропорции кегля: мера честная.
        #expect(abs(PlanTitleLayout.width(t.full) / PlanTitleLayout.width(t.full, size: 18) - 22.0 / 18) < 0.03)
    }

    private struct Case { let label: String; let full: String; let short: String }

    private func cases() -> [Case] {
        var out: [Case] = []
        for code in Self.langs {
            let d = DateText(language: code, timeZone: Self.utc)
            let a = Self.day(2026, 9, 23), m = Self.day(2027, 9, 1)
            let t = PlanTitleLayout.dayTitles(dates: d, day: a, year: "")
            let t27 = PlanTitleLayout.dayTitles(dates: d, day: a, year: " 2027")
            out.append(Case(label: "\(code) день", full: t.full, short: t.short))
            out.append(Case(label: "\(code) день другого года", full: t27.full, short: t27.short))
            out.append(Case(label: "\(code) месяц", full: d.monthTitle(m) + " 2027", short: d.monthAbbr(m) + " 2027"))
        }
        return out
    }

    private static let widths: [CGFloat] = [320, 375, 393, 430, 440]

    /// Ступень лесенки по ширине; таблица печатается («TITLELADDER»), условия — для всех языков и ширин.
    @Test func ladderNeverLosesTheWord() {
        func rank(_ s: PlanTitleLayout.TitleStep, _ axis: CGFloat) -> Int {
            if s.leading != axis { return 4 }          // ушло с оси
            if s.scale < PlanTitleLayout.invisibleSqueeze { return 3 }   // сжато на оси
            return s.short ? 2 : 1                     // короткий месяц / целиком
        }
        var table = ["TITLELADDER ширина → ступень (1 целиком · 2 короткий месяц · 3 сжато · 4 между кнопками), масштаб"]
        for c in cases() {
            var row = c.label.padding(toLength: 22, withPad: " ", startingAt: 0)
            var prev = 0
            for w in Self.widths.reversed() {
                let axis = PlanTitleLayout.insets(rightButtons: 3).leading
                let s = PlanTitleLayout.choose(full: c.full, short: c.short, screenWidth: w, rightButtons: 3, wholeFirst: false)
                let shown = PlanTitleLayout.width(s.short ? c.short : c.full) * s.scale
                let room = w - 32 - s.leading - s.trailing
                #expect(s.scale >= PlanTitleLayout.minScale && s.scale <= 1, "\(c.label) \(w): масштаб \(s.scale)")
                // Сжатие на оси не глубже пола; глубже — слово уже ушло на свободное место.
                if s.leading == axis { #expect(s.scale >= PlanTitleLayout.squeezeFloor, "\(c.label) \(w): на оси сжато до \(s.scale)") }
                #expect(shown <= room + 0.5, "\(c.label) \(w): слово \(shown) не влезает в \(room)")
                #expect(shown > 20, "\(c.label) \(w): слово пропало")
                let r = rank(s, axis)
                #expect(r >= prev, "\(c.label) \(w): ступень \(r) легче, чем на более широком экране (\(prev))")
                prev = r
                row += String(format: " | %.0f: %d %.2f", w, r, s.scale)
            }
            table.append(row)
        }
        print(table.joined(separator: "\n"))
        // Запасная лесенка (без шага «целиком», слово 18 pt как до 30.10) на длинном слове («23 сентября»): 440 pt целиком; 393 pt: короткий месяц.
        let m18: (String) -> CGFloat = { PlanTitleLayout.width($0, size: 18) }
        let ru = DateText(language: "ru", timeZone: Self.utc), a = Self.day(2026, 9, 23)
        // «Сентябрь» на 22 pt: на 320 pt целиком нигде не влезает, слово не пропадает и не сжато глубже пола или ушло между кнопок.
        let day = PlanTitleLayout.dayTitles(dates: ru, day: a, year: "")
        let s320 = PlanTitleLayout.choose(full: day.full, short: day.short, screenWidth: 320, rightButtons: 3)
        #expect(s320.scale >= PlanTitleLayout.minScale && PlanTitleLayout.width(s320.short ? day.short : day.full) * s320.scale > 20)
        let s440 = PlanTitleLayout.choose(full: ru.dMon(a), short: ru.dMonAbbr(a), screenWidth: 440, rightButtons: 3, wholeFirst: false, width: m18)
        #expect(!s440.short && s440.scale >= PlanTitleLayout.invisibleSqueeze)
        let s393 = PlanTitleLayout.choose(full: ru.dMon(a), short: ru.dMonAbbr(a), screenWidth: 393, rightButtons: 3, wholeFirst: false, width: m18)
        #expect(s393.short && s393.scale >= PlanTitleLayout.invisibleSqueeze, "393 pt: «23 сент.» без заметного сжатия")
    }

    /// Мера по `NSString` и ширина `Text` в шапке сходятся (разрядка −0,3): на этом держится выбор ступени.
    @Test func measuredWidthMatchesText() {
        for t in ["23 сентября", "23 сент.", "Сентябрь 2027", "Сент. 2027", "9月23日", "September 23"] {
            let v = Text(t).font(webFont(18, 650)).tracking(-0.3).lineLimit(1).fixedSize()
            let host = UIHostingController(rootView: v).sizeThatFits(in: CGSize(width: 2000, height: 100)).width
            #expect(abs(host - PlanTitleLayout.width(t, size: 18)) <= 1.5, "«\(t)»: Text \(host), мера \(PlanTitleLayout.width(t, size: 18))")
        }
        for t in ["Октябрь", "Сентябрь", "October", "September"] {
            let v = Text(t).font(webFont(22, 650)).tracking(-0.3).lineLimit(1).fixedSize()
            let host = UIHostingController(rootView: v).sizeThatFits(in: CGSize(width: 2000, height: 100)).width
            #expect(abs(host - PlanTitleLayout.width(t, size: 22)) <= 1.5, "22 pt «\(t)»: Text \(host), мера \(PlanTitleLayout.width(t, size: 22))")
        }
    }

    // MARK: листы для отчёта

    private func header(width: CGFloat, full: String, short: String) -> some View {
        let pal = Palette(.dark)
        let step = PlanTitleLayout.choose(full: full, short: short, screenWidth: width, rightButtons: 3)
        let kinds: [PlanGlyph.Kind] = [.add, .stats, .search]
        let colors: [PlanGlyph.Kind: Color] = [.add: pal.brass, .stats: pal.brass, .search: pal.ink]
        return HStack(spacing: 6) {
            Icon("view_day", size: PlanTitleLayout.scopeGlyph, line: 1.6).foregroundStyle(pal.brass).frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(pal.sheet))
            Spacer(minLength: 0)
            HStack(spacing: PlanTitleLayout.buttonGap) {
                ForEach(kinds, id: \.self) { k in
                    PlanGlyph(kind: k).stroke(colors[k] ?? pal.ink, style: StrokeStyle(lineWidth: PlanTitleLayout.actionStroke, lineCap: .round, lineJoin: .round))
                        .frame(width: PlanTitleLayout.actionGlyph, height: PlanTitleLayout.actionGlyph)
                        .frame(width: PlanTitleLayout.buttonSide, height: PlanTitleLayout.buttonSide)
                }
            }
        }
        .overlay {
            Text(step.short ? short : full).font(webFont(PlanTitleLayout.titleFont, 650)).tracking(-0.3).foregroundStyle(pal.ink)
                .lineLimit(1).minimumScaleFactor(PlanTitleLayout.minScale)
                .overlay(alignment: .leading) {
                    Icon("chevron", size: 16, line: 1.6).rotationEffect(.degrees(180)).foregroundStyle(pal.ink4)
                        .fixedSize().offset(x: -PlanTitleLayout.chevronReach)
                }
                .padding(.leading, step.leading).padding(.trailing, step.trailing).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(width: width, height: 52)
        .background(pal.surface)
    }

    /// `LIGHT_LINE_OUT=<папка>`: шапка с лесенкой на 320 / 375 / 393 / 430 pt (тёмная тема) для «23 сентября», «Сентябрь 2027» и других языков.
    @Test func writesTheLadderSheetsWhenAsked() throws {
        guard let dir = ProcessInfo.processInfo.environment["LIGHT_LINE_OUT"] else { return }
        for c in cases() where ["ru день", "ru месяц", "en-US день", "ja день", "zh месяц", "es месяц"].contains(c.label) {
            for w in Self.widths {
                let r = ImageRenderer(content: header(width: w, full: c.full, short: c.short).environment(\.colorScheme, .dark))
                r.scale = 3
                if let cg = r.cgImage, let data = UIImage(cgImage: cg).pngData() {
                    let name = "ladder_\(c.label.replacingOccurrences(of: " ", with: "_"))_\(Int(w)).png"
                    try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
                }
            }
        }
    }
}
