import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Перестановка кадров в папке мудборда (29.3в)

/// Драг кадра в сетке папки (веб `mbGridDrag`, L21725–21890; правила — `MbFrameDragRules`).
/// Удержание 0,42 с — кадр поднимается (`scale 1,06`, 0,22 с с перелётом, отдача `mbFrameLift`); отпустили, не
/// двигая, — лист кадра, как было до 29.3в. Повели — кадр едет за пальцем, соседи расступаются (0,22 с `ease`),
/// у края папка листается сама; отпустили — кадр ложится на место (0,3 с с перелётом), новый порядок пишется
/// сразу, если сменился (отдача `mbFrameDrop`). Только на голой сетке (`MbFrameDragRules.reorderable`).
///
/// Отход от беты: у веба посадка 0,3 с не видна — с тех пор как за пальцем едет копия, кадр в сетке стоит без
/// сдвига, и при отпускании копия исчезает, а кадр уже на месте (замер Playwright 13.10: прыжок за один кадр).
/// Здесь кадр едет сам и ложится по кривой беты, как она задумана (`transform .3s cubic-bezier(.2,1.3,.35,1)`).
@MainActor @Observable
final class MbFrameDrag {
    /// Поднятый кадр: его id, порядок `items[]` на подъёме, где палец взял плитку и где было касание.
    struct Lift: Equatable {
        let id: String
        let home: [String]
        /// Палец от левого верхнего угла плитки (веб `grabX`, `grabY`).
        let grab: CGSize
        let start: CGPoint
    }

    private(set) var lift: Lift?
    /// Порядок `items[]` сейчас (веб `order`): меняется, когда палец проходит над соседом.
    private(set) var order: [String] = []
    /// Палец в координатах сетки.
    private(set) var hand: CGPoint = .zero
    /// Палец ушёл от точки подъёма — это перенос, а не «подержал» (веб `dragged`).
    private(set) var moved = false
    /// Отпущен и ложится на место: новый жест не начинается.
    private(set) var settling = false

    /// Места плиток для порядка (сетка считает их сама: высоты кадров, плитки «+» и корзины).
    @ObservationIgnored var cells: ([String]) -> [MbFrameDragRules.Cell] = { _ in [] }
    /// Кадр под пальцем на касании — его поднимет удержание.
    @ObservationIgnored var armed: String?
    /// Точка касания в сетке: от неё считается, где палец взял плитку.
    @ObservationIgnored var downAt: CGPoint = .zero
    /// До какого мгновения тап по кадру ничего не открывает: подъём и отпускание — не тап (веб `consumed`).
    @ObservationIgnored var swallowTill: TimeInterval = 0
    @ObservationIgnored private var skip: String?
    /// «Уменьшение движения»: посадка без кривой — без ожидания (свой ответ у теста).
    @ObservationIgnored var still: () -> Bool = { PlanMotion.still }

    #if DEBUG && os(iOS)
    /// Прибор кадров 28з на время жеста (только с `-LPMbFrameLog`): пропущенные кадры и CPU главного потока.
    @ObservationIgnored private var meter: EdgeBackMeter?
    #endif

    nonisolated static var clock: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var swallows: Bool { Self.clock < swallowTill }
    var active: Bool { lift != nil }

    func meterStart() {
        #if DEBUG && os(iOS)
        guard MbFrameLog.on else { return }
        if meter == nil { meter = EdgeBackMeter { MbFrameLog.note($0) } }
        meter?.start()
        #endif
    }

    func meterStop(silently: Bool = false) {
        #if DEBUG && os(iOS)
        meter?.stop(silently: silently)
        #endif
    }

    /// Подъём (веб таймер 420 мс): отдача 16 мс, порядок и места снимаются сейчас.
    @discardableResult
    func begin(id: String, items: [String], at p: CGPoint) -> Bool {
        guard lift == nil, !settling, items.contains(id), let c = cells(items).first(where: { $0.id == id }) else { return false }
        lift = Lift(id: id, home: items, grab: CGSize(width: p.x - c.x, height: p.y - c.y), start: p)
        order = items
        hand = p
        moved = false
        skip = nil
        swallowTill = .infinity
        Haptics.play(.mbFrameLift)
        MbFrameLog.note("lift id=\(id) at=\(Self.f(p.x)),\(Self.f(p.y)) cell=\(Self.f(c.x)),\(Self.f(c.y)) \(Self.f(c.w))x\(Self.f(c.h))"
                        + " n=\(items.count)")
        return true
    }

