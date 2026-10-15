import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Режим сортировки и перенос подборок (29.3б)

/// Режим сортировки мудборда (веб `mbSorting`, `mbStartDrag` … `mbDrop`, L21382–21710; справка 28, п. 2.9).
/// Долгий тап 0,42 с по плитке, у которой есть перестановка (жанры на полосе и в галерее, папки
/// полки), включает режим и сразу поднимает плитку. В режиме плитки качаются, у каждой минус,
/// тап по плитке зовёт её лист (полка с несколькими папками — открывается), сдвиг ≥ 8 pt
/// поднимает плитку без нового удержания. Выход — тап мимо плиток, Escape, смена вкладки.
///
/// Перенос — как у демки Алексея (31.08.2026): клетки ряда снимаются один раз, при подъёме;
/// место — клетка под центром поднятой; соседи едут сдвигом от своих клеток, ряд не
/// перестраивается до записи; запись — через 0,32 с после отпускания, если порядок сменился.
/// Слияния перетаскиванием нет (веб убрал 31.08.2026: «объединение убираем совсем»).
@MainActor @Observable
final class MbSort {
    /// Режим включён (веб `body.mb-sorting`).
    private(set) var on = false
    /// Вход в режим: от него фаза покачивания — у веба анимация начинается у всех плиток с класса на `body`.
    @ObservationIgnored private(set) var since = Date.distantPast
    /// Поднятая плитка (веб `mbDrag`): ряд, ключ, порядок и клетки на подъёме.
    private(set) var lift: Lift?
    /// Порядок ряда сейчас (веб `d.order`): меняется, когда поднятая переходит в другую клетку.
    private(set) var order: [String] = []
    /// Ход поднятой от её клетки за пальцем, pt (веб `translate(dx, dy)`).
    private(set) var hand: CGSize = .zero
    /// Отпущена и доезжает (веб `mbSettling`): новый жест не начинается.
    private(set) var settling = false

    struct Lift: Equatable {
        let row: String
        let me: String
        let home: [String]
        let cells: [MbSortRules.Cell]
        let from: Int
    }

