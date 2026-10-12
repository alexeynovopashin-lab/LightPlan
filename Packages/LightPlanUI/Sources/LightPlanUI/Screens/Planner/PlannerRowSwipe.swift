import SwiftUI

/// Свайп влево по строке съёмки (29.3г; план § D.4 «Свайп влево | строка съёмки | удалить в корзину», слово
/// Алексея 07.10 «Добавить свайп влево»). У беты жеста нет (аудит K4: там удержание и веер) — поведение по
/// обычаю iOS: частичный протяг открывает кнопку «Удалить» и держит её, длинный протяг удаляет на отпускании.
/// Действие одно; «Перенести» Алексей не называл.
///
/// Здесь — числа и решение на отпускании, без вида и без UIKit: их держит тест.
enum RowSwipeRule {
    /// Ширина кнопки «Удалить», pt: слово 15 pt («Удалить» ≈ 60) и поля по 14.
    static let button: CGFloat = 88
    /// Отпустил дальше половины кнопки — кнопка остаётся открытой.
    static let openFraction: CGFloat = 0.5
    /// Длинный протяг: половина ширины строки (у жеста «назад» — треть экрана, `EdgeBackRule.commitFraction`;
    /// здесь больше: удаление дороже ошибки, и открытая кнопка должна оставлять запас до порога).
    static let fireFraction: CGFloat = 0.5
    /// Порог не ближе 40 pt за открытой кнопкой — на узкой строке частичный протяг не удаляет.
    static let fireBeyondButton: CGFloat = 40
    /// Бросок пальцем, pt/с: влево — открыть, вправо — закрыть (как `EdgeBackRule.backVelocity` по модулю).
    static let flick: CGFloat = 300
    /// Касание у левого края отдано жесту «назад» (28з): строка его не берёт.
    static let edgeZone: CGFloat = 20

    enum Phase: String, Equatable { case idle, revealing, open, fired }

    /// Где удаление на отпускании (pt влево), при ширине строки `width`.
    static func fireAt(width: CGFloat) -> CGFloat { max(width * fireFraction, button + fireBeyondButton) }
    static var openAt: CGFloat { button * openFraction }

    /// Сдвиг строки под пальцем: от покоя (`base` 0) или от открытой кнопки (`base` −88); вправо за покой и
    /// влево за всю ширину не едет.
    static func offset(base: CGFloat, dx: CGFloat, width: CGFloat) -> CGFloat {
        min(0, max(-max(width, button), base + dx))
    }

    /// Протяг перешёл порог удаления — кнопка во всю ширину, слово едет за краем строки.
    static func armed(offset: CGFloat, width: CGFloat) -> Bool { -offset >= fireAt(width: width) }

    /// Палец отпущен: удалить, оставить кнопку открытой или закрыть.
    static func release(offset: CGFloat, velocity: CGFloat, width: CGFloat) -> Phase {
        if armed(offset: offset, width: width) { return .fired }
        if velocity >= flick { return .idle }
        if velocity <= -flick, offset < 0 { return .open }
        return -offset >= openAt ? .open : .idle
    }

    /// Начинать ли жест: ведут вбок, а не вдоль списка; влево — всегда, вправо — только открытую строку.
    static func begins(dx: CGFloat, dy: CGFloat, isOpen: Bool, startX: CGFloat) -> Bool {
        guard startX > edgeZone, abs(dx) > abs(dy) else { return false }
        return dx < 0 || isOpen
    }
}

/// Состояние свайпа на всё приложение: открыта одна строка за раз.
@MainActor @Observable
final class RowSwipe {
    /// Строка с открытой кнопкой (ключ `<список>.<id>`).
    private(set) var open: String?
    /// Идущий жест: чья строка и её сдвиг.
    private(set) var live: Live?
    /// Строка удаляется: стоит, где её отпустили (кнопка во всю ширину или открытая), пока летит в корзину.
    private(set) var held: Live?

    struct Live: Equatable {
        let key: String
        var offset: CGFloat
        var armed: Bool
    }