    /// Палец в координатах сетки (веб `move` → `track`): кадр едет, сосед под пальцем уступает место.
    func move(to p: CGPoint) {
        guard let l = lift, !settling else { return }
        if !moved {
            guard Double(abs(p.x - l.start.x) + abs(p.y - l.start.y)) >= MbFrameDragRules.movedSlop else { return }
            moved = true
            MbFrameLog.note("moved")
        }
        hand = p
        let others = cells(order).filter { $0.id != l.id }
        let s = MbFrameDragRules.step(order, moving: l.id, over: MbFrameDragRules.hit(Double(p.x), Double(p.y), cells: others),
                                      skip: skip)
        skip = s.skip
        guard s.changed else { return }
        order = s.order
        MbFrameLog.note("zone over=\(s.skip ?? "-") at=\(order.firstIndex(of: l.id) ?? -1) order=\(order.joined(separator: ","))")
    }

    /// Что вышло из жеста при отпускании.
    enum Outcome: Equatable {
        /// Подержали, не двигая — лист кадра (веб `onMenu`).
        case menu(String)
        /// Повели и поставили на новое место.
        case reordered([String])
        /// Повели, но вернули на своё место.
        case same
        /// Повели, а запись отказала: подборку поменяли за время жеста. Кадр ложится на прежнее место, без отдачи.
        case refused
    }

    /// Отпустили (веб `release`): кадр ложится на место 0,3 с, порядок пишется сразу (`commit(порядок, порядок на
    /// подъёме)`), если сменился. Касание, отнятое системой, — то же отпускание (веб `pointercancel` → `release`).
    @discardableResult
    func drop(commit: ([String], [String]) -> Bool) -> Outcome? {
        guard let l = lift, !settling else { return nil }
        var out: Outcome = !moved ? .menu(l.id) : (order != l.home ? .reordered(order) : .same)
        if case .reordered(let o) = out, !commit(o, l.home) {
            out = .refused
            order = l.home   // кадр ложится туда, откуда взят: на экране то, что записано
        }
        settling = true
        #if DEBUG && os(iOS)
        meter?.beginSettle()
        #endif
        MbFrameLog.note("drop hand=\(Self.f(hand.x)),\(Self.f(hand.y)) to=\(order.firstIndex(of: l.id) ?? -1) \(Self.word(out))")
        if case .reordered = out { Haptics.play(.mbFrameDrop) }
        let wait = still() ? 0 : MbFrameMotion.landDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.finish() }
        return out
    }

    /// Касание отняла система, а кадр ещё не поднят — ничего не было.
    func cancelArm() {
        guard lift == nil else { return }
        armed = nil
        meterStop(silently: true)
    }

    private func finish() {
        guard lift != nil else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            lift = nil; order = []; moved = false; settling = false; skip = nil
        }
        armed = nil
        swallowTill = Self.clock + 0.35
        meterStop()
        MbFrameLog.note("landed")
    }

    // MARK: что рисует плитка

    /// Место плитки сейчас: поднятая — за пальцем (при посадке — своя клетка), остальные — своя клетка.
    func origin(_ id: String, cell: MbFrameDragRules.Cell) -> CGPoint {
        guard let l = lift, l.id == id, !settling else { return CGPoint(x: cell.x, y: cell.y) }
        guard moved else { return CGPoint(x: cell.x, y: cell.y) }
        return CGPoint(x: hand.x - l.grab.width, y: hand.y - l.grab.height)
    }

    func isLifted(_ id: String) -> Bool { lift?.id == id }

    static func f(_ v: CGFloat) -> String { String(format: "%.1f", Double(v)) }
    static func f(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func word(_ o: Outcome) -> String {
        switch o {
        case .menu: "menu"
        case .reordered: "reordered"
        case .same: "same"
        case .refused: "refused"
        }
    }
}

