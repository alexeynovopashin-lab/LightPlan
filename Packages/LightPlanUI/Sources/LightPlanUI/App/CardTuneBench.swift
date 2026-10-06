import SwiftUI
import os

#if DEBUG && os(iOS)
import UIKit

/// Стенд сжатия блоков (27а.2, Debug): `-LPTuneBench 1 -LPTuneLog <файл>`. После открытия карточки три раза
/// вход → пауза → выход → пауза тем же путём, что тап по «ползункам». На каждый ход — строка: процессорное время
/// главного потока на кадр (в симуляторе интервалы кадра врут: до 60 % — ожидание рендера), число кадров и
/// высоты обёрток блоков по времени (зонд `CardTuneProbe`): за сколько они дошли до конца и до какой высоты.
@MainActor
enum CardTuneBench {
    private static var started = false

    static func startIfAsked(_ app: AppModel) {
        guard !started, UserDefaults.standard.bool(forKey: "LPTuneBench"),
              let path = UserDefaults.standard.string(forKey: "LPTuneLog") else { return }
        started = true
        let url = URL(fileURLWithPath: path)
        func log(_ s: String) {
            let data = Data((s + "\n").utf8)
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
            else { try? data.write(to: url) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            for round in 1...3 {
                for entering in [true, false] {
                    CardTuneProbe.reset()
                    var cpu = ""
                    let meter = EdgeBackMeter { cpu = $0 }
                    meter.start()
                    let t0 = CACurrentMediaTime()
                    app.toggleCardTuning(still: false)
                    try? await Task.sleep(for: .seconds(0.9))
                    meter.stop()
                    let cpuPart = cpu.components(separatedBy: " | ").first { $0.hasPrefix("cpu") } ?? "cpu ?"
                    let framePart = cpu.components(separatedBy: " | ").first ?? ""
                    log("round=\(round) \(entering ? "enter" : "exit") \(framePart) | \(cpuPart) | \(CardTuneProbe.summary(since: t0))")
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            // Повторный тап посреди хода: четыре переключения через 0,12 с — карточка должна встать в обычный вид,
            // счётчик хода — вернуться к нулю, высоты — к естественным (как после выхода выше).
            CardTuneProbe.reset()
            let t1 = CACurrentMediaTime()
            for _ in 1...4 { app.toggleCardTuning(still: false); try? await Task.sleep(for: .seconds(0.12)) }
            try? await Task.sleep(for: .seconds(1.2))
            log("rapid x4 tuning=\(app.cardTuning) moves=\(app.cardTuneMoves) | \(CardTuneProbe.summary(since: t1))")
            // Нечётное число: останавливается в «ползунках»; строки по 56 + зазор.
            CardTuneProbe.reset()
            let t2 = CACurrentMediaTime()
            for _ in 1...3 { app.toggleCardTuning(still: false); try? await Task.sleep(for: .seconds(0.12)) }
            try? await Task.sleep(for: .seconds(1.2))
            log("rapid x3 tuning=\(app.cardTuning) moves=\(app.cardTuneMoves) | \(CardTuneProbe.summary(since: t2))")
            log("done")
        }
    }
}

/// Высоты обёрток блоков по времени (`onGeometryChange` зовёт и вне главного потока — замок).
enum CardTuneProbe {
    nonisolated private static let samples = OSAllocatedUnfairLock<[String: [(Double, Double)]]>(initialState: [:])

    nonisolated static func reset() { samples.withLock { $0 = [:] } }
    nonisolated static func note(_ block: String, height: CGFloat) {
        samples.withLock { $0[block, default: []].append((CACurrentMediaTime(), Double(height))) }
    }

    /// По блоку: высота до хода → после; время от тапа до первого кадра с конечной высотой (±0,5 pt).
    nonisolated static func summary(since t0: Double) -> String {
        samples.withLock { all in
            all.sorted { $0.key < $1.key }.map { name, s in
                guard let first = s.first, let last = s.last else { return "\(name) -" }
                let done = s.first { abs($0.1 - last.1) <= 0.5 }.map { ($0.0 - t0) * 1000 } ?? -1
                return String(format: "%@ %.1f→%.1f t=%.0fms n=%d", name, first.1, last.1, done, s.count)
            }.joined(separator: "; ")
        }
    }
}
#endif
