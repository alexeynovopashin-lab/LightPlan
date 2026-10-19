import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI

/// Слова калибровки AR про чехол MagSafe (шаг 29.8в.10): инструкция называет чехол до всего, подсказка «лучше не стало»
/// — чехол и MagSafe раньше металла и машин, а без ответа системы о точности этой подсказки нет.
@MainActor
struct SunARCalibrationCaseTests {
    private let langs = ["ru", "en", "es", "ja", "zh"]

    @Test("инструкция: «Снимите чехол MagSafe…» дословно в начале, причина одной фразой, на пяти языках")
    func instructionNamesTheCase() {
        #expect(Lexicon("ru").t("ar.calCase").hasPrefix("Снимите чехол MagSafe"))
        for code in langs {
            let t = Lexicon(code)
            let how = t.t("ar.calCase"), why = t.t("ar.calCaseWhy")
            #expect(how.contains("MagSafe"), "\(code): в инструкции нет MagSafe")
            #expect(!how.hasPrefix("ar."), "\(code): ключ ar.calCase без перевода")
            #expect(!why.isEmpty && !why.hasPrefix("ar."), "\(code): нет причины")
        }
    }

    @Test("«лучше не стало»: чехол и MagSafe названы раньше металла и машин; ключи русский, английский, испанский")
    func notImprovedNamesCaseFirst() {
        let metal = ["ru": "металл", "en": "metal", "es": "metal"]
        for code in langs {
            let s = Lexicon(code).t("ar.calNotImproved")
            let magsafe = s.range(of: "MagSafe")
            #expect(magsafe != nil, "\(code): в подсказке нет MagSafe: \(s)")
            if let word = metal[code], let m = magsafe, let k = s.range(of: word) {
                #expect(m.lowerBound < k.lowerBound, "\(code): металл назван раньше чехла: \(s)")
            }
        }
    }

    @Test("нет ответа системы о точности — подсказки «лучше не стало» нет; есть ответ — она есть")
    func noHintWithoutAccuracy() {
        #expect(SunARCalibrationView.notImprovedKey(accuracyKnown: true) == "ar.calNotImproved")
        #expect(SunARCalibrationView.notImprovedKey(accuracyKnown: false) == "ar.calNoAnswer")
        for code in langs {
            let t = Lexicon(code)
            #expect(t.t("ar.calNoAnswer") != t.t("ar.calNotImproved"), "\(code): фразы совпали")
        }
    }

    // MARK: «Сейчас» на стекле панели

    /// Яркость по WCAG из sRGB-каналов 0…1.
    private func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func ch(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
    }

    @Test("«Сейчас» в таймбаре AR: тон не ниже 4,5 к 1 на стекле панели над белым (0,056) и голубым (0,036) небом; прежняя латунь — ниже")
    func nowToneContrast() {
        // Яркость стекла под словом — замер `Tools/ar_contrast.py` на сплошных подложках (29.8в.10, симулятор).
        let glass = [("белое небо", 0.056), ("голубое небо", 0.036), ("ночное небо", 0.007)]
        let newInk = luminance(0xD9 / 255, 0xAC / 255, 0x6B / 255)      // SunARInk.nowTone
        let oldInk = luminance(0xC9 / 255, 0x85 / 255, 0x3F / 255)      // brassDeep, тёмная
        for (name, bg) in glass {
            let was = (oldInk + 0.05) / (bg + 0.05), now = (newInk + 0.05) / (bg + 0.05)
            print(String(format: "ARCON «Сейчас» на %@: было %.2f, стало %.2f", name, was, now))
            #expect(now >= 4.5, "\(name): \(now)")
        }
        #expect((oldInk + 0.05) / (0.056 + 0.05) < 4.5, "прежняя латунь уже годилась — правка не нужна")
        #expect(SunARInk.nowTone == Color(hex: 0xD9AC6B), "константа SunARInk.nowTone разошлась с числами теста")
    }
}
