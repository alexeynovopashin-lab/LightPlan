import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
@testable import LightPlanUI
#if os(iOS)
import UIKit

/// Строка неба среднего виджета без съёмок (DECISIONS 30.10 «рассвет · яркий», без «завтра»): все десять строк каждого из пяти языков (рассвет и
/// закат × пять слов, слова — из словаря приложения, как их пишет `AppModel.widgetWords`) влезают в левую колонку целиком, без «…», на плашках
/// 338 × 158 и 364 × 170 в трёх размерах текста. «Влезает» = идеальная ширина строки у SwiftUI (`sizeThatFits` без предела) не больше рамки,
/// которую ей даёт вид: SwiftUI режет строку ровно тогда, когда она шире рамки. В Б (съёмка без маршрута) то же слово стоит в барабане света.
@MainActor
struct WidgetSkyLineTests {
    private static let types: [(String, DynamicTypeSize)] = [("обычный", .large), ("крупный", .xxLarge), ("огромный", .accessibility3)]
    private static let plates = [CGSize(width: 338, height: 158), CGSize(width: 364, height: 170)]
    /// 05:00 — сегодняшний рассвет (строка со знаком), 14:00 — закат (со знаком), 21:00 — завтрашний рассвет (вечерняя строка, без знака).
    private static let hours = [5, 14, 21]

    private func idealWidth(_ text: String, size: Double, type: DynamicTypeSize) -> Double {
        let v = Text(text).font(.system(size: size, weight: .medium)).lineLimit(1).fixedSize().environment(\.dynamicTypeSize, type)
        return Double(UIHostingController(rootView: v).sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)).width)
    }

    @Test func everySkyLineOfFiveLanguagesFitsTheLeftColumnWhole() throws {
        var report: [String] = []
        for lang in WidgetSkySheets.langs {
            let words = AppModel.widgetWords(Lexicon(lang))
            if lang != "ru" { #expect(words[.skyVivid] != WidgetFeed.Words()[.skyVivid], "\(lang): слова неба из словаря, а не запасные русские") }
            var longest = (text: "", w12: 0.0, width: 0.0, fit: BraunIdleContent.ratingFit("", icon: true))
            for h in Self.hours {
                for q in DayQuality.allCases {
                    let f = WidgetSkySheets.frame(lang: lang, hour: h, quality: q)
                    let line = try #require(BraunIdle.ratingLine(f), "\(lang) \(h):00 \(q): строки нет")
                    // Предмет — то светило, чьё время крупно (днём закат, утром и вечером рассвет); слово — по категории; «завтра» нет.
                    #expect(line == words[h == 14 ? .skySet : .skyRise].replacingOccurrences(of: "{t}", with: words.sky(q)), "\(lang) \(h):00 \(q): «\(line)»")
                    #expect(!line.lowercased().contains(words[.tomorrow].lowercased()), "\(lang): «\(line)» без «завтра»")
                    let fit = BraunIdleContent.ratingFit(line, icon: h != 21)
                    for (tn, t) in Self.types {
                        let w = idealWidth(line, size: fit.size, type: t)
                        let tag = "\(lang) \(h):00 «\(line)» \(fit.size) pt \(fit.icon ? "со знаком" : "без знака") \(tn)"
                        #expect(w <= fit.width + 0.01, "\(tag): \(w) > \(fit.width)")
                        #expect(fit.x + w <= BraunGauge.x - 1 + 0.01, "\(tag): заходит на столбик")
                        let w12 = BraunText.width(line, size: 12, semibold: false)
                        if w12 > longest.w12 || (w12 == longest.w12 && w > longest.width) { longest = (line, w12, w, fit) }
                    }
                }
            }
            report.append(String(format: "%@: самая длинная «%@» (в 12 pt %.1f) стоит %.1f pt из %.0f, кегль %.0f, %@", lang, longest.text, longest.w12, longest.width, longest.fit.width,
                                 longest.fit.size, longest.fit.icon ? "со знаком" : "без знака"))
            // Б: слово рядом с названием в барабане света (или вторая строкой) — название не рвётся, оба целиком.
            for p in Self.plates {
                for h in Self.hours {
                    for q in DayQuality.allCases {
                        let wedding = WidgetFeed.Shoot(id: "w", start: Moment(WidgetSkySheets.tsk(4)).milliseconds, end: Moment(WidgetSkySheets.tsk(23)).milliseconds,
                                                       title: "Свадьба", genre: "wedding", names: "Анна и Игорь")
                        let f = WidgetSkySheets.frame(lang: lang, hour: h, quality: q, shoots: [wedding])
                        let L = BraunLayout(plan: try #require(DayPlan(f)), size: p, medium: true, bare: true)
                        let tag = "Б \(lang) \(Int(p.width)) \(h):00 \(q)"
                        for r in L.rows where r.light != nil && r.extra != nil {
                            let k = r.light?.kind ?? .sunrise
                            let name = f.words[k == .sunrise ? .sunrise : (k == .golden ? .golden : .sunset)]
                            #expect(r.step.lines == 1, "\(tag): название в одну строку")
                            let room = L.drumNameWidth - BraunLayout.lightSignWidth(offset: r.slot.offset)
                            let word = BraunLayout.ratingWidth(r.extra ?? "", icon: r.extraIcon, size: r.extraSize)
                            #expect(BraunText.width(name, size: r.step.size, semibold: r.slot.offset == 0) + (r.extraStacked ? 0 : word) <= room + 0.01,
                                    "\(tag): «\(name)» + «\(r.extra ?? "")» \(r.extraStacked ? "(второй строкой)" : "") не влезли в \(room)")
                            if r.extraStacked { #expect(word <= room + 0.01, "\(tag): слово второй строкой шире колонки") }
                        }
                    }
                }
            }
        }
        print("SKY-LINE\n" + report.joined(separator: "\n"))
        try? report.joined(separator: "\n").write(toFile: "/tmp/cc-sky-line.log", atomically: true, encoding: .utf8)
    }
}
#endif
