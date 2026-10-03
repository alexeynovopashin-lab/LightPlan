import SwiftUI

/// Жест «назад» свайпом от левого края (итерация 28з). Экраны здесь — слои поверх вкладок, а не системная
/// навигация, поэтому системного жеста у них нет: каждый слой записывается в реестр модификатором
/// `.edgeBack`, а один распознаватель края на окне (`EdgeBackHost`) двигает верхний слой за пальцем.

/// Правила отпускания и сдвига нижнего слоя — числа системного жеста.
enum EdgeBackRule {
    /// Дальше трети ширины — закрыть.
    static let commitFraction: CGFloat = 1.0 / 3
    /// Быстрый короткий свайп: скорость вправо от этой — закрыть.
    static let flickVelocity: CGFloat = 600
    /// Быстрый возврат пальцем влево — вернуть, даже если дотянули дальше трети.
    static let backVelocity: CGFloat = -300
    /// Нижний слой стоит на 30 % ширины левее и доезжает до нуля, как у системы.
    static let parallax: CGFloat = 0.3
    /// Граница «оболочечных» слоёв: слои ниже — внутри «Съёмок» (лента года, поиск, статистика).
    static let shellFloor: Double = 0.9

    static func commits(dx: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        if velocity <= backVelocity { return false }
        return dx > width * commitFraction || velocity >= flickVelocity
    }
}

@MainActor @Observable
final class EdgeBack {
    struct Layer {
        let id: UUID
        let z: Double
        /// Высота слоя, внутри которого лежит этот (раздел и бумага внутри «Документов»): их сдвиги не складываются.
        let inside: Double?
        let close: @MainActor () -> Void
    }

    private(set) var layers: [Layer] = []
    /// Закрытые жестом слои: пока они уходят из дерева, жест их не берёт.
    private var closing: Set<UUID> = []
    private var samples: [(t: TimeInterval, x: CGFloat)] = []
    static let velocityWindow = 0.12
    /// Сдвиг верхнего слоя вправо, pt.
    private(set) var dx: CGFloat = 0
    private(set) var width: CGFloat = 390
    /// Палец ведёт слой.
    private(set) var dragging = false
    /// Слой доезжает до конца или возвращается — новый жест в это время не берётся.
    private(set) var settling = false
    /// Сколько раз жест закрыл слой (для тестов и замеров).
    private(set) var closedCount = 0

    static let settle = Animation.timingCurve(0.25, 1, 0.4, 1, duration: 0.28)
    static let settleSeconds = 0.3

    var active: Bool { dragging || settling }

    #if DEBUG
    /// Замер на симуляторе (`-LPEdgeBackLog <файл>`): строка на начало, отпускание, закрытие и отказ.
    private let logURL = UserDefaults.standard.string(forKey: "LPEdgeBackLog").map { URL(fileURLWithPath: $0) }
    #endif
    func note(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let url = logURL, let data = (line() + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }

    /// Открытые слои сверху вниз; на равной высоте выше тот, кто записан позже (так рисует `ZStack`).
    private var ordered: [Layer] {
        let live = layers.enumerated().filter { !closing.contains($0.element.id) }
        return live.sorted { ($0.element.z, $0.offset) > ($1.element.z, $1.offset) }.map(\.element)
    }
    var top: Layer? { ordered.first }
    private var second: Layer? { ordered.dropFirst().first }

    var canBegin: Bool { top != nil && !active }

    // MARK: реестр

    func register(_ id: UUID, z: Double, inside: Double? = nil, close: @escaping @MainActor () -> Void) {
        layers.removeAll { $0.id == id }
        layers.append(Layer(id: id, z: z, inside: inside, close: close))
    }

    func unregister(_ id: UUID) {
        layers.removeAll { $0.id == id }
        closing.remove(id)
    }

    // MARK: жест

    @discardableResult
    func begin(width: CGFloat) -> Bool {
        guard canBegin else { note("refused top=\(top?.z ?? -1) active=\(active)"); return false }
        self.width = max(1, width)
        samples = []
        note("begin top=\(top?.z ?? -1) layers=\(ordered.map(\.z))")
        dx = 0
        dragging = true
        return true
    }

    func move(_ x: CGFloat, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard dragging else { return }
        dx = min(max(0, x), width)
        samples.append((time, x))
        samples.removeAll { time - $0.t > Self.velocityWindow }
    }

    /// Скорость пальца вправо, pt/с, по последним 0,12 с движения. Палец, замерший перед отпусканием, даёт 0:
    /// у распознавателя скорость не гаснет без новых касаний (измерено: 568–671 pt/с у пальца, стоявшего 1,3 с).
    func releaseVelocity(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> CGFloat {
        let recent = samples.filter { time - $0.t <= Self.velocityWindow }
        guard let a = recent.first, let b = recent.last, b.t - a.t > 0.015 else { return 0 }
        return CGFloat((b.x - a.x) / (b.t - a.t))
    }

    /// Палец отпущен: решение и доезд. `velocity` — pt/с вправо; без неё — замер по последним движениям.
    func end(velocity: CGFloat? = nil, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard dragging else { return }
        let v = velocity ?? releaseVelocity(at: time)
        let commit = EdgeBackRule.commits(dx: dx, velocity: v, width: width)
        note("end dx=\(Int(dx)) v=\(Int(v)) commit=\(commit)")
        samples = []
        settle(commit: commit)
    }

    func cancel() {
        guard dragging else { return }
        note("cancel dx=\(Int(dx))")
        settle(commit: false)
    }

    private func settle(commit: Bool) {
        dragging = false
        settling = true
        withAnimation(Self.settle) { dx = commit ? width : 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.settleSeconds))
            finishSettle(commit: commit)
        }
    }

