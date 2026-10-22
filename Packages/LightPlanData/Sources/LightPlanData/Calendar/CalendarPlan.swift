import Foundation
import LightPlanCore
import LightPlanDomain

/// Что должно стоять в календаре телефона (шаг 30.1, `docs/14`, «Что именно зеркалим»).
///
/// Здесь только расчёт: записи → список событий. Ни EventKit, ни слов — слова названий и ответ «какой пояс у
/// места» приходят снаружи, как у `StudioSchedule`.
///
/// | запись | событие |
/// |---|---|
/// | съёмка, встреча | да |
/// | занятое время (`blocks`) | да |
/// | событие из чужого календаря (`kind == .event`) | **нет** — оно и так в календаре, зеркалить его назад было бы дублем |
/// | съёмка в корзине | нет: в `sessions` её уже нет |
/// | золотой час, восход, фазы луны | нет (`04_ANTI_GOALS`) |
public enum CalendarPlan {

    public struct Context: Sendable {
        public var studios: [Studio]
        public var spots: [Spot]
        public var zones: ZoneCache
        /// Пояс места приложения: по нему идёт запись без точки и занятость, записанная руками.
        public var homeZone: ZoneID
        /// Календарь телефона, по которому ложатся события «на весь день».
        public var calendar: Calendar
        /// «Свадьба · Ирина»: название съёмки или встречи.
        public var title: @Sendable (Session) -> String
        /// «Дорога», «Перелёт · Москва»: название занятости.
        public var blockTitle: @Sendable (Block) -> String
        /// Заметки события: телефоны клиента и заметки съёмки (`CalendarNotes`); `nil` — писать нечего.
        public var notes: @Sendable (Session) -> String?

        public init(studios: [Studio], spots: [Spot], zones: ZoneCache, homeZone: ZoneID,
                    calendar: Calendar = .current,
                    title: @escaping @Sendable (Session) -> String,
                    blockTitle: @escaping @Sendable (Block) -> String,
                    notes: @escaping @Sendable (Session) -> String? = { _ in nil }) {
            self.studios = studios; self.spots = spots; self.zones = zones; self.homeZone = homeZone
            self.calendar = calendar; self.title = title; self.blockTitle = blockTitle; self.notes = notes
        }
    }

    /// Ссылка записи: тап по событию в Календаре открывает её у нас.
    public static func url(shoot id: String) -> URL { link("shoot", id) }
    public static func url(block id: String) -> URL { link("block", id) }

    private static func link(_ host: String, _ id: String) -> URL {
        var c = URLComponents()
        c.scheme = "lightplan"
        c.host = host
        c.path = "/" + id
        return c.url ?? URL(string: "lightplan://\(host)")!
    }

    /// Наша ли ссылка: ровно `lightplan://shoot/<id>` или `lightplan://block/<id>`. Другие ссылки своей схемы
    /// (`lightplan://quest?…`, чужая правка в поле «ссылка») событие нашим не делают: проход такое не трогает.
    public static func isRecordLink(_ url: URL?) -> Bool {
        guard let url, url.scheme == "lightplan", let host = url.host, host == "shoot" || host == "block" else { return false }
        return url.path.count > 1
    }

    /// Занятое время по ссылке из события: `lightplan://block/<id>`.
    public static func blockId(in url: URL) -> String? {
        guard url.scheme == "lightplan", url.host == "block" else { return nil }
        let id = String(url.path.dropFirst())
        return id.isEmpty ? nil : id
    }

    /// Запись по ссылке из события: `lightplan://shoot/<id>`.
    public static func shootId(in url: URL) -> String? {
        guard url.scheme == "lightplan", url.host == "shoot" else { return nil }
        let id = String(url.path.dropFirst())
        return id.isEmpty ? nil : id
    }

    /// События по всем записям: порядок — по времени, равные — по ссылке (чтобы вывод не зависел от обхода).
    public static func drafts(sessions: [Session], blocks: [Block], context ctx: Context) -> [EventDraft] {
        var out = sessions.compactMap { draft(of: $0, ctx) }
        out += blocks.map { draft(of: $0, ctx) }
        return out.sorted { ($0.start, $0.key) < ($1.start, $1.key) }
    }

    // MARK: - Съёмка и встреча

