import Foundation
import Synchronization
import LightPlanCore
import LightPlanDomain

// Чужие календари призраками (шаг 30.5, `docs/14` «Чужие календари — призраками»).
//
// Рабочий календарь, расписание детей, матч сына показываются в Light Plan **призраками**: видны, но не правятся,
// не двигаются и ни на что в данных не влияют. Призрак живёт только в памяти этого телефона: считается из
// EventKit на видимый отрезок дней, в снимок съёмок, в веб и на другие устройства не попадает и в Календарь
// обратно не пишется. Приватность: берутся название, время, место и имя календаря — заметки, участники и ссылки
// чужих событий в приложение не читаются.

// MARK: - Что показывать по умолчанию

/// Какие календари показываются, пока человек ничего не отмечал (решение Алексея 22.10.2026: «3А, протестируем,
/// Б мне нравится больше»).
public enum GhostCalendarsDefault: String, Sendable, CaseIterable {
    /// Все личные календари, кроме «Light Plan», подписок (праздники, расписания) и дней рождения; человек
    /// снимает галочки с лишнего.
    case allPersonal
    /// Ничего: человек сам отмечает, что показывать.
    case none
}

public enum GhostPolicy {
    /// **Единственное место, где выбирается режим по умолчанию.** Меняется одной строкой; отметки, которые человек
    /// поставил сам, режим не трогает (они хранятся отдельно, `GhostRecord.picks`).
    public static let ghostCalendarsDefault: GhostCalendarsDefault = .allPersonal

    /// Личный календарь — свой, а не подписка и не «Дни рождения»: по виду, а не по названию («Праздники» может
    /// называться как угодно, подписка остаётся подпиской). Праздники из учётной записи Google приходят обычным
    /// календарём — по виду их не отличить, человек снимает галочку сам.
    public static func isPersonal(_ c: StoredCalendar) -> Bool {
        switch c.type {
        case .local, .account, .exchange: true
        case .subscription, .birthday: false
        }
    }

    /// Наш календарь «Light Plan» (по записи зеркала и по имени — прежний после переустановки): его события — уже
    /// наши записи, показывать их призраками значило бы удвоить свои съёмки.
    public static func isOurs(_ c: StoredCalendar, mirrorCalendarId: String?) -> Bool {
        c.id == mirrorCalendarId || c.title == CalendarMirror.calendarTitle
    }

    /// Показывается ли календарь, пока человек не отметил его сам.
    public static func defaultShown(_ c: StoredCalendar, mode: GhostCalendarsDefault = ghostCalendarsDefault) -> Bool {
        mode == .allPersonal && isPersonal(c)
    }
}

// MARK: - Память телефона

/// Выбор человека: включены ли призраки и какие календари он отметил или снял сам. Лежит на устройстве, рядом с
/// памятью зеркала, но отдельно от неё: выключение зеркала стирает его запись, а выбор призраков — нет.
public struct GhostRecord: Codable, Equatable, Sendable {
    /// Человек включил «Другие календари». Выключено, пока он не сказал: читать чужие календари без спроса нельзя.
    public var on = false
    /// Календарь → отметка человека. Нет записи — действует режим по умолчанию (`GhostPolicy`).
    public var picks: [String: Bool] = [:]

    public init() {}
    public init(on: Bool, picks: [String: Bool] = [:]) { self.on = on; self.picks = picks }

    private enum CodingKeys: String, CodingKey { case on, picks }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        picks = try c.decodeIfPresent([String: Bool].self, forKey: .picks) ?? [:]
    }
}

public protocol GhostMemory: AnyObject, Sendable {
    var record: GhostRecord { get set }
}

public final class InMemoryGhostMemory: GhostMemory, @unchecked Sendable {
    private let box: Mutex<GhostRecord>
    public init(_ record: GhostRecord = GhostRecord()) { box = Mutex(record) }
    public var record: GhostRecord {
        get { box.withLock { $0 } }
        set { box.withLock { $0 = newValue } }
    }
}

public final class DeviceGhostMemory: GhostMemory, @unchecked Sendable {
    public static let key = "lightplan.native.calendar.ghosts"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var record: GhostRecord {
        get { defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(GhostRecord.self, from: $0) } ?? GhostRecord() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key) }
    }
}

