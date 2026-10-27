import Foundation
import LightPlanCore

/// Форма виджета (WidgetKit `WidgetFamily` без WidgetKit — Domain его не знает): от формы зависит, какие моменты нужны ленте.
public enum WidgetShape: Sendable, CaseIterable {
    case small, medium, large, inline, circular, rectangular
}

/// Что виджет показывает в данный момент (30б.2): одно правило для малого, среднего и строки экрана блокировки.
///
/// Слова Алексея (24.10): «Нет съемок — время рассвета, затем время заката. Есть съемки, ближайшая съемка и свет
/// (если съемке он нужен), во время съемки отсчет студийного времени, следующую точку, маршрут.»
/// Оркестраторский вариант (обратимо): ближайшая съёмка выходит на плашку, когда она сегодня или завтра по часам её места
/// (`WidgetFrame.horizonDays`); дальше — свет, а ближайшая съёмка уходит в нижнюю строку.
public struct WidgetFrame: Equatable, Sendable {

    /// Сколько суток вперёд съёмка вытесняет свет с плашки: 1 — сегодня и завтра.
    public static let horizonDays = 1

    public enum Kind: Equatable, Sendable {
        /// Приложение ещё не оставило места (его не открывали после установки).
        case blank
        /// Съёмок рядом нет: рассвет, затем закат.
        case light
        /// Ближайшая съёмка ещё не началась.
        case upcoming
        /// Съёмка идёт.
        case live
    }

    public enum LightKind: Equatable, Sendable { case sunrise, sunset, polarDay, polarNight }

    /// Ближайшая точка света на свободный день: восход, потом закат; в полярные сутки — слово.
    public struct LightEvent: Equatable, Sendable {
        public var kind: LightKind
        public var at: Date?
        /// 0 — сегодня, 1 — завтра (по часам места).
        public var dayOffset: Int
    }

    public struct Countdown: Equatable, Sendable {
        /// `studio` — до выхода из зала (студийный час), `end` — до конца съёмки.
        public enum Kind: Equatable, Sendable { case studio, end }
        public var kind: Kind
        public var to: Date
        public var studio: String
    }

    public struct ShootFrame: Equatable, Sendable, Identifiable {
        public var shoot: WidgetFeed.Shoot
        /// Часы места съёмки: время на плашке идёт по ним, а не по часам телефона.
        public var zone: TimeZone
        /// Сколько суток от сегодняшнего дня в этом месте до дня начала.
        public var dayOffset: Int
        /// Свет того дня, который съёмка рисует на плашке: у ещё не начавшейся — день её начала (завтрашняя — завтрашний свет),
        /// у идущей — сегодня; по часам и месту самой съёмки, как и золотой час.
        public var day: WidgetFeed.DayLight?
        /// Начало золотого часа, если съёмке нужен закат и этот час ещё не прошёл целиком.
        public var golden: Date?
        public var countdown: Countdown?
        /// Следующая точка маршрута и все оставшиеся (первая в `left` — следующая).
        public var left: [WidgetFeed.Stop]
        public var next: WidgetFeed.Stop? { left.first }
        public var id: String { shoot.id }
    }

    public var kind: Kind
    public var now: Date
    public var place: WidgetFeed.Spot
    public var zone: TimeZone
    public var light: LightEvent?
    /// Свет сегодняшнего дня на месте «Света»: среднему виджету.
    public var day: WidgetFeed.DayLight?
    /// Главная съёмка плашки: `upcoming` или `live`.
    public var primary: ShootFrame?
    /// Две ближайшие нерозданные съёмки (с идущей, если она есть): список среднего виджета и нижняя строка свободного дня.
    public var shoots: [ShootFrame]
    public var words: WidgetFeed.Words
    public var url: URL
    public var lang: String
    public var clock12: Bool
    /// 30б.2в-5. Оценка заката сегодняшнего дня места «Света»; `nil` — прогноза нет (виджет молчит, числа не выдумываются).
    public var rating: WidgetFeed.Rating? = nil
    /// Свет завтрашнего дня места «Света»: вечером ближайшее событие — завтрашний рассвет.
    public var tomorrow: WidgetFeed.DayLight? = nil
    /// Список съёмок недели среднего вида: до `weekRows` ближайших нерозданных съёмок, что начинаются в ближайшие `weekDays` суток
    /// (сегодня и дальше по часам места съёмки), с идущей, если она есть.
    public var week: [ShootFrame] = []
    /// Последний день недели («до сб 31»): сегодня плюс `weekDays − 1`. `nil` — места ещё нет.
    public var weekEnd: Date? = nil

