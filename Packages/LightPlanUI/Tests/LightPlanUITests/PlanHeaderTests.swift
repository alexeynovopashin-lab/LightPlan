import Testing
import SwiftUI
import UIKit
@testable import LightPlanUI

/// Кнопки шапки «Съёмок» крупнее на четверть (слово Алексея 28.10): зоны нажатия не меньше 44 × 44 и не перекрываются,
/// линия значков держит прежнее отношение к стороне, шапка по высоте не растёт, заголовок сжимается по записанной мере.
@MainActor
struct PlanHeaderTests {

    @Test func everyHitSquareIsAtLeast44AndTheyDoNotOverlap() {
        #expect(PlanTitleLayout.buttonSide >= 44)
        #expect(PlanTitleLayout.buttonGap >= 0, "квадраты нажатия не должны заходить друг на друга")
        #expect(PlanTitleLayout.rightWidth(buttons: 3) == CGFloat(132))
        #expect(PlanTitleLayout.rightWidth(buttons: 4) == CGFloat(176))
        // Высоту строки шапки держит кнопка вида (44) — правые кнопки в неё помещаются, шапка не растёт.
        #expect(PlanTitleLayout.buttonSide <= PlanTitleLayout.leftWidth)
    }

    @Test func glyphsAreAQuarterLargerWithTheSameStrokeRatio() {
        #expect(abs(PlanTitleLayout.actionGlyph / 22 - 1.25) < 0.03, "значки действий были 22 pt")
        #expect(abs(PlanTitleLayout.scopeGlyph / 21 - 1.25) < 0.03, "значок вида был 21 pt")
        // Линия значков действий: прежнее отношение 1,7 к 22.
        #expect(abs(PlanTitleLayout.actionStroke / PlanTitleLayout.actionGlyph - 1.7 / 22) < 1e-9)
    }

    private func titleWidth(_ text: String, size: DynamicTypeSize = .large) -> CGFloat {
        let v = Text(text).font(webFont(18, 650)).tracking(-0.3).lineLimit(1).fixedSize().dynamicTypeSize(size)
        return UIHostingController(rootView: v).sizeThatFits(in: CGSize(width: 2000, height: 100)).width
    }

    /// Слово заголовка и место ему: печатается по ширинам 320 / 393 / 430 / 440 для трёх кнопок справа; от размера шрифта системы
    /// не зависит (шрифт шапки с фиксированным кеглем) — в обеих крайних размерах ширина одна.
    @Test func titleRoomAtWidths() {
        let titles = ["23 сентября", "28 сентября", "Сентябрь 2027", "Сен – Окт 2027"]
        for t in titles {
            let normal = titleWidth(t), huge = titleWidth(t, size: .accessibility5)
            #expect(abs(normal - huge) < 0.5, "«\(t)»: ширина слова зависит от Dynamic Type (\(normal) и \(huge))")
        }
        var line = "PLANHEADER"
        for w in [320.0, 393, 430, 440] {
            let room = PlanTitleLayout.room(screenWidth: w, rightButtons: 3)
            let sc = titles.map { String(format: "%.2f", PlanTitleLayout.scale(title: titleWidth($0), screenWidth: w, rightButtons: 3)) }
            line += String(format: "  w%.0f: место %.0f масштаб %@", w, room, sc.joined(separator: "/"))
        }
        print(line + "  слова: " + titles.map { String(format: "%.1f", titleWidth($0)) }.joined(separator: "/"))
        // На самом широком экране слово «23 сентября» помещается целиком.
        #expect(PlanTitleLayout.scale(title: titleWidth("23 сентября"), screenWidth: 440, rightButtons: 3) == 1)
    }

    /// Слово шапки не уходит под кнопки: место, что ему отдано, не заходит на зоны слева и справа (по 6 + 8 pt запаса).
    @Test func titleNeverOverlapsButtons() {
        for w in [CGFloat(320), 393, 430, 440] {
            let i = PlanTitleLayout.insets(rightButtons: 3)
            #expect(i.leading >= PlanTitleLayout.leftWidth + 6)
            #expect(i.trailing >= PlanTitleLayout.rightWidth(buttons: 3) + 6)
            #expect(PlanTitleLayout.room(screenWidth: CGFloat(w), rightButtons: 3) == CGFloat(w) - 32 - i.leading - i.trailing)
        }
    }

    // MARK: листы для отчёта

    /// Шапка по мерам `side` / `glyph` / `gap`, кнопки справа `kinds`, заголовок сжимается как в приложении (`minScale`).
    private func header(width: CGFloat, title: String, kinds: [PlanGlyph.Kind], side: CGFloat, glyph: CGFloat, gap: CGFloat) -> some View {
        let pal = Palette(.dark)
        let right = CGFloat(kinds.count) * side + CGFloat(max(0, kinds.count - 1)) * gap
        let inset = max(44 + 6 + 8, right + 6 + 8)
        let colors: [PlanGlyph.Kind: Color] = [.add: pal.brass, .stats: pal.brass, .search: pal.ink]
        return HStack(spacing: 6) {
            Icon("view_day", size: glyph * 26 / 28, line: 1.6).foregroundStyle(pal.brass).frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(pal.sheet))
            Spacer(minLength: 0)
            HStack(spacing: gap) {
                ForEach(kinds, id: \.self) { k in
                    PlanGlyph(kind: k).stroke(colors[k] ?? pal.ink, style: StrokeStyle(lineWidth: 1.7 * glyph / 22, lineCap: .round, lineJoin: .round))
                        .frame(width: glyph, height: glyph).frame(width: side, height: side)
                }
            }
        }
        .overlay {
            Text(title).font(webFont(18, 650)).tracking(-0.3).foregroundStyle(pal.ink)
                .lineLimit(1).minimumScaleFactor(PlanTitleLayout.minScale)
                .padding(.horizontal, inset).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(width: width, height: 52)
        .background(pal.surface)
    }

    /// `LIGHT_LINE_OUT=<папка>`: шапка до / после и вариант «две кнопки» на 393 и 430 pt, тёмная тема.
    @Test func writesTheHeaderSheetsWhenAsked() throws {
        guard let dir = ProcessInfo.processInfo.environment["LIGHT_LINE_OUT"] else { return }
        let three: [PlanGlyph.Kind] = [.add, .stats, .search]
        for (w, title) in [(393.0, "23 сентября"), (430, "23 сентября"), (430, "Сентябрь 2027"), (320, "23 сентября")] {
            let variants: [(String, AnyView)] = [
                ("before", AnyView(header(width: w, title: title, kinds: three, side: 34, glyph: 22, gap: 8))),
                ("A_three_large", AnyView(header(width: w, title: title, kinds: three, side: 44, glyph: 28, gap: 0))),
                ("B_two_large", AnyView(header(width: w, title: title, kinds: [.add, .search], side: 44, glyph: 28, gap: 0)))]
            for (name, v) in variants {
                let r = ImageRenderer(content: v.environment(\.colorScheme, .dark))
                r.scale = 3
                if let cg = r.cgImage, let data = UIImage(cgImage: cg).pngData() {
                    let file = "header_\(Int(w))_\(title.hasPrefix("Сент") ? "month" : "day")_\(name).png"
                    try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
                }
            }
        }
    }
}