    /// Жест идёт — свайп экрана не листает вид (как `DayGrip.armed`).
    @ObservationIgnored private(set) var active = false
    @ObservationIgnored private(set) var activeEnd: TimeInterval = -1
    /// Метка касания, которое видела строка: сторож экрана по ней знает, что касание было на строке.
    @ObservationIgnored var rowTouch: TimeInterval = -1
    /// До какого мгновения тап по строке не открывает карточку: касание закрыло чужую открытую кнопку.
    @ObservationIgnored private(set) var swallowTill: TimeInterval = 0
    /// Тик уже был в этом жесте.
    @ObservationIgnored private var ticked = false
    @ObservationIgnored private var base: CGFloat = 0
    /// Откуда считать часы (тест подставляет свои).
    @ObservationIgnored var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    /// Боковой увод пальца со строки не листает месяц и неделю — ни во время жеста, ни сразу после (конец
    /// свайпа экрана приходит позже конца жеста строки).
    var blocksSwipe: Bool { active || clock() - activeEnd < 0.4 }
    var swallows: Bool { clock() < swallowTill }

    func offset(_ key: String) -> CGFloat {
        if let live, live.key == key { return live.offset }
        if let held, held.key == key { return held.offset }
        return open == key ? -RowSwipeRule.button : 0
    }

    func isArmed(_ key: String) -> Bool {
        (live?.key == key && live?.armed == true) || (held?.key == key && held?.armed == true)
    }

    /// Удаление пошло: строка замирает в своём положении, открытой кнопки больше нет.
    func hold(_ key: String) {
        held = Live(key: key, offset: offset(key), armed: isArmed(key))
        open = nil
        live = nil
    }

    /// Строка ушла (или запись вернули): держать нечего.
    func unhold(_ key: String) { if held?.key == key { held = nil } }

    /// Касание строки. Открыта другая — закрываем, и этот тап карточку не открывает (как список iOS).
    func touchDown(_ key: String, stamp: TimeInterval) {
        rowTouch = stamp
        if let o = open, o != key {
            close("touch row=\(key)")
            swallowTill = clock() + 0.6
        }
    }

    /// Касание мимо строк (сторож экрана): открытая кнопка закрывается.
    func outsideTouch(stamp: TimeInterval) {
        guard rowTouch != stamp, open != nil else { return }
        close("outside")
    }

    /// Тап по строке: открытая кнопка этой строки или только что закрытая чужая — тап только закрывает.
    func takesTap(_ key: String) -> Bool {
        if open == key { close("tap row=\(key)"); return true }
        if swallows { RowSwipeLog.note("swallow tap row=\(key)"); return true }
        return false
    }

    func began(_ key: String) {
        if let o = open, o != key { close("other row=\(key)") }
        held = nil
        base = offset(key)
        active = true
        ticked = open == key
        live = Live(key: key, offset: base, armed: false)
        RowSwipeLog.note("began row=\(key) base=\(Int(base))")
    }

    /// Шаг пальца: `dx` от касания. Отдаёт `true`, когда пора тикнуть (кнопка раскрылась целиком впервые за жест).
    @discardableResult
    func moved(_ key: String, dx: CGFloat, width: CGFloat) -> Bool {
        guard live?.key == key else { return false }
        let off = RowSwipeRule.offset(base: base, dx: dx, width: width)
        let armed = RowSwipeRule.armed(offset: off, width: width)
        live = Live(key: key, offset: off, armed: armed)
        var tick = false
        if !ticked, -off >= RowSwipeRule.button { ticked = true; tick = true }
        RowSwipeLog.note("move row=\(key) dx=\(Int(dx)) off=\(Int(off)) state=\(armed ? "armed" : "revealing")"
                         + " open=\(Int(RowSwipeRule.openAt)) fire=\(Int(RowSwipeRule.fireAt(width: width)))\(tick ? " tick" : "")")
        return tick
    }