    /// Размер ряда на экране: ширина сетки и высота плитки (клетки — решётка 3 × N, `MbSortRules.cells`).
    struct RowSize { var width: CGFloat = 0; var tileH: CGFloat = 0 }
    @ObservationIgnored var rows: [String: RowSize] = [:]
    /// Плитки на экране в координатах окна, по слоям (`strip.…`, `gallery.…`, `shelf.…`): тап мимо них выводит из режима.
    /// Без наблюдения: рамки меняются каждый кадр прокрутки.
    @ObservationIgnored var tiles: [String: CGRect] = [:]
    /// До какого мгновения тап по плитке ничего не открывает: подъём и отпускание — не тап (веб `consumed`).
    @ObservationIgnored var swallowTill: TimeInterval = 0
    /// Ключ под пальцем на касании — его поднимет удержание или сдвиг.
    @ObservationIgnored var armed: String?
    @ObservationIgnored private var zone = 0
    @ObservationIgnored private var commit: (([String]) -> Void)?
    /// Порядок ключей каждого ряда на экране сейчас: сетка сообщает его при каждой смене (`track`). К записи
    /// сверяется с порядком на подъёме — подборки могли поменяться за время жеста (ревью GPT к 29.3б).
    @ObservationIgnored private(set) var live: [String: [String]] = [:]
    /// Отложенный вызов записи. Тест подставляет свои часы: окна в миллисекундах за очередью главного актора
    /// в полном наборе не держатся (замер 13.10).
    @ObservationIgnored var after: (Double, @escaping @MainActor () -> Void) -> Void = { d, f in
        DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated { f() } }
    }

    #if DEBUG && os(iOS)
    /// Прибор кадров 28з на время жеста (только с `-LPMbSortLog`): пропущенные кадры и CPU главного потока.
    @ObservationIgnored private var meter: EdgeBackMeter?
    #endif

    /// Замер кадров от касания (вход в режим и подъём — в его первой части) до конца посадки.
    func meterStart() {
        #if DEBUG && os(iOS)
        guard MbSortLog.on else { return }
        if meter == nil { meter = EdgeBackMeter { MbSortLog.note($0) } }
        meter?.start()
        #endif
    }

    func meterStop(silently: Bool = false) {
        #if DEBUG && os(iOS)
        meter?.stop(silently: silently)
        #endif
    }

    nonisolated static var clock: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var swallows: Bool { Self.clock < swallowTill }
    /// Календарь «Съёмок» не листается, пока режим включён или плитка в руке (веб L34416).
    var blocksSwipe: Bool { on || lift != nil }

    func turnOn() {
        guard !on else { return }
        on = true
        since = Date()
        Haptics.play(.mbSortOn)
        MbSortLog.note("on")
    }

    func off() {
        guard on else { return }
        on = false
        MbSortLog.note("off")
    }

    // MARK: перенос

    /// Ряд сообщает свой порядок ключей на экране.
    func track(_ row: String, keys: [String]) { live[row] = keys }

    /// Ряд за время жеста стал другим: то, что в руке, писать нельзя (`lift.home` — порядок на подъёме).
    private func stale(_ l: Lift) -> Bool { live[l.row].map { $0 != l.home } ?? false }

    func cells(_ row: String, count: Int, first: Int) -> [MbSortRules.Cell] {
        let r = rows[row] ?? RowSize()
        return MbSortRules.cells(count: count, first: first, width: Double(r.width), tileHeight: Double(r.tileH))
    }

    /// Подъём (веб `lift`): отдача 14 мс, клетки снимаются сейчас.
    @discardableResult
    func begin(row: String, key: String, keys: [String], first: Int, commit: @escaping ([String]) -> Void) -> Bool {
        guard lift == nil, !settling, let from = keys.firstIndex(of: key) else { return false }
        let cells = cells(row, count: keys.count, first: first)
        guard cells.count == keys.count, cells.first.map({ $0.w > 0 && $0.h > 0 }) == true else { return false }
        lift = Lift(row: row, me: key, home: keys, cells: cells, from: from)
        live[row] = keys
        order = keys
        hand = .zero
        zone = from
        self.commit = commit
        swallowTill = .infinity
        Haptics.play(.mbSortLift)
        MbSortLog.note("lift row=\(row) key=\(key) from=\(from) n=\(keys.count) cell=\(Self.f(cells[from].w))x\(Self.f(cells[from].h))"
                       + " cells=" + cells.map { "\(Self.f($0.x)),\(Self.f($0.y))" }.joined(separator: " "))
        return true
    }

    /// Ход пальца от касания в пространстве ряда (веб `mbFrame`): поднятая едет, соседи расступаются.
    func move(_ d: CGSize) {
        guard let l = lift, !settling else { return }
        hand = d
        let c = l.cells[l.from]
        guard let z = MbSortRules.zone(centerX: c.midX + Double(d.width), centerY: c.midY + Double(d.height), cells: l.cells),
              z != zone else { return }
        zone = z
        order = MbSortRules.move(order, l.me, to: z)
        Haptics.play(.mbSortZone)
        MbSortLog.note("zone \(z) order=\(order.joined(separator: ","))")
    }

    /// Отпустили (веб `mbDrop`): плитка доезжает до клетки, порядок пишется через 0,32 с, если сменился.
    func drop() {
        guard let l = lift, !settling else { return }
        settling = true
        // Ряд уже другой — плитка ложится туда, откуда взята, а не в клетку нового порядка.
        if stale(l) { order = l.home }
        #if DEBUG && os(iOS)
        meter?.beginSettle()
        #endif
        MbSortLog.note("drop hand=\(Self.f(Double(hand.width))),\(Self.f(Double(hand.height))) to=\(order.firstIndex(of: l.me) ?? -1)")
        after(MbSortRules.settleDelay) { [weak self] in self?.finish() }
    }

    private func finish() {
        guard let l = lift else { return }
        // Порядок, что в руке, пишется только на тот ряд, с которого поднят; разошёлся — не пишем, ряд на экране
        // уже актуальный, он и остаётся.
        let refused = stale(l)
        let ord = order, changed = !refused && ord != l.home, write = commit
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            if changed { write?(ord) }
            lift = nil; order = []; hand = .zero; settling = false
        }
        commit = nil
        swallowTill = Self.clock + 0.35
        meterStop()
        if changed { Haptics.play(.mbSortSaved) }
        MbSortLog.note(refused ? "refused" : changed ? "saved order=\(ord.joined(separator: ","))" : "same")
    }

    // MARK: что рисует плитка

    func isLifted(_ row: String?, _ key: String) -> Bool { row != nil && lift?.row == row && lift?.me == key }

    /// Сдвиг плитки ряда: поднятая — за пальцем или к новой клетке, сосед — к клетке нового места.
    func offset(_ row: String, _ key: String) -> CGSize {
        guard let l = lift, l.row == row else { return .zero }
        if key == l.me {
            guard settling, let j = order.firstIndex(of: key), j < l.cells.count else { return hand }
            return CGSize(width: l.cells[j].x - l.cells[l.from].x, height: l.cells[j].y - l.cells[l.from].y)
        }
        let s = MbSortRules.shift(key, order: order, home: l.home, cells: l.cells)
        return CGSize(width: s.dx, height: s.dy)
    }

    /// Тап по точке окна попал в плитку верхнего слоя (веб `mbKeeps`).
    func keeps(_ p: CGPoint, layer: String) -> Bool {
        tiles.contains { $0.key.hasPrefix(layer + ".") && $0.value.contains(p) }
    }

    static func f(_ v: Double) -> String { String(format: "%.1f", v) }
}

