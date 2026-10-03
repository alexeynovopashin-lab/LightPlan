import SwiftUI

#if os(iOS)
import UIKit

/// Распознаватель края (итерация 28з): тот же `UIScreenEdgePanGestureRecognizer`, что у системной навигации, один
/// на окно. Сам различает «от края» и «не от края», не перехватывает касания внутри экрана и не мешает
/// барабану, ползункам и карте: им краевой жест достаётся, только если палец лёг в зону края.
struct EdgeBackHost: UIViewRepresentable {
    let app: AppModel

    func makeUIView(context: Context) -> EdgeBackProbe {
        let v = EdgeBackProbe()
        v.app = app
        return v
    }

    func updateUIView(_ v: EdgeBackProbe, context: Context) { v.app = app }
}

final class EdgeBackProbe: UIView {
    weak var app: AppModel? { didSet { gate.app = app } }
    private var pan: UIScreenEdgePanGestureRecognizer?
    private let gate = EdgeBackGate()
    #if DEBUG
    private var benchStarted = false
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let pan { pan.view?.removeGestureRecognizer(pan); self.pan = nil }
        guard let window else { return }
        let g = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handle(_:)))
        g.edges = .left
        g.delegate = gate
        window.addGestureRecognizer(g)
        pan = g
        #if DEBUG
        // Стенд без пальца (`-LPEdgeBackBench 1`): тот же путь `begin` → `move` → `end`, один раз за запуск.
        if let app, UserDefaults.standard.bool(forKey: "LPEdgeBackBench"), !benchStarted {
            benchStarted = true
            let width = window.bounds.width
            Task { @MainActor in await EdgeBackBench.run(app, width: width) }
        }
        #endif
    }

    @objc private func handle(_ g: UIScreenEdgePanGestureRecognizer) {
        guard let app, let window = g.view else { return }
        let edge = app.edgeBack
        let x = g.translation(in: window).x
        switch g.state {
        case .began:
            guard edge.begin(width: window.bounds.width) else { return }
            // Клавиатура уходит с началом жеста: слой уедет, а набор остался бы без поля.
            window.endEditing(true)
            edge.move(x)
        case .changed:
            edge.move(x)
        case .ended:
            // Последнее положение уже записано движением: отпускание своей точки не добавляет, иначе стоявший палец
            // выглядел бы двигавшимся.
            edge.end(recognizer: g.velocity(in: window).x)
        case .cancelled, .failed:
            edge.cancel()
        default:
            break
        }
    }

}

/// Решает, брать ли жест: слой есть, не идёт доезд, нет просмотра кадров, поверх нет листа.
final class EdgeBackGate: NSObject, UIGestureRecognizerDelegate {
    weak var app: AppModel?

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let app, let window = g.view as? UIWindow else { return false }
        let ok = app.edgeBack.canBegin && !app.edgeBackBlocked && Self.allowsBack(window)
        if !ok { app.edgeBack.note("gate no: canBegin=\(app.edgeBack.canBegin) blocked=\(app.edgeBackBlocked) allows=\(Self.allowsBack(window)) style=\(Self.topStyle(window))") }
        return ok
    }

    static func topStyle(_ window: UIWindow) -> Int {
        var vc = window.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc?.modalPresentationStyle.rawValue ?? -1
    }

    /// Лист, диалог и всё, что поднято не на весь экран, жест не берут: у них свой жест закрытия.
    /// Форма записи поднята на весь экран (SwiftUI ставит `.overFullScreen`) — она жест берёт.
    static func allowsBack(_ window: UIWindow) -> Bool {
        var vc = window.rootViewController
        while let p = vc?.presentedViewController {
            let style = p.modalPresentationStyle
            if p.isBeingDismissed || p is UIAlertController || !(style == .fullScreen || style == .overFullScreen) { return false }
            vc = p
        }
        return true
    }
}
#else
/// На Mac системной навигации и края нет: слои закрываются кнопкой.
struct EdgeBackHost: View {
    let app: AppModel
    var body: some View { EmptyView() }
}
#endif