    /// Палец отпущен (или жест отняла система — тогда строка закрывается). Отдаёт решение и нужен ли тик.
    func ended(_ key: String, velocity: CGFloat, width: CGFloat, cancelled: Bool = false) -> (phase: RowSwipeRule.Phase, tick: Bool) {
        let off = live?.key == key ? live!.offset : offset(key)
        let phase = cancelled ? .idle : RowSwipeRule.release(offset: off, velocity: velocity, width: width)
        if phase == .fired { held = Live(key: key, offset: off, armed: true) }
        live = nil
        active = false
        activeEnd = clock()
        open = phase == .open ? key : nil
        let tick = phase == .open && !ticked
        ticked = false
        RowSwipeLog.note("\(cancelled ? "cancelled" : "ended") row=\(key) off=\(Int(off)) v=\(Int(velocity)) state=\(phase.rawValue)\(tick ? " tick" : "")")
        return (phase, tick)
    }

    func close(_ why: String) {
        guard open != nil || live != nil else { return }
        RowSwipeLog.note("close \(why) row=\(open ?? live?.key ?? "-") state=idle")
        open = nil
        live = nil
    }
}

/// Журнал свайпа строки (Debug, `-LPRowSwipeLog <файл>`; имя без «/» — файл в `Documents` приложения): касание,
/// каждый кадр жеста (`dx`, сдвиг, состояние idle / revealing / armed / open / fired, строка, пороги), закрытие.
enum RowSwipeLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPRowSwipeLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    #endif
    static func note(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let url, let data = (String(format: "%.3f ", ProcessInfo.processInfo.systemUptime) + line() + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}

// MARK: - Вид

extension View {
    /// Строка съёмки со свайпом влево: под ней справа терракотовая кнопка «Удалить». `key` — список и запись
    /// (`m.`, `w.`, `s.` + id), `corner` — скругление строки, `word` — «Удалить» из словаря (`swipe.del`).
    func rowSwipe(_ app: AppModel, key: String, id: String, corner: CGFloat, word: String) -> some View {
        modifier(RowSwipeRow(app: app, swipe: app.rowSwipe, key: key, id: id, corner: corner, word: word))
    }
}

private struct RowSwipeRow: ViewModifier {
    let app: AppModel
    let swipe: RowSwipe
    let key: String
    let id: String
    let corner: CGFloat
    let word: String
    @State private var width: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let off = swipe.offset(key), armed = swipe.isArmed(key), dragging = swipe.live?.key == key
        let pal = Palette(scheme)
        // Пружина без перелёта; при «Уменьшении движения» кнопка встаёт сразу. Под пальцем — без анимации.
        let settle: Animation? = reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9)
        ZStack(alignment: .trailing) {
            if off < 0 {
                Button { fire("button") } label: {
                    Text(word).font(webFont(15, 500)).foregroundStyle(.white).lineLimit(1).fixedSize()
                        .padding(.horizontal, 14)
                        .frame(width: max(0, -off), alignment: armed ? .leading : .trailing)
                        .frame(maxHeight: .infinity)
                        .background(pal.terra)
                        // Слово шире узкой кнопки в начале протяга — режем рамкой, сквозь строку оно не видно.
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: armed)
                .shotNode("swipe.del")
            }
            content.offset(x: off)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        // Сдвинутая строка не ловит касаний за своей рамкой: иначе палец у левого края (жест «назад») попадал
        // в уехавшую часть и срабатывал её тап (замер 29.3г).
        .contentShape(Rectangle())
        .animation(dragging ? nil : settle, value: off)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        #if os(iOS)
        .gesture(RowSwipeGesture(
            isOpen: { swipe.open == key },
            down: { swipe.touchDown(key, stamp: $0) },
            began: { swipe.began(key) },
            moved: { dx in if swipe.moved(key, dx: dx, width: width) { Haptics.play(.rowReveal) } },
            ended: { v, cancelled in
                let r = swipe.ended(key, velocity: v, width: width, cancelled: cancelled)
                if r.tick { Haptics.play(.rowReveal) }
                if r.phase == .fired { fire("full") }
            },
            refused: { if swipe.open == key { swipe.close("refused row=\(key)") } }))
        #endif
        .onDisappear {
            if swipe.open == key { swipe.close("gone row=\(key)") }
            swipe.unhold(key)
        }
        // Вся строка с кнопкой улетает в корзину (у строки внутри свой ключ — для веера и карточки).
        .binSubject(app, "swipe." + key)
    }

    /// Удаление тем же путём, что из веера и карточки (29.7): полёт, смятие, в глоток — корзина и «Вернуть».
    private func fire(_ how: String) {
        RowSwipeLog.note("fired \(how) row=\(key) state=fired")
        swipe.hold(key)
        let id = id, key = key, swipe = swipe
        app.flyToBin(["swipe." + key]) { [app] in app.trashSession(id: id) }
        // Строка уходит в глоток; если запись не стёрлась (её уже нет), строка возвращается в покой после полёта.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(BinTimeline.hideAtTotal + 0.2))
            swipe.unhold(key)
        }
    }
}

