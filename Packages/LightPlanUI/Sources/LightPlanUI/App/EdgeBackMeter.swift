import SwiftUI
import os

#if DEBUG && os(iOS)
import UIKit

/// Замер кадров жеста «назад» (Debug, включается `-LPEdgeBackLog <файл>`): `CADisplayLink` на время от начала жеста
/// до конца доезда. Кадр, у которого интервал больше полутора периодов экрана, — пропущенный (главный поток не
/// успел собрать слой). Строка в журнал: кадры, пропущенные, p50 / p95 / max интервала отдельно для пальца и доезда,
/// сколько раз пересчитывались `body` (счётчик `count`).
@MainActor
final class EdgeBackMeter: NSObject {
    private enum Phase { case drag, settle }

    private var link: CADisplayLink?
    private var phase = Phase.drag
    private var last: CFTimeInterval?
    private var drag: [Double] = []
    private var settle: [Double] = []
    /// Процессорное время главного потока между соседними тиками, с: без ожиданий. Интервал кадра у симулятора
    /// раздувают ожидания драйвера Metal (`waitUntilScheduled`, XPC), процессорное время ближе к тому, что будет на телефоне.
    private var dragCPU: [Double] = []
    private var settleCPU: [Double] = []
    private var lastCPU: UInt64 = 0
    private var period: Double = 1.0 / 60
    private var moves = 0
    private var bodiesAtStart: [String: Int] = [:]
    private let report: (String) -> Void

    init(report: @escaping (String) -> Void) { self.report = report }

    // MARK: счётчик пересчётов (из любого потока: `onGeometryChange` считает вне главного)

    nonisolated private static let counts = OSAllocatedUnfairLock<[String: Int]>(initialState: [:])
    nonisolated static func count(_ name: String) { counts.withLock { $0[name, default: 0] += 1 } }
    nonisolated private static func snapshot() -> [String: Int] { counts.withLock { $0 } }

    // MARK: жизнь замера

    func start() {
        stop(silently: true)
        phase = .drag; last = nil; drag = []; settle = []; dragCPU = []; settleCPU = []; moves = 0
        bodiesAtStart = Self.snapshot()
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // 120 Гц на ProMotion: без запроса система сама понижает частоту до 60–80, и замер врёт в обратную сторону.
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func move() { moves += 1 }

    func beginSettle() { phase = .settle }

    func stop(silently: Bool = false) {
        guard let l = link else { return }
        l.invalidate()
        link = nil
        guard !silently else { return }
        let d = Self.counts.withLock { $0 }.reduce(into: [String: Int]()) { r, kv in
            let n = kv.value - (bodiesAtStart[kv.key] ?? 0)
            if n > 0 { r[kv.key] = n }
        }
        let bodies = d.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        func raw(_ d: [Double]) -> String { d.map { f($0 * 1000) }.joined(separator: ",") }
        report("meter period=\(f(period * 1000))ms moves=\(moves) | drag \(line(drag)) | settle \(line(settle)) | cpu drag \(cpuLine(dragCPU)) settle \(cpuLine(settleCPU)) | bodies \(bodies.isEmpty ? "-" : bodies) | raw drag=\(raw(drag)) settle=\(raw(settle)) cpudrag=\(raw(dragCPU)) cpusettle=\(raw(settleCPU))")
    }

    @objc private func tick(_ l: CADisplayLink) {
        // Период экрана — по первому тику: у симулятора и телефона он разный (16,7 / 8,3 мс).
        let cpu = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        if last == nil { period = max(0.004, l.targetTimestamp - l.timestamp) }
        if let p = last {
            let dt = l.timestamp - p
            let busy = Double(cpu &- lastCPU) / 1e9
            if phase == .drag { drag.append(dt); dragCPU.append(busy) } else { settle.append(dt); settleCPU.append(busy) }
        }
        last = l.timestamp
        lastCPU = cpu
    }

    // MARK: итоги

    struct Stats: Equatable {
        let n: Int
        /// Пропущенные кадры: интервал, округлённый до k периодов экрана, даёт k − 1.
        let missed: Int
        let p50: Double, p95: Double, max: Double
    }

    /// Итог по интервалам кадров, с. Квантиль — по отсортированному ряду, номер `⌊n·p⌋`.
    static func stats(_ dts: [Double], period: Double) -> Stats? {
        guard !dts.isEmpty else { return nil }
        let sorted = dts.sorted()
        func q(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.down)))] }
        let missed = dts.reduce(0) { $0 + max(0, Int(($1 / period).rounded()) - 1) }
        return Stats(n: dts.count, missed: missed, p50: q(0.5), p95: q(0.95), max: sorted.last!)
    }

    private func line(_ dts: [Double]) -> String {
        guard let s = Self.stats(dts, period: period) else { return "n=0" }
        return "n=\(s.n) missed=\(s.missed) p50=\(f(s.p50 * 1000)) p95=\(f(s.p95 * 1000)) max=\(f(s.max * 1000))"
    }

    private func cpuLine(_ v: [Double]) -> String {
        guard let s = Self.stats(v, period: 1) else { return "n=0" }
        return "p50=\(f(s.p50 * 1000)) p95=\(f(s.p95 * 1000)) max=\(f(s.max * 1000))"
    }

    private func f(_ v: Double) -> String { String(format: "%.1f", v) }
}

