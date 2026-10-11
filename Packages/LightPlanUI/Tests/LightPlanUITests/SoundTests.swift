import CryptoKit
import Foundation
import Testing
@testable import LightPlanUI

/// Звуки (29.6): ресурс, формулы и привязка к отдаче сверяются с живой бетой через `Tools/sound_ref.js`.
@MainActor
struct SoundTests {

    private struct Ref: Decodable {
        struct Step: Decodable { let at: Int; let pa: Int; let pb: Int; let rate: Double; let gain: Double }
        let clickSha256: String
        let clickBytes: Int
        let piDigits: String
        let steps: [Step]
        let shutterGain: Double
    }

    private static let ref: Ref = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "sound_ref.json")
        return try! JSONDecoder().decode(Ref.self, from: Data(contentsOf: url))
    }()

    private static func resource(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/LightPlanUI/Resources/Sound/\(name).wav")
        return try! Data(contentsOf: url)
    }

    @Test func clickWavIsByteForByteTheBetaSample() {
        let data = Self.resource("click")
        #expect(data.count == Self.ref.clickBytes)
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(hex == Self.ref.clickSha256)
    }

    @Test func shutterGainIsTheBetas() {
        #expect(Double(SoundCue.shutter.gain) == Self.ref.shutterGain)
        #expect(Self.ref.shutterGain == 0.2695)
    }

    @Test func piTableIsTheBetas() {
        let mine = SoundCenter.piDigits.map(String.init).joined()
        #expect(mine == Self.ref.piDigits)
    }

    /// Первые 10 шагов — те, что просили; сверяем все 98 (круг и два шага по новой).
    @Test func clickFormulasMatchTheBetaStepByStep() {
        var cursor = SoundCenter.PiCursor()
        for (i, step) in Self.ref.steps.enumerated() {
            #expect(cursor.tick == step.at, "шаг \(i): указатель")
            let v = cursor.next()
            #expect(abs(v.rate - step.rate) < 1e-12, "шаг \(i): rate \(v.rate) ≠ \(step.rate)")
            #expect(abs(v.gain - step.gain) < 1e-12, "шаг \(i): gain \(v.gain) ≠ \(step.gain)")
        }
        #expect(Self.ref.steps.count >= 10)
    }

    // MARK: - Привязка к отдаче

    /// События со щелчком — ровно перечень беты (`tickClick`); остальные тики тихи.
    private static let clicking: Set<HapticEvent> = [
        .deadlineStop, .fan, .dayLift, .dayNotch, .routePointLift, .dayStripDate, .daySwipe, .laneDot,
    ]

    private static func played(_ body: () -> Void) -> [SoundPlay] {
        let before = SoundCenter.journal.count
        body()
        return Array(SoundCenter.journal.dropFirst(before))
    }

    @Test func everyHapticEventSoundsOrStaysQuietAsTheBetaDoes() {
        for e in HapticEvent.allCases {
            #expect((e.sound != nil) == Self.clicking.contains(e), "\(e)")
        }
    }

    @Test func oneTickIsExactlyOneClick() {
        let was = UserDefaults.standard.object(forKey: SoundCenter.enabledKey)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        UserDefaults.standard.set(true, forKey: SoundCenter.enabledKey)
        for e in HapticEvent.allCases where !e.awaitsGesture {
            let log = Self.played { Haptics.play(e) }
            #expect(log.count == (Self.clicking.contains(e) ? 1 : 0), "\(e): \(log.count)")
            if let p = log.first { #expect(p.event == e.rawValue && p.cue == .click) }
        }
    }

    @Test func dateTapClicksOnlyWhenTheDayChanged() {
        let was = UserDefaults.standard.object(forKey: SoundCenter.enabledKey)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        UserDefaults.standard.set(true, forKey: SoundCenter.enabledKey)
        #expect(Self.played { Haptics.play(.dayStripDate, sound: false) }.isEmpty)
        #expect(Self.played { Haptics.play(.dayStripDate, sound: true) }.count == 1)
    }

    @Test func toggleOffSilencesEverything() {
        let was = UserDefaults.standard.object(forKey: SoundCenter.enabledKey)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        UserDefaults.standard.set(false, forKey: SoundCenter.enabledKey)
        let log = Self.played {
            for e in HapticEvent.allCases { Haptics.play(e) }
            TimebarHaptics().detent()
            TimebarSound().playSnap()
        }
        #expect(log.isEmpty)
    }

    @Test func togglingOnClicksOnce() {
        let was = UserDefaults.standard.object(forKey: SoundCenter.enabledKey)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        let log = Self.played { SoundCenter.setEnabled(true) }
        #expect(log.count == 1 && log[0].event == "soundToggle" && log[0].cue == .click)
        #expect(Self.played { SoundCenter.setEnabled(false) }.isEmpty)
    }

    @Test func timebarDetentAndSnapSound() {
        let was = UserDefaults.standard.object(forKey: SoundCenter.enabledKey)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        UserDefaults.standard.set(true, forKey: SoundCenter.enabledKey)
        let d = Self.played { TimebarHaptics().detent() }
        #expect(d.count == 1 && d[0].cue == .click && d[0].event == "timebar.detent")
        let s = Self.played { TimebarSound().playSnap() }
        #expect(s.count == 1 && s[0].cue == .shutter && s[0].gain == 0.2695)
    }
}
