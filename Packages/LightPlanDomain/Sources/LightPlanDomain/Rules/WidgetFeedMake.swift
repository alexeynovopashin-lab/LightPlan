import Foundation
import LightPlanCore

extension WidgetFeed {

    /// Файл виджета из данных приложения (30б.2): съёмки со вчера до `horizonDays` вперёд, что ещё не кончились.
    ///
    /// Чистая функция — приложение даёт только то, что знает само: пояс по точке (`offset`, из кэша зон приложения),
    /// название жанра (`title`, на языке приложения), имена клиентов (`names`, как в шапке карточки), знак точки (`sign`,
    /// `PointSign.name` приложения) и слова. Телефонов, заметок и прочего из записи клиента в файл не попадает: имена — единственное.
    ///
    /// - Parameters:
    ///   - place: место «Света».
    ///   - manualEnd: настройка «Завершение съёмки»: незакрытая съёмка идёт, пока не нажмут.
    ///   - offset: смещение пояса точки в часах на день; `nil` — место приложения.
    ///   - forecast: оценки заката дней места «Света» из настоящего прогноза (30б.2в-5); пусто — прогноза нет.
    public static func make(
        place: Spot, sessions: [Session], studios: [Studio], spots: [LightPlanDomain.Spot], now: Date,
        manualEnd: Bool, offset: (GeoPoint?, CivilDate) -> Double, title: (Session) -> String,
        names: (Session) -> String = { _ in "" },
        sign: (_ name: String, _ place: String, _ studio: Bool) -> String = { _, _, _ in "dot" },
        words: Words, forecast: [Rating] = [], lang: String, clock12: Bool
    ) -> WidgetFeed {
        let today = place.today(at: now) ?? Self.civil(now)
        let from = today.adding(days: -1), to = today.adding(days: horizonDays)
        var out: [Shoot] = []
        for s in sessions where s.kind == .shoot && !(s.day < from) && !(to < s.day) {
            let point = Stops.skyPoint(of: s, spots: spots, studios: studios)
            let off = offset(point, s.day)
            func moment(_ minutes: Int) -> Int64 {
                WallTime(day: s.day, minutes: minutes).moment(utcOffsetHours: off).milliseconds
            }
            let open = manualEnd && s.doneAt == nil
            let end = moment(s.doneAt ?? s.endMinute)
            if !open && Moment(milliseconds: end).date <= now { continue }

            var rents: [Rent] = []
            func addRent(_ w: RentWindow) {
                rents.append(Rent(from: moment(w.from), to: moment(w.to), deadline: moment(w.deadline),
                                  studio: w.studio.name))
            }
            for r in s.route {
                guard let st = Stops.studio(r.studioId, in: studios), let a = r.start, let b = r.end else { continue }
                addRent(RentWindow(studio: st, hallId: r.hallId, from: a, to: b))
            }
            if rents.isEmpty, let st = Stops.studio(s.studioId, in: studios) {
                addRent(RentWindow(studio: st, hallId: s.hallId, from: s.rentFrom ?? s.start, to: s.rentTo ?? s.endMinute))
            }

            let stops = s.timedRoute.map { r -> Stop in
                let place = Stops.place(of: r, spots: spots, studios: studios)?.name ?? r.placeText
                return Stop(at: moment(r.start ?? 0), name: r.name, place: place,
                            sign: sign(r.name, place, Stops.studio(r.studioId, in: studios) != nil))
            }
            let who = names(s)
            out.append(Shoot(
                id: s.id, start: moment(s.start), end: end, open: open, title: title(s), place: s.placeText,
                spot: point.map { Spot(name: "", latitude: $0.latitude, longitude: $0.longitude, zone: "fixed:\(Int((off * 3600).rounded()))") },
                wantsSunset: s.wishes.contains(.sunset), rents: rents, stops: stops,
                genre: s.genre?.rawValue, names: who.isEmpty ? nil : who))
        }
        out.sort { ($0.start, $0.id) < ($1.start, $1.id) }
        return WidgetFeed(place: place, shoots: Array(out.prefix(40)), words: words, forecast: forecast, lang: lang, clock12: clock12)
    }

    private static func civil(_ d: Date) -> CivilDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }
}
