import Foundation
import LightPlanCore

// 30б.2в-5 — средний виджет «Braun» без маршрута: числа и правила «Семьи виджетов» Алексея (27.10)
// (`light_plan:Light_Plan/docs/widget_design_2026-10-26/`: `FamilySizes.dc.html` — числа, `_gen/family.js` — раскладка).
// Как и `WidgetBraun.swift`: только то, что не зависит от шрифта и SwiftUI, чтобы `swift test` проверял на любом хосте.
//
// Состояния доски: Б — съёмка идёт, маршрута нет (круг считает всю съёмку, справа свет); Г — съёмка сегодня впереди;
// Д — день без съёмок; Е — вечер после заката. В Г, Д, Е слева свет, справа неделя съёмок.

public enum BraunIdle {

    // MARK: Какое состояние

    /// Левая колонка и риски: Г — съёмка сегодня впереди, Д — день без съёмок, Е — после заката (ближайшее — завтрашний рассвет).
    public enum Form: Equatable, Sendable { case shootAhead, noShoots, evening }

    /// Ближайшая съёмка ещё не началась и стоит сегодня (по часам её места): единственный случай с рисками по периметру
    /// («риски есть только в день со съёмкой», Алексей 27.10). Завтрашняя съёмка день не делает съёмочным: периметр чист.
    public static func shootToday(_ f: WidgetFrame) -> Bool {
        guard f.kind == .upcoming, let p = f.primary else { return false }
        return p.dayOffset <= 0
    }

    /// Закат сегодня уже был: столбика оценки нет (заката сегодня больше не будет), ближайшее — завтрашний рассвет.
    public static func isNight(_ f: WidgetFrame) -> Bool {
        guard let set = f.day?.sunset else { return false }
        return f.now >= set
    }

    public static func form(_ f: WidgetFrame) -> Form {
        if shootToday(f) { return .shootAhead }
        return isNight(f) ? .evening : .noShoots
    }

    /// Съёмка идёт, а маршрута у неё нет: состояние Б (круг считает всю съёмку).
    public static func isBare(_ f: WidgetFrame) -> Bool {
        f.kind == .live && f.primary?.shoot.stops.isEmpty == true
    }

    // MARK: Б — круг на всю съёмку

    /// Сколько точек горит: `round(60 × осталось / вся съёмка)`. Точки гаснут с верха по часовой (горят последние перед верхней).
    public static func wholeShootLit(left: TimeInterval, total: TimeInterval) -> Int {
        guard total > 0 else { return 0 }
        return min(BraunDial.dots, max(0, Int((Double(BraunDial.dots) * left / total).rounded())))
    }

    /// Размер числа и единицы в круге по частям отсчёта: если в обеих частях «ч» и «мин» по две цифры и больше («10 ч 12 мин»), на
    /// больших часах 20 / 12 вместо 22 / 13 (`dial()` генератора доски); одна часть или однозначные часы — как у `BraunDial`.
    public static func countdownSizes(diameter d: Double, parts: [BraunDial.Part]) -> (number: Double, unit: Double) {
        let wide = parts.count > 1 && parts.allSatisfy { $0.value >= 10 }
        return BraunDial.isBig(diameter: d) && !wide ? (22, 13) : (20, 12)
    }

    // MARK: Свет слева (Г, Д, Е)

    public enum Role: Equatable, Sendable {
        /// Прошло — тусклый.
        case past
        /// Ближайшее — цвет текущей точки (янтарь / чёрный).
        case next
        /// Дальнее — основной текст.
        case far
    }

    /// Роль каждого из трёх времён света: прошедшее тусклое, ближайшее янтарное, дальнее основным цветом. Все прошли — все тусклые.
    /// Времени нет (полярные сутки) — оно считается прошедшим: «—» тусклым.
    public static func roles(now: Date, _ times: [Date?]) -> [Role] {
        let next = times.firstIndex { ($0 ?? .distantPast) > now }
        return times.indices.map { i in
            guard let next else { return .past }
            return i < next ? .past : (i == next ? .next : .far)
        }
    }

    /// Балл на столбике: доля заливки 0…1 от низа; чёрточки 6 × 0,5 на 20 / 40 / 60 / 80.
    public static func gaugeLevel(score: Int) -> Double { Double(min(100, max(0, score))) / 100 }
    public static let gaugeMarks = [20, 40, 60, 80]

    // MARK: Барабан света (Б)

    public enum LightKind: Equatable, Sendable { case sunrise, golden, sunset }

    public struct LightItem: Equatable, Sendable {
        public var kind: LightKind
        public var at: Date
        /// Завтрашний рассвет после заката: подпись «завтра».
        public var tomorrow: Bool
    }

