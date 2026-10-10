import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Время события рукой на ленте дня (29а; веб `dlGrip` … `dlCommit`, DECISIONS
/// «Время события рукой на ленте дня», 18.09). Удержание 0,45 с поднимает
/// событие; повёл, не отпуская, — время едет с шагом ленты; отпустил на месте —
/// прежний веер, без затемнения, а у события две ручки: начало сверху справа,
/// конец снизу слева. Выделенное тянется и за тело, уже без удержания. Касание
/// мимо снимает выделение — и больше ничего не делает.
///
/// Здесь — состояние, которое видит рисунок, и то, что держит жест между
/// касаниями. Числа (шаг, сетка, пределы, «матрёшка», след) — `DayDrag` домена.
@MainActor @Observable
final class DayGrip {
    /// Выделенная запись (веб `dlSel`): у неё ручки. Живёт только на ленте часов.
    var selected: String?
    /// Идущий жест после подъёма (веб `dlG.armed`): время, которое сейчас под
    /// пальцем, и поднято ли событие над соседями.
    var live: Live?

    struct Live: Equatable {
        let id: String
        let mode: DayDrag.Mode
        var start: Int
        var end: Int
        var lifted: Bool
        var moved = false
    }

    /// Что держит жест от касания до отпускания (веб `dlG`).
    struct Hand {
        let id: String
        let mode: DayDrag.Mode
        /// Непустая съёмка: целиком не переносится, удержание — ручки и веер.
        let pinned: Bool
        /// Поднята удержанием (а не взята за ручку или выделенное тело).
        let hold: Bool
        let a0: Int
        let b0: Int
        let nest: NestSpan?
        let step: Int
        /// Точка касания на ленте.
        var y0: CGFloat = 0
    }
    @ObservationIgnored var hand: Hand?
    /// Удержание пустого часа: час и минута, на которые встанет меню часа.
    @ObservationIgnored var slotHold: (hour: Int, at: Int)?
    /// Жест поднят (веб `dlG.armed`): от подъёма или взятой ручки до отпускания.
    @ObservationIgnored var armed = false

    /// До какого мгновения тап по ленте не открывает ни карточку, ни меню часа
    /// (веб `dlSwallowTill`): после жеста и после касания, снявшего выделение.
    @ObservationIgnored var swallowTill: TimeInterval = 0
    /// Когда кончился жест: свайп дней его не подхватывает (веб `dlArmedEnd`).
    @ObservationIgnored var armedEnd: TimeInterval = 0
    /// Метка касания, которое видела лента: сторож экрана по ней понимает, что
    /// касание было мимо ленты.
    @ObservationIgnored var laneTouch: TimeInterval = -1
    /// Рамка ленты в пространстве веера — от неё ставится веер у события.
    @ObservationIgnored var laneFrame: CGRect = .zero

    nonisolated static var clock: TimeInterval { ProcessInfo.processInfo.systemUptime }

    var swallows: Bool { Self.clock < swallowTill }
    /// Боковой увод пальца при сдвиге не листает день — ни во время жеста, ни
    /// сразу после (конец жеста приходит раньше конца свайпа).
    var blocksSwipe: Bool { armed || Self.clock - armedEnd < 0.4 }

    func deselect() {
        if selected != nil { selected = nil }
    }

    #if os(iOS)
    private let lift = UIImpactFeedbackGenerator(style: .light)
    private let notch = UISelectionFeedbackGenerator()
    /// Отдача подъёма — та же, что у веера удержания (`.impact(.light)`).
    func tapLift() { lift.impactOccurred() }
    /// Щелчок на каждой ступени времени (веб `tickClick` в `dlTrack`).
    func tapNotch() { notch.selectionChanged() }
    #else
    func tapLift() {}
    func tapNotch() {}
    #endif
}

/// Журнал жеста для замеров на симуляторе (Debug, `-LPDayGripLog <файл>`; имя без
/// «/» — файл в `Documents` приложения): касание и что под ним, подъём, путь
/// пальца в pt и минуты, запись, сдвиг прокрутки ленты, проглоченные тапы и свайпы.
enum DayGripLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPDayGripLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    #endif
    static func note(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let url, let data = (String(format: "%.3f ", DayGrip.clock) + line() + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}

/// Как лента приняла касание (`DayGripPan.Start`): мимо, сразу, удержанием
/// события, удержанием пустого часа (меню часа).
enum DayGripStart { case none, now, hold, slot }

/// Жест ленты. `down` — касание (точка ленты, метка касания) и решение:
/// мимо / берём сразу (ручка, тело выделенного) / после удержания.
/// `began`, `moved` — точка ленты; `ended(true)` — касание отняла система.
/// `autoScroll` — листать ли ленту у краёв сейчас.
struct DayGripGesture {
    var down: (CGPoint, TimeInterval) -> DayGripStart
    var began: (CGPoint) -> Void
    var moved: (CGPoint) -> Void
    var ended: (Bool) -> Void
    /// Распознаватель вернулся в покой — и после отказа, когда `ended` не зовут.
    var reset: () -> Void
    var autoScroll: () -> Bool
}

#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

extension DayGripGesture: UIGestureRecognizerRepresentable {

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter, gesture: self)
    }

    func makeUIGestureRecognizer(context: Context) -> DayGripPan {
        let pan = DayGripPan()
        pan.delegate = context.coordinator
        let coordinator = context.coordinator
        pan.decide = { [weak coordinator] stamp in
            guard let coordinator else { return .none }
            return coordinator.gesture.down(coordinator.converter.localLocation, stamp)
        }
        pan.onReset = { [weak coordinator, weak pan] in
            guard let coordinator else { return }
            #if DEBUG
            // Отказ (палец ушёл в прокрутку или отпущен до удержания): где теперь лента.
            if let pan, pan.failedHold {
                // Отказ приходит раньше, чем прокрутка тронется: её сдвиг виден строкой следующего жеста.
                DayGripLog.note("failed scroll=\(Int(coordinator.scroll?.contentOffset.y ?? -1))")
            }
            #endif
            coordinator.gesture.reset()
        }
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: DayGripPan, context: Context) {
        context.coordinator.converter = context.converter
        context.coordinator.gesture = self
    }

    func handleUIGestureRecognizerAction(_ recognizer: DayGripPan, context: Context) {
        let c = context.coordinator
        switch recognizer.state {
        case .began:
            c.track(recognizer)
            c.scrollAtBegan = c.offsetAtTouch
            DayGripLog.note("began scroll=\(Int(c.offsetAtTouch))")
            c.gesture.began(c.point)
            c.startAuto(recognizer)
        case .changed:
            c.track(recognizer)
            c.gesture.moved(c.point)
        case .ended, .cancelled, .failed:
            c.stopAuto()
            DayGripLog.note("\(recognizer.state == .ended ? "ended" : "cancelled") scroll=\(Int(c.scroll?.contentOffset.y ?? 0))"
                            + " auto=\(Int((c.scroll?.contentOffset.y ?? 0) - c.scrollAtBegan))")
            c.gesture.ended(recognizer.state != .ended)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var converter: CoordinateSpaceConverter
        var gesture: DayGripGesture
        /// Палец на ленте с поправкой на автопрокрутку после последнего касания:
        /// стоящий палец продолжает вести время, пока лента едет под ним.
        private(set) var point: CGPoint = .zero
        private(set) var offsetAtTouch: CGFloat = 0
        /// Прокрутка на подъёме — для журнала: сколько лента уехала сама.
        var scrollAtBegan: CGFloat = 0
        private(set) weak var scroll: UIScrollView?
        private weak var pan: DayGripPan?
        private var link: CADisplayLink?
        private var lastTick: CFTimeInterval = 0
        /// Край включается не раньше, чем палец из него выйдет (веб `edgeOk`):
        /// событие, поднятое у нижней кромки, не должно само уехать вниз.
        private var edgeOk = false

        init(converter: CoordinateSpaceConverter, gesture: DayGripGesture) {
            self.converter = converter
            self.gesture = gesture
        }

        func track(_ r: DayGripPan) {
            if scroll == nil {
                // Распознаватель SwiftUI вешает на корневой вид, выше прокрутки:
                // ищем её от вида под пальцем.
                var v = r.touchView
                while let x = v, !(x is UIScrollView) { v = x.superview }
                scroll = v as? UIScrollView
                DayGripLog.note("scroll \(scroll.map { "found h=\(Int($0.bounds.height)) inset=\(Int($0.adjustedContentInset.top)),\(Int($0.adjustedContentInset.bottom))" } ?? "missing")")
            }
            point = converter.localLocation
            offsetAtTouch = scroll?.contentOffset.y ?? 0
        }

        /// Прокрутка ленты ждёт, пока жест откажется: удержание события не
        /// срывается в прокрутку, а быстрый палец (сдвиг > 8 pt до подъёма)
        /// отдаётся ей сразу. Жест «назад» от края (28з) висит на окне — его
        /// это не касается.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }

        // MARK: Лента сама листается у краёв (веб `dlAuto`)

        func startAuto(_ r: DayGripPan) {
            pan = r
            edgeOk = false
            lastTick = 0
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }

        func stopAuto() {
            link?.invalidate()
            link = nil
        }

        /// Поле края — 48 pt от низа шапки и от верха панели вкладок; скорость —
        /// `min(12, ⌈заход / 4⌉)` pt за кадр 60 Гц, как у веба.
        @objc private func tick(_ l: CADisplayLink) {
            guard let sv = scroll, let r = pan, gesture.autoScroll() else { return }
            let dt = lastTick == 0 ? 1 / 60 : min(0.05, l.timestamp - lastTick)
            lastTick = l.timestamp
            let inset = sv.adjustedContentInset
            let y = r.location(in: sv).y - sv.contentOffset.y
            let top = inset.top, bot = sv.bounds.height - inset.bottom, edge: CGFloat = 48
            var dy: CGFloat = 0
            if !edgeOk {
                if y > top + edge && y < bot - edge { edgeOk = true }
            } else if y < top + edge {
                dy = -min(12, ((top + edge - y) / 4).rounded(.up))
            } else if y > bot - edge {
                dy = min(12, ((y - bot + edge) / 4).rounded(.up))
            }
            guard dy != 0 else { return }
            let lo = -inset.top, hi = max(lo, sv.contentSize.height + inset.bottom - sv.bounds.height)
            let was = sv.contentOffset.y
            let to = min(max(was + dy * CGFloat(dt * 60), lo), hi)
            guard to != was else { return }
            sv.contentOffset.y = to
            point.y += to - offsetAtTouch
            offsetAtTouch = to
            gesture.moved(point)
        }
    }
}

/// Распознаватель ленты. Свой, а не `UILongPressGestureRecognizer`: на
/// касании он спрашивает ленту, что под пальцем, и берёт палец сразу (ручка,
/// тело выделенного), через 0,45 с (событие) или отказывается — тогда палец
/// целиком у прокрутки и тапов. Сдвиг больше 8 pt до удержания — прокрутка
/// или свайп, не наш жест (веб `dlMove`).
final class DayGripPan: UIGestureRecognizer {
    var decide: ((TimeInterval) -> DayGripStart)?
    var onReset: (() -> Void)?
    private var touch: UITouch?
    private var start: CGPoint = .zero
    /// Вид под пальцем — от него ищется прокрутка ленты.
    var touchView: UIView? { touch?.view }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        // Второй палец жесту не нужен.
        if touch != nil { touches.forEach { ignore($0, for: event) }; return }
        guard touches.count == 1, let t = touches.first else { state = .failed; return }
        touch = t
        start = t.location(in: view)
        switch decide?(t.timestamp) ?? .none {
        case .none: state = .failed
        case .now: state = .began
        // Во всех режимах цикла: пока прокрутка ждёт нашего отказа, цикл может стоять в режиме слежения.
        case .hold, .slot: perform(#selector(arm), with: nil, afterDelay: 0.45, inModes: [.common])
        }
    }

    @objc private func arm() {
        if state == .possible { state = .began }
    }
    /// Удержание не дождались: для журнала замера.
    private(set) var failedHold = false

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let t = touch, touches.contains(t) else { return }
        switch state {
        case .possible:
            let p = t.location(in: view)
            if abs(p.x - start.x) > 8 || abs(p.y - start.y) > 8 { cancelArm(); failedHold = true; state = .failed }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let t = touch, touches.contains(t) else { return }
        cancelArm()
        if state == .possible { failedHold = true }
        state = state == .began || state == .changed ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let t = touch, touches.contains(t) else { return }
        cancelArm()
        state = state == .began || state == .changed ? .cancelled : .failed
    }

    private func cancelArm() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(arm), object: nil)
    }

    override func reset() {
        super.reset()
        cancelArm()
        onReset?()
        touch = nil
        failedHold = false
    }
}

/// Сторож экрана: любое касание «Съёмок» сообщает метку и точку в пространстве
/// веера и тут же отказывается — ничему не мешает. Нужен, чтобы касание мимо
/// ленты (шапка, полоса мудборда) тоже снимало выделение, как у веба
/// (`pointerdown` на документе).
struct TouchProbe: UIGestureRecognizerRepresentable {
    var down: (TimeInterval) -> Void

    func makeUIGestureRecognizer(context: Context) -> ProbeRecognizer {
        let r = ProbeRecognizer()
        r.cancelsTouchesInView = false
        r.delaysTouchesEnded = false
        r.down = down
        return r
    }

    func updateUIGestureRecognizer(_ recognizer: ProbeRecognizer, context: Context) {
        recognizer.down = down
    }

    final class ProbeRecognizer: UIGestureRecognizer {
        var down: ((TimeInterval) -> Void)?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            if let t = touches.first { down?(t.timestamp) }
            state = .failed
        }
    }
}
#endif