/// Кривые беты (CSS); при «Уменьшении движения» — сразу (`PlanMotion.pick`).
enum MbFrameMotion {
    /// Подъём: `transform .22s cubic-bezier(.2,1.4,.4,1)` (веб L21817).
    static let lift = Animation.timingCurve(0.2, 1.4, 0.4, 1, duration: 0.22)
    /// Соседи расступаются: `transform .22s ease` (L21914); CSS `ease` = `cubic-bezier(.25,.1,.25,1)`.
    static let shift = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.22)
    /// Посадка: `transform .3s cubic-bezier(.2,1.3,.35,1)` (L21862).
    static let landDuration: Double = 0.3
    static let land = Animation.timingCurve(0.2, 1.3, 0.35, 1, duration: landDuration)
}

/// Журнал жеста для замеров на симуляторе (Debug, `-LPMbFrameLog <файл>`; имя без «/» — файл в `Documents`
/// приложения): касание и решение, подъём, сдвиг пальца, смена места, автопрокрутка, отпускание и исход;
/// по кадрам — масштаб поднятого (`look`) и сдвиги плиток (`pos`).
enum MbFrameLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPMbFrameLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    nonisolated(unsafe) private static var handle: FileHandle?
    #endif
    static var on: Bool {
        #if DEBUG
        url != nil
        #else
        false
        #endif
    }
    static func note(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let url, let data = (String(format: "%.3f ", MbFrameDrag.clock) + line() + "\n").data(using: .utf8) else { return }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
        }
        handle?.write(data)
        #endif
    }
}

// MARK: - Плитка в сетке

/// Плитка на своём месте (абсолютная раскладка масонри): сдвиг к клетке и подъём. Соседи едут 0,22 с, пока
/// идёт перенос; вне жеста места меняются без кривой (первая раскладка, смена ширины).
struct MbFrameSlot: ViewModifier {
    let drag: MbFrameDrag
    let id: String
    let cell: MbFrameDragRules.Cell
    let pal: Palette

    func body(content: Content) -> some View {
        let lifted = drag.isLifted(id)
        let o = drag.origin(id, cell: cell)
        let curve: Animation? = lifted ? (drag.settling ? MbFrameMotion.land : nil) : (drag.active ? MbFrameMotion.shift : nil)
        let up = lifted && !drag.settling
        content
            .modifier(MbFrameLook(k: up ? 1 : 0, pal: pal, tag: id))
            .animation(PlanMotion.pick(up ? MbFrameMotion.lift : MbFrameMotion.land), value: up)
            .modifier(MbFramePos(x: o.x, y: o.y, tag: id, live: drag.active))
            .animation(curve.flatMap { PlanMotion.pick($0) }, value: o)
            .zIndex(lifted ? 10 : 0)
    }
}

/// Подъём кадра (веб `scale(1.06)` и `box-shadow 0 10px 24px var(--glass-cast)`): `k` от 0 до 1, кривая с перелётом.
private struct MbFrameLook: ViewModifier, @preconcurrency Animatable {
    var k: Double
    let pal: Palette
    let tag: String
    var animatableData: Double {
        get { k }
        set { k = newValue }
    }

    func body(content: Content) -> some View {
        if MbFrameLog.on, k > 0.0005, k < 0.9995 || k > 1.0005 {
            MbFrameLog.note("look id=\(tag) k=\(String(format: "%.3f", k)) scale=\(String(format: "%.4f", 1 + (MbFrameDragRules.liftScale - 1) * k))")
        }
        let s = max(0, min(1, k))
        return content
            .background {
                if s > 0 {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pal.sheet)
                        .shadow(color: pal.glassCast.opacity(s), radius: 12 * s, y: 10 * s)
                }
            }
            .scaleEffect(1 + (MbFrameDragRules.liftScale - 1) * k)
    }
}

private struct MbFramePos: ViewModifier, @preconcurrency Animatable {
    var x: CGFloat
    var y: CGFloat
    let tag: String
    let live: Bool
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }

    func body(content: Content) -> some View {
        if live, MbFrameLog.on { MbFrameLog.note("pos id=\(tag) x=\(MbFrameDrag.f(x)) y=\(MbFrameDrag.f(y))") }
        // Отступ, а не `offset`: место плитки — раскладка, и её рамка (просмотрщик летит из плитки) верна.
        return content.padding(.leading, x).padding(.top, y)
    }
}

extension View {
    /// Сетка папки, которую можно переставлять: один распознаватель на сетку (образец 29.3б).
    /// `items` — `items[]` подборки, `commit` — запись нового порядка, `menu` — лист кадра по удержанию без сдвига.
    func mbFrameGrid(_ drag: MbFrameDrag, on: Bool, items: [String], commit: @escaping ([String], [String]) -> Bool,
                     menu: @escaping (String) -> Void) -> some View {
        modifier(MbFrameGridModifier(drag: drag, on: on, items: items, commit: commit, menu: menu))
    }
}