/// Стенд жестов без пальца (`-LPEdgeBackBench 1` вместе с `-LPEdgeBackLog`): после запуска сценария тот же путь, что
/// у распознавателя (`begin` → `move` на каждом кадре → `end`), с заданной скоростью. Повторяется ровно, в отличие от
/// руки; живой палец через `simctl` проверяет те же числа выборочно.
@MainActor
enum EdgeBackBench {
    struct Run { let name: String; let to: CGFloat; let seconds: Double; var cancel = false }

    /// Возвраты (медленный, быстрый) и два закрытия: хвост закрытий берёт второй слой, если он есть. Возвраты
    /// повторяются (`-LPEdgeBackReps`, по умолчанию 3): закрытие одно на слой, а разброс замера у симулятора большой.
    /// `cancel-mid` — систему оборвала жест на полпути (распознаватель отменён): слой возвращается с того места, где стоял.
    static var runs: [Run] {
        let reps = max(1, UserDefaults.standard.integer(forKey: "LPEdgeBackReps"))
        return Array(repeating: Run(name: "slow-return", to: 0.28, seconds: 1.0), count: reps)
            + Array(repeating: Run(name: "fast-return", to: 0.28, seconds: 0.12), count: reps)
            + [Run(name: "cancel-mid", to: 0.3, seconds: 0.5, cancel: true),
               Run(name: "slow-close", to: 0.6, seconds: 1.2), Run(name: "fast-close", to: 0.5, seconds: 0.15)]
    }

    /// Кадры экрана как async-последовательность: палец на iOS отдаёт касания раз в кадр, не чаще — стенд ведёт слой так же.
    @MainActor private final class Frames: NSObject {
        private var link: CADisplayLink?
        private var waiter: CheckedContinuation<CFTimeInterval, Never>?
        override init() {
            super.init()
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            l.add(to: .main, forMode: .common)
            link = l
        }
        @objc private func tick(_ l: CADisplayLink) { waiter?.resume(returning: l.timestamp); waiter = nil }
        func next() async -> CFTimeInterval { await withCheckedContinuation { waiter = $0 } }
        func stop() { link?.invalidate(); link = nil }
    }

    private static func drive(_ r: Run, edge: EdgeBack, width: CGFloat, frames: Frames) async {
        edge.note("bench \(r.name) to=\(r.to) seconds=\(r.seconds)")
        guard edge.begin(width: width) else { return }
        let t0 = await frames.next()
        while true {
            let t = (await frames.next() - t0) / r.seconds
            edge.move(width * r.to * CGFloat(min(1, t)))
            if t >= 1 { break }
        }
        if r.cancel { edge.cancel() } else { edge.end(velocity: 0) }
        while edge.active { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .seconds(1))
    }

    /// Кадр слоя в покое и на первом кадре жеста (`-LPEdgeBackHold <pt>`): сдвиг на полпикселя, дальше слой стоит.
    /// Снимки снимает `Tools/edge_back_bench.js --shade` по строкам журнала `hold rest` и `hold gesture`.
    private static func hold(_ edge: EdgeBack, width: CGFloat, dx: CGFloat) async {
        edge.note("hold rest")
        try? await Task.sleep(for: .seconds(2.5))
        guard edge.begin(width: width) else { edge.note("hold refused"); return }
        edge.move(dx)
        try? await Task.sleep(for: .milliseconds(500))
        edge.note("hold gesture dx=\(dx)")
        try? await Task.sleep(for: .seconds(2.5))
        edge.cancel()
        while edge.active { try? await Task.sleep(for: .milliseconds(50)) }
        edge.note("hold done")
    }

    static func run(_ app: AppModel, width: CGFloat) async {
        let edge = app.edgeBack
        try? await Task.sleep(for: .seconds(5))
        if let pt = UserDefaults.standard.string(forKey: "LPEdgeBackHold").flatMap(Double.init) {
            await hold(edge, width: width, dx: CGFloat(pt))
            return
        }
        let frames = Frames()
        defer { frames.stop() }
        for r in runs {
            guard edge.canBegin else { edge.note("bench \(r.name) skipped (no layer)"); continue }
            await drive(r, edge: edge, width: width, frames: frames)
        }
        // Слой, только что открытый: жест через 100 мс после тапа, пока он ещё въезжает.
        if !edge.canBegin {
            withAnimation(overlaySlide) { app.openOrgs() }
            try? await Task.sleep(for: .milliseconds(100))
            await drive(Run(name: "fresh-return", to: 0.28, seconds: 1.0), edge: edge, width: width, frames: frames)
        }
        edge.note("bench done")
    }
}
#endif

/// Счёт пересчётов `body` (Debug): `let _ = EdgeBackCount.hit("Имя")` в теле экрана. В выпуске — пусто.
enum EdgeBackCount {
    static func hit(_ name: String) {
        #if DEBUG && os(iOS)
        EdgeBackMeter.count(name)
        #endif
    }
}
