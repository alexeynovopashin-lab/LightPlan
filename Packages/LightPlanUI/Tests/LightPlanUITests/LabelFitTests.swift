import Testing
import Foundation
import CoreText

/// Шаг 30а.5: подписи кнопок в рядах равной ширины умещаются на iPhone SE (375 pt) и 15 Pro Max (430 pt)
/// на en/es/ja/zh. Меряется шрифтом (CoreText, системный SF и его подстановки для иероглифов), без снимка:
/// ширина строки против ширины, которую оставляет раскладка. Раскладку и числа берём из кода экранов
/// (ссылки в `Slot.where_`); если там поменялись поля или шрифт, меняются и числа здесь.
/// Каталог читаем как файл, поэтому тест идёт и на хосте. Носитель слова не проверял.
struct LabelFitTests {

    struct Slot: Sendable {
        let name: String
        let where_: String
        let keys: [String]
        let size: CGFloat
        let tracking: CGFloat
        /// Сколько строк раскладка отдаёт подписи (`lineLimit`).
        let lines: Int
        /// Ширина под текст при ширине экрана W.
        let avail: @Sendable (CGFloat) -> CGFloat
    }

    static let wishes = ["any", "clear", "cloudy", "fog", "moon", "rain", "stars", "sunset"].map { "wish." + $0 }
    static let genres = ["ad", "animals", "architecture", "family", "landscape", "lovestory", "party", "portrait",
                         "product", "report", "street", "wedding"].map { "genre." + $0 }

    static let slots: [Slot] = [
        // FormPlace.ways/way: форма с полями 24, в ряду поля 15/15, зазор 8, внутри по 4; подпись 12, до двух строк.
        // Замер на SE: кнопка 93,5 pt, под текст 85,5.
        Slot(name: "form.ways", where_: "FormPlace.swift ways()/way()", keys: ["loc.wayAddr", "loc.wayStudio", "loc.wayGeo"],
             size: 12, tracking: 0, lines: 2, avail: { ($0 - 48 - 30 - 16) / 3 - 8 }),
        // То же в списке точек: слева 35.
        Slot(name: "form.ways.inList", where_: "FormPlace.swift ways(inList)", keys: ["loc.wayAddr", "loc.wayStudio", "loc.wayGeo"],
             size: 12, tracking: 0, lines: 2, avail: { ($0 - 48 - 50 - 16) / 3 - 8 }),
        // PlannerDayStates: три действия дня в месяце, поля 24, зазор 6; подпись 11, одна строка.
        Slot(name: "month.states", where_: "PlannerMonthView.swift PlannerDayStates", keys: ["plan.shortShoot", "plan.shortMeet", "plan.shortBlock"],
             size: 11, tracking: 0, lines: 1, avail: { ($0 - 48 - 12) / 3 }),
        // PlannerDayView.slotMenu: меню часа, слева 88, справа 24, время ≈ 40, зазор 8, внутри по 4.
        Slot(name: "day.slotMenu", where_: "PlannerDayView.swift slotMenu()", keys: ["day.actShoot", "day.actMeet", "day.actBusy"],
             size: 11, tracking: 0, lines: 1, avail: { (($0 - 112) - 40 - 32) / 3 - 8 }),
        // FormPlace.tile / FormPieces: четыре колонки, до сжатия 0,8.
        Slot(name: "form.wish", where_: "FormPlace.swift tile()", keys: wishes, size: 10, tracking: 0, lines: 1,
             avail: { (($0 - 48 - 30 - 18) / 4 - 4) / 0.8 }),
        Slot(name: "form.genre", where_: "FormPieces.swift face()", keys: genres, size: 10, tracking: 0, lines: 1,
             avail: { (($0 - 48 - 30 - 18) / 4 - 4) / 0.8 }),
        // PlannerBlockSheet.kinds: четыре чипа подряд (проверяется суммой ниже).
        // WebSeg в настройках: сегменты поровну, поля 24, рамка 3, внутри по 11; подпись 14.
        Slot(name: "set.seg3", where_: "SettingsLook.swift WebSeg (3)", keys: ["set.delvGenre", "set.delvSingle", "set.delvNone"],
             size: 14, tracking: 0, lines: 1, avail: { ($0 - 54) / 3 - 22 }),
        Slot(name: "set.seg2", where_: "SettingsLook.swift WebSeg (2)", keys: ["net.auto", "net.direct", "set.modeSimple", "set.modePro", "fb.idea", "fb.bug"],
             size: 14, tracking: 0, lines: 1, avail: { ($0 - 54) / 2 - 22 }),
        // StudioAlertAskPlate.answer: плашка ≤ 360, поля 20, зазор 10.
        Slot(name: "studio.ask.answer", where_: "StudioAlertAskPlate.swift answer()", keys: ["studio.askNo", "studio.askYes"],
             size: 16, tracking: 0, lines: 1, avail: { (min(360, $0 - 48) - 40 - 10) / 2 }),
    ]

