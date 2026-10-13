import Testing
import SwiftUI
@testable import LightPlanUI

/// 29.2ж: все движения «Съёмок» идут через `PlanMotion.pick` — при «Уменьшении движения» кривой нет.
@MainActor
struct PlanMotionTests {
    private static let curves: [(String, Animation)] = [
        ("overlay", PlanMotion.overlay), ("stats", PlanMotion.stats), ("snap", PlanMotion.snap), ("fan", PlanMotion.fan),
        ("undoBar", PlanMotion.undoBar), ("bin", PlanMotion.bin), ("jump", PlanMotion.jump),
        ("yearZoom", PlanMotion.yearZoom), ("yearFadeIn", PlanMotion.yearFadeIn), ("yearFadeOut", PlanMotion.yearFadeOut),
    ]

    @Test func everyCurveIsDroppedWhenMotionIsReduced() {
        for (name, a) in Self.curves {
            #expect(PlanMotion.pick(a, still: true) == nil, "\(name)")
        }
    }

    @Test func everyCurveStaysWhenMotionIsNotReduced() {
        for (name, a) in Self.curves {
            #expect(PlanMotion.pick(a, still: false) == a, "\(name)")
        }
    }

    @Test func layerSlidesFollowTheSystemSetting() {
        defer { PlanMotion.stillOverride = nil }
        PlanMotion.stillOverride = true
        #expect(overlaySlide == nil)
        #expect(statsSlide == nil)
        #expect(YearZoom.motion == nil)
        #expect(PlanTop.fanToggle == nil)
        PlanMotion.stillOverride = false
        #expect(overlaySlide == PlanMotion.overlay)
        #expect(statsSlide == PlanMotion.stats)
        #expect(YearZoom.motion == PlanMotion.yearZoom)
        #expect(PlanTop.fanToggle == PlanMotion.fan)
    }

    /// Сторож: в «Съёмках» кривая с литералом (`withAnimation(.snappy…)`, `.animation(.easeOut…)`) не пишется — только
    /// через `PlanMotion.pick` (или с проверкой `still` рядом). Новое движение мимо `pick` краснит этот тест.
    @Test func plannerScreensDoNotUseRawCurves() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LightPlanUI/Screens/Planner")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 10)
        var raw: [String] = []
        for f in files {
            let lines = try String(contentsOf: f, encoding: .utf8).components(separatedBy: "\n")
            for (i, l) in lines.enumerated() {
                let trimmed = l.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                let rawCurve = l.contains("withAnimation(.") || l.contains(".animation(.") || l.contains("withAnimation(Animation")
                if rawCurve, !l.contains("PlanMotion"), !l.contains("still"), !l.contains("reduceMotion"), !l.contains("bench-old") {
                    raw.append("\(f.lastPathComponent):\(i + 1)")
                }
            }
        }
        #expect(raw.isEmpty, "кривая мимо PlanMotion.pick: \(raw)")
    }
}
