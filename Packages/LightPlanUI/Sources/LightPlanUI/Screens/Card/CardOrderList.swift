import SwiftUI
import LightPlanCore
import LightPlanDomain
import QuartzCore

// MARK: - Перестановка блоков («ползунки», `#cardOrder`, итерация 26, шаг 5а)

/// Куда встанет строка при перетаскивании (веб: шаг = высота строки + зазор,
/// место = старт + `round(dy / 64)`, зажато краями).
enum CardOrderDrag {
    /// Высота строки 56 и зазор 8.
    static let step: CGFloat = 64
    /// Порог, с которого жест считается перетаскиванием.
    static let threshold: CGFloat = 4

    static func slot(start: Int, dy: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        // `Math.round` веба: половина уходит вверх, и −0,5 даёт 0, а не −1 (ревью GPT).
        return min(max(start + Int(((dy / step) + 0.5).rounded(.down)), 0), count - 1)
    }

    /// Порядок строк, каким он станет, если блок отпустить на `slot`. Строки на экране
    /// порядок не меняют (едут сдвигом, `CardRowDrag.place`) — это проверка, что сдвиг
    /// и перестановка сходятся.
    static func preview(_ rows: [CardBlock], moving b: CardBlock, to slot: Int) -> [CardBlock] {
        guard let i = rows.firstIndex(of: b), rows.indices.contains(slot), i != slot else { return rows }
        var out = rows
        out.remove(at: i)
        out.insert(b, at: slot)
        return out
    }
}

/// Строка в руке (27а.3): откуда взята, где встанет, на сколько ушёл палец. Строки
/// списка порядка не меняют, пока блок в руке: каждая стоит на своём месте плюс
/// сдвиг (`offset(of:)`), как у точек маршрута на Карте — поэтому соседи
/// расступаются мгновенно, а под рукой остаётся слот.
struct CardRowDrag: Equatable {
    let block: CardBlock
    let from: Int
    let count: Int
    /// Палец в момент касания (координаты экрана) и прокрутка листа в этот момент: сдвиг
    /// строки — путь пальца плюс то, на сколько уехал лист (автопрокрутка у краёв).
    let startY: CGFloat
    let startScroll: CGFloat
    private(set) var dy: CGFloat = 0
    private(set) var to: Int
    private(set) var fingerY: CGFloat

    init(block: CardBlock, from: Int, count: Int, startY: CGFloat = 0, startScroll: CGFloat = 0) {
        self.block = block; self.from = from; self.count = count
        self.startY = startY; self.startScroll = startScroll
        fingerY = startY; to = from
    }

    /// Палец на `y` экрана, лист прокручен на `scroll`.
    mutating func follow(finger y: CGFloat, scroll: CGFloat) {
        fingerY = y
        follow((y - startY) + (scroll - startScroll))
    }

    /// Палец ушёл на `raw` от места касания. Строка не выходит за края списка: выше первой
    /// и ниже последней ей встать некуда.
    mutating func follow(_ raw: CGFloat) {
        let step = CardOrderDrag.step
        dy = min(max(raw, -CGFloat(from) * step), CGFloat(count - 1 - from) * step)
        to = CardOrderDrag.slot(start: from, dy: dy, count: count)
    }

    /// Место строки `i`, когда блок `from` встал на `to`: поднятая — на слоте, остальные сдвинуты им.
    func place(_ i: Int) -> Int {
        if i == from { return to }
        let p = i > from ? i - 1 : i
        return p >= to ? p + 1 : p
    }

    /// Сдвиг строки `i` от её места в списке: поднятая идёт за пальцем, соседи — на шаг.
    func offset(of i: Int) -> CGFloat {
        i == from ? dy : CGFloat(place(i) - i) * CardOrderDrag.step
    }
}

/// Что записать, когда блок отпустили: он `block` встал на `to`.
struct CardMove: Equatable {
    let block: CardBlock
    let to: Int
}