    /// Барабан света: события сегодняшних суток по порядку — рассвет, золотой час, закат; в центре ближайшее к «сейчас» (на доске в 15:18 —
    /// золотой час), по сторонам предыдущее и следующее. После заката к ним добавляется завтрашний рассвет и встаёт в центр (на доске Е он
    /// ближайший). До рассвета в центре сегодняшний рассвет. Полярные сутки: событий нет, барабан пуст.
    /// Возвращает пять мест −2 … +2; нет события — `nil`, остальные стоят на своих местах (как у барабана маршрута).
    public static func lightDrum(_ f: WidgetFrame) -> [LightItem?] {
        var items: [LightItem] = []
        if let d = f.day {
            if let r = d.sunrise { items.append(LightItem(kind: .sunrise, at: r, tomorrow: false)) }
            if let g = d.golden { items.append(LightItem(kind: .golden, at: g, tomorrow: false)) }
            if let s = d.sunset { items.append(LightItem(kind: .sunset, at: s, tomorrow: false)) }
        }
        if isNight(f), let r = f.tomorrow?.sunrise { items.append(LightItem(kind: .sunrise, at: r, tomorrow: true)) }
        let centre = items.firstIndex { $0.at > f.now } ?? max(0, items.count - 1)
        return BraunDrum.neighbours(items, current: items.isEmpty ? nil : centre)
    }

    /// Пять строк барабана света: центр 28 (две строки — 42) на середине колонки, остальные четыре — одной высоты `(D − центр) / 4`
    /// (22 на круге 116; правило 27.10: дальние строки не мельчают, их гасит маска прозрачности по краям колонки).
    public static func drumSlots(diameter d: Double, centerLines: Int) -> [BraunDrum.Slot] {
        let hc = BraunDrum.centerHeight(lines: centerLines), hs = (d - hc) / 4, top = d / 2 - hc / 2
        return [BraunDrum.Slot(offset: -2, y: top - 2 * hs, height: hs), BraunDrum.Slot(offset: -1, y: top - hs, height: hs),
                BraunDrum.Slot(offset: 0, y: top, height: hc),
                BraunDrum.Slot(offset: 1, y: top + hc, height: hs), BraunDrum.Slot(offset: 2, y: top + hc + hs, height: hs)]
    }

    /// Маска прозрачности колонки высотой `d`: 0 / 0,3 / 0,55 / 0,8 / 0,95 / 1 на 0 / 4 / 9 / 15 / 20 / 26 от верхнего и нижнего края.
    public static func drumFade(height d: Double) -> [(at: Double, opacity: Double)] {
        let head: [(Double, Double)] = [(0, 0), (4, 0.3), (9, 0.55), (15, 0.8), (20, 0.95), (26, 1)]
        return head.map { (at: $0.0, opacity: $0.1) } + head.reversed().map { (at: d - $0.0, opacity: $0.1) }
    }

    // MARK: Неделя справа (Г, Д, Е)

    /// Строка списка недели: знак жанра, имена, и вторая строка «ср 28 · 11:00» (+ «· через 3 дня» у ближайшей).
    public struct WeekRow: Equatable, Sendable {
        public var id: String
        public var genre: String?
        public var names: String
        public var day: String
        public var time: String
        /// «через 3 дня» — только у ближайшей строки и только если съёмка не сегодня и не завтра (там день уже сказан словом).
        public var relative: String?
        public var near: Bool

        public init(id: String, genre: String?, names: String, day: String, time: String, relative: String?, near: Bool) {
            self.id = id; self.genre = genre; self.names = names; self.day = day; self.time = time; self.relative = relative; self.near = near
        }

        /// Вторая строка: «ср 28 · 11:00 · через 3 дня».
        public var line2: String { ([day, time] + (relative.map { [$0] } ?? [])).joined(separator: " · ") }
    }

    public static func weekRows(_ f: WidgetFrame) -> [WeekRow] {
        f.week.enumerated().map { i, s in
            let named = (s.shoot.names ?? "").trimmingCharacters(in: .whitespaces)
            let day: String
            switch s.dayOffset {
            case ..<1: day = f.words[.today].lowercased()
            case 1: day = f.words[.tomorrow].lowercased()
            default: day = dayAndNumber(s.shoot.startDate, in: s.zone, f)
            }
            return WeekRow(id: s.id, genre: s.shoot.genre, names: named.isEmpty ? s.shoot.title : named, day: day,
                           time: f.clock(s.shoot.startDate, in: s.zone), relative: i == 0 && s.dayOffset >= 2 ? f.words.inDays(s.dayOffset) : nil,
                           near: i == 0)
        }
    }