#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Распознаватель строки. Начинается, только если палец повели вбок (влево или вправо по открытой строке);
/// повели вдоль списка — отказ, палец у прокрутки. Прокрутка ждёт нашего отказа (как у ленты дня 29а), иначе
/// она забирает и боковой увод. Тап и удержание 0,45 с (веер) этот жест не трогает: он ждёт сдвига.
struct RowSwipeGesture: UIGestureRecognizerRepresentable {
    var isOpen: () -> Bool
    var down: (TimeInterval) -> Void
    var began: () -> Void
    var moved: (CGFloat) -> Void
    var ended: (CGFloat, Bool) -> Void
    /// Жест отказался (вели вдоль списка): открытая кнопка этой строки закрывается прокруткой.
    var refused: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator(gesture: self) }

    func makeUIGestureRecognizer(context: Context) -> RowSwipePan {
        let pan = RowSwipePan()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        let c = context.coordinator
        pan.onDown = { [weak c] stamp in c?.gesture.down(stamp) }
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: RowSwipePan, context: Context) {
        context.coordinator.gesture = self
    }

    func handleUIGestureRecognizerAction(_ r: RowSwipePan, context: Context) {
        let g = context.coordinator.gesture
        switch r.state {
        case .began: g.began(); g.moved(r.moved.x)
        case .changed: g.moved(r.moved.x)
        case .ended: g.ended(r.velocity(in: r.view).x, false)
        case .cancelled, .failed: g.ended(0, true)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var gesture: RowSwipeGesture
        init(gesture: RowSwipeGesture) { self.gesture = gesture }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? RowSwipePan else { return false }
            // `translation` в момент вопроса бывает нулевым (замер 29.3г: `refuse dx=0 dy=0`) — сдвиг считаем по касанию сами.
            let t = pan.moved
            let open = gesture.isOpen()
            let ok = RowSwipeRule.begins(dx: t.x, dy: t.y, isOpen: open, startX: pan.startX)
            if !ok {
                RowSwipeLog.note("refuse dx=\(Int(t.x)) dy=\(Int(t.y)) x0=\(Int(pan.startX))")
                gesture.refused()
            }
            return ok
        }

        /// Прокрутка списка ждёт, пока строка откажется. Жест «назад» от края (28з) висит на окне — не задет.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

/// Панорама с меткой касания: строка отмечается раньше сторожа экрана и закрывает чужую открытую кнопку.
final class RowSwipePan: UIPanGestureRecognizer {
    var onDown: ((TimeInterval) -> Void)?
    /// Где палец коснулся и где он сейчас, по окну: у левого края — жест «назад».
    private var start: CGPoint = .zero
    private var now: CGPoint = .zero
    var startX: CGFloat { start.x }
    /// Сдвиг пальца от касания.
    var moved: CGPoint { CGPoint(x: now.x - start.x, y: now.y - start.y) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let t = touches.first {
            start = t.location(in: nil)
            now = start
            onDown?(t.timestamp)
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let t = touches.first { now = t.location(in: nil) }
        super.touchesMoved(touches, with: event)
    }
}
#endif
