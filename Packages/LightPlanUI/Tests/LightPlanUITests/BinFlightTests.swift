import CryptoKit
import Foundation
import Testing
@testable import LightPlanUI

/// Полёт в корзину (29.7): звук — записанный `TRASH_B64` и громкость `trashSound` (сверка с живой бетой через
/// `Tools/sound_ref.js`), порядок и интервалы фаз — `deleteToBin` беты, `Reduce Motion` без звука.
/// Серийно: журнал фаз и ответ на «Уменьшить движение» — общие на процесс.
@MainActor
@Suite(.serialized)
struct BinFlightTests {

    private struct Ref: Decodable {
        let trashSha256: String
        let trashBytes: Int
        let trashGain: Double
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

    @Test func trashWavIsByteForByteTheBetaSample() {
        let data = Self.resource("trash")
        #expect(data.count == Self.ref.trashBytes)
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(hex == Self.ref.trashSha256)
    }

    @Test func trashGainIsTheBetas() {
        #expect(SoundCue.trash.gain == Self.ref.trashGain)
        #expect(Self.ref.trashGain == 0.165)
    }

    /// Числа `deleteToBin` и стилей беты: пауза 0,2, глоток на 0,43 полёта, уезд +0,32, скрыт +0,34.
    @Test func timelineIsTheBetas() {
        #expect(BinTimeline.size == 56)
        #expect(BinTimeline.offscreen == 120)
        #expect(BinTimeline.rise == 0.34)
        #expect(BinTimeline.pause == 0.2)
        #expect(BinTimeline.flight == 0.42)
        #expect(BinTimeline.flightScale == 0.05)
        #expect(abs(BinTimeline.gulpAtTotal - 0.63) < 1e-9)
        #expect(BinTimeline.gulp == 0.3 && BinTimeline.gulpPeak == 1.16 && BinTimeline.gulpPeakAt == 0.4)
        #expect(abs(BinTimeline.leaveAtTotal - 0.95) < 1e-9)
        #expect(abs(BinTimeline.hideAtTotal - 1.29) < 1e-9)
        // `bottom: tabh + 26`, `--tabh` 84 (замер беты на 430×932).
        #expect(BinTimeline.lift == 110)
        #expect(BinTimeline.lift == TabBarView.height + 26)
    }

    private static func withSound<T>(_ on: Bool, _ body: () async -> T) async -> T {
        let was = UserDefaults.standard.object(forKey: SoundCenter.enabledKey)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        UserDefaults.standard.set(on, forKey: SoundCenter.enabledKey)
        return await body()
    }

    private static func trashPlays(since n: Int) -> [SoundPlay] {
        Array(SoundCenter.journal.dropFirst(n)).filter { $0.cue == .trash }
    }

    @Test func oneDeletionIsOneSoundAndOnePhaseSequence() async {
        await Self.withSound(true) {
            BinFlightControl.calm(false)
            defer { BinFlightControl.reset() }
            BinLog.reset()
            // Движок прогрет, как в приложении (`Haptics.prepare`): первая сборка узлов — не часть полёта.
            SoundCenter.prepare()
            let flight = BinFlight()
            let before = SoundCenter.journal.count
            var commits = 0, commitAt = 0.0
            let start = ProcessInfo.processInfo.systemUptime
            flight.fly(subjects: ["x"]) { commits += 1; commitAt = ProcessInfo.processInfo.systemUptime - start }
            #expect(commits == 0, "запись стирается в глоток, не сразу")
            try? await Task.sleep(for: .milliseconds(1500))
            let phases = BinLog.journal.map(\.phase)
            #expect(phases == ["rise", "fly", "gulp", "leave", "hide"], "\(phases)")
            let t = BinLog.journal.map(\.at)
            let want = [0.2, 0.43, 0.32, 0.34]
            for i in 0..<4 {
                #expect(abs((t[i + 1] - t[i]) - want[i]) < 0.034, "интервал \(i): \(t[i + 1] - t[i]) ≠ \(want[i])")
            }
            #expect(commits == 1)
            #expect(abs(commitAt - 0.63) < 0.05, "commit на \(commitAt)")
            let plays = Self.trashPlays(since: before)
            #expect(plays.count == 1)
            #expect(plays.first?.gain == 0.165 && plays.first?.event == "binTrash")
            #expect(!flight.shown && !flight.busy && flight.subjects.isEmpty)
        }
    }

    @Test func reduceMotionErasesAtOnceWithoutSound() async {
        await Self.withSound(true) {
            BinFlightControl.calm(true)
            defer { BinFlightControl.reset() }
            BinLog.reset()
            let flight = BinFlight()
            let before = SoundCenter.journal.count
            var commits = 0
            flight.fly(subjects: ["x"]) { commits += 1 }
            #expect(commits == 1)
            #expect(Self.trashPlays(since: before).isEmpty)
            #expect(BinLog.journal.map(\.phase) == ["calm"])
            #expect(!flight.shown)
        }
    }

    @Test func switchedOffClicksSilenceTheCrumple() async {
        await Self.withSound(false) {
            BinFlightControl.calm(false)
            defer { BinFlightControl.reset() }
            let flight = BinFlight()
            let before = SoundCenter.journal.count
            var commits = 0
            flight.fly { commits += 1 }
            try? await Task.sleep(for: .milliseconds(1400))
            #expect(commits == 1)
            #expect(Self.trashPlays(since: before).isEmpty)
        }
    }
}