/// Кривые беты (CSS), при «Уменьшении движения» — сразу (`PlanMotion.pick`), покачивание выключено.
enum MbSortMotion {
    /// Подъём обложки: `transform .2s cubic-bezier(.2,1.3,.4,1)` (веб L21552).
    static let lift = Animation.timingCurve(0.2, 1.3, 0.4, 1, duration: 0.2)
    /// Обложка опускается: `.3s cubic-bezier(.2,1.2,.35,1)` (L21656).
    static let unlift = Animation.timingCurve(0.2, 1.2, 0.35, 1, duration: 0.3)
    /// Соседи расступаются: `.3s cubic-bezier(.22,.9,.25,1)` (L21637).
    static let shift = Animation.timingCurve(0.22, 0.9, 0.25, 1, duration: 0.3)
    /// Посадка: `.36s cubic-bezier(.2,1.25,.35,1)` (L21652).
    static let land = Animation.timingCurve(0.2, 1.25, 0.35, 1, duration: 0.36)
    /// Минус: `opacity .16s ease`, `transform .18s cubic-bezier(.2,1.5,.4,1)` (L3918).
    static let minusFade = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.16)
    static let minusPop = Animation.timingCurve(0.2, 1.5, 0.4, 1, duration: 0.18)
}

/// Журнал жеста для замеров на симуляторе (Debug, `-LPMbSortLog <файл>`; имя без «/» — файл в
/// `Documents` приложения): касание и решение, режим, подъём с клетками, смена клетки, отпускание,
/// запись; по кадрам — угол покачивания первых трёх плиток ряда, масштаб поднятой, сдвиги плиток.
enum MbSortLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPMbSortLog").map {
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
        guard let url, let data = (String(format: "%.3f ", MbSort.clock) + line() + "\n").data(using: .utf8) else { return }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
        }
        handle?.write(data)
        #endif
    }
}

// MARK: - Плитка в режиме

/// Что плитка знает о режиме: ряд и ключ (у переставляемых), слой, место в сетке (CSS `nth-child`,
/// с 1) и есть ли у неё минус (у «Все» его нет).
struct MbSortTile {
    let sort: MbSort
    /// Ряд переставляемых плиток; `nil` — плитка качается, но не переносится (съёмки, «Все»).
    var row: String?
    var key: String
    let nth: Int
    var minus = true
}

/// Обложка в режиме (веб `.mb-tile-art`): качается, носит минус, поднятая — крупнее и с тенью.
struct MbSortArt<Art: View>: View {
    let tile: MbSortTile?
    @ViewBuilder let art: Art

    var body: some View {
        if let tile { MbSortArtLive(tile: tile, art: art) } else { art }
    }
}