    /// Сколько суток и строк занимает неделя среднего вида: семь суток от сегодняшних, три строки (больше в высоту не влезает).
    public static let weekDays = 7, weekRows = 3

    /// Время на плашке в часах `tz`, по привычке приложения (24 или 12 часов, язык приложения).
    public func clock(_ date: Date, in tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: lang)
        f.timeZone = tz
        f.setLocalizedDateFormatFromTemplate(clock12 ? "h:mm a" : "HH:mm")
        return f.string(from: date)
    }

    /// Короткий день недели («сб») для съёмки дальше завтра.
    public func weekday(_ date: Date, in tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: lang)
        f.timeZone = tz
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }

    /// «Сегодня» / «Завтра» / день недели — подпись дня съёмки.
    public func dayWord(_ s: ShootFrame) -> String {
        switch s.dayOffset {
        case ..<1: return words[.today]
        case 1: return words[.tomorrow]
        default: return weekday(s.shoot.startDate, in: s.zone)
        }
    }
}

extension WidgetFeed {

    /// Все съёмки, что ещё не кончились к `now`, по началу.
    private func unfinished(at now: Date) -> [Shoot] {
        shoots.filter { $0.open || $0.endDate > now }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    private func zone(of shoot: Shoot) -> TimeZone {
        (shoot.spot ?? place).timeZone ?? place.timeZone ?? .current
    }

    private func spot(of shoot: Shoot) -> Spot { shoot.spot ?? place }

    func shootFrame(_ s: Shoot, at now: Date) -> WidgetFrame.ShootFrame {
        let tz = zone(of: s)
        let nowDay = Spot.day(of: now, in: tz), startDay = Spot.day(of: s.startDate, in: tz)
        var golden: Date?
        if s.wantsSunset, let l = spot(of: s).light(on: startDay), let g = l.golden {
            // Золотой час «нужен» до заката: пока он не кончился, строка про него остаётся.
            if now < (l.sunset ?? g.addingTimeInterval(3600)) { golden = g }
        }
        let live = s.startDate <= now
        var countdown: WidgetFrame.Countdown?
        if live {
            if let r = s.rents.sorted(by: { $0.from < $1.from }).first(where: {
                Moment(milliseconds: $0.from).date <= now && Moment(milliseconds: $0.deadline).date > now
            }) {
                countdown = .init(kind: .studio, to: Moment(milliseconds: r.deadline).date, studio: r.studio)
            } else if !s.open, s.endDate > now {
                countdown = .init(kind: .end, to: s.endDate, studio: "")
            }
        }
        return WidgetFrame.ShootFrame(
            shoot: s, zone: tz, dayOffset: startDay.days(since: nowDay), day: spot(of: s).light(on: live ? nowDay : startDay),
            golden: golden, countdown: countdown,
            left: s.stops.sorted { $0.at < $1.at }.filter { $0.date > now })
    }

    public func frame(at now: Date) -> WidgetFrame {
        let spot = place
        let tz = spot.timeZone ?? .current
        let upcoming = unfinished(at: now).prefix(2).map { shootFrame($0, at: now) }
        var f = WidgetFrame(kind: .blank, now: now, place: spot, zone: tz, light: nil, day: nil, primary: nil,
                            shoots: Array(upcoming), words: words, url: URL(string: "lightplan://")!,
                            lang: lang, clock12: clock12)
        guard let today = spot.today(at: now) else { return f }
        f.day = spot.light(on: today)
        f.tomorrow = spot.light(on: today.adding(days: 1))
        f.rating = rating(on: today)
        f.week = Array(unfinished(at: now).map { shootFrame($0, at: now) }.filter { $0.dayOffset < WidgetFrame.weekDays }.prefix(WidgetFrame.weekRows))
        f.weekEnd = Self.noon(of: today.adding(days: WidgetFrame.weekDays - 1), in: tz)
        f.url = Self.dayURL(today)

        if let live = unfinished(at: now).first(where: { $0.startDate <= now }) {
            f.kind = .live
            f.primary = shootFrame(live, at: now)
        } else if let soon = upcoming.first, soon.dayOffset <= WidgetFrame.horizonDays {
            f.kind = .upcoming
            f.primary = soon
        } else {
            f.kind = .light
            f.light = lightEvent(at: now, today: today)
            return f
        }
        f.url = Self.shootURL(f.primary!.id)
        return f
    }

    /// Полдень дня `day` в поясе `tz`: от него берут день недели и число («сб 31»), не рискуя сдвинуть сутки.
    static func noon(of day: CivilDate, in tz: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
    }

    /// Следующая точка света, три дня вперёд: восход до восхода, закат после него, после заката — завтрашний восход.
    private func lightEvent(at now: Date, today: CivilDate) -> WidgetFrame.LightEvent {
        for off in 0...2 {
            guard let l = place.light(on: today.adding(days: off)) else { continue }
            if let r = l.sunrise, r > now { return .init(kind: .sunrise, at: r, dayOffset: off) }
            if let s = l.sunset, s > now { return .init(kind: .sunset, at: s, dayOffset: off) }
        }
        let polar = place.light(on: today)?.polar ?? .normal
        return .init(kind: polar == .night ? .polarNight : .polarDay, at: nil, dayOffset: 0)
    }

    /// Моменты, в которые плашка меняется сама, пока приложение закрыто: начала и концы съёмок и точек, студийный
    /// час, свет места и съёмок, полночь. Между ними плашка одна и та же. `now` первым.
    public func changes(from now: Date, horizon: TimeInterval = 36 * 3600, limit: Int = Self.entryLimit) -> [Date] {
        timeline(from: now, horizon: horizon, limit: limit).dates
    }

    /// Записей в одной ленте не больше стольки (по минуте — три часа). Предел записей WidgetKit не называет, лимит у него —
    /// на перезагрузки ленты (40–70 в сутки на виджет, Apple, «Keeping a widget up to date»), поэтому лента длиннее, а
    /// перезагрузок меньше: день свадьбы в 12,5 часа с минутным кольцом — пять-шесть перезагрузок.
    public static let entryLimit = 180

    /// Лента и когда просить новую. Обычно через `horizon`; если моментов больше `limit` и лента обрезана — на
    /// последнем показанном моменте, иначе после него виджет держал бы устаревшую плашку до конца горизонта.
    public struct Schedule: Equatable, Sendable {
        public var dates: [Date]
        public var reload: Date
        public init(dates: [Date], reload: Date) { self.dates = dates; self.reload = reload }
    }

    /// - Parameter shape: форма виджета. `nil` — только события; кольцо (малый, средний) добавляет каждую минуту идущей
    ///   съёмки, круг блокировки — каждую минуту до золотого часа, большой с дугой солнца — каждые 10 минут светового дня:
    ///   цифры там статичные (системный `Text(timerInterval:)` пишет «62:00», а не «62 мин»), значит, меняет их лента.
    public func timeline(from now: Date, horizon: TimeInterval = 36 * 3600, limit: Int = Self.entryLimit,
                         shape: WidgetShape? = nil) -> Schedule {
        let end = now.addingTimeInterval(horizon)
        var all: [Date] = []
        func add(_ d: Date?) { if let d, d > now, d <= end { all.append(d) } }
        func spotMoments(_ spot: Spot) {
            guard let tz = spot.timeZone, let today = spot.today(at: now) else { return }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            for off in 0...2 {
                let day = today.adding(days: off)
                if let l = spot.light(on: day) { add(l.sunrise); add(l.sunset); add(l.golden) }
                add(cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day)))
            }
        }
        spotMoments(place)
        for s in shoots where s.open || s.endDate > now {
            add(s.startDate)
            if !s.open { add(s.endDate) }
            for p in s.stops { add(p.date) }
            for r in s.rents {
                add(Moment(milliseconds: r.from).date); add(Moment(milliseconds: r.to).date)
                add(Moment(milliseconds: r.deadline).date)
            }
            if let own = s.spot { spotMoments(own) }
        }
        if let shape { all += paceMoments(shape, from: now, to: end).filter { $0 > now } }
        var seen = Set<Date>()
        let sorted = all.sorted().filter { seen.insert($0).inserted }
        let shown = Array(sorted.prefix(max(limit - 1, 0)))
        let truncated = sorted.count > shown.count
        return Schedule(dates: [now] + shown, reload: truncated ? (shown.last ?? end) : end)
    }

    /// Целые минуты от `a` (не раньше) до `b` включительно с шагом `step` секунд: ровно в :00, как идут часы.
    private static func marks(_ a: Date, _ b: Date, step: TimeInterval) -> [Date] {
        guard b >= a else { return [] }
        var t = (a.timeIntervalSince1970 / step).rounded(.up) * step
        var out: [Date] = []
        while t <= b.timeIntervalSince1970 {
            out.append(Date(timeIntervalSince1970: t))
            t += step
        }
        return out
    }

    /// Поминутные (и подесятиминутные) моменты формы: по ним меняются статичные цифры и ход кольца.
    private func paceMoments(_ shape: WidgetShape, from now: Date, to end: Date) -> [Date] {
        switch shape {
        case .inline, .rectangular:
            return []
        case .small, .medium:
            // Кольцо рисуется, пока съёмка идёт: от «сейчас» (или начала) до конца; закрытая руками — до записанного конца.
            // Незакрытая вручную съёмка после записанного конца минут не просит: остаток и доли кольца у неё зажаты на нуле и
            // единице (`DayPlan`), по минутам нечему меняться (ревью GPT к 8d3f1c2 — тест `anOpenShootPastItsEnd…`).
            let running = shoots.flatMap { s -> [Date] in
                guard s.open || s.endDate > now else { return [] }
                return Self.marks(max(s.startDate, now), min(s.endDate, end), step: 60)
            }
            // 30б.2в-5: средний в день съёмки впереди рисует риски по световому дню (150 на ~10 ч, риска — 4 минуты): пока он идёт,
            // кольцо двигает лента, раз в 10 минут. Без съёмки сегодня периметр чист, и записи не нужны.
            guard shape == .medium, let today = place.today(at: now) else { return running }
            let day = (0...1).flatMap { off -> [Date] in
                guard let l = place.light(on: today.adding(days: off)), let r = l.sunrise, let s = l.sunset else { return [] }
                return Self.marks(max(r, now), min(s, end), step: 600).filter { BraunIdle.shootToday(frame(at: $0)) }
            }
            return running + day
        case .circular:
            guard let tz = place.timeZone, let today = place.today(at: now) else { return [] }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            return (0...2).flatMap { off -> [Date] in
                let day = today.adding(days: off)
                guard let g = place.light(on: day)?.golden,
                      let midnight = cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
                else { return [] }
                return Self.marks(max(midnight, now), min(g, end), step: 60)
            }
        case .large:
            // Точка «сейчас» на дуге солнца ходит от восхода к закату; без съёмок это весь вид (со съёмкой дуги нет).
            guard let today = place.today(at: now) else { return [] }
            return (0...2).flatMap { off -> [Date] in
                guard let l = place.light(on: today.adding(days: off)), let r = l.sunrise, let s = l.sunset else { return [] }
                return Self.marks(max(r, now), min(s, end), step: 600).filter { frame(at: $0).kind == .light }
            }
        }
    }
}

extension WidgetFeed {
    public func clock(_ date: Date, in tz: TimeZone) -> String { frame(at: date).clock(date, in: tz) }
}
