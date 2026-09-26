import LightPlanCore

/// Масштаб календаря (веб `calScope`). Год и год-12 — не масштабы, а слои
/// поверх «Съёмок» (веб `#yearOverlay`, `#year12Overlay`; итерация 22).
public enum CalScope: String, Sendable, CaseIterable {
    case month, week, day
}

/// Одно состояние на три вида «Съёмок» (итерация 21; веб `calScope`,
/// `calSel`, `calMonth`, `dayShift`). Виды не держат своих копий дня: месяц,
/// неделя и день читают отсюда, и переход между ними ничего не теряет.
///
/// Переживает перезапуск только свёрнутая сводка дня (`dayFold` снимка, живёт
/// в `AppModel`), как в вебе: календарь открывается на месяце и сегодняшнем
/// дне (Алексей, 24 сентября 2026). День «Света» и «Карты» — отдельный, листание
/// календаря его не двигает (веб `selDate` против `calSel`).
public struct PlannerState: Hashable, Sendable {
    public private(set) var scope: CalScope = .month
    /// Выбранный день (веб `calSel`).
    public private(set) var selected: CivilDate
    /// Показанный месяц, всегда первое число (веб `calMonth`). В месяце листается
    /// сам по себе, выбранный день при этом стоит.
    public private(set) var month: CivilDate
    /// Откуда въезжает лента дня: +1 — день вперёд, въезд справа; −1 — назад;
    /// 0 — без въезда. Потребляется один раз (`consumeDayShift`), как веб
    /// читает и сам обнуляет `dayShift`.
    public private(set) var dayShift = 0
    /// Раскрытая строка недели (веб `.wk-day-row.open`). Открыта всегда одна;
    /// перерисовка календаря (листание, смена масштаба) закрывает её, как веб
    /// пересобирает строки без `open`.
    public private(set) var weekOpen: CivilDate?

    public init(today: CivilDate) {
        selected = today
        month = Self.first(of: today)
    }

    // MARK: - Переходы

    /// Выбор масштаба в веере видов. Масштабы синхронны по выбранному дню.
    public mutating func setScope(_ s: CalScope) {
        guard s != scope else { return }
        scope = s
        month = Self.first(of: selected)
        weekOpen = nil
    }

    /// Свайп по экрану (веб `stepCal`): день — на сутки с въездом, неделя —
    /// на семь дней, месяц — только показанный месяц.
    public mutating func step(_ dir: Int) {
        switch scope {
        case .day:
            dayShift = dir
            selected = selected.adding(days: dir)
            month = Self.first(of: selected)
        case .week:
            selected = selected.adding(days: dir * 7)
            month = Self.first(of: selected)
        case .month:
            month = Self.addMonths(month, dir)
        }
        weekOpen = nil
    }

    /// Тап по дате в закреплённой неделе дня. Возвращает `true`, если день
    /// сменился — тогда щелчок отдачи (веб `tickClick`).
    @discardableResult
    public mutating func pickInStrip(_ day: CivilDate) -> Bool {
        dayShift = day > selected ? 1 : day < selected ? -1 : 0
        selected = day
        month = Self.first(of: day)
        return dayShift != 0
    }

    /// Тап по ячейке месяца. Первый тап выбирает; второй по уже выбранному
    /// дню своего месяца — вход в день (веб — через `partMonthIntoDay`,
    /// анимация перенесена в итерацию 29). Тап по дню соседнего месяца
    /// перелистывает на его месяц. Возвращает `true`, если вошли в день.
    @discardableResult
    public mutating func tapMonthCell(_ day: CivilDate) -> Bool {
        let outside = !Self.sameMonth(day, month)
        if !outside, day == selected {
            scope = .day
            month = Self.first(of: day)
            weekOpen = nil
            return true
        }
        selected = day
        if outside { month = Self.first(of: day) }
        return false
    }

    /// Тап по голове строки недели: выбирает день и раскрывает его строку,
    /// повторный тап сворачивает.
    public mutating func tapWeekRow(_ day: CivilDate) {
        selected = day
        weekOpen = weekOpen == day ? nil : day
    }

    /// «↺ сегодня» (веб `calNow`).
    public mutating func goToday(_ today: CivilDate) {
        month = Self.first(of: today)
        selected = today
        weekOpen = nil
    }

    /// Тап по числу в ленте месяцев года (итерация 22, веб `buildMonthEl`):
    /// в день. Раскол месяца на ленту дня (`partMonthIntoDay`) — движение,
    /// итерация 29, как и вход в день из месяца.
    public mutating func enterDay(_ day: CivilDate) {
        scope = .day
        selected = day
        month = Self.first(of: day)
        dayShift = 0
        weekOpen = nil
    }

    /// Тап по имени месяца в ленте года: в месяц. Выбран сегодняшний день,
    /// если это нынешний месяц, иначе первое число.
    public mutating func enterMonth(_ first: CivilDate, today: CivilDate) {
        scope = .month
        month = Self.first(of: first)
        selected = Self.sameMonth(first, today) ? today : month
        weekOpen = nil
    }

    /// Прочитать направление въезда и обнулить его.
    public mutating func consumeDayShift() -> Int {
        defer { dayShift = 0 }
        return dayShift
    }

    // MARK: - Что показывать

    /// Показывать ли «↺ сегодня» (веб `markScopeNow`): в дне и неделе — выбран
    /// не сегодняшний день, в месяце — показан не нынешний месяц.
    public func isAway(from today: CivilDate) -> Bool {
        switch scope {
        case .day, .week: selected != today
        case .month: !Self.sameMonth(month, today)
        }
    }

    /// Неделя выбранного дня, с понедельника (веб `weekStart`).
    public var week: [CivilDate] { Self.week(of: selected) }

    /// Сетка месяца: дни с понедельника первой недели до воскресенья последней
    /// (веб `renderCal`: хвост прошлого месяца, месяц, голова следующего).
    public var monthGrid: [CivilDate] {
        let start = Self.weekStart(month)
        let last = Self.addMonths(month, 1).adding(days: -1)
        let end = Self.weekStart(last).adding(days: 6)
        return (0...end.days(since: start)).map { start.adding(days: $0) }
    }

    // MARK: - Календарная арифметика

    /// Понедельник недели дня.
    public static func weekStart(_ d: CivilDate) -> CivilDate {
        d.adding(days: -((weekday(d) + 6) % 7))
    }

    public static func week(of d: CivilDate) -> [CivilDate] {
        let m = weekStart(d)
        return (0..<7).map { m.adding(days: $0) }
    }

    /// День недели как `Date.getDay()` веба: 0 — воскресенье.
    public static func weekday(_ d: CivilDate) -> Int {
        // 1970-01-01 — четверг (4).
        ((d.daysSince1970 % 7) + 7 + 4) % 7
    }

    public static func first(of d: CivilDate) -> CivilDate {
        CivilDate(year: d.year, month: d.month, day: 1)
    }

    public static func sameMonth(_ a: CivilDate, _ b: CivilDate) -> Bool {
        a.year == b.year && a.month == b.month
    }

    /// Первое число месяца через `n` месяцев.
    public static func addMonths(_ d: CivilDate, _ n: Int) -> CivilDate {
        let m0 = d.year * 12 + (d.month - 1) + n
        let y = m0 >= 0 ? m0 / 12 : (m0 - 11) / 12
        return CivilDate(year: y, month: m0 - y * 12 + 1, day: 1)
    }
}