    /// Доезд закончен. Закрытие — без анимации: слой уже за краем, второй выезд был бы лишним.
    func finishSettle(commit: Bool) {
        guard settling else { return }
        if commit, let t = top {
            let id = t.id
            closing.insert(id)
            closedCount += 1
            note("closed z=\(t.z)")
            var off = Transaction()
            off.disablesAnimations = true
            withTransaction(off) {
                t.close()
                dx = 0
                settling = false
            }
            // Слой, который закрытие не убрало, возвращается в игру.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                closing.remove(id)
            }
        } else {
            dx = 0
            settling = false
        }
    }

    // MARK: сдвиги

    /// Сдвиг слоя `id`: верхний идёт за пальцем, лежащий прямо под ним — с параллаксом.
    func offset(of id: UUID) -> CGFloat {
        guard active, let me = layers.first(where: { $0.id == id }) else { return 0 }
        // Слой внутри другого (раздел внутри «Документов») уже едет с хозяином: свой сдвиг — разница.
        let host = me.inside.flatMap { z in ordered.first { $0.z == z } }
        return net(me) - (host.map(net) ?? 0)
    }

    /// Где слой должен оказаться на экране: верхний — за пальцем, лежащий под ним — с параллаксом.
    private func net(_ l: Layer) -> CGFloat {
        if top?.id == l.id { return dx }
        if second?.id == l.id { return -EdgeBackRule.parallax * (width - dx) }
        return 0
    }

    func isTop(_ id: UUID) -> Bool { active && top?.id == id }

    /// Сдвиг общей основы: вкладок (`tabs`) или календаря «Съёмок» (`planner`) — когда прямо под верхним слоем лежит она.
    enum Base { case tabs, planner }
    func baseOffset(_ base: Base) -> CGFloat {
        guard active, let t = top else { return 0 }
        let shell = t.z >= EdgeBackRule.shellFloor
        let belowIsShell = second.map { $0.z >= EdgeBackRule.shellFloor } ?? false
        let moves: Bool
        switch base {
        case .tabs: moves = shell && !belowIsShell
        case .planner: moves = !shell && second == nil
        }
        return moves ? -EdgeBackRule.parallax * (width - dx) : 0
    }
}

// MARK: - Модификаторы

private struct EdgeBackLayer: ViewModifier {
    let edge: EdgeBack
    let z: Double
    let inside: Double?
    let close: @MainActor () -> Void
    @State private var id = UUID()

    func body(content: Content) -> some View {
        let x = edge.offset(of: id)
        let top = edge.isTop(id)
        content
            // Край слоя отбрасывает тень на то, что под ним, как у системной страницы.
            .shadow(color: .black.opacity(top ? 0.22 * (1 - Double(edge.dx / edge.width)) : 0), radius: 9, x: -3)
            .offset(x: x)
            .onAppear { edge.register(id, z: z, inside: inside, close: close) }
            .onDisappear { edge.unregister(id) }
    }
}

private struct EdgeBackBase: ViewModifier {
    let edge: EdgeBack
    let base: EdgeBack.Base
    func body(content: Content) -> some View {
        content.offset(x: edge.baseOffset(base))
    }
}

extension View {
    /// Слой закрывается свайпом от левого края. `z` — высота слоя (как `zIndex`), `close` — чистая смена
    /// состояния без анимации: жест сам довозит слой за край и закрывает его без второго выезда.
    func edgeBack(_ app: AppModel, z: Double, inside: Double? = nil, close: @escaping @MainActor () -> Void) -> some View {
        modifier(EdgeBackLayer(edge: app.edgeBack, z: z, inside: inside, close: close))
    }

    /// То, что лежит под слоями: сдвигается на 30 % ширины, пока верхний слой едет за пальцем.
    func edgeBackBase(_ app: AppModel, _ base: EdgeBack.Base) -> some View {
        modifier(EdgeBackBase(edge: app.edgeBack, base: base))
    }
}

/// Высоты слоёв (они же `zIndex` оболочки). Равные — тот, кто объявлен ниже, лежит выше.
enum BackZ {
    static let docs = 0.9
    static let docsSection = 0.91
    static let docsPaper = 0.92
    static let card = 1.0
    static let gallery = 1.2
    static let shelf = 1.3
    static let folder = 1.4
    static let refs = 1.5
    static let orgList = 1.52
    static let contacts = 1.54
    static let orgCard = 1.6
    static let form = 10.0
    // Слои «Съёмок»: лента, «Год целиком», поиск, статистика.
    static let lenta = 0.11
    static let year12 = 0.12
    static let search = 0.2
    static let stats = 0.3
}

extension AppModel {
    /// Жест не берётся там, где у экрана свои горизонтальные жесты у края: полноэкранный просмотр кадров.
    var edgeBackBlocked: Bool {
        refsFull?.pager != nil || mb.pager != nil
    }
}
