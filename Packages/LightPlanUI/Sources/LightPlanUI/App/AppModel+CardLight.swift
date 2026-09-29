import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Реплика блока «Свет»: знак, слова, плохое ли небо (терракотовый свет по
/// периметру) и синий ли знак.
struct CardSay: Hashable {
    enum Kind: Hashable { case golden, stars, moon }
    let kind: Kind
    let icon: String
    let text: String
    let bad: Bool
}

/// Колонка панели часов (`renderWxPane`): время, знак неба, градус, облачность
/// и знак света; `aside` — час до или после съёмки по краям.
struct WxColumn: Hashable {
    let minute: Int
    let aside: Bool
    /// `nil` — прогноз в пути: место под знак пустое, числа — прочерки.
    let sky: String?
    let temp: String
    let cloud: String
    /// Знак света в минуту точки (`pointLight`) и синий ли он.
    let light: String?
    let blue: Bool
}

enum CardWeather: Hashable {
    case columns([WxColumn])
    /// До съёмки дальше, чем видит прогноз, или служба не ответила ничем:
    /// честная строка вместо выдуманной погоды (Алексей 29.09).
    case noData
}

// MARK: - Свет и погода карточки (итерация 26, шаг 3)

extension AppModel {

    // MARK: Место и солнце точки

    /// Сутки съёмки, в которые попадает минута шкалы (деление с округлением вниз).
    private func dayIndex(_ t: Int) -> Int { t >= 0 ? t / 1440 : -((-t + 1439) / 1440) }

    /// Место с поясом: точка съёмки, без неё — место приложения.
    func cardPlace(_ p: GeoPoint?) -> Place {
        guard let p else { return place.place }
        return Place(latitude: p.latitude, longitude: p.longitude,
                     zone: place.zones.zoneOrEstimate(at: GeoCoordinate(latitude: p.latitude, longitude: p.longitude)))
    }

    func cardSun(_ p: GeoPoint?, _ d: CivilDate) -> SolarDay { SolarDay(date: d, place: cardPlace(p)) }

    private func anchor(_ s: Session) -> GeoPoint? { Stops.skyPoint(of: s, spots: snapshot.spots, studios: snapshot.studios) }

    /// Точки дня «что во сколько» у работы; у встречи и события — нет.
    private func lightRoute(_ s: Session) -> [RoutePoint] { s.kind.isWork ? s.timedRoute : [] }

    // MARK: Прогноз точек

    /// Видит ли прогноз эти сутки (веб `ptReach`: от −5 до +15 дней от сегодня).
    func forecastReaches(_ d: CivilDate) -> Bool {
        let k = d.ordinal - today.ordinal
        return k >= -5 && k <= 15
    }

    /// Спросить прогноз якоря и первых шести точек маршрута (веб `cardWxPts`).
    /// Запись без места прогноза не ждёт; после съёмки не спрашивается.
    func askCardWeather(_ s: Session) {
        guard phase(of: s) != .after, let a = anchor(s), forecastReaches(s.day) else { return }
        pointWeather.ask(cardPlace(a))
        for r in lightRoute(s).prefix(6) {
            if let p = Stops.place(of: r, spots: snapshot.spots, studios: snapshot.studios)?.point {
                pointWeather.ask(cardPlace(p))
            }
        }
    }

    /// Настоящий прогноз точки в эти сутки; выдумки нет: вне окна прогноза,
    /// в пути или без ответа — `nil`.
    func pointDay(_ p: GeoPoint?, _ d: CivilDate) -> (day: WeatherDay, hours: [Int: HourRecord])? {
        guard let p, forecastReaches(d), case .ready(let days, let hourly)? = pointWeather.state(at: cardPlace(p)),
              let day = days[d] else { return nil }
        return (day, hourly[d] ?? [:])
    }

    /// Плохое ли небо (дождь, туман) у якоря в эти сутки — только по прогнозу.
    private func skyIsBad(_ s: Session, _ d: CivilDate) -> Bool {
        guard let q = pointDay(anchor(s), d)?.day.quality else { return false }
        return q == .poor || q == .fog
    }

    // MARK: Свет

    /// Золотой час (веб `lightCase`, только «Закат» — Алексей 29.09).
    func cardLightCase(_ s: Session, phase: EventPhase) -> LightCase? {
        guard phase != .after else { return nil }
        return LightCase.of(s, route: lightRoute(s), spots: snapshot.spots, studios: snapshot.studios,
                            evening: { p, d in let sun = self.cardSun(p, d); return EveningLight(goldenB: sun.goldenB, blueB: sun.blueB) },
                            skyIsBad: { self.skyIsBad(s, $0) })
    }

    private func starNight(_ p: GeoPoint?, _ d: CivilDate) -> StarNight {
        let pl = cardPlace(p)
        let key = "\(PointWeather.key(pl))|\(d)"
        if let hit = nightCache[key] { return hit }
        let w = MilkyWayWindow(date: d, place: pl)
        let n = StarNight(spans: w.spans.map { Int($0.from.rounded())...Int($0.to.rounded()) }, dark: w.dark, moonBlocks: w.moonBlocks,
                          moonPercent: MoonVsStars(date: d, place: pl).percent)
        nightCache[key] = n
        return n
    }

    private func moonArcs(_ p: GeoPoint?, _ d: CivilDate) -> [ClosedRange<Int>] {
        let pl = cardPlace(p)
        let key = "\(PointWeather.key(pl))|\(d)"
        if let hit = moonCache[key] { return hit }
        let arcs = MoonDay(date: d, place: pl).arcs.map { Int($0.rise.rounded())...Int($0.set.rounded()) }
        moonCache[key] = arcs
        return arcs
    }

    func cardStars(_ s: Session, phase: EventPhase) -> NightLight? {
        guard phase != .after else { return nil }
        return NightLight.stars(s, route: lightRoute(s), spots: snapshot.spots, studios: snapshot.studios,
                                night: starNight)
    }

    func cardMoon(_ s: Session, phase: EventPhase) -> NightLight? {
        guard phase != .after else { return nil }
        return NightLight.moon(s, route: lightRoute(s), spots: snapshot.spots, studios: snapshot.studios,
                               arcs: moonArcs,
                               lit: { p, d, t in
                                   let pl = self.cardPlace(p)
                                   let f = MoonPhase(date: d, minutes: Double(t), utcOffsetHours: pl.zone.utcOffsetHours(on: d)).fraction
                                   return Int((f * 100).rounded())
                               })
    }

    /// Реплики блока «Свет» сверху вниз: золотой час, звёзды, луна.
    func cardSays(_ s: Session, phase: EventPhase) -> [CardSay] {
        let f = PlannerFacts(app: self, dark: false)
        func name(_ p: LightPoint?) -> String { p?.name ?? lexicon.t("card.shootPoint") }
        func range(_ w: ClosedRange<Int>) -> String { f.range(Double(w.lowerBound), Double(w.upperBound)) }
        var out: [CardSay] = []
        switch cardLightCase(s, phase: phase) {
        case .badSky(_, let d)?:
            let day = pointDay(anchor(s), d)?.day
            out.append(CardSay(kind: .golden, icon: "warn", text: lexicon.t("light.waitedSunset", [
                "cond": lexicon.t("qualCond." + (day?.quality.rawValue ?? "poor")).lowercased(),
                "cloud": "\(day?.cloud ?? 0)"]), bad: true))
        case .inGolden(let p, let w)?:
            out.append(CardSay(kind: .golden, icon: "sun", text: lexicon.t("light.inGolden", [
                "name": name(p), "range": f.range(w.start, w.end)]), bad: false))
        case .nearGolden(let p, let w, let gap)?:
            out.append(CardSay(kind: .golden, icon: "sun", text: lexicon.t("light.missGolden", [
                "name": name(p), "range": f.range(w.start, w.end), "gap": f.durLabel(gap)]), bad: false))
        case nil: break
        }
        if let n = cardStars(s, phase: phase) {
            let text: String
            switch n {
            case .starsIn(let p, let w): text = lexicon.t("light.inStars", ["name": name(p), "range": range(w)])
            case .starsNear(let p, let w, let gap):
                text = lexicon.t("light.missStars", ["name": name(p), "range": range(w), "gap": f.durLabel(gap)])
            case .starsMoon(let pct): text = lexicon.t("light.starsMoon", ["p": "\(pct)"])
            case .starsLow: text = lexicon.t("light.starsLow")
            default: text = lexicon.t("light.starsNoDark")
            }
            out.append(CardSay(kind: .stars, icon: "stars", text: text, bad: false))
        }
        if let n = cardMoon(s, phase: phase) {
            let text: String
            switch n {
            case .moonUp(let p, let a, let pct):
                text = lexicon.t("light.inMoon", ["name": name(p), "range": range(a), "p": "\(pct)"])
            case .moonNear(let p, let a, let gap):
                text = lexicon.t("light.missMoon", ["name": name(p), "range": range(a), "gap": f.durLabel(gap)])
            default: text = lexicon.t("light.moonNone")
            }
            out.append(CardSay(kind: .moon, icon: "moon", text: text, bad: false))
        }
        return out
    }

    /// Точка «Золотой» на ленте плитки дня (веб `lanePoints`): свет есть и не
    /// «плохой», начало вечернего золотого часа в [первая − 60, последняя + 60]
    /// и ни одна точка не ближе 20 минут к нему.
    func laneGolden(_ s: Session, route: [RoutePoint], phase: EventPhase) -> Int? {
        guard let first = route.first?.start, let last = route.last?.start else { return nil }
        let w: GoldenWindow
        switch cardLightCase(s, phase: phase) {
        case .inGolden(_, let x)?, .nearGolden(_, let x, _)?: w = x
        default: return nil
        }
        let g = Int(w.start.rounded())
        guard g >= first - 60, g <= last + 60, !route.contains(where: { abs(($0.start ?? .max) - g) < 20 }) else { return nil }
        return g
    }

    // MARK: Свет у точки (`pointLight`)

    /// Знак света в минуту `t` (от полуночи первого дня) у точки `p`: говорит
    /// только тон «отлично». Вечер в пределах `goldB − 10` — уже золотой.
    func pointLight(_ s: Session, _ p: GeoPoint?, _ t: Int) -> (icon: String, blue: Bool)? {
        let k = dayIndex(t), m = t - k * 1440
        let sun = cardSun(p, s.date(ofDay: k))
        if let b = sun.goldenB, Double(m) >= b - LightCase.goldEarly, Double(m) < b { return ("golden", false) }
        let st = sun.state(at: Double(m))
        guard st.tone == .excellent else { return nil }
        switch st.code {
        case .golden: return ("golden", false)
        case .dawn, .dawning: return ("sunrise", false)
        case .blue: return ("sunset", true)
        default: return ("sunset", false)
        }
    }

    // MARK: Погода

    /// Панель часов (веб `renderWxPane`): колонки — точки маршрута (первые
    /// шесть, у каждой своё место), без маршрута — часы съёмки у якоря. Меньше
    /// двух — блока нет; меньше трёх — по краям час до и после. Запись без
    /// места прогноза не ждёт — блока нет (DECISIONS 29.09, шаг 1).
    func cardWeather(_ s: Session, phase: EventPhase) -> CardWeather? {
        guard phase != .after, let a = anchor(s) else { return nil }
        var cols: [(t: Int, p: GeoPoint, aside: Bool)]
        let route = lightRoute(s)
        if route.isEmpty {
            cols = LightCase.hours(of: s).map { ($0, a, false) }
        } else {
            cols = route.prefix(6).map { r in
                (r.start ?? 0, Stops.place(of: r, spots: snapshot.spots, studios: snapshot.studios)?.point ?? a, false)
            }
        }
        guard cols.count >= 2 else { return nil }
        if cols.count < 3 {
            cols = [(cols[0].t - 60, cols[0].p, true)] + cols + [(cols[cols.count - 1].t + 60, cols[cols.count - 1].p, true)]
        }
        guard forecastReaches(s.day) else { return .noData }
        if case .empty? = pointWeather.state(at: cardPlace(a)) { return .noData }
        let fahrenheit = settings.tempUnit == .f
        let out = cols.map { c -> WxColumn in
            let k = dayIndex(c.t)
            let light = pointLight(s, c.p, c.t)
            guard let (day, hours) = pointDay(c.p, s.date(ofDay: k)) ?? pointDay(a, s.date(ofDay: k)) else {
                return WxColumn(minute: c.t, aside: c.aside, sky: nil, temp: "—", cloud: "—",
                                light: light?.icon, blue: light?.blue ?? false)
            }
            let h = Int((Double(c.t - k * 1440) / 60).rounded())
            let rec = Weather.nearHour(hours, h)
            let cloud = Int((rec?.cloud ?? Double(day.cloud)).rounded())
            let code = rec?.code ?? 0
            let sky = code >= 51 ? "rain" : (code == 45 || code == 48) ? "cloud" : cloud >= 55 ? "cloud" : cloud >= 25 ? "part" : "sun"
            let c0 = rec?.temperature ?? Double(day.temperatureBase)
            let temp = Int((fahrenheit ? c0 * 9 / 5 + 32 : c0).rounded())
            return WxColumn(minute: c.t, aside: c.aside, sky: sky, temp: "\(temp)°", cloud: "\(cloud)%",
                            light: light?.icon, blue: light?.blue ?? false)
        }
        return .columns(out)
    }

    // MARK: Строка под листом (`#cdWarn`)

    /// «Ожидался закат. Прогноз на этот день — дождь.» — только по настоящему
    /// прогнозу якоря. Молчит при «Неважно» и когда прогноз совпал с
    /// пожеланием (туман ↔ туман, осадки ↔ дождь) — ошибка 13 веба.
    func cardWishMissed(_ s: Session, phase: EventPhase) -> String? {
        let wishes = s.wishes.filter { $0 != .any }
        guard phase != .after, !wishes.isEmpty, let q = pointDay(anchor(s), s.day)?.day.quality,
              q == .poor || q == .fog else { return nil }
        if q == .fog && wishes.contains(.fog) { return nil }
        if q == .poor && wishes.contains(.rain) { return nil }
        let words = wishes.enumerated().map { i, w in
            let x = lexicon.t("wish.was." + w.rawValue)
            return i == 0 ? x : x.lowercased()
        }
        return lexicon.t("card.wishMissed", ["wish": words.joined(separator: ", "),
                                             "cond": lexicon.t("qualCond." + q.rawValue).lowercased()])
    }

    // MARK: Сдвиг времени (`#cdMoved`)

    /// «Было 18:00 – 19:30, стало 18:30 – 20:00.» — пока время на ленте не
    /// вернули как было и крестик не нажат. Все фазы.
    func cardMoved(_ s: Session) -> (from: String, to: String)? {
        guard let m = s.dayMoved, !(m.start == s.start && m.end == s.endMinute) else { return nil }
        let f = PlannerFacts(app: self, dark: false)
        return (f.range(Double(m.start), Double(m.end)), f.range(Double(s.start), Double(s.endMinute)))
    }

    /// Крестик строки сдвига: `dayMoved` стирается, строка гаснет.
    public func clearDayMoved(id: String) {
        guard let i = snapshot.sessions.firstIndex(where: { $0.id == id }), snapshot.sessions[i].dayMoved != nil else { return }
        snapshot.sessions[i].dayMoved = nil
        snapshot.sessions[i].modifiedAt = nowMs
        persist()
    }
}