// MARK: - Призрак

/// Чужое событие, каким его видит Light Plan: ничего сверх названия, времени, места и имени календаря.
public struct Ghost: Sendable, Hashable, Identifiable {
    /// События-вхождения повторяющегося события делят идентификатор, поэтому в ключ входит и начало.
    public let id: String
    public let calendarId: String
    public let calendarTitle: String
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let location: String?
    /// «На весь день»: первый и последний день по часам телефона; у событий по часам — `nil`.
    public let firstDay: CivilDate?
    public let lastDay: CivilDate?

    public init(id: String, calendarId: String, calendarTitle: String, title: String, start: Date, end: Date,
                allDay: Bool, location: String? = nil, firstDay: CivilDate? = nil, lastDay: CivilDate? = nil) {
        self.id = id; self.calendarId = calendarId; self.calendarTitle = calendarTitle; self.title = title
        self.start = start; self.end = end; self.allDay = allDay; self.location = location
        self.firstDay = firstDay; self.lastDay = lastDay
    }

    /// Событие «на весь день» стоит в этом дне.
    public func covers(_ day: CivilDate) -> Bool {
        guard allDay, let a = firstDay, let b = lastDay else { return false }
        return day >= a && day <= b
    }

    /// Из прочитанного события: другого в `GhostEvent` и нет — заметки, участники и ссылка остаются за порогом.
    static func make(_ e: GhostEvent, in calendar: StoredCalendar, using cal: Calendar) -> Ghost {
        let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = e.location?
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: ", ")
        var first: CivilDate?, last: CivilDate?
        if e.allDay {
            // Конец «на весь день» читается по-разному (23:59:59 последнего дня у EventKit, полночь следующего у части
            // источников): секунда назад попадает в последний день в обоих случаях.
            first = civil(e.start, cal)
            last = e.end > e.start ? civil(e.end.addingTimeInterval(-1), cal) : first
            if let f = first, let l = last, l < f { last = f }
        }
        return Ghost(id: "\(e.id)@\(Int(e.start.timeIntervalSince1970))", calendarId: calendar.id,
                     calendarTitle: calendar.title, title: title, start: e.start, end: e.end, allDay: e.allDay,
                     location: (place?.isEmpty ?? true) ? nil : place, firstDay: first, lastDay: last)
    }

    private static func civil(_ d: Date, _ cal: Calendar) -> CivilDate {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return CivilDate(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }
}

// MARK: - Призрак в сутках

/// Часть призрака, попавшая в сутки ленты дня: минуты этих суток, как у `DayItem`.
public struct GhostPart: Sendable, Hashable, Identifiable {
    public let ghost: Ghost
    public let start: Int
    public let end: Int
    public let fromYesterday: Bool
    public let intoTomorrow: Bool
    public var id: String { ghost.id + "#\(start)" }

    public init(ghost: Ghost, start: Int, end: Int, fromYesterday: Bool, intoTomorrow: Bool) {
        self.ghost = ghost; self.start = start; self.end = end
        self.fromYesterday = fromYesterday; self.intoTomorrow = intoTomorrow
    }
}

public enum GhostDay {
    /// События по часам в сутках `day` по часам пояса `zone` (пояс места приложения): событие через полночь даёт
    /// кусок каждому дню. Порядок — по началу, потом по концу. «На весь день» здесь нет (`allDay(on:)`).
    public static func timed(on day: CivilDate, zone: ZoneID, ghosts: [Ghost]) -> [GhostPart] {
        let a = WallTime(day: day, minutes: 0).moment(in: zone).date
        let b = WallTime(day: day.adding(days: 1), minutes: 0).moment(in: zone).date
        var out: [GhostPart] = []
        for g in ghosts where !g.allDay {
            // Событие нулевой длины — точка: рисуется минимальным блоком от своего начала.
            let end = max(g.end, g.start)
            let inside = end > g.start ? (g.start < b && end > a) : (g.start >= a && g.start < b)
            guard inside else { continue }
            let s = max(g.start, a), e = min(end, b)
            let from = Int((s.timeIntervalSince(a) / 60).rounded(.down))
            let to = Int((e.timeIntervalSince(a) / 60).rounded(.up))
            out.append(GhostPart(ghost: g, start: min(from, 1440), end: min(max(to, from), 1440),
                                 fromYesterday: g.start < a, intoTomorrow: end > b))
        }
        return out.sorted { ($0.start, $0.end, $0.ghost.id) < ($1.start, $1.end, $1.ghost.id) }
    }