private struct MbSortArtLive<Art: View>: View {
    let tile: MbSortTile
    let art: Art
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = tile.sort
        let lifted = s.isLifted(tile.row, tile.key)
        let up = lifted && !s.settling
        let shaking = s.on && !lifted && !PlanMotion.still
        let since = s.since
        let pal = Palette(scheme)
        TimelineView(.animation(minimumInterval: nil, paused: !shaking)) { ctx in
            let a = shaking ? MbSortRules.jiggle(t: ctx.date.timeIntervalSince(since), nth: tile.nth) : 0
            let _ = logJiggle(a, shaking)
            art
                .overlay(alignment: .topLeading) { if tile.minus { minus(s.on && !lifted, pal) } }
                .rotationEffect(.degrees(a), anchor: UnitPoint(x: 0.5, y: 0.55))
        }
        .modifier(MbLiftLook(k: up ? 1 : 0, pal: pal, tag: tile.key))
        .animation(PlanMotion.pick(up ? MbSortMotion.lift : MbSortMotion.unlift), value: up)
    }

    private func logJiggle(_ a: Double, _ shaking: Bool) {
        guard MbSortLog.on, shaking, tile.nth <= 3 else { return }
        MbSortLog.note("jig \(tile.row ?? "-") nth=\(tile.nth) a=\(String(format: "%.3f", a))")
    }

    /// Минус (веб `.mb-del`): зона 38, кружок 23 цвета чернил, тень `0 2 6 .5`, черта 11 × 2 цвета фона.
    /// Тап по нему — тот же тап по плитке (лист подборки); касание на нём перенос не начинает (`MbSortRowModifier`).
    private func minus(_ show: Bool, _ pal: Palette) -> some View {
        Circle().fill(pal.ink).frame(width: 23, height: 23)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            .overlay { Capsule().fill(pal.surface).frame(width: 11, height: 2) }
            .frame(width: 38, height: 38)
            .scaleEffect(show ? 1 : 0.3)
            .animation(PlanMotion.pick(MbSortMotion.minusPop), value: show)
            .opacity(show ? 1 : 0)
            .animation(PlanMotion.pick(MbSortMotion.minusFade), value: show)
            .allowsHitTesting(false)
            .shotNode(show ? "mb.del" : "", text: tile.key)
    }
}

/// Подъём обложки (веб `scale(1.09)` и `box-shadow 0 18px 32px rgba(0,0,0,.4)`): `k` от 0 до 1, кривая
/// с перелётом. Тень без скругления, как у `.mb-tile-art`; прямоугольник под ней закрыт обложкой.
private struct MbLiftLook: ViewModifier, @preconcurrency Animatable {
    var k: Double
    let pal: Palette
    let tag: String
    var animatableData: Double {
        get { k }
        set { k = newValue }
    }

    func body(content: Content) -> some View {
        if MbSortLog.on, k > 0.0005, k < 0.9995 || k > 1.0005 {
            MbSortLog.note("look key=\(tag) k=\(String(format: "%.3f", k)) scale=\(String(format: "%.4f", 1 + 0.09 * k))")
        }
        let s = max(0, k)
        return content
            .background {
                if s > 0 {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet)
                        .shadow(color: .black.opacity(0.4 * min(1, s)), radius: 16 * s, y: 18 * s)
                }
            }
            .scaleEffect(1 + 0.09 * k)
    }
}

/// Сдвиг плитки ряда (веб `translate` на `.mb-tile`): поднятая — за пальцем без кривой, при посадке —
/// 0,36 с; соседи — 0,3 с. Пишет в журнал каждый кадр, пока ряд в работе.
struct MbSortSlot: ViewModifier {
    let sort: MbSort
    let row: String
    let key: String

    func body(content: Content) -> some View {
        let lifted = sort.isLifted(row, key)
        let o = sort.offset(row, key)
        let curve: Animation? = lifted ? (sort.settling ? MbSortMotion.land : nil) : MbSortMotion.shift
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                sort.rows[row, default: MbSort.RowSize()].tileH = h
            }
            .modifier(MbShift(dx: o.width, dy: o.height, tag: key, live: sort.lift?.row == row))
            .animation(curve.flatMap { PlanMotion.pick($0) }, value: o)
            .zIndex(lifted ? 60 : 0)
    }
}

private struct MbShift: ViewModifier, @preconcurrency Animatable {
    var dx: CGFloat
    var dy: CGFloat
    let tag: String
    let live: Bool
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(dx, dy) }
        set { dx = newValue.first; dy = newValue.second }
    }

    func body(content: Content) -> some View {
        if live, MbSortLog.on { MbSortLog.note("shift key=\(tag) dx=\(MbSort.f(Double(dx))) dy=\(MbSort.f(Double(dy)))") }
        return content.offset(x: dx, y: dy)
    }
}