    /// «сб 31»: короткий день недели (строчными, как на доске) и число по часам места.
    public static func dayAndNumber(_ date: Date, in tz: TimeZone, _ f: WidgetFrame) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return "\(f.weekday(date, in: tz).lowercased()) \(cal.component(.day, from: date))"
    }

    /// Строка вместо списка, если съёмок на неделе нет: «до сб 31 съёмок нет». Съёмки есть — `nil`; места нет — `nil`.
    public static func emptyWeekLine(_ f: WidgetFrame) -> String? {
        guard f.week.isEmpty, let end = f.weekEnd else { return nil }
        return f.words[.noShootsUntil].replacingOccurrences(of: "{d}", with: dayAndNumber(end, in: f.zone, f))
    }

    // MARK: Что оценивает виджет (30б.2в-6)

    /// Событие, которое оценивает средний вид, и его оценка. Слова Алексея 27.10: «виджет до конца утреннего золотого часа показывает
    /// рассвет, потом закат, после заката — завтрашний рассвет».
    public struct RatedEvent: Equatable, Sendable {
        public var kind: LightKind
        /// Завтрашний рассвет после заката.
        public var tomorrow: Bool
        public var at: Date
        /// Балл 0…100 того события; `nil` — часа в прогнозе нет (нет столбика).
        public var score: Int?
        /// Категория того события; `nil` — прогноза нет (нет слова).
        public var quality: DayQuality?
    }

    /// Какое событие виджет оценивает в момент `f.now` (место «Света», его сутки):
    /// - после заката — рассвет завтра;
    /// - до конца утреннего золотого часа (солнце ниже 6°; нет такого — до самого восхода) — рассвет сегодня, и ночью до рассвета тоже;
    /// - иначе, до заката, — закат сегодня.
    /// В полночь «сегодня» сменяется, а событие нет: вчерашнее «завтра» становится сегодняшним рассветом. Нет события (полярные сутки:
    /// ни восхода, ни заката) — `nil`.
    /// Слово: у заката — категория дня (как было); у рассвета — «туман», если утром туман, иначе категория рассветного балла.
    public static func ratedEvent(_ f: WidgetFrame) -> RatedEvent? {
        guard let today = f.day else { return nil }
        if let set = today.sunset, f.now >= set {
            guard let rise = f.tomorrow?.sunrise else { return nil }
            return event(.sunrise, tomorrow: true, at: rise, rating: f.tomorrowRating)
        }
        if let rise = today.sunrise, f.now < (today.goldenEnd ?? rise) {
            return event(.sunrise, tomorrow: false, at: rise, rating: f.rating)
        }
        if let set = today.sunset { return event(.sunset, tomorrow: false, at: set, rating: f.rating) }
        return nil
    }

    private static func event(_ kind: LightKind, tomorrow: Bool, at: Date, rating: WidgetFeed.Rating?) -> RatedEvent {
        guard let rating else { return RatedEvent(kind: kind, tomorrow: tomorrow, at: at, score: nil, quality: nil) }
        if kind == .sunset { return RatedEvent(kind: kind, tomorrow: tomorrow, at: at, score: rating.score, quality: rating.category) }
        let q: DayQuality? = rating.category == .fog ? .fog : rating.sunrise.map(SunsetScore.category)
        return RatedEvent(kind: kind, tomorrow: tomorrow, at: at, score: rating.sunrise, quality: q)
    }

    /// Слово неба; нет прогноза на это событие — `nil`, строки нет.
    public static func ratingWord(_ f: WidgetFrame) -> String? {
        ratedEvent(f)?.quality.map { f.words.sky($0) }
    }

    /// «рассвет · яркий» / «закат · серый» — строка оценки по шаблону языка (`skyRise`/`skySet`), без «завтра»: что рассвет завтра, видно и так
    /// (Алексей 30.10). Нет прогноза — `nil`.
    public static func ratingLine(_ f: WidgetFrame) -> String? {
        guard let e = ratedEvent(f), let q = e.quality else { return nil }
        return f.words[e.kind == .sunrise ? .skyRise : .skySet].replacingOccurrences(of: "{t}", with: f.words.sky(q))
    }

    /// Высоты строк списка: ближайшая и остальные, зазор 2 (на 170 pt — 46 / 40, три строки = 130; на 158 pt — 44 / 38, чтобы три строки
    /// остались в 126 pt между полями: числа доски на 158 pt не заданы).
    public static func weekRowHeights(plateHeight h: Double) -> (near: Double, other: Double) { h >= 170 ? (46, 40) : (44, 38) }
    public static let weekRowGap = 2.0
}
