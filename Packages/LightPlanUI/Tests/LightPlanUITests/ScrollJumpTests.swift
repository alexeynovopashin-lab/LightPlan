import Testing
import Foundation
import CoreGraphics
import LightPlanDomain
@testable import LightPlanUI

/// Общая кнопка прыжка по длинной странице (Алексей, 28.10): вид мудборда сохранён, правило показа — одно на все экраны;
/// с 30.10 она везде парит, полосы под прокруткой нет.
struct ScrollJumpTests {
    /// Галерея мудборда была 40 pt, `ink4`, поля 20 / 24; папка — 38 pt, `ink3`, поля 24 / 24 (снимки до и после: разница 0).
    @Test func looksKeepTheMoodboardNumbers() {
        let g = ScrollJump.Look.standard, f = ScrollJump.Look.folder
        #expect(g.size == 40 && !g.strong && g.trailing == 20 && g.bottom == 24)
        #expect(f.size == 38 && f.strong && f.trailing == 24 && f.bottom == 24)
    }

    /// Кнопка нужна, когда прокрутки не меньше 0,6 окна; от начала ведёт вниз, за серединой — вверх.
    @Test func ruleIsTheMoodboardOne() {
        #expect(!Moodboard.jumpVisible(scrollable: 515, screen: 860))
        #expect(Moodboard.jumpVisible(scrollable: 516, screen: 860))
        #expect(Moodboard.jumpGoesDown(offset: 0, scrollable: 1000))
        #expect(!Moodboard.jumpGoesDown(offset: 600, scrollable: 1000))
    }

    /// Кнопка парит на всех длинных страницах (Алексей, 30.10: «удаляй черную плашку»): низ прокрутки получает запас под кнопку
    /// с её отступом — 64 pt у обычной, 62 pt у папки мудборда, — чтобы последняя строка доезжала выше кнопки.
    @Test func reserveIsTheButtonWithItsBottomGap() {
        #expect(ScrollJump.reserve(.standard) == 64)
        #expect(ScrollJump.reserve(.folder) == 62)
    }

    /// Запас не трогает порог: окно прокрутки приходит без запаса, `measure` его возвращает — ответ тот же, что у мудборда без
    /// запаса (и у прежней полосы, считавшей по окну без неё): 515 pt прокрутки на окне 860 — кнопки нет, 516 — есть.
    @Test func reserveDoesNotMoveTheThreshold() {
        let r = ScrollJump.reserve(.standard)
        for content in stride(from: 1200 as CGFloat, through: 1500, by: 1) {
            let m = ScrollJump.measure(content: content, container: 860 - r, reserve: r)
            #expect(m.window == 860)
            #expect(Moodboard.jumpVisible(scrollable: m.scrollable, screen: m.window)
                    == Moodboard.jumpVisible(scrollable: max(0, content - 860), screen: 860))
        }
        let low = ScrollJump.measure(content: 1375, container: 860 - r, reserve: r)
        let high = ScrollJump.measure(content: 1376, container: 860 - r, reserve: r)
        #expect(!Moodboard.jumpVisible(scrollable: low.scrollable, screen: low.window))
        #expect(Moodboard.jumpVisible(scrollable: high.scrollable, screen: high.window))
        // Мудборд без запаса — как был.
        let bare = ScrollJump.measure(content: 1376, container: 860, reserve: 0)
        #expect(bare.scrollable == 516 && bare.window == 860)
    }

    private var screens: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LightPlanUI/Screens")
    }

    /// Строки `.scrollJump(` во всех экранах, без комментариев: файл → строка вызова.
    private func calls() throws -> [(file: String, line: String)] {
        let files = FileManager.default.enumerator(at: screens, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "ScrollJump.swift" }
        return try files.flatMap { url in
            try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
                .filter { $0.contains(".scrollJump(") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .map { (url.lastPathComponent, $0) }
        }
    }

    /// Полосы под прокруткой больше нет: ни размещения `.strip`, ни её высоты, ни Debug-флага «поставить поверх».
    @Test func theStripIsGone() throws {
        let code = try String(contentsOf: screens.appendingPathComponent("ScrollJump.swift"), encoding: .utf8)
        for word in ["Placement", ".strip", "stripHeight", "stripShown", "stripVisible", "LPScrollJumpFloating"] {
            #expect(!code.contains(word), "в ScrollJump осталось «\(word)»")
        }
        #expect(code.contains(".overlay(alignment: .bottomTrailing)"), "кнопка висит поверх прокрутки")
        for c in try calls() { #expect(!c.line.contains("placement:"), "\(c.file): размещение кнопки больше не выбирается") }
    }

    /// Без запаса — только два экрана мудборда (их вид сохранён как был); остальные длинные страницы берут запас.
    @Test func onlyTheMoodboardSkipsTheReserve() throws {
        let all = try calls()
        #expect(all.count >= 13, "экраны с кнопкой прыжка: \(all.count)")
        let bare = Set(all.filter { $0.line.contains("reserve: false") }.map(\.file))
        #expect(bare == ["MoodboardGallery.swift", "MoodboardFolder.swift"])
    }
}
