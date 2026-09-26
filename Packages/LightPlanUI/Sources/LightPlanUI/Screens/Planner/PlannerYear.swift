import Foundation
import LightPlanCore
import LightPlanDomain

/// Счёт года и статистики (итерация 22; веб `renderYear`, `buildMiniMonth12`,
/// `renderMonthBars`, `renderOverloadSignal`, `renderDeliveryStats`,
/// `renderSearch`). Чистые функции: экран подаёт записи, сегодня и ступень
/// сдачи, получает числа. Справка по вебу — `docs/native_22_planner_web_spec.md`.
enum YearMath {

    // MARK: - Сетка месяца

    /// Пустых клеток перед первым числом (неделя с понедельника) и дней в месяце.
    /// Хвоста после последнего числа у веба нет — строка обрывается.
    static func monthShape(year: Int, month: Int) -> (lead: Int, days: Int) {
        let first = CivilDate(year: year, month: month, day: 1)
        let next = PlannerState.addMonths(first, 1)
        return ((PlannerState.weekday(first) + 6) % 7, next.days(since: first))
    }

    // MARK: - Год

    /// Рабочие записи года (веб `all`: встречи и события не съёмки).
    static func work(_ sessions: [Session], year: Int) -> [Session] {
        sessions.filter { $0.day.year == year && $0.kind.isWork }
    }

