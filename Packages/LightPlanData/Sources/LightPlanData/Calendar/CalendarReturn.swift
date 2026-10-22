import Foundation
import LightPlanCore
import LightPlanDomain

/// Что из Календаря возвращается в запись (шаг 30.4, `docs/14`: «в Календаре можно двигать, но не переписывать»).
///
/// Возвращаются **время и место**. Название, заметки, клиент и деньги остаются нашими. Расчёт чистый: событие и запись
/// на входе, запись на выходе; метку правки (`mt`) и сохранение ставит тот, кто вызвал.
extension CalendarPlan {

    // MARK: - Подвинули событие

    /// Запись после правки события в Календаре; `nil` — менять нечего или записи такого рода это не касается
    /// (занятое время возвращается к виду, который стоит у нас).
    ///
    /// - Время: часы события пересчитываются в часах **места съёмки**, как они туда и уходили: день, начало и
    ///   длительность. Событие, пересёкшее полночь, даёт конец больше 1 440 минут, как у съёмки до утра. Часы аренды и
    ///   точки маршрута не двигаются (так же, как при сдвиге на ленте дня).
    /// - Место: событие названо иначе или стоит в другой точке — место съёмки становится таким. Студия — это бронь, а
    ///   не строка: если первая точка дня студия, место из Календаря не берётся, возвращается только время.
    /// - Пояс считается по месту **после** правки: мгновение, которое показывает Календарь, не должно съехать.
    public static func applying(_ e: StoredEvent, to s: Session, _ ctx: Context) -> Session? {
        guard s.kind == .shoot || s.kind == .meet, !e.allDay, e.end > e.start else { return nil }
        guard let current = draft(of: s, ctx) else { return nil }
        var out = s
        // Место: сравниваем с тем, что мы сами положили бы в событие.
        let placeMoved = !placeMatches(e, current)
        if placeMoved, Stops.all(of: s, spots: ctx.spots, studios: ctx.studios).first?.isStudio != true {
            setPlace(&out, from: e)
            if e.latitude == nil || e.longitude == nil { out.latitude = nil; out.longitude = nil }
        }
        // Время: сдвинули — пишем; не сдвигали, но место (а с ним пояс) сменилось — часы пересчитываются, потому
        // что то же мгновение в другом поясе показывает другие часы.
        let timeMoved = abs(e.start.timeIntervalSince(current.start)) >= 1 || abs(e.end.timeIntervalSince(current.end)) >= 1
        if timeMoved || zone(of: out, ctx) != zone(of: s, ctx) { setTime(&out, from: e, ctx) }
        return out == s ? nil : out
    }

