import SwiftUI

// MARK: - Гармошка стопки (29.3а; веб «Потянуть стопку», `beta/index.html` ~28505)

/// Числа гармошки — те же, что у веба. Тянешь лист карточки вниз — края
/// стопки разъезжаются вниз от верхнего края стопки: самый дальний стоит на
/// месте, ближние едут под ним, дальше всех — сам лист. Раскрытый край
/// показывает 44 pt (две строки), ближний — целиком 74, отсюда ход листа
/// `(N−1)·44 + 74 − N·22`; на одном крае это прежние 52. Длина протяга
/// растёт мягче стопки: `110 + (N−1)·30`.
enum StackPull {
    /// Высота края (веб `PEEK_H`); `CardStack.peekHeight` берёт её отсюда.
    static let peekHeight: CGFloat = 74
    /// Сколько показывает раскрытый край (веб `PEEK_OPEN`).
    static let peekOpen: CGFloat = 44
    /// Ступень края (веб `STEP` = `PEEK_STEP`).
    static let step: CGFloat = 22
    /// Сдвиг вниз, после которого жест наш (веб `dy > 6`).
    static let slop: CGFloat = 6
    /// Лист считается не прокрученным до 2 pt (веб `overlay.scrollTop > 2`).
    static let scrollSlack: CGFloat = 2

    /// Ход листа при полном протяге (веб `sheetTravel`): без краёв — ноль.
    static func sheetTravel(_ n: Int) -> CGFloat {
        n > 0 ? CGFloat(n - 1) * peekOpen + peekHeight - CGFloat(n) * step : 0
    }

    /// Длина протяга до полного раскрытия (веб `pullLen`).
    static func pullLength(_ n: Int) -> CGFloat { 110 + CGFloat(max(0, n - 1)) * 30 }

    /// Ход края k (0 — ближний к листу) при полном протяге: дальний край стоит.
    static func peekTravel(k: Int, n: Int) -> CGFloat { CGFloat(n - 1 - k) * step }

    /// Сдвиг края k на доле протяга `p` (веб `(stackN − 1 − k)·STEP·p`).
    static func peekOffset(k: Int, n: Int, p: CGFloat) -> CGFloat { peekTravel(k: k, n: n) * p }

    /// Доля протяга по сдвигу пальца вниз, `0…1`.
    static func progress(dy: CGFloat, n: Int) -> CGFloat { min(1, max(0, dy / pullLength(n))) }

    /// Берёт ли лист касание (веб `touchstart`): один палец, края видны, не
    /// режим «ползунки» (там тем же движением таскают блоки), лист не
    /// прокручен. Иначе касание целиком у прокрутки и кнопок.
    static func canStart(n: Int, tuning: Bool, touches: Int, scrollTop: CGFloat) -> Bool {
        n > 0 && !tuning && touches == 1 && scrollTop <= scrollSlack
    }

    /// Что делать с касанием по сдвигу пальца, пока жест не взят: вниз больше
    /// 6 pt — наш; вверх больше 6 или вбок сильнее, чем вниз, — прокрутке и
    /// жесту «назад»; иначе ждём.
    enum Verdict: Equatable { case wait, take, refuse }
    static func verdict(dx: CGFloat, dy: CGFloat) -> Verdict {
        if abs(dx) > slop && abs(dx) > dy { return .refuse }
        if dy > slop { return .take }
        if dy < -slop { return .refuse }
        return .wait
    }

    /// Пружина обратно (`.peek`, `.card-sheet`: `0,42 с cubic-bezier(0.34, 1.42, 0.5, 1)` — с перелётом).
    /// При «Уменьшении движения» — та же длина без перелёта (CSS `ease`): палец по-прежнему ведёт лист,
    /// но назад он не отскакивает.
    static func settle(still: Bool) -> Animation {
        still ? .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.42) : .timingCurve(0.34, 1.42, 0.5, 1, duration: 0.42)
    }
}

/// Сдвиг листа или края на долю протяга. Свой эффект, а не `.offset`: SwiftUI
/// зовёт его на каждом кадре пружины с промежуточной долей — журнал видит то,
/// что нарисовано. Только перенос: стекло не крутят и не масштабируют (28п).
struct PullShift: GeometryEffect {
    /// Ход при полном протяге.
    var travel: CGFloat
    var p: CGFloat
    /// Имя в журнале: `sheet` или `k0`, `k1`, …
    var tag: String