    /// Когда съёмка или встреча идёт на самом деле — моментами, с поясом места (шаг 30.5: наложение с чужими
    /// календарями сравнивается моментами, а не часами на стене двух разных поясов). `nil` — запись другого вида.
    public static func span(of s: Session, _ ctx: Context) -> (start: Date, end: Date)? {
        draft(of: s, ctx).map { ($0.start, $0.end) }
    }

    static func draft(of s: Session, _ ctx: Context) -> EventDraft? {
        guard s.kind == .shoot || s.kind == .meet else { return nil }
        let stops = Stops.all(of: s, spots: ctx.spots, studios: ctx.studios)
        let zone = zone(of: s, ctx)
        let offset = zone.utcOffsetHours(on: s.day)
        let start = WallTime(day: s.day, minutes: s.start).moment(utcOffsetHours: offset)
        var endMinute = s.endMinute
        if endMinute <= s.start { endMinute = s.start + 90 }
        let end = WallTime(day: s.day, minutes: endMinute).moment(utcOffsetHours: offset)

        let place = stops.first
        let name = place?.name.isEmpty == false ? place!.name : s.placeText
        let address = place?.address.isEmpty == false ? place!.address : s.placeAddress
        // «Парк» и «Парк Горького, Москва» — одно и то же место: остаётся то, что подробнее.
        let location = [name, address].filter { !$0.isEmpty }.reduce(into: [String]()) { acc, part in
            if acc.contains(where: { $0.contains(part) }) { return }
            if let i = acc.firstIndex(where: { part.contains($0) }) { acc[i] = part } else { acc.append(part) }
        }.joined(separator: ", ")

        return EventDraft(
            title: ctx.title(s), start: start.date, end: end.date, allDay: false,
            timeZoneId: iana(zone), offsetSeconds: Int((offset * 3600).rounded()),
            locationTitle: location.isEmpty ? nil : location,
            // Точка без названия в событие не попадает: место без заголовка календарь не хранит.
            latitude: location.isEmpty ? nil : place?.point.latitude, longitude: location.isEmpty ? nil : place?.point.longitude,
            url: url(shoot: s.id), notes: ctx.notes(s), recordModified: s.modifiedAt)
    }

    /// Пояс — места съёмки, а не телефона: съёмка в Москве не едет, когда телефон в Томске (`docs/16`).
    static func zone(of s: Session, _ ctx: Context) -> ZoneID {
        Stops.skyPoint(of: s, spots: ctx.spots, studios: ctx.studios)
            .map { ctx.zones.zoneOrEstimate(at: GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude)) }
            ?? ctx.homeZone
    }

    // MARK: - Занятое время

    static func draft(of b: Block, _ ctx: Context) -> EventDraft {
        let link = url(block: b.id)
        // Нет часов — нет и времени суток: событие на весь день (правило «нет времени» — весь день).
        guard !b.allDay, let startMinute = b.start else {
            let first = dayStart(b.from, ctx.calendar)
            return EventDraft(title: ctx.blockTitle(b), start: first, end: dayStart(b.lastDay, ctx.calendar),
                              allDay: true, url: link, recordModified: b.modifiedAt)
        }
        // Дорога из формы помнит пояс вылета: её минуты — часы билета (`docs/16`, «Перелёт»), длительность —
        // настоящее время в пути. Занятость, записанная руками, поясов не знает: её часы — часы места приложения.
        let offset = b.zoneFrom ?? ctx.homeZone.utcOffsetHours(on: b.from)
        let start = WallTime(day: b.from, minutes: startMinute).moment(utcOffsetHours: offset)
        let end = start.adding(minutes: max(b.duration ?? 120, 1))
        return EventDraft(title: ctx.blockTitle(b), start: start.date, end: end.date, allDay: false,
                          timeZoneId: b.zoneFrom == nil ? iana(ctx.homeZone) : nil,
                          offsetSeconds: Int((offset * 3600).rounded()), url: link, recordModified: b.modifiedAt)
    }

    // MARK: - Мелочи

    /// Имя пояса, понятное EventKit; у зоны «задана смещением» его нет.
    private static func iana(_ z: ZoneID) -> String? {
        TimeZone(identifier: z.identifier) == nil ? nil : z.identifier
    }

    private static func dayStart(_ d: CivilDate, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: d.year, month: d.month, day: d.day)) ?? Date(timeIntervalSince1970: 0)
    }
}