struct MbFrameGridModifier: ViewModifier {
    let drag: MbFrameDrag
    let on: Bool
    let items: [String]
    let commit: ([String], [String]) -> Bool
    let menu: (String) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        if on { content.gesture(gesture) } else { content }
        #else
        content
        #endif
    }

    #if os(iOS)
    private var gesture: MbFrameGesture {
        MbFrameGesture(
            down: { p in down(p) },
            began: {
                guard let id = drag.armed else { return false }
                return drag.begin(id: id, items: items, at: drag.downAt)
            },
            moved: { p in drag.move(to: p) },
            ended: { if case .menu(let id)? = drag.drop(commit: commit) { menu(id) } },
            reset: { drag.cancelArm() },
            autoScroll: { drag.active && !drag.settling })
    }

    /// Касание сетки (веб `pointerdown` на кадре): мимо кадров («+», корзина, зазор) — не наш, иначе ждём удержания.
    private func down(_ p: CGPoint) -> Bool {
        guard !drag.active else { MbFrameLog.note("down x=\(Int(p.x)) y=\(Int(p.y)) busy"); return false }
        let cells = drag.cells(items)
        guard let id = MbFrameDragRules.hit(Double(p.x), Double(p.y), cells: cells), items.contains(id) else {
            MbFrameLog.note("down x=\(Int(p.x)) y=\(Int(p.y)) miss"); return false
        }
        drag.armed = id
        drag.downAt = p
        drag.meterStart()
        MbFrameLog.note("down id=\(id) x=\(Int(p.x)) y=\(Int(p.y)) hold")
        return true
    }
    #endif
}