    var animatableData: CGFloat {
        get { p }
        set { p = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        StackLog.note(String(format: "fx %@ p=%.4f y=%.2f", tag, p, travel * p))
        return ProjectionTransform(CGAffineTransform(translationX: 0, y: travel * p))
    }
}

/// Журнал гармошки для замеров на симуляторе (Debug, `-LPStackLog <файл>`; имя
/// без «/» — файл в `Documents`): касание и решение, ход пальца с долей и
/// сдвигами по формулам, отпускание, и `fx` — сдвиг каждого листа на кадре.
enum StackLog {
    #if DEBUG
    static let url = UserDefaults.standard.string(forKey: "LPStackLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    #endif
    static func note(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let url, let data = (String(format: "%.4f ", ProcessInfo.processInfo.systemUptime) + line() + "\n")
            .data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}

/// Жест гармошки. `down` — касание (сколько пальцев, прокрутка листа) и
/// решение, брать ли; `moved` — сдвиг пальца вниз от касания; `ended(true)` —
/// касание отняла система.
struct StackPullGesture {
    var down: (_ touches: Int, _ scrollTop: CGFloat) -> Bool
    var moved: (CGFloat) -> Void
    var ended: (Bool) -> Void
}

#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Подложка листа: её рамка — где касание начинает гармошку, а сам
/// распознаватель она ставит на прокрутку карточки, а не на лист через
/// `.gesture`. У SwiftUI жест кнопки внутри листа (телефон, блоки, тумблеры)
/// важнее родительского: протяг, начатый на кнопке, распознаватель листа не
/// получал вовсе — ни одного движения (замер: касание на кнопке телефона,
/// `reset state=0 dy=0`). У веба `touchstart` на листе ловит всё, что в нём.
/// На прокрутке распознаватель — обычный UIKit: кнопки он отменяет, когда
/// жест взят, и не трогает, пока не взят.
struct StackPullHost: UIViewRepresentable {
    var gesture: StackPullGesture

    func makeUIView(context: Context) -> StackPullProbe {
        let v = StackPullProbe()
        v.gesture = gesture
        return v
    }

    func updateUIView(_ v: StackPullProbe, context: Context) { v.gesture = gesture }

    static func dismantleUIView(_ v: StackPullProbe, coordinator: ()) { v.detach() }
}

final class StackPullProbe: UIView, UIGestureRecognizerDelegate {
    var gesture: StackPullGesture?
    private var pan: StackPullPan?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard window != nil else { return }
        var v = superview
        while let x = v, !(x is UIScrollView) { v = x.superview }
        guard let scroll = v as? UIScrollView else { StackLog.note("host scroll missing"); return }
        let g = StackPullPan(target: self, action: #selector(handle(_:)))
        g.delegate = self
        g.probe = self
        scroll.addGestureRecognizer(g)
        pan = g
        StackLog.note("host on scroll h=\(Int(scroll.bounds.height))")
    }

    func detach() {
        if let pan { pan.view?.removeGestureRecognizer(pan); self.pan = nil }
    }

    /// Касание на листе и лист берёт его (`down`); иначе отказ сразу.
    func decide(_ t: UITouch, touches: Int, scroll: UIScrollView) -> Bool {
        let p = t.location(in: self)
        guard bounds.contains(p) else { return false }
        let top = scroll.contentOffset.y + scroll.adjustedContentInset.top
        return gesture?.down(touches, top) ?? false
    }

    @objc private func handle(_ r: StackPullPan) {
        guard let g = gesture else { return }
        switch r.state {
        case .began, .changed: g.moved(r.dy)
        case .ended: g.ended(false)
        case .cancelled: g.ended(true)
        default: break
        }
    }

    /// Прокрутка листа ждёт нашего отказа, иначе быстрый протяг вниз ушёл
    /// бы в оттяжку прокрутки. Отказ приходит сразу на касании, если оно мимо
    /// листа, лист прокручен, «ползунки» или краёв нет, и через 6 pt — при
    /// движении вверх или вбок. Жест «назад» (28з) висит на окне и в эту
    /// очередь не встаёт: его зона у края экрана, а лист начинается в 24 pt
    /// от края — такое касание мимо листа, отказ на касании.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer && other.view is UIScrollView
    }
}

/// Распознаватель гармошки. Свой, а не `UIPanGestureRecognizer`: решает на
/// касании (на листе ли палец, прокручен ли лист) и отказывается при первом
/// движении вверх или вбок, отдавая палец прокрутке. Сдвиг считается в
/// координатах окна: лист под пальцем сам едет, его свои координаты плывут.
final class StackPullPan: UIGestureRecognizer {
    weak var probe: StackPullProbe?
    private var touch: UITouch?
    private var start: CGPoint = .zero
    /// Сдвиг пальца вниз от касания, pt окна.
    private(set) var dy: CGFloat = 0

    /// Уступаем только прокрутке и жесту «назад». Нажатие кнопки SwiftUI
    /// срабатывает на касании и по умолчанию гасит соседей, пока те не взяты:
    /// протяг с кнопки телефона не получал ни одного движения (замер:
    /// `reset state=0 dy=0`, лист ушёл в прокрутку).
    override func canBePrevented(by g: UIGestureRecognizer) -> Bool {
        g is UIScreenEdgePanGestureRecognizer || (g is UIPanGestureRecognizer && g.view is UIScrollView)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let t = touch {
            // Второй палец: до взятия — не наш жест (веб `touches.length !== 1`), после — не мешает.
            if state == .possible { state = .failed } else { touches.filter { $0 !== t }.forEach { ignore($0, for: event) } }
            return
        }
        guard let t = touches.first else { state = .failed; return }
        touch = t
        start = t.location(in: nil)
        dy = 0
        guard let probe, let scroll = view as? UIScrollView,
              probe.decide(t, touches: event.allTouches?.count ?? touches.count, scroll: scroll) else {
            state = .failed; return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let t = touch, touches.contains(t) else { return }
        let p = t.location(in: nil)
        dy = p.y - start.y
        switch state {
        case .possible:
            switch StackPull.verdict(dx: p.x - start.x, dy: dy) {
            case .take: state = .began
            case .refuse:
                StackLog.note(String(format: "refuse dx=%.1f dy=%.1f", p.x - start.x, dy))
                state = .failed
            case .wait: break
            }
        case .began, .changed: state = .changed
        default: break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let t = touch, touches.contains(t) else { return }
        state = state == .began || state == .changed ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let t = touch, touches.contains(t) else { return }
        StackLog.note("touches cancelled state=\(state.rawValue)")
        state = state == .began || state == .changed ? .cancelled : .failed
    }

    override func reset() {
        StackLog.note(String(format: "reset dy=%.1f", dy))
        super.reset()
        touch = nil
        dy = 0
    }
}
#endif