/// Плитка в реестре «тап мимо». Пишется всегда, без ветки по режиму: ветка сменила бы плитке
/// личность при входе в режим, и минус появился бы без своей кривой.
struct MbSortHit: ViewModifier {
    let sort: MbSort
    let id: String

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { sort.tiles[id] = $0 }
            .onDisappear { sort.tiles[id] = nil }
    }
}

extension View {
    /// Плитка в реестре «тап мимо» (`layer.имя`).
    func mbSortHit(_ sort: MbSort, _ id: String) -> some View { modifier(MbSortHit(sort: sort, id: id)) }

    /// Ряд переставляемых плиток: один распознаватель на сетку. `keys` — ключи плиток по порядку,
    /// `first` — сколько мест перед ними занято (рамка «+»), `commit` — запись нового порядка.
    func mbSortRow(_ sort: MbSort, row: String, keys: [String], first: Int,
                   commit: @escaping ([String]) -> Void) -> some View {
        modifier(MbSortRowModifier(sort: sort, row: row, keys: keys, first: first, commit: commit))
    }
}

struct MbSortRowModifier: ViewModifier {
    let sort: MbSort
    let row: String
    let keys: [String]
    let first: Int
    let commit: ([String]) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                sort.rows[row, default: MbSort.RowSize()].width = w
            }
            .onChange(of: keys, initial: true) { _, k in sort.track(row, keys: k) }
            .gesture(gesture)
            .zIndex(sort.lift?.row == row ? 1 : 0)
        #else
        content
        #endif
    }

    #if os(iOS)
    private var gesture: MbSortGesture {
        MbSortGesture(
            down: { p in down(p) },
            began: {
                guard let key = sort.armed else { return false }
                if !sort.on { sort.turnOn() }
                return sort.begin(row: row, key: key, keys: keys, first: first, commit: commit)
            },
            moved: { d in sort.move(d) },
            ended: { sort.drop() },
            reset: { if sort.lift == nil { sort.armed = nil; sort.meterStop(silently: true) } },
            autoScroll: { sort.lift?.row == row && !sort.settling })
    }

    /// Касание сетки (веб `pointerdown` на плитке): мимо плиток — не наш; минус — не ручка; вне режима —
    /// ждём удержания, в режиме — сдвига.
    private func down(_ p: CGPoint) -> MbSortStart {
        guard sort.lift == nil, !sort.settling else {
            MbSortLog.note("down row=\(row) x=\(Int(p.x)) y=\(Int(p.y)) busy"); return .none
        }
        let cells = sort.cells(row, count: keys.count, first: first)
        guard let i = MbSortRules.hit(Double(p.x), Double(p.y), cells: cells) else {
            MbSortLog.note("down row=\(row) x=\(Int(p.x)) y=\(Int(p.y)) miss on=\(sort.on)"); return .none
        }
        if sort.on, CGRect(x: cells[i].x, y: cells[i].y, width: 38, height: 38).contains(p) {
            MbSortLog.note("down row=\(row) key=\(keys[i]) minus"); return .none
        }
        sort.armed = keys[i]
        sort.meterStart()
        MbSortLog.note("down row=\(row) key=\(keys[i]) x=\(Int(p.x)) y=\(Int(p.y)) \(sort.on ? "slide" : "hold")")
        return sort.on ? .slide : .hold
    }
    #endif
}

/// Как ряд принял касание: мимо, ждём удержания 0,42 с (вне режима), ждём сдвига ≥ 8 (в режиме).
enum MbSortStart { case none, hold, slide }