    /// События «на весь день», стоящие в этом дне.
    public static func allDay(on day: CivilDate, ghosts: [Ghost]) -> [Ghost] {
        ghosts.filter { $0.covers(day) }.sorted { ($0.calendarTitle, $0.title, $0.id) < ($1.calendarTitle, $1.title, $1.id) }
    }
}

// MARK: - Наложение

public enum GhostOverlap {
    /// Призраки, с которыми пересекается отрезок `[start, end)`. `day` — день записи по её часам, `lastDay` — последний
    /// день, которого она касается (съёмка через полночь): к этим дням прикладываются события «на весь день». Мягкое предупреждение формы, не запрет (решение Алексея 22.10,
    /// «1А»). Порядок: сначала по часам, по началу; потом «на весь день».
    public static func find(start: Date, end: Date, day: CivilDate, through lastDay: CivilDate? = nil, in ghosts: [Ghost]) -> [Ghost] {
        let end = max(end, start.addingTimeInterval(60))
        let timed = ghosts.filter { !$0.allDay && $0.start < end && start < max($0.end, $0.start.addingTimeInterval(1)) }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        // Съёмка через полночь касается и следующих дней: событие «на весь день» любого из них — наложение (ревью GPT).
        let last = max(lastDay ?? day, day)
        let whole = ghosts.filter { g in
            guard g.allDay, let a = g.firstDay, let b = g.lastDay else { return false }
            return a <= last && b >= day
        }.sorted { ($0.calendarTitle, $0.id) < ($1.calendarTitle, $1.id) }
        return timed + whole
    }
}

// MARK: - «Занять»

extension Ghost {
    /// Обычное занятое время («Занят») на время призрака, с названием события в заметке. Решение остаётся за
    /// фотографом: вызывает только кнопка «Занять» — сам призрак ничего не создаёт.
    ///
    /// По часам — в часах пояса места приложения (как занятость, записанная руками); короче 15 минут и длиннее
    /// двух суток лист «Занять время» не берёт: первое подтягивается до 15 минут, второе становится занятостью на
    /// весь день по дням события.
    public func busyBlock(id: String, zone: ZoneID, now: Int64, calendar cal: Calendar = .current) -> Block {
        var b = Block(id: id, kind: .busy, from: firstDay ?? Self.wall(start, zone).day)
        b.note = title
        b.modifiedAt = now
        let spanMinutes = Moment(end).minutes(since: Moment(start))
        if allDay || spanMinutes > 2880 {
            let first = firstDay ?? Self.wall(start, zone).day
            let last = lastDay ?? Self.wall(max(end.addingTimeInterval(-1), start), zone).day
            b.from = first
            b.allDay = true
            // Лист «Занять время» не берёт больше двух месяцев (`BlockSheet.maxSpan`).
            b.days = min(max(1, last.days(since: first) + 1), 61)
        } else {
            let w = Self.wall(start, zone)
            b.from = w.day
            b.start = w.minutes
            b.duration = min(max(spanMinutes, 15), 2880)
        }
        return b
    }

    /// Начало и конец по часам пояса (для слов «в это время …»).
    public func wallRange(in zone: ZoneID) -> (start: WallTime, end: WallTime) {
        (Self.wall(start, zone), Self.wall(max(end, start), zone))
    }

    /// Часы пояса в момент: смещение берётся на день, в который выпало начало (у зон с летним временем сосед).
    static func wall(_ date: Date, _ zone: ZoneID) -> WallTime {
        let utcDay = CivilDate(daysSince1970: Int((date.timeIntervalSince1970 / 86_400).rounded(.down)))
        let guess = zone.utcOffsetHours(on: utcDay)
        var w = WallTime(moment: Moment(date), utcOffsetHours: guess)
        let exact = zone.utcOffsetHours(on: w.day)
        if exact != guess { w = WallTime(moment: Moment(date), utcOffsetHours: exact) }
        return w
    }
}