    static let langs = ["en", "es", "ja", "zh"]
    static let widths: [CGFloat] = [375, 430]

    static func catalog() throws -> [String: Any] {
        let url = TextFixtures.root.appendingPathComponent("Packages/LightPlanUI/Sources/LightPlanUI/Resources/Localizable.xcstrings")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require((obj as? [String: Any])?["strings"] as? [String: Any])
    }

    static func value(_ strings: [String: Any], _ key: String, _ lang: String) -> String? {
        let loc = ((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?[lang] as? [String: Any]
        return (loc?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// Число строк, на которое текст ложится в ширину `avail` (перенос по границам слов и знаков, как у SwiftUI).
    static func lineCount(_ text: String, size: CGFloat, tracking: CGFloat, avail: CGFloat) -> Int {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let attr = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking])
        let setter = CTTypesetterCreateWithAttributedString(attr)
        var start = 0, n = 0
        while start < attr.length {
            let len = CTTypesetterSuggestLineBreak(setter, start, Double(avail))
            start += max(len, 1); n += 1
        }
        return n
    }

    @Test func labelsFitTheirSlotsOnNarrowAndWideScreens() throws {
        let strings = try Self.catalog()
        var bad: [String] = []
        for lang in Self.langs {
            for w in Self.widths {
                for slot in Self.slots {
                    for key in slot.keys {
                        guard let text = Self.value(strings, key, lang) else { bad.append("\(lang) \(key): нет строки"); continue }
                        let n = Self.lineCount(text, size: slot.size, tracking: slot.tracking, avail: slot.avail(w))
                        if n > slot.lines {
                            bad.append("\(lang) \(Int(w)) pt · \(slot.name) (\(slot.where_)) · \(key) «\(text)»: \(n) стр. при \(slot.lines), ширина \(String(format: "%.1f", slot.avail(w)))")
                        }
                    }
                }
            }
        }
        #expect(bad.isEmpty, Comment(rawValue: bad.joined(separator: "\n")))
    }

    @Test func occupationKindsFitInOneRow() throws {
        let strings = try Self.catalog()
        for lang in Self.langs {
            let words = ["busy", "flight", "off", "road"].compactMap { Self.value(strings, "blkKind." + $0, lang) }
            #expect(words.count == 4, "\(lang): нет подписей вида занятости")
            // Чип: знак 22 или подпись 10 с разрядкой 0,2, поля по 2; между чипами 8; поля листа 24.
            let font = CTFontCreateUIFontForLanguage(.system, 10, nil)!
            let total = words.reduce(CGFloat(24)) { acc, word in
                let a = NSAttributedString(string: word, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTKernAttributeName as String): 0.2])
                let w = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(a), nil, nil, nil))
                return acc + max(w, 22) + 4
            }
            #expect(total <= 375 - 48, "\(lang): чипы занятости \(total) pt шире строки на SE")
        }
    }

    /// Порча: без второй строки у кнопки «Фотостудия» испанская подпись на SE не помещается (так и было до 30а.5).
    @Test func spanishStudioLabelWouldBeCutOnOneLine() throws {
        let strings = try Self.catalog()
        let text = try #require(Self.value(strings, "loc.wayStudio", "es"))
        let slot = Self.slots[0]
        #expect(Self.lineCount(text, size: slot.size, tracking: 0, avail: slot.avail(375)) == 2, "«\(text)» должна занимать две строки на SE")
        #expect(Self.lineCount(text, size: slot.size, tracking: 0, avail: slot.avail(430)) == 2, "и на 15 Pro Max (430 pt) не хватает: 108,1 > 104")
    }

    /// Шаг 30а.6: «スタジオ» вместо «フォトスタジオ» — слово кнопки пути умещается в одну строку на SE (375 pt) и на 430 pt.
    @Test func japaneseStudioLabelFitsOneLine() throws {
        let strings = try Self.catalog()
        let text = try #require(Self.value(strings, "loc.wayStudio", "ja"))
        #expect(text == "スタジオ", "ja loc.wayStudio: \(text)")
        let slot = Self.slots[0]
        for w in Self.widths {
            #expect(Self.lineCount(text, size: slot.size, tracking: 0, avail: slot.avail(w)) == 1, "«\(text)» не в одну строку при \(Int(w)) pt")
        }
    }

    /// Раскладка отдаёт кнопке две строки, как и считает таблица: если вернуть `lineLimit(1)`, подпись режется «…».
    @Test func waysLabelKeepsTwoLinesInTheLayout() throws {
        let url = TextFixtures.root.appendingPathComponent("Packages/LightPlanUI/Sources/LightPlanUI/Screens/Form/FormPlace.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(src.contains("Text(t.t(key)).font(.system(size: 12)).lineLimit(2)"), "подпись кнопки пути больше не в две строки")
        #expect(src.contains(".fixedSize(horizontal: false, vertical: true)"), "кнопки ряда путей не выровнены по высоте")
    }
}
