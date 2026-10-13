import Foundation

/// Режим сортировки мудборда и перестановка подборок (29.3б; веб «Жест сортировки подборок»,
/// `mbStartDrag` … `mbReseat`, `beta/index.html` L21355–21710). Числа беты, без поправок.
///
/// Как устроено у веба (демка Алексея 31.08.2026, перенесена один в один): клетки ряда
/// снимаются один раз — при подъёме; место поднятой — клетка, под которой её центр (с
/// допуском 6 pt за край клетки); соседи едут сдвигом от своей домашней клетки к клетке
/// нового порядка, сам ряд во время жеста не перестраивается. Порядок пишется после
/// отпускания — подборки садятся на те же места в `boards[]`, что и занимали.
public enum MbSortRules {
    /// Удержание до входа в режим (веб `MB_HOLD`, 420 мс).
    public static let hold = 0.42
    /// Сдвиг `|dx| + |dy|` меньше 8 — ещё не сдвиг (веб L21505).
    public static let slop = 8.0
    /// Выход из режима тапом мимо плиток: сдвиг не больше 12 (веб `mbTapUp`).
    public static let tapSlop = 12.0
    /// Допуск клетки: центр поднятой дальше `w/2 + 6` от центра клетки — не в ней (веб `mbFrame`).
    public static let zoneSlack = 6.0
    /// Через сколько после отпускания пишется порядок (веб `setTimeout(…, 320)`).
    public static let settleDelay = 0.32

    // MARK: - Клетки

    public struct Cell: Equatable, Sendable {
        public var x, y, w, h: Double
        public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
        public var midX: Double { x + w / 2 }
        public var midY: Double { y + h / 2 }
        public func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px <= x + w && py >= y && py <= y + h }
    }

    /// Клетки сетки плиток (веб `.mb-tiles`: три колонки, зазор 10). `first` — сколько мест
    /// впереди занято не переставляемыми плитками (рамка «+» у «Подборок»), `count` —
    /// сколько переставляемых. Высота клетки — высота плитки, шаг ряда — она же плюс зазор.
    public static func cells(count: Int, first: Int, width: Double, tileHeight: Double,
                             columns: Int = 3, gap: Double = 10) -> [Cell] {
        guard count > 0, columns > 0 else { return [] }
        let w = (width - gap * Double(columns - 1)) / Double(columns)
        return (0..<count).map { i in
            let k = first + i
            return Cell(x: Double(k % columns) * (w + gap), y: Double(k / columns) * (tileHeight + gap), w: w, h: tileHeight)
        }
    }

    /// Какая клетка под точкой (касание): только сама плитка, зазор — мимо.
    public static func hit(_ px: Double, _ py: Double, cells: [Cell]) -> Int? {
        cells.firstIndex { $0.contains(px, py) }
    }

    /// Клетка под центром поднятой (веб `mbFrame`): из тех, куда центр попал с допуском,
    /// — ближайшая; `nil` — центр между клетками или за рядом (место не меняется).
    public static func zone(centerX cx: Double, centerY cy: Double, cells: [Cell]) -> Int? {
        var best = Double.infinity, z: Int?
        for (i, q) in cells.enumerated() {
            let ax = cx - q.midX, ay = cy - q.midY
            if abs(ax) > q.w * 0.5 + zoneSlack || abs(ay) > q.h * 0.5 + zoneSlack { continue }
            let d = ax * ax + ay * ay
            if d < best { best = d; z = i }
        }
        return z
    }

    // MARK: - Порядок

    /// Переставить `id` на место `to` (веб `mbMoveTo`: вынуть и вставить). Места за краем
    /// ряда прижимаются к краю; чужой `id` — ряд как был.
    public static func move(_ order: [String], _ id: String, to: Int) -> [String] {
        guard let cur = order.firstIndex(of: id) else { return order }
        var out = order
        out.remove(at: cur)
        out.insert(id, at: min(max(to, 0), out.count))
        return out
    }

    /// Сдвиг соседа от его домашней клетки к клетке нынешнего места (веб `mbApplyOrder`).
    public static func shift(_ id: String, order: [String], home: [String], cells: [Cell]) -> (dx: Double, dy: Double) {
        guard let j = order.firstIndex(of: id), let h = home.firstIndex(of: id), j < cells.count, h < cells.count
        else { return (0, 0) }
        return (cells[j].x - cells[h].x, cells[j].y - cells[h].y)
    }

    // MARK: - Автопрокрутка (веб `mbAutoScroll`)

    /// Полоса у верхнего края видимой части, где лист едет вверх.
    public static let edgeTop = 120.0
    /// Полоса у нижнего края.
    public static let edgeBottom = 140.0
    /// Предел скорости за такт.
    public static let edgeMax = 15.0
    /// Такт веба (`setInterval(mbFrame, 60)`): скорость задана в точках за 60 мс.
    public static let edgeTick = 0.06

    /// Скорость за такт 60 мс по расстоянию пальца до верхнего и нижнего края видимой части:
    /// минус — вверх. Полоса начинает работать, только когда палец из неё уже выходил (`armed`).
    public static func edgeSpeed(top: Double, bottom: Double, armed: Bool) -> Double {
        guard armed else { return 0 }
        if top < edgeTop { return -min(edgeMax, (edgeTop - top) / 5) }
        if bottom < edgeBottom { return min(edgeMax, (edgeBottom - bottom) / 5) }
        return 0
    }

    /// Палец вне обеих полос — с этой минуты края работают (веб `d.edgeOk`).
    public static func edgeArms(top: Double, bottom: Double) -> Bool { top >= edgeTop && bottom >= edgeBottom }

    // MARK: - Покачивание (веб `mbJiggle`, L3931–3939)

    /// Размах: от −0,8° до +0,8°.
    public static let jiggleAngle = 0.8
    /// Полупериод: `0,26 s … infinite alternate`.
    public static let jiggleHalf = 0.26

    /// Сдвиг фазы по месту в сетке, считая с 1 (CSS `nth-child`): каждая третья — −0,07 с,
    /// иначе каждая вторая — −0,13 с (правило `3n` стоит в CSS ниже и перебивает `2n`).
    public static func jiggleDelay(nth: Int) -> Double {
        if nth % 3 == 0 { return -0.07 }
        if nth % 2 == 0 { return -0.13 }
        return 0
    }

    /// Угол в градусах через `t` секунд от входа в режим: `ease-in-out`, туда-обратно.
    public static func jiggle(t: Double, nth: Int) -> Double {
        let tau = max(0, t - jiggleDelay(nth: nth)) / jiggleHalf
        let k = Int(tau.rounded(.down))
        let p = tau - Double(k)
        let e = CubicBezier.easeInOut.y(at: k % 2 == 0 ? p : 1 - p)
        return -jiggleAngle + 2 * jiggleAngle * e
    }
}