#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Жест сетки. `down` — точка касания в сетке и решение; `began` — подъём (`false` — подъёма не было); `moved` —
/// палец в координатах сетки (с поправкой на автопрокрутку); `ended` — отпустили или касание отняла система.
struct MbFrameGesture: UIGestureRecognizerRepresentable {
    var down: (CGPoint) -> Bool
    var began: () -> Bool
    var moved: (CGPoint) -> Void
    var ended: () -> Void
    var reset: () -> Void
    var autoScroll: () -> Bool

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter, gesture: self)
    }

    func makeUIGestureRecognizer(context: Context) -> MbFramePan {
        let pan = MbFramePan()
        pan.delegate = context.coordinator
        let coordinator = context.coordinator
        pan.decide = { [weak coordinator, unowned pan] in
            guard let coordinator else { return false }
            let p = coordinator.converter.localLocation
            pan.downLocal = p
            return coordinator.gesture.down(p)
        }
        pan.onReset = { [weak coordinator] in coordinator?.gesture.reset() }
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: MbFramePan, context: Context) {
        context.coordinator.converter = context.converter
        context.coordinator.gesture = self
    }

    func handleUIGestureRecognizerAction(_ recognizer: MbFramePan, context: Context) {
        let c = context.coordinator
        switch recognizer.state {
        case .began:
            c.find(recognizer)
            guard c.gesture.began() else {
                MbFrameLog.note("began refused")
                recognizer.state = .cancelled
                return
            }
            c.lifted = true
            c.startAuto(recognizer)
        case .changed:
            guard c.lifted else { return }
            c.track(recognizer)
        case .ended, .cancelled, .failed:
            c.stopAuto()
            if c.lifted {
                MbFrameLog.note("\(recognizer.state == .ended ? "ended" : "cancelled") scroll=\(Int(c.scroll?.contentOffset.y ?? 0))"
                                + " auto=\(Int((c.scroll?.contentOffset.y ?? 0) - c.scrollAtLift))")
                c.gesture.ended()
            }
            c.lifted = false
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var converter: CoordinateSpaceConverter
        var gesture: MbFrameGesture
        var lifted = false
        private(set) weak var scroll: UIScrollView?
        /// Точка касания в пространстве прокрутки и в сетке: палец в сетке = касание + ход в прокрутке.
        private var start: CGPoint = .zero
        private var startLocal: CGPoint = .zero
        var scrollAtLift: CGFloat = 0
        private weak var pan: MbFramePan?
        private var link: CADisplayLink?
        private var lastTick: CFTimeInterval = 0
        /// Край включается, лишь когда палец из полосы вышел (веб `edgeOk`).
        private var edgeOk = false

        init(converter: CoordinateSpaceConverter, gesture: MbFrameGesture) {
            self.converter = converter
            self.gesture = gesture
        }

        /// Прокрутку ищем от вида под пальцем (распознаватель SwiftUI висит выше неё) и снимаем точку касания.
        func find(_ r: MbFramePan) {
            var v = r.touchView
            while let x = v, !(x is UIScrollView) { v = x.superview }
            scroll = v as? UIScrollView
            let space: UIView? = scroll ?? r.view
            start = space?.convert(r.downInWindow, from: nil) ?? r.downInWindow
            startLocal = r.downLocal
            scrollAtLift = scroll?.contentOffset.y ?? 0
            MbFrameLog.note("scroll \(scroll.map { "found h=\(Int($0.bounds.height)) y=\(Int($0.contentOffset.y))" } ?? "missing")")
        }

        func track(_ r: MbFramePan) {
            let p = r.location(in: scroll ?? r.view)
            gesture.moved(CGPoint(x: startLocal.x + p.x - start.x, y: startLocal.y + p.y - start.y))
        }

        /// Прокрутка ждёт, пока жест откажется: удержание не срывается в прокрутку, а палец, ушедший на 8 pt до
        /// подъёма, отдаётся ей. Жест «назад» от края висит на окне — его это не касается.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }

        // MARK: автопрокрутка (веб `autoScroll`: полоса 56, 12 pt за кадр)

        func startAuto(_ r: MbFramePan) {
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

        @objc private func tick(_ l: CADisplayLink) {
            guard let sv = scroll, let r = pan, gesture.autoScroll() else { return }
            let dt = lastTick == 0 ? MbFrameDragRules.edgeTick : min(0.05, l.timestamp - lastTick)
            lastTick = l.timestamp
            let inset = sv.adjustedContentInset
            let y = r.location(in: sv).y - sv.contentOffset.y
            let top = Double(y - inset.top), bot = Double(sv.bounds.height - inset.bottom - y)
            if !edgeOk { edgeOk = MbFrameDragRules.edgeArms(top: top, bottom: bot); return }
            let v = MbFrameDragRules.edgeSpeed(top: top, bottom: bot, armed: true)
            guard v != 0 else { return }
            let lo = -inset.top, hi = max(lo, sv.contentSize.height + inset.bottom - sv.bounds.height)
            let was = sv.contentOffset.y
            let to = min(max(was + CGFloat(v * dt), lo), hi)
            guard to != was else { return }
            sv.contentOffset.y = to
            MbFrameLog.note("auto v=\(MbFrameDrag.f(v)) y=\(Int(to))")
            track(r)
        }
    }
}

/// Распознаватель сетки. Свой, а не `UILongPressGestureRecognizer`: на касании спрашивает сетку, что под пальцем,
/// и берёт палец через 0,42 с или отказывается — тогда палец целиком у прокрутки и тапов. Сдвиг больше 8 pt до
/// подъёма — прокрутка (веб L21835).
final class MbFramePan: UIGestureRecognizer {
    var decide: (() -> Bool)?
    var onReset: (() -> Void)?
    private var touch: UITouch?
    private(set) var downInWindow: CGPoint = .zero
    /// Точка касания в сетке — её даёт `decide` через конвертер; хранится для хода пальца.
    var downLocal: CGPoint = .zero
    var touchView: UIView? { touch?.view }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        // Ведёт только свой палец (веб `pid`): второй жесту не нужен.
        if touch != nil { touches.forEach { ignore($0, for: event) }; return }
        guard touches.count == 1, let t = touches.first else { state = .failed; return }
        touch = t
        downInWindow = t.location(in: nil)
        guard decide?() == true else { state = .failed; return }
        perform(#selector(arm), with: nil, afterDelay: MbFrameDragRules.hold, inModes: [.common])
    }

    @objc private func arm() {
        if state == .possible { state = .began }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let t = touch, touches.contains(t) else { return }
        switch state {
        case .possible:
            let p = t.location(in: nil)
            if Double(abs(p.x - downInWindow.x) + abs(p.y - downInWindow.y)) > MbFrameDragRules.slop { cancelArm(); state = .failed }
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
    }
}
#endif