    /// Место съёмки — название из события, адрес в нём уже внутри названия («Парк, ул. Ленина 5»).
    private static func setPlace(_ s: inout Session, from e: StoredEvent) {
        s.place = (e.locationTitle ?? "")
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: ", ")
        s.placeAddress = ""
        if let la = e.latitude, let lo = e.longitude { s.latitude = la; s.longitude = lo }
    }

    /// Часы события в часах места съёмки, каким оно стало: день, начало, конец и длительность.
    private static func setTime(_ s: inout Session, from e: StoredEvent, _ ctx: Context) {
        let zone = zone(of: s, ctx)
        let utcDay = CivilDate(daysSince1970: Int((e.start.timeIntervalSince1970 / 86_400).rounded(.down)))
        let guess = zone.utcOffsetHours(on: utcDay)
        var wall = WallTime(moment: Moment(e.start), utcOffsetHours: guess)
        // Смещение берётся на день, в который выпало начало: у зон с летним временем он может оказаться соседним.
        let exact = zone.utcOffsetHours(on: wall.day)
        if exact != guess { wall = WallTime(moment: Moment(e.start), utcOffsetHours: exact) }
        let minutes = max(1, Moment(e.end).minutes(since: Moment(e.start)))
        s.day = wall.day
        s.start = wall.minutes
        s.end = wall.minutes + minutes
        s.duration = minutes
    }

    private static func placeMatches(_ e: StoredEvent, _ d: EventDraft) -> Bool {
        guard (e.locationTitle ?? "") == (d.locationTitle ?? "") else { return false }
        switch (e.latitude, d.latitude) {
        case (nil, nil): break
        case let (x?, y?): if abs(x - y) >= 1e-5 { return false }
        default: return false
        }
        switch (e.longitude, d.longitude) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) < 1e-5
        default: return false
        }
    }

    // MARK: - Подвинули занятое время

    /// Занятое время после правки его события в Календаре; `nil` — менять нечего или событие другого вида, чем мы положили
    /// («на весь день» стало событием по часам и наоборот — такое перепишется как у нас).
    ///
    /// - «На весь день» (или блок без часов): первый день и число дней — по дням события.
    /// - По часам: день, начало и длительность — в часах блока: у дороги из формы это пояс вылета, у остального — место
    ///   приложения (как и туда).
    public static func applying(_ e: StoredEvent, to b: Block, _ ctx: Context) -> Block? {
        guard !e.recurring, e.end >= e.start else { return nil }
        var out = b
        if b.allDay || b.start == nil {
            guard e.allDay else { return nil }
            out.from = civil(e.start, ctx.calendar)
            if b.allDay { out.days = max(1, civil(e.end, ctx.calendar).days(since: out.from) + 1) }
        } else {
            guard !e.allDay else { return nil }
            let utcDay = CivilDate(daysSince1970: Int((e.start.timeIntervalSince1970 / 86_400).rounded(.down)))
            let guess = b.zoneFrom ?? ctx.homeZone.utcOffsetHours(on: utcDay)
            var wall = WallTime(moment: Moment(e.start), utcOffsetHours: guess)
            if b.zoneFrom == nil {
                let exact = ctx.homeZone.utcOffsetHours(on: wall.day)
                if exact != guess { wall = WallTime(moment: Moment(e.start), utcOffsetHours: exact) }
            }
            out.from = wall.day
            out.start = wall.minutes
            out.duration = max(1, Moment(e.end).minutes(since: Moment(e.start)))
        }
        return out == b ? nil : out
    }

    private static func civil(_ d: Date, _ calendar: Calendar) -> CivilDate {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return CivilDate(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    // MARK: - Завели событие

    /// Черновик съёмки из события, заведённого руками в нашем календаре; `nil` — событие не годится
    /// (`CalendarMirror.isDraftable`: на весь день, повторяющееся, длиннее суток).
    ///
    /// Черновик — **съёмка** (`kind == .shoot`) с пустыми жанром и клиентом и пометкой `fromCalendar`: у съёмки уже есть
    /// всё, что фотограф будет дозаполнять (карточка, клиент, жанр, деньги, маршрут), а встреча без жанра и занятое
    /// время (оно без клиента и без карточки) — не то. Название события остаётся названием: `fromCalendar` и первая
    /// строка заметок. Заметки самого события тоже переезжают в запись: дальше заметки — наше поле, и без этого шага
    /// первая же запись в событие их стёрла бы.
    public static func newDraft(from e: StoredEvent, id: String, modifiedAt: Int64, _ ctx: Context) -> Session? {
        guard CalendarMirror.isDraftable(e) else { return nil }
        var s = Session(id: id, kind: .shoot, day: CivilDate(daysSince1970: 0), start: 0)
        let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        s.fromCalendar = title
        s.notes = importedNotes(title: title, notes: e.notes, url: e.url)
        s.modifiedAt = modifiedAt
        setPlace(&s, from: e)
        setTime(&s, from: e, ctx)
        return s
    }

    /// Первая строка — название события, дальше его заметки и чужая ссылка (её место займёт наша).
    static func importedNotes(title: String, notes: String?, url: URL?) -> String {
        let body = (notes ?? "").replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [title, body].filter { !$0.isEmpty }
        if let url, !isRecordLink(url) { parts.append(url.absoluteString) }
        return parts.joined(separator: "\n")
    }
}