#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Жест ряда. `down` — точка касания в сетке и решение; `began` — подъём (ответ `false` — подъёма не
/// было); `moved` — ход пальца от касания в пространстве прокрутки (с поправкой на автопрокрутку);
/// `ended` — отпустили или касание отняла система (как у веба `pointercancel` → `mbDrop`).
struct MbSortGesture: UIGestureRecognizerRepresentable {
    var down: (CGPoint) -> MbSortStart
    var began: () -> Bool
    var moved: (CGSize) -> Void
    var ended: () -> Void
    var reset: () -> Void
    var autoScroll: () -> Bool

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter, gesture: self)
    }

    func makeUIGestureRecognizer(context: Context) -> MbSortPan {
        let pan = MbSortPan()
        pan.delegate = context.coordinator
        let coordinator = context.coordinator
        pan.decide = { [weak coordinator] in
            guard let coordinator else { return .none }
            return coordinator.gesture.down(coordinator.converter.localLocation)
        }
        pan.onReset = { [weak coordinator] in coordinator?.gesture.reset() }
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: MbSortPan, context: Context) {
        context.coordinator.converter = context.converter
        context.coordinator.gesture = self
    }

    func handleUIGestureRecognizerAction(_ recognizer: MbSortPan, context: Context) {
        let c = context.coordinator
        switch recognizer.state {
        case .began:
            c.find(recognizer)
            guard c.gesture.began() else {
                MbSortLog.note("began refused")
                recognizer.state = .cancelled
                return
            }
            c.lifted = true
            c.track(recognizer)
            c.startAuto(recognizer)
        case .changed:
            guard c.lifted else { return }
            c.track(recognizer)
        case .ended, .cancelled, .failed:
            c.stopAuto()
            if c.lifted {
                MbSortLog.note("\(recognizer.state == .ended ? "ended" : "cancelled") scroll=\(Int(c.scroll?.contentOffset.y ?? 0))"
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
        var gesture: MbSortGesture
        var lifted = false
        private(set) weak var scroll: UIScrollView?
        /// Точка касания в пространстве прокрутки: ход считается от неё (веб `sx`, `sy`).
        private var start: CGPoint = .zero
        var scrollAtLift: CGFloat = 0
        private weak var pan: MbSortPan?
        private var link: CADisplayLink?
        private var lastTick: CFTimeInterval = 0
        /// Край включается, лишь когда палец из полосы вышел (веб `d.edgeOk`).
        private var edgeOk = false

        init(converter: CoordinateSpaceConverter, gesture: MbSortGesture) {
            self.converter = converter
            self.gesture = gesture
        }

        /// Прокрутку ищем от вида под пальцем (распознаватель SwiftUI висит выше неё) и снимаем точку касания.
        func find(_ r: MbSortPan) {
            var v = r.touchView
            while let x = v, !(x is UIScrollView) { v = x.superview }
            scroll = v as? UIScrollView
            let space: UIView? = scroll ?? r.view
            start = space?.convert(r.downInWindow, from: nil) ?? r.downInWindow
            scrollAtLift = scroll?.contentOffset.y ?? 0
            MbSortLog.note("scroll \(scroll.map { "found h=\(Int($0.bounds.height)) y=\(Int($0.contentOffset.y))" } ?? "missing")")
        }

        func track(_ r: MbSortPan) {
            let p = r.location(in: scroll ?? r.view)
            gesture.moved(CGSize(width: p.x - start.x, height: p.y - start.y))
        }

        /// Прокрутка ждёт, пока жест откажется: удержание не срывается в прокрутку, а палец, ушедший
        /// на 8 pt до подъёма, отдаётся ей. Жест «назад» от края висит на окне — его это не касается.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }

        // MARK: автопрокрутка (веб `mbAutoScroll`: полосы 120 / 140, до 15 pt за такт 60 мс)

        func startAuto(_ r: MbSortPan) {
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
            let dt = lastTick == 0 ? 1.0 / 60 : min(0.05, l.timestamp - lastTick)
            lastTick = l.timestamp
            let inset = sv.adjustedContentInset
            let y = r.location(in: sv).y - sv.contentOffset.y
            let top = Double(y - inset.top), bot = Double(sv.bounds.height - inset.bottom - y)
            if !edgeOk { edgeOk = MbSortRules.edgeArms(top: top, bottom: bot); return }
            let v = MbSortRules.edgeSpeed(top: top, bottom: bot, armed: true)
            guard v != 0 else { return }
            let lo = -inset.top, hi = max(lo, sv.contentSize.height + inset.bottom - sv.bounds.height)
            let was = sv.contentOffset.y
            let to = min(max(was + CGFloat(v * dt / MbSortRules.edgeTick), lo), hi)
            guard to != was else { return }
            sv.contentOffset.y = to
            MbSortLog.note("auto v=\(MbSort.f(v)) y=\(Int(to))")
            track(r)
        }
    }
}

/// Распознаватель ряда. Свой, а не `UILongPressGestureRecognizer`: на касании он спрашивает ряд, что
/// под пальцем, и берёт палец через 0,42 с (вне режима), на сдвиге ≥ 8 pt (в режиме) или отказывается —
/// тогда палец целиком у прокрутки и тапов. Вне режима сдвиг до удержания — прокрутка (веб L21509).
final class MbSortPan: UIGestureRecognizer {
    var decide: (() -> MbSortStart)?
    var onReset: (() -> Void)?
    private var touch: UITouch?
    private var mode: MbSortStart = .none
    private(set) var downInWindow: CGPoint = .zero
    var touchView: UIView? { touch?.view }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        // Ведёт только свой палец (веб `pd.id`): второй жесту не нужен.
        if touch != nil { touches.forEach { ignore($0, for: event) }; return }
        guard touches.count == 1, let t = touches.first else { state = .failed; return }
        touch = t
        downInWindow = t.location(in: nil)
        mode = decide?() ?? .none
        switch mode {
        case .none: state = .failed
        case .hold: perform(#selector(arm), with: nil, afterDelay: MbSortRules.hold, inModes: [.common])
        case .slide: break
        }
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
            guard Double(abs(p.x - downInWindow.x) + abs(p.y - downInWindow.y)) >= MbSortRules.slop else { return }
            if mode == .slide { state = .began } else { cancelArm(); state = .failed }
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
        mode = .none
    }
}

// MARK: - Выход тапом мимо плиток (веб `mbTapDown` / `mbTapUp`)

/// Пассивный распознаватель на окне: пока режим включён, тап (сдвиг ≤ 12) мимо плиток верхнего слоя
/// выключает режим. Касание ничего не отнимает и ни с кем не спорит.
struct MbSortTapOutHost: UIViewRepresentable {
    var sorting: () -> Bool
    var keeps: (CGPoint) -> Bool
    var leave: () -> Void

    func makeUIView(context: Context) -> MbSortTapOutProbe {
        let v = MbSortTapOutProbe()
        v.rules = self
        return v
    }

    func updateUIView(_ v: MbSortTapOutProbe, context: Context) { v.rules = self }
}

final class MbSortTapOutProbe: UIView {
    var rules: MbSortTapOutHost? {
        didSet { recognizer?.rules = rules }
    }
    private var recognizer: MbSortTapOut?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer); self.recognizer = nil }
        guard let window else { return }
        let r = MbSortTapOut()
        r.rules = rules
        window.addGestureRecognizer(r)
        recognizer = r
    }
}