/// Рука: ведёт одну строку или пуста. Отпускание и прерванный жест разведены: отпущенная
/// строка даёт ход, прерванная — ничего, порядок остаётся, как был до подъёма. Любой из двух
/// концов очищает руку, второй за ним ничего не делает (конец жеста и сброс «палец держит»
/// приходят оба, замер 27а.3: сперва конец, потом сброс).
struct CardHand: Equatable {
    private(set) var drag: CardRowDrag?

    var isLifted: Bool { drag != nil }

    /// Поднять строку `block` с места `from` из `count`; уже занятая рука не берёт вторую.
    @discardableResult
    mutating func lift(_ block: CardBlock, from: Int, count: Int, startY: CGFloat, startScroll: CGFloat) -> Bool {
        guard drag == nil else { return false }
        drag = CardRowDrag(block: block, from: from, count: count, startY: startY, startScroll: startScroll)
        return true
    }

    /// Палец или лист сдвинулись.
    mutating func follow(finger y: CGFloat, scroll: CGFloat) {
        drag?.follow(finger: y, scroll: scroll)
    }

    /// Отпустили на `y`: ход, который надо записать (даже «на то же место»), и пустая рука.
    mutating func release(finger y: CGFloat, scroll: CGFloat) -> CardMove? {
        guard var d = drag else { return nil }
        d.follow(finger: y, scroll: scroll)
        drag = nil
        return CardMove(block: d.block, to: d.to)
    }

    /// Жест прервала система: рука пуста, ничего не пишется.
    mutating func interrupt() {
        drag = nil
    }
}

