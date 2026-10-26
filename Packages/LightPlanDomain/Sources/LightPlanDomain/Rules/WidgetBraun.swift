import Foundation

// 30б.2в-4 — правила среднего и малого виджета «Braun»: числа и правила демки Алексея 26.10
// (`light_plan:Light_Plan/docs/widget_design_2026-10-26/`: `Spec.dc.html` — числа, `Widget.dc.html` — формулы `renderVals()`, `ticks()`, `fit()`).
// Здесь только то, что не зависит от шрифта и SwiftUI, чтобы `swift test` проверял его на любом хосте; виды и палитра — в `LightPlanWidget/Views`.

/// Плашка: поля, скругление, шапка и диаметр круга.
public enum BraunPlate {
    /// Поля содержимого со всех сторон.
    public static let pad = 16.0
    /// Знак жанра 16 и зазор до имён 6: имена начинаются правее поля на 22.
    public static let signAndGap = 22.0

    /// Скругление плашки: 22 у 364 × 170 (Pro Max), 20,5 у 338 × 158 (спецификация); между ними — по высоте, за пределами — как у ближайшей.
    public static func cornerRadius(plateHeight h: Double) -> Double { 20.5 + 1.5 * min(1, max(0, (h - 158) / 12)) }

    /// Высота шапки: одна строка имён — 18, две (малый) — 32.
    public static func headerHeight(lines: Int) -> Double { lines > 1 ? 32 : 18 }

    /// Диаметр часов точки: высота − поля − шапка − 4 (116 на 364 × 170, 104 на 338 × 158).
    public static func dialDiameter(plateHeight h: Double, headerHeight: Double) -> Double { h - 2 * pad - headerHeight - 4 }
}

/// Часы точки: 60 точек по кругу, горят оставшиеся минуты (правило А — «последний час»).
public enum BraunDial {
    public static let dots = 60

    /// Сколько точек горит: `min(60, осталось минут)`.
    public static func lit(minutesLeft m: Int) -> Int { min(dots, max(0, m)) }

    /// Горит ли точка `k` (0 — сверху, дальше по часовой): горят последние `lit` точек перед верхней, то есть считая против часовой от 60.
    public static func isLit(dot k: Int, minutesLeft m: Int) -> Bool { k >= dots - lit(minutesLeft: m) }

    /// Диаметр точки: каждая пятая крупнее.
    public static func dotSize(_ k: Int) -> Double { k % 5 == 0 ? 3.2 : 2 }

    /// Радиус, на котором стоят центры точек.
    public static func dotRadius(diameter d: Double) -> Double { d / 2 - 6 }

    /// Центр точки `k` от центра часов (экранные оси: y вниз).
    public static func dotCenter(_ k: Int, diameter d: Double) -> (x: Double, y: Double) {
        let a = Double(k) * 6 * .pi / 180, r = dotRadius(diameter: d)
        return (r * sin(a), -r * cos(a))
    }

    /// Крупные ли часы: от 112 числа 22 / 13, меньше — 20 / 12.
    public static func isBig(diameter d: Double) -> Bool { d >= 112 }
    public static func numberSize(diameter d: Double) -> Double { isBig(diameter: d) ? 22 : 20 }
    public static func unitSize(diameter d: Double) -> Double { isBig(diameter: d) ? 13 : 12 }

    public enum Unit: Sendable { case hour, minute }
    public struct Part: Equatable, Sendable {
        public var value: Int
        public var unit: Unit
        public init(_ value: Int, _ unit: Unit) { self.value = value; self.unit = unit }
    }

    /// Отсчёт в центре: «12 мин»; от часа — «1 ч 42 мин», ровный час — «2 ч»; ноль — «0 мин».
    public static func countdown(minutes m: Int) -> [Part] {
        let n = max(0, m)
        guard n >= 60 else { return [Part(n, .minute)] }
        return [Part(n / 60, .hour)] + (n % 60 != 0 ? [Part(n % 60, .minute)] : [])
    }
}

/// Риски по периметру: вся съёмка, 150 рисок от середины верха по часовой.
public enum BraunTicks {
    public static let count = 150
    /// Внешний конец риски — в 3 от края плашки.
    public static let outerInset = 3.0
    public static let minorLength = 4.0, minorWidth = 1.25
    public static let hourLength = 7.5, hourWidth = 1.75

    /// Номера рисок-«часов»: для каждого ровного часа (по часам места) от начала съёмки до конца — ближайшая риска.
    /// `start` — начало съёмки в секундах от полуночи по часам места (можно с днями), `duration` — длина съёмки в секундах.
    public static func hourIndexes(start: Double, duration: Double) -> Set<Int> {
        guard duration > 0 else { return [] }
        var out = Set<Int>()
        var h = (start / 3600).rounded(.up) * 3600
        while h <= start + duration {
            out.insert(Int(((h - start) / duration * Double(count)).rounded()) % count)
            h += 3600
        }
        return out
    }

    /// Прошла ли риска `i`: её момент раньше, чем прошло с начала.
    public static func isPast(index i: Int, duration: Double, elapsed: Double) -> Bool {
        Double(i) / Double(count) * duration < elapsed
    }
}

/// Барабан маршрута: пять строк (центр на подложке и по две соседние), высоты и поля.
public enum BraunDrum {
    public struct Slot: Equatable, Sendable {
        /// −2 … 2 от текущей точки.
        public var offset: Int
        public var y: Double
        public var height: Double
    }

    /// Поля строки, колонка времени, зазор: имена с одного x.
    public static let rowPadding = 10.0, timeColumn = 46.0, gap = 8.0
    /// Радиус подложки центра.
    public static let pillRadius = 9.0
    /// Колонка барабана начинается правее часов на 14.
    public static let columnGap = 14.0