    /// Съёмок в каждом дне месяца по дню начала (веб `counts` в
    /// `buildMiniMonth12`): ночная съёмка метит только свой первый день.
    static func dayCounts(_ sessions: [Session], year: Int, month: Int) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for s in sessions where s.kind.isWork && s.day.year == year && s.day.month == month {
            out[s.day.day, default: 0] += 1
        }
        return out
    }

    /// Итог года (веб `#yearSum`): сколько съёмок и ближайшая, сегодняшняя
    /// тоже впереди. Порядок равных — порядок записей (сортировка веба устойчива).
    static func summary(_ sessions: [Session], year: Int, today: CivilDate) -> (count: Int, next: CivilDate?) {
        let all = work(sessions, year: year)
        let next = all.filter { $0.day >= today }.map(\.day).min()
        return (all.count, next)
    }

    // MARK: - Статистика: занятость по месяцам

    struct MonthBar: Equatable {
        let count: Int
        /// Доля полосы, % (веб `max(8, round(n/maxN·100))`), 0 — пусто.
        let percent: Int
        /// Самая тяжёлая ступень сдачи месяца; первая при равных.
        let worst: DeliveryStatus?
    }

    /// Двенадцать полос (веб `renderMonthBars`). Считает все записи месяца,
    /// встречи тоже — так у веба (у всех прочих чисел года встречи не в счёт);
    /// цвет у встречи серый нулевой ступени и на цвет месяца не влияет.
    static func monthBars(_ sessions: [Session], year: Int,
                          status: (Session) -> DeliveryStatus) -> [MonthBar] {
        var n = [Int](repeating: 0, count: 12)
        var worst = [DeliveryStatus?](repeating: nil, count: 12)
        for s in sessions where s.day.year == year {
            let m = s.day.month - 1
            n[m] += 1
            let st = status(s)
            if worst[m] == nil || st.rank > worst[m]!.rank { worst[m] = st }
        }
        let maxN = max(1, n.max() ?? 0)
        return (0..<12).map { m in
            let pct = n[m] > 0 ? max(8, Int((Double(n[m]) / Double(maxN) * 100).rounded())) : 0
            return MonthBar(count: n[m], percent: pct, worst: worst[m])
        }
    }

    // MARK: - Статистика: жанры

    /// Отснятое и предстоящее по жанрам (веб `genreLine`): по убыванию числа,
    /// равные — в порядке первого появления.
    static func genreCounts(_ list: [Session]) -> [(genre: Genre, count: Int)] {
        var order: [Genre] = [], by: [Genre: Int] = [:]
        for s in list {
            guard let g = s.genre else { continue }
            if by[g] == nil { order.append(g) }
            by[g, default: 0] += 1
        }
        return order.enumerated()
            .sorted { by[$0.element]! != by[$1.element]! ? by[$0.element]! > by[$1.element]! : $0.offset < $1.offset }
            .map { ($0.element, by[$0.element]!) }
    }

    // MARK: - Статистика: прибыль

    struct Profit: Equatable {
        /// Прибыль года в домашней валюте.
        let amount: Decimal
        /// Нарастающим итогом по месяцам — спарклайн кончается на `amount`.
        let cumulative: [Decimal]
        /// Другие валюты, каждая своей суммой, без пересчёта.
        let others: [Other]
        struct Other: Equatable { let currency: Currency; let sum: Decimal }
    }

    /// Прибыль года (веб: `yearProfitAmt`, `yearProfitCum`, `yearProfitOther`).
    /// Все рабочие записи года, и будущие, и неоплаченные — это ожидаемое.
    static func profit(_ sessions: [Session], year: Int, home: Currency) -> Profit {
        let all = work(sessions, year: year)
        let net = { (s: Session) in Money.net(of: s, among: sessions) }
        let homeAll = all.filter { Money.currency(of: $0, home: home) == home }
        var run: Decimal = 0, cum: [Decimal] = []
        for m in 1...12 {
            for s in homeAll where s.day.month == m { run += net(s) }
            cum.append(run)
        }
        let others = Money.sumByCurrency(all, home: home, amount: net)
            .filter { $0.currency != home }
            .map { Profit.Other(currency: $0.currency, sum: $0.sum) }
        return Profit(amount: homeAll.reduce(0) { $0 + net($1) }, cumulative: cum, others: others)
    }

    /// Точки спарклайна (веб `sparkPoints(vals, 320, 42, 4)`): ноль всегда в
    /// шкале, x — равными шагами, y — вниз.
    static func sparkPoints(_ vals: [Double], width w: Double = 320, height h: Double = 42,
                            pad: Double = 4) -> [CGPoint] {
        guard !vals.isEmpty else { return [] }
        let lo = min(0, vals.min()!), hi = max(0, vals.max()!)
        let range = hi - lo == 0 ? 1 : hi - lo
        let n = vals.count
        return vals.enumerated().map { i, v in
            let x = pad + (w - 2 * pad) * (n > 1 ? Double(i) / Double(n - 1) : 0)
            let y = pad + (h - 2 * pad) * (1 - (v - lo) / range)
            return CGPoint(x: (x * 10).rounded() / 10, y: (y * 10).rounded() / 10)
        }
    }

    // MARK: - Статистика: перегруз

    /// Порог веба (`OVERLOAD_*`): три просроченные сдачи и три съёмки впереди
    /// за 30 дней. Числа веба помечены «не откалиброваны» — переносятся как есть.
    static let overloadOverdue = 3, overloadUpcoming = 3, overloadWindowDays = 30

    /// Просрочено и впереди (веб `renderOverloadSignal`) — факты сегодняшнего
    /// дня, не года. Сегодняшняя съёмка — не «впереди»: у веба дата — полночь,
    /// а сейчас уже позже. `nil` — сигнала нет.
    static func overload(_ sessions: [Session], now: Date, zone: TimeZone,
                         deadline: (Session) -> CivilDate?) -> (overdue: Int, upcoming: Int)? {
        let t = now.timeIntervalSince1970 * 1000
        let soon = t + Double(overloadWindowDays) * 86_400_000
        var overdue = 0, upcoming = 0
        for s in sessions where s.kind.isWork {
            if !s.delivered, let dl = deadline(s), midnight(dl, zone) < t { overdue += 1 }
            let d = midnight(s.day, zone)
            if d > t && d <= soon { upcoming += 1 }
        }
        guard overdue >= overloadOverdue, upcoming >= overloadUpcoming else { return nil }
        return (overdue, upcoming)
    }

    // MARK: - Статистика: сроки сдачи

    /// Меньше пяти сдач — угадывание, не статистика (веб `DELV_STAT_MIN`).
    static let deliveryStatMin = 5

    /// Жанры, которые сдаются позже срока (веб `renderDeliveryStats`): за всё
    /// время, по записям с меткой сдачи и сроком. Срок — по нынешним
    /// настройкам, полночь дня срока; средняя меньше полудня — «вовремя»,
    /// о раньше срока экран молчит (Алексей: «не нужно предлагать сокращать»).
    static func lateGenres(_ sessions: [Session], zone: TimeZone,
                           deadline: (Session) -> CivilDate?) -> [(genre: Genre, days: Int)] {
        var order: [Genre] = [], by: [Genre: [Double]] = [:]
        for s in sessions {
            guard let at = s.deliveredAt, let dl = deadline(s), let g = s.genre else { continue }
            if by[g] == nil { order.append(g) }
            by[g, default: []].append((at.timeIntervalSince1970 * 1000 - midnight(dl, zone)) / 86_400_000)
        }
        var rows: [(genre: Genre, days: Int, at: Int)] = []
        for (k, g) in order.enumerated() {
            let arr = by[g]!
            guard arr.count >= deliveryStatMin else { continue }
            let avg = arr.reduce(0, +) / Double(arr.count)
            guard avg >= 0.5 else { continue }
            let n = Int((avg + 0.5).rounded(.down))   // Math.round
            guard n >= 1 else { continue }
            rows.append((g, n, k))
        }
        return rows.sorted { $0.days != $1.days ? $0.days > $1.days : $0.at < $1.at }.map { ($0.genre, $0.days) }
    }

    /// Полночь дня в поясе, миллисекунды (веб `new Date(y, m, d)`).
    static func midnight(_ d: CivilDate, _ zone: TimeZone) -> Double {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        let date = c.date(from: DateComponents(year: d.year, month: d.month, day: d.day)) ?? Date()
        return date.timeIntervalSince1970 * 1000
    }

    // MARK: - Поиск

    /// Основа слова (веб `searchStem`): одна-две гласные или знака на конце
    /// срезаются, если остаётся не меньше пяти букв — «свадьбу» находит
    /// «свадьба», «Ольга» остаётся целой. Латиница не тронута.
    static func stem(_ q: String) -> String {
        let re = try! NSRegularExpression(pattern: "^(.*[^аеёиоуыэюяйьъ])[аеёиоуыэюяйьъ]{1,2}$")
        let ns = q as NSString
        guard let m = re.firstMatch(in: q, range: NSRange(location: 0, length: ns.length)) else { return q }
        let base = ns.substring(with: m.range(at: 1))
        return (base as NSString).length >= 5 ? base : q
    }

    /// Найденное (веб `renderSearch`): клиент, имя съёмки, место и город —
    /// одной строкой, подстрока без учёта регистра. Новые даты первыми,
    /// равные — в порядке записей. Встречи в поиске есть, события — если
    /// включён их слой.
    static func search(_ query: String, in sessions: [Session], eventsLayer: Bool,
                       typeName: (Session) -> String) -> [Session] {
        let qs = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !qs.isEmpty else { return [] }
        let needle = stem(qs)
        return sessions.enumerated()
            .filter { _, s in
                guard s.isShown(eventsLayer: eventsLayer) else { return false }
                let hay = (s.contact + " " + typeName(s) + " " + s.place + " " + s.placeTown).lowercased()
                return hay.contains(needle)
            }
            .sorted { $0.element.day != $1.element.day ? $0.element.day > $1.element.day : $0.offset < $1.offset }
            .map(\.element)
    }
}