/// Блоки листа и их строки перестановки (27а.2). Каждый блок живёт под
/// обёрткой `CardSqueezeLayout`: в обычном виде это сам блок, в «ползунках» —
/// строка в 56 pt, между ними высота идёт по кривой веба. Ветка листа не
/// подменяется: блок остаётся в дереве, поэтому его таймер, фолды и состояние
/// живут через вход и выход. Строки есть у каждого блока с данными, у
/// выключенного — тоже (чтобы было чем вернуть), внизу «По умолчанию» и «Готово».
struct CardOrderList<Content: View>: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette
    @ViewBuilder let content: (CardBlock) -> Content

    @Environment(\.accessibilityReduceMotion) private var still
    /// Блок в руке; рука пуста — никто не тянет.
    @State private var hand = CardHand()
    private var drag: CardRowDrag? { hand.drag }
    /// Палец держит ручку. Систему прервала жест (звонок, шторка, уход в фон) —
    /// `onEnded` не приходит, а это значение сбрасывается само: тогда строка
    /// возвращается на прежнее место (известный залип, справка 27а.1, §3).
    @GestureState private var holding = false
    @State private var lifts = 0
    @State private var autoscroll: Task<Void, Never>?
    @Environment(\.cardScroll) private var scroll

    var body: some View {
        let tuning = app.cardTuning
        let rows = app.cardOrderRows(s, phase: phase)
        VStack(spacing: 0) {
            // Первая строка встаёт вплотную к шапке, как у веба: пара мерила +10.
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element) { i, b in
                    slot(b, at: i, tuning: tuning, rows: rows)
                }
            }
            // Слот под строкой в руке: пустое место, куда она встанет (маршрут на Карте:
            // `hair3`, радиус 6). Лежит на сетке строк, строки едут над ним.
            .background(alignment: .top) {
                if let d = drag {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pal.hair3)
                        .frame(height: CardTuneSqueeze.rowHeight)
                        .offset(y: CGFloat(d.to) * CardOrderDrag.step)
                }
            }
            // Узел списка — только в «ползунках»: в обычном виде набор узлов карточки тот же, что до 27а.2.
            .background { if tuning { Color.clear.shotNode("card.order.list") } }
            // Подвал веб показывает и прячет сразу, без перехода.
            if tuning { footer.transition(.identity) }
        }
        .haptic(.cardBlockLift, trigger: lifts)
        // Снимок «блок в руке»: без пальца рука встаёт сразу с нужным сдвигом (`-LPShotDrag`).
        .onChange(of: tuning, initial: true) { _, on in
            if on, !hand.isLifted, let t = app.cardShotDrag, let i = rows.firstIndex(of: t.block),
               hand.lift(t.block, from: i, count: rows.count, startY: 0, startScroll: 0) {
                hand.follow(finger: t.dy, scroll: 0)
            }
        }
        .onChange(of: holding) { _, on in
            CardDragProbe.log("holding \(on) drag=\(drag.map { "\($0.block.rawValue) \($0.from)→\($0.to)" } ?? "nil")")
            if !on { cancel() }
        }
        .onChange(of: tuning) { _, on in if !on { cancel() } }
    }

    /// Обёртка блока: начинка гаснет сразу (`visibility: hidden`), шапка-строка
    /// проявляется за 0,22 с, а выходит без затухания; фон и поля строки — в первом кадре.
    private func slot(_ b: CardBlock, at i: Int, tuning: Bool, rows: [CardBlock]) -> some View {
        let off = app.isCardBlockOff(b, for: s)
        let moving = app.cardTuneMoving
        let lifted = drag?.block == b
        return CardSqueezeLayout(t: tuning ? 1 : 0, gap: i == 0 ? 0 : CardTuneSqueeze.gap) {
            VStack(spacing: 0) { if !off { content(b) } }
                .environment(\.shotSilent, tuning)
                .opacity(tuning ? 0 : 1)
                .allowsHitTesting(!tuning)
                .accessibilityHidden(tuning)
                .animation(nil, value: tuning)
            ZStack {
                if tuning { row(b, rows: rows).transition(CardTuneSqueeze.capTransition(still: still)) }
            }
        }
        #if DEBUG && os(iOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { CardTuneProbe.note(b.rawValue, height: $0) }
        #endif
        // Обрезка по краю — пока высота едет; в покое границы открыты (тень поднятой строки).
        .clipShape(Rectangle().inset(by: moving ? 0 : -40))
        // Сдвиг — снаружи обрезки: она едет вместе со строкой. Соседи встают мгновенно (без `.animation`).
        .offset(y: drag?.offset(of: i) ?? 0)
        .zIndex(lifted ? 1 : 0)
    }

    // MARK: Строка (`.ord-cap`)

    private func row(_ b: CardBlock, rows: [CardBlock]) -> some View {
        let off = app.isCardBlockOff(b, for: s)
        let held = drag?.block == b
        return HStack(spacing: 12) {
            HStack(spacing: 12) {
                Icon(b.iconName, size: 17, line: 1.6).foregroundStyle(pal.brass)
                    .frame(width: 32, height: 32)
                    .background(pal.badgeBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(app.lexicon.t("cdBlock.\(b.rawValue)")).font(webFont(15.5)).foregroundStyle(pal.ink)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .opacity(off ? 0.4 : 1)
            // Тумблер сжат в 0,784 раза, как у веба (40×24 от 51×31); у iOS 26 системный
            // 63×28, на экране выходит 49×22 (замер симулятора, 29.09).
            Toggle("", isOn: Binding(get: { !off }, set: { app.setCardBlock(b, shown: $0, for: s) }))
                .labelsHidden().tint(pal.brass)
                .scaleEffect(0.784)
                .frame(width: 49, height: 22)
                .shotNode("card.order.toggle.\(b.rawValue)", text: off ? "off" : "on")
            handle(b, rows: rows)
        }
        .padding(.leading, 14)
        .frame(height: 56)
        .background(held ? pal.press : pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: held ? .black.opacity(0.45) : .clear, radius: held ? 12 : 0, y: held ? 8 : 0)
        .shotNode("card.order.row.\(b.rawValue)")
    }

    /// Ручка 56×56, две линии 20×20: тянуть можно только за неё, иначе жест
    /// спорит с прокруткой листа.
    private func handle(_ b: CardBlock, rows: [CardBlock]) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 4, y: 9)); p.addLine(to: CGPoint(x: 20, y: 9))
            p.move(to: CGPoint(x: 4, y: 15)); p.addLine(to: CGPoint(x: 20, y: 15))
        }
        .stroke(pal.ink7, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        .frame(width: 24, height: 24)
        .frame(width: 56, height: 56)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: CardOrderDrag.threshold, coordinateSpace: .global)
                .updating($holding) { _, on, _ in on = true }
                .onChanged { g in follow(b, rows: rows, g) }
                .onEnded { g in drop(finger: g.location.y) }
        )
        .shotNode("card.order.handle.\(b.rawValue)")
    }

    // MARK: Жест

    /// Палец ведёт блок: первый сдвиг поднимает строку (отдача), дальше она идёт за пальцем.
    private func follow(_ b: CardBlock, rows: [CardBlock], _ g: DragGesture.Value) {
        let at = scroll?.offset ?? 0
        if !hand.isLifted {
            guard let i = rows.firstIndex(of: b),
                  hand.lift(b, from: i, count: rows.count, startY: g.startLocation.y, startScroll: at) else { return }
            lifts += 1   // 29.5/29.6 заменят единым слоем отдачи
            startAutoscroll()
            CardDragProbe.log("lift \(b.rawValue) from=\(i) count=\(rows.count) scroll=\(Int(at))")
        }
        guard drag?.block == b else { return }
        hand.follow(finger: g.location.y, scroll: at)
        CardDragProbe.log("move y=\(Int(g.location.y)) row=\(Int(drag?.dy ?? 0)) to=\(drag?.to ?? -1) scroll=\(Int(at))")
    }

    /// Отпустили: строка падает на слот без доводки, порядок пишется один раз.
    private func drop(finger: CGFloat) {
        let rowDy = drag?.dy ?? 0
        guard let move = hand.release(finger: finger, scroll: scroll?.offset ?? 0) else { return }
        stopAutoscroll()
        CardDragProbe.log("drop \(move.block.rawValue) →\(move.to) row=\(Int(rowDy)) scroll=\(Int(scroll?.offset ?? 0))")
        app.moveCardBlock(move.block, to: move.to, for: s)
    }

    private func stopAutoscroll() {
        autoscroll?.cancel()
        autoscroll = nil
    }

    // MARK: Автопрокрутка

    /// Пока строка в руке, раз в кадр: палец у верхнего или нижнего края окна листа — лист едет,
    /// и строка идёт за пальцем по листу (палец при этом может стоять).
    private func startAutoscroll() {
        guard scroll != nil else { return }
        autoscroll?.cancel()
        autoscroll = Task { @MainActor in
            var last = CACurrentMediaTime()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(CardAutoScroll.tick))
                let now = CACurrentMediaTime()
                scrollStep(dt: now - last)
                last = now
            }
        }
    }

    private func scrollStep(dt: Double) {
        guard let bridge = scroll, let d = drag else { return }
        let v = CardAutoScroll.velocity(y: d.fingerY, top: bridge.viewport.minY, bottom: bridge.viewport.maxY)
        guard v != 0 else { return }
        let y = CardAutoScroll.next(offset: bridge.offset, velocity: v, dt: dt, max: bridge.maxOffset)
        guard y != bridge.offset else { return }
        bridge.offset = y
        bridge.scrollTo(y)
        hand.follow(finger: d.fingerY, scroll: y)
        CardDragProbe.log("scroll v=\(Int(v)) offset=\(Int(y)) row=\(Int(drag?.dy ?? 0)) to=\(drag?.to ?? -1)")
    }

    /// Жест прервала система: порядок остаётся, как был до подъёма. Второй вызов после
    /// `drop` ничего не делает — `drag` уже пуст.
    private func cancel() {
        if let d = drag { CardDragProbe.log("cancel \(d.block.rawValue) \(d.from)→\(d.to)") }
        hand.interrupt()
        stopAutoscroll()
    }

    // MARK: Подвал (`.ord-foot`)

    private var footer: some View {
        HStack(spacing: 10) {
            footButton(app.lexicon.t("card.orderReset"), color: pal.ink3, weight: 400, node: "card.order.reset") {
                app.resetCardOrder(for: s)
            }
            footButton(app.lexicon.t("card.orderDone"), color: pal.brassDeep, weight: 650, node: "card.order.done") {
                app.toggleCardTuning(still: still)
            }
        }
        .padding(.top, 18)
    }

    private func footButton(_ title: String, color: Color, weight: Int, node: String,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(webFont(15, weight)).foregroundStyle(color)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressFade())
        .shotNode(node)
    }
}