final class MbSortTapOut: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var rules: MbSortTapOutHost?
    private var touch: UITouch?
    private var at: CGPoint = .zero
    private var out = false

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touch == nil, let t = touches.first, let rules, MainActor.assumeIsolated({ rules.sorting() }) else {
            if touch == nil { state = .failed }
            return
        }
        touch = t
        at = t.location(in: nil)
        out = !MainActor.assumeIsolated { rules.keeps(at) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touch, touches.contains(t), let rules else { return }
        let p = t.location(in: nil)
        let tap = Double(abs(p.x - at.x) + abs(p.y - at.y)) <= MbSortRules.tapSlop
        if out, tap, !MainActor.assumeIsolated({ rules.keeps(p) }) {
            MbSortLog.note("tap-out x=\(Int(p.x)) y=\(Int(p.y))")
            MainActor.assumeIsolated { rules.leave() }
        }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }

    override func reset() {
        super.reset()
        touch = nil
        out = false
    }
}
#endif

/// Escape выводит из режима, если поверх нет листа (веб `mbSortKey`: лист закрывается первым).
struct MbSortEscape: View {
    let app: AppModel

    var body: some View {
        // Кнопка стоит всегда и только выключается: появляясь, она перекладывала бы корень (замер 29.3б).
        Button("") { app.mbSort.off() }.keyboardShortcut(.escape, modifiers: [])
            .disabled(!(app.mbSort.on && app.mb.sheet == nil))
            .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}

/// Подсказка под «Подборками» (веб `.mb-strip-hint`, `mbSortHint`): 10,5 цвета `--ink-7`, отступ 14 сверху;
/// в режиме текст меняется на «Тащите, чтобы переставить…».
struct MbSortHint: View {
    let app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let key = app.mbSort.on ? "mb.sortHint" : "mb.holdHint"
        Text(app.lexicon.t(key)).font(webFont(10.5)).foregroundStyle(Palette(scheme).ink7).lineSpacing(3)
            .padding(.top, 14).padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shotNode("mb.hint", text: key)
    }
}