// MARK: - Чтение

/// Читает чужие календари телефона и отдаёт призраков на отрезок дней. Запоминает последний ответ: пока календарная
/// база не менялась (`invalidate()` по `EKEventStoreChanged`), тот же отрезок не читается заново.
public actor GhostCalendars {

    /// Строка списка в настройках: календарь и показывается ли он.
    public struct Choice: Sendable, Hashable, Identifiable {
        public let calendar: StoredCalendar
        public let shown: Bool
        /// Личный по виду (не подписка и не дни рождения): остальные в списке стоят, но по умолчанию сняты.
        public let personal: Bool
        public var id: String { calendar.id }
        public init(calendar: StoredCalendar, shown: Bool, personal: Bool) {
            self.calendar = calendar; self.shown = shown; self.personal = personal
        }
    }

    private struct Key: Hashable { let from: Date; let to: Date }

    private let store: any CalendarStoring
    private let mirrorMemory: (any CalendarMirrorMemory)?
    private let memory: any GhostMemory
    private let mode: GhostCalendarsDefault
    private let calendar: Calendar
    private var cache: [Key: [Ghost]] = [:]
    /// Поколение кэша: растёт при каждом сбросе. Чтение, начатое до сброса, а законченное после, в кэш не пишется
    /// (ревью GPT: иначе старый ответ вставал на место нового).
    private var generation = 0
    /// Сколько раз ходили в календарную базу за событиями (проверка кэша).
    public private(set) var reads = 0

    public init(store: any CalendarStoring, mirrorMemory: (any CalendarMirrorMemory)? = nil, memory: any GhostMemory,
                mode: GhostCalendarsDefault = GhostPolicy.ghostCalendarsDefault, calendar: Calendar = .current) {
        self.store = store; self.mirrorMemory = mirrorMemory; self.memory = memory
        self.mode = mode; self.calendar = calendar
    }

    public var record: GhostRecord { memory.record }

    public func setOn(_ on: Bool) {
        var r = memory.record
        r.on = on
        memory.record = r
        drop()
    }

    /// Человек поставил или снял галочку у календаря; `nil` — вернуть решение режиму по умолчанию.
    public func setShown(_ calendarId: String, _ shown: Bool?) {
        var r = memory.record
        r.picks[calendarId] = shown
        memory.record = r
        drop()
    }

    public func invalidate() { drop() }

    private func drop() { cache = [:]; generation += 1 }

    /// Календари для списка: все, кроме «Light Plan». Права нет — пусто.
    public func choices() async -> [Choice] {
        guard await store.authorization() == .allowed else { return [] }
        let ours = mirrorMemory?.record.calendarId
        let picks = memory.record.picks
        return await store.allCalendars()
            .filter { !GhostPolicy.isOurs($0, mirrorCalendarId: ours) }
            .map { c in Choice(calendar: c, shown: picks[c.id] ?? GhostPolicy.defaultShown(c, mode: mode),
                               personal: GhostPolicy.isPersonal(c)) }
    }

    /// Призраки на отрезок `[from, to)`. Выключено или права нет — пусто (и ничего не читается).
    public func ghosts(from: Date, to: Date) async -> [Ghost] {
        guard memory.record.on, await store.authorization() == .allowed else { return [] }
        let key = Key(from: from, to: to)
        if let hit = cache[key] { return hit }
        let started = generation
        var out: [Ghost] = []
        for ch in await choices() where ch.shown {
            reads += 1
            for e in await store.ghostEvents(calendarId: ch.calendar.id, from: from, to: to) {
                // Отменённое, отклонённое владельцем и наши собственные записи (ссылка lightplan://…, где бы они ни лежали)
                // призраками не бывают.
                if e.cancelled || e.declined || e.ours { continue }
                out.append(Ghost.make(e, in: ch.calendar, using: calendar))
            }
        }
        out.sort { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        // Пока читали, кэш сбросили (база изменилась, сменили галочку): ответ годится этому вызову, но не кэшу.
        if started == generation { cache = [key: out] }
        return out
    }
}