    /// Ширина под название в строке колонки шириной `column`.
    public static func nameWidth(column: Double) -> Double { column - rowPadding - timeColumn - gap - rowPadding }

    /// Высоты: центр 28 (две строки — 42), ±1 — 22 (на малых часах 21), ±2 — 17 (16).
    public static func centerHeight(lines: Int) -> Double { lines > 1 ? 42 : 28 }
    public static func nearHeight(diameter d: Double) -> Double { BraunDial.isBig(diameter: d) ? 22 : 21 }
    public static func farHeight(diameter d: Double) -> Double { BraunDial.isBig(diameter: d) ? 17 : 16 }

    /// Пять строк колонки высотой `diameter`: центр стоит на середине, остальные по сторонам встык; лишнее срезает колонка.
    public static func slots(diameter d: Double, centerLines: Int) -> [Slot] {
        let near = nearHeight(diameter: d), far = farHeight(diameter: d), hc = centerHeight(lines: centerLines)
        let top = d / 2 - hc / 2
        return [Slot(offset: -2, y: top - near - far, height: far), Slot(offset: -1, y: top - near, height: near),
                Slot(offset: 0, y: top, height: hc),
                Slot(offset: 1, y: top + hc, height: near), Slot(offset: 2, y: top + hc + near, height: far)]
    }

    /// Точки вокруг текущей (−2 … +2); нет соседа — `nil`, пустая строка, остальные стоят на своих местах.
    /// Нет текущей точки (съёмка идёт, а первая точка ещё не началась) — центр пуст, ниже идут ближайшие.
    public static func neighbours<T>(_ items: [T], current: Int?) -> [T?] {
        let c = current ?? -1
        return (-2...2).map { o in items.indices.contains(c + o) ? items[c + o] : nil }
    }
}

/// Подбор шрифта по ширине (`fit()` демки): первый размер цепочки, в который текст влез; шаг с несколькими строками берётся сразу;
/// не влезло нигде — последний.
public enum BraunFit {
    public struct Step: Equatable, Sendable {
        public var size: Double
        public var lines: Int
        public var lineHeight: Double
        public init(_ size: Double, lines: Int = 1, lineHeight: Double) { self.size = size; self.lines = lines; self.lineHeight = lineHeight }
    }

    /// Имена в шапке среднего: 15 → 13 → 12; в малом: 15 → 13 → 13 в две строки.
    public static let headerMedium = [Step(15, lineHeight: 18), Step(13, lineHeight: 18), Step(12, lineHeight: 18)]
    public static let headerSmall = [Step(15, lineHeight: 18), Step(13, lineHeight: 18), Step(13, lines: 2, lineHeight: 16)]
    /// Центр барабана: 16 → 14 → 13 в две строки; ±1: 13 → 12 → 11; ±2: 11 → 10 (соседние строки в одну).
    public static let centerRow = [Step(16, lineHeight: 20), Step(14, lineHeight: 18), Step(13, lines: 2, lineHeight: 16)]
    public static let nearRow = [Step(13, lineHeight: 18), Step(12, lineHeight: 18), Step(11, lineHeight: 18)]
    public static let farRow = [Step(11, lineHeight: 18), Step(10, lineHeight: 18)]

    /// `width(size)` — ширина текста этим размером в одну строку.
    public static func pick(_ chain: [Step], avail: Double, width: (Double) -> Double) -> Step {
        for step in chain where step.lines > 1 || width(step.size) <= avail { return step }
        return chain[chain.count - 1]
    }
}

/// Окошко Braun со сколько осталось свадьбы. Цифры тикают сами (`Text(timerInterval:)`), а часы в них включаются раз — на записи ленты,
/// поэтому формат выбирается так, чтобы он держался всю жизнь записи (запись — минута, `WidgetFeed.timeline`): запись, которая начинается,
/// когда осталось больше часа, кончается не раньше, чем останется час, и «10:42:00» не превращается в «0:59:59» (ревью GPT к 89cc5c1).
public enum BraunWindow {
    /// Красный флажок Braun — шеврон слева от окошка, как на кварцевых Braun с датой на трёх часах: по центру окошка по высоте, остриём к окошку
    /// (слова Алексея 26.10; числа — оркестратора). Размер 7 × 12, от острия до левого края окошка 3.
    public static let flagWidth = 7.0, flagHeight = 12.0, flagGap = 3.0
    /// Сколько ширины шапки занимают флажок и зазор до него (7 + 3).
    public static var flagReserve: Double { flagWidth + flagGap }

    /// Левый край флажка при окошке с левым краем `windowX`.
    public static func flagX(windowX: Double) -> Double { windowX - flagGap - flagWidth }
    /// Верх флажка при окошке высотой 18 с верхом `windowY`: по центру.
    public static func flagY(windowY: Double, windowHeight: Double = 18) -> Double { windowY + (windowHeight - flagHeight) / 2 }

    /// Шеврон в прямоугольнике `width × height`: (0,0) → (½w,0) → (w,½h) → (½w,h) → (0,h) → (½w,½h); слева V-вырез.
    public static func flagPoints(width w: Double, height h: Double) -> [(x: Double, y: Double)] {
        [(0, 0), (w / 2, 0), (w, h / 2), (w / 2, h), (0, h), (w / 2, h / 2)]
    }

    /// С часами («10:42:00») — только пока осталось больше часа; ровно час и меньше — «60:00», «42:00».
    public static func showsHours(remaining: TimeInterval) -> Bool { remaining > 3600 }

    /// Та же строка, что рисует система, статично (снимки, тесты).
    public static func text(remaining: TimeInterval) -> String {
        let s = Int(max(0, remaining).rounded(.down))
        return showsHours(remaining: remaining)
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