/// Кривая CSS `cubic-bezier(x1, y1, x2, y2)`: доля хода по доле времени. Нужна покачиванию и
/// сверке журнала жеста с числами беты.
public struct CubicBezier: Sendable, Equatable {
    public var x1, y1, x2, y2: Double
    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2 }

    /// CSS `ease-in-out`.
    public static let easeInOut = CubicBezier(0.42, 0, 0.58, 1)

    private func coord(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    /// Ход в момент `x` (0…1) — параметр ищется делением пополам, абсцисса кривой монотонна.
    public func y(at x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if coord(mid, x1, x2) < x { lo = mid } else { hi = mid }
        }
        return coord((lo + hi) / 2, y1, y2)
    }
}

extension RefLibrary {

    /// Порядок жанров ряда (веб `mbSetGenreOrder`): папки названных жанров садятся на их же
    /// места в `boards[]` в новом порядке жанров; внутри жанра папки сохраняют свой порядок,
    /// переезжает жанр целиком. Жанры, которых в списке нет (не влезли в ряд), не трогаются.
    public mutating func setGenreOrder(_ genres: [String]) {
        var rank: [String: Int] = [:]
        for (i, g) in genres.enumerated() where rank[g] == nil { rank[g] = i }
        func mine(_ b: RefBoard) -> Bool { b.kind == .tpl && b.genre.flatMap { rank[$0] } != nil }
        let want = boards.enumerated().filter { mine($0.element) }
            .sorted { (rank[$0.element.genre!]!, $0.offset) < (rank[$1.element.genre!]!, $1.offset) }
            .map(\.element)
        reseat(mine, want)
    }

    /// Порядок папок полки (веб `mbSetFolderOrder`). Знак, которого нет в фонде, — ряд
    /// разошёлся с фондом: ничего не трогаем, ответ `false`.
    @discardableResult
    public mutating func setFolderOrder(_ ids: [String]) -> Bool {
        let want = ids.compactMap { board($0) }
        guard want.count == ids.count, Set(ids).count == ids.count else { return false }
        let set = Set(ids)
        reseat({ set.contains($0.id) }, want)
        return true
    }

    /// Подборки садятся на те же места, что занимали (веб `mbReseat`): съёмочные доски и
    /// не названные подборки между ними не сдвигаются.
    private mutating func reseat(_ pick: (RefBoard) -> Bool, _ want: [RefBoard]) {
        var q = 0
        for i in boards.indices where pick(boards[i]) && q < want.count {
            boards[i] = want[q]; q += 1
        }
    }
}
