import SwiftUI

/// Журнал «кто взял касание» для замеров жестов на симуляторе (29.4; Debug, `-LPMapGestureLog <файл>`; имя без «/» —
/// файл в `Documents` приложения). Свидетель — распознаватель на окне, который сам ничего не берёт: остаётся
/// «возможным» до конца касания, касаний не задерживает и не отменяет. На каждое касание он вешает цель на все
/// распознаватели, которым это касание досталось, и одной строкой на жест пишет: где легли пальцы и на какой вид,
/// путь первого пальца, кто взял жест (`began`/`ended`), кто отказал, и что сказал экран до и после (`probe`).
enum TouchWitness {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPMapGestureLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    /// Состояние экрана в одну строку (у «Карты» — уровень и центр камеры, голый холст, свод).
    @MainActor static var probe: (() -> String)?
    #endif

    static func note(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let url, let data = (String(format: "%.3f ", ProcessInfo.processInfo.systemUptime) + line() + "\n")
            .data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}

#if DEBUG && os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct TouchWitnessHost: UIViewRepresentable {
    func makeUIView(context: Context) -> TouchWitnessProbe { TouchWitnessProbe() }
    func updateUIView(_ v: TouchWitnessProbe, context: Context) {}
}

final class TouchWitnessProbe: UIView {
    private var witness: TouchWitnessRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let witness { witness.view?.removeGestureRecognizer(witness); self.witness = nil }
        guard TouchWitness.url != nil, let window else { return }
        let w = TouchWitnessRecognizer()
        window.addGestureRecognizer(w)
        witness = w
    }
}

final class TouchWitnessRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Одно касание от первого пальца до отпускания последнего; итог пишется позже — касание к тому времени уже
    /// закрыто, и следующее заводит своё.
    private final class Sequence {
        var watched: [(g: UIGestureRecognizer, states: [String])] = []
        var downs: [String] = []
        var first: (touch: UITouch, at: CGPoint)?
        var last: CGPoint = .zero
        var fingers = 0
        var before = ""
    }
    private var live: Sequence?
    private var pending: [Sequence] = []

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let window = view else { return }
        let q: Sequence
        if let live { q = live } else {
            q = Sequence()
            q.before = MainActor.assumeIsolated { TouchWitness.probe?() } ?? ""
            live = q
        }
        for t in touches {
            let p = t.location(in: window)
            q.fingers += 1
            if q.first == nil { q.first = (t, p); q.last = p }
            q.downs.append(String(format: "(%.0f,%.0f)@%@", p.x, p.y, Self.name(t.view)))
            for g in t.gestureRecognizers ?? [] where g !== self && !q.watched.contains(where: { $0.g === g }) {
                g.addTarget(self, action: #selector(seen(_:)))
                q.watched.append((g, []))
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let q = live, let f = q.first, touches.contains(f.touch), let window = view { q.last = f.touch.location(in: window) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        guard let q = live else { return }
        if let f = q.first, touches.contains(f.touch), let window = view { q.last = f.touch.location(in: window) }
        q.fingers -= touches.count
        guard q.fingers <= 0 else { return }
        live = nil
        pending.append(q)
        // Итог — через 0,6 с: одиночный тап, ждущий отказа двойного, признаётся через ~0,3 с после отпускания.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, q] in self?.report(q) }
        state = .failed
    }

    @objc private func seen(_ g: UIGestureRecognizer) {
        // Распознаватель отчитывается тому касанию, что идёт сейчас, иначе — последнему закрытому, где он был.
        guard let q = live?.watched.contains(where: { $0.g === g }) == true ? live
                : pending.last(where: { $0.watched.contains { $0.g === g } }),
              let i = q.watched.firstIndex(where: { $0.g === g }) else { return }
        let s = Self.stateName(g.state)
        if q.watched[i].states.last != s { q.watched[i].states.append(s) }
    }

    private func report(_ q: Sequence) {
        pending.removeAll { $0 === q }
        var took: [String] = [], refused: [String] = []
        for (g, states) in q.watched {
            let name = Self.name(g.view) + "." + String(describing: type(of: g))
                + ((g as? UITapGestureRecognizer).map { $0.numberOfTapsRequired > 1 ? "×\($0.numberOfTapsRequired)" : "" } ?? "")
            if states.isEmpty { refused.append(name) } else { took.append(name + "[" + states.joined(separator: ">") + "]") }
            let still = (live?.watched.contains { $0.g === g } ?? false) || pending.contains { $0.watched.contains { $0.g === g } }
            if !still { g.removeTarget(self, action: #selector(seen(_:))) }
        }
        let a = q.first?.at ?? .zero
        let after = MainActor.assumeIsolated { TouchWitness.probe?() } ?? ""
        TouchWitness.note(String(format: "touch n=%d down=%@ path=(%.0f,%.0f) took=%@ quiet=%@ before={%@} after={%@}",
                                 q.downs.count, q.downs.joined(separator: ","), q.last.x - a.x, q.last.y - a.y,
                                 took.sorted().joined(separator: ","), refused.sorted().joined(separator: ","),
                                 q.before, after))
    }

    private static func name(_ v: UIView?) -> String {
        guard let v else { return "nil" }
        let s = String(describing: type(of: v))
        // Обёртки SwiftUI длинные и с параметрами типа — нужна только суть.
        if let cut = s.firstIndex(of: "<") { return String(s[..<cut]) }
        return s
    }

    private static func stateName(_ s: UIGestureRecognizer.State) -> String {
        switch s {
        case .possible: "possible"
        case .began: "began"
        case .changed: "changed"
        case .ended: "ended"
        case .cancelled: "cancelled"
        case .failed: "failed"
        @unknown default: "?"
        }
    }
}
#endif
