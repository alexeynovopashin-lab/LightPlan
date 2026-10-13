import Foundation

/// Перестановка кадров в папке мудборда пальцем (веб `mbGridDrag` … `mbFlipReorder`, L21725–21927; справка 28,
/// п. 2.9, строка «драг кадра в папке»). Чистые правила без экрана: когда сетку можно переставлять, раскладка
/// масонри для любого порядка, над чьим местом палец, шаг перестановки, автопрокрутка у края.
///
/// Удержание 0,42 с поднимает кадр; отпустили, не двигая, — лист кадра (как было); двигали — кадр лёг на новое
/// место и порядок записан, если сменился. Сдвиг больше 8 pt до подъёма отдаёт палец прокрутке.
public enum MbFrameDragRules {
    /// Удержание до подъёма, с (веб `setTimeout(…, 420)`, L21823).
    public static let hold: TimeInterval = 0.42
    /// Сдвиг до подъёма, после которого удержание отменяется: `|dx| + |dy| > 8` (L21835).
    public static let slop: Double = 8
    /// Сдвиг после подъёма, с которого жест — перенос, а не «подержал и отпустил» (лист кадра). У веба — любое
    /// `pointermove` («хоть на пиксель», L21869); палец на стекле дрожит на доли точки, поэтому порог 2 pt.
    public static let movedSlop: Double = 2
    /// Масштаб поднятого кадра (`scale(1.06)`, L21818).
    public static let liftScale: Double = 1.06
    /// Полоса у края папки, в которой она листается, и шаг за кадр 60 Гц (`edge = 56, speed = 12`, L21786).
    public static let edge: Double = 56
    public static let edgeStep: Double = 12
    /// Кадр rAF веба: шаг 12 pt — за 1/60 с.
    public static let edgeTick: Double = 1.0 / 60
    /// Зазор масонри (`column-gap` и отступ между плитками, `.mb-grid`).
    public static let gap: Double = 8

    /// Переставлять можно только голую сетку: без выбора, без раздела и поиска, с ручным порядком — иначе место
    /// в отфильтрованном списке разошлось бы с местом в `items[]` (веб `reorderable`, L23085).
    public static func reorderable(picking: Bool, filtered: Bool, sort: Int) -> Bool {
        !picking && !filtered && sort == 0
    }

    /// Место плитки в сетке, в координатах сетки (pt).
    public struct Cell: Sendable, Equatable {
        public var id: String
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double
        public init(id: String, x: Double, y: Double, w: Double, h: Double) {
            self.id = id; self.x = x; self.y = y; self.w = w; self.h = h
        }
        public var midX: Double { x + w / 2 }
        public var midY: Double { y + h / 2 }
    }

    /// Раскладка масонри в две колонки (`column-count: 2`): первые `n` плиток — первая колонка сверху вниз,
    /// остальные — вторая; `n` — `RefColumns.firstColumnCount`. `ids` и `heights` одной длины (плитки «+» и
    /// корзины — со своими ключами в конце). Ответ — места в том же порядке и высота сетки.
    public static func layout(ids: [String], heights: [Double], column w: Double) -> (cells: [Cell], height: Double) {
        let n = RefColumns.firstColumnCount(heights: heights)
        var cells: [Cell] = []
        var ys = [0.0, 0.0]
        for (i, h) in heights.enumerated() {
            let c = i < n ? 0 : 1
            cells.append(Cell(id: i < ids.count ? ids[i] : "", x: Double(c) * (w + gap), y: ys[c], w: w, h: h))
            ys[c] += h + gap
        }
        let tall = ys.map { $0 > 0 ? $0 - gap : 0 }.max() ?? 0
        return (cells, tall)
    }

    /// Над чьим местом палец (веб `cellAt`): точка внутри прямоугольника, края включены; поднятый кадр в
    /// поиске не участвует — его места в `cells` нет.
    public static func hit(_ x: Double, _ y: Double, cells: [Cell]) -> String? {
        cells.first { x >= $0.x && x <= $0.x + $0.w && y >= $0.y && y <= $0.y + $0.h }?.id
    }

    /// Шаг перестановки (веб `track`): палец над соседом `over` — поднятый кадр встаёт на его место
    /// (`splice` из прежнего места и вставка на место соседа). С кем только что поменялись (`skip`), того не
    /// трогаем, пока палец с него не ушёл: кадры разной высоты, и пара менялась бы туда-обратно на каждом
    /// движении. Палец ни над кем — `skip` снимается.
    public struct Step: Sendable, Equatable {
        public var order: [String]
        public var skip: String?
        public var changed: Bool
    }

    public static func step(_ order: [String], moving id: String, over: String?, skip: String?) -> Step {
        guard let over else { return Step(order: order, skip: nil, changed: false) }
        if over == skip { return Step(order: order, skip: skip, changed: false) }
        guard let from = order.firstIndex(of: id), let to = order.firstIndex(of: over), from != to else {
            return Step(order: order, skip: skip, changed: false)
        }
        var o = order
        o.remove(at: from)
        o.insert(id, at: to)
        return Step(order: o, skip: over, changed: true)
    }

    /// Край включается, лишь когда палец из полосы вышел (веб `edgeOk`): до первого движения удержание у края
    /// само листало папку. `top`/`bottom` — расстояния от пальца до верхнего и нижнего края видимой части.
    public static func edgeArms(top: Double, bottom: Double) -> Bool { top >= edge && bottom >= edge }

    /// Скорость автопрокрутки, pt/с (минус — вверх): 12 pt за кадр 60 Гц, пока палец в полосе 56.
    public static func edgeSpeed(top: Double, bottom: Double, armed: Bool) -> Double {
        guard armed else { return 0 }
        if top < edge { return -edgeStep / edgeTick }
        if bottom < edge { return edgeStep / edgeTick }
        return 0
    }
}

extension RefLibrary {
    /// Новый порядок кадров подборки после перестановки пальцем (веб `board.items = order`). Пишется, только если
    /// это те же ссылки в другом порядке: подборку могли поменять за время жеста (импорт Pinterest, лист кадра), и
    /// старый порядок затёр бы новые кадры. Тот же порядок — `false`, ничего не меняется.
    @discardableResult
    public mutating func reorder(_ order: [String], of boardId: String, now: Double? = nil) -> Bool {
        guard let i = boards.firstIndex(where: { $0.id == boardId }), order != boards[i].items,
              order.sorted() == boards[i].items.sorted() else { return false }
        boards[i].items = order
        if let now { boards[i].mt = now }
        return true
    }
}
