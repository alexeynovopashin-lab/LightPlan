import Foundation
import LightPlanCore

/// Место съёмки, каким его держит форма (веб `sessionPlace`): производное от
/// первой точки дня. В записи оно лежит своими полями (`place`, `placeTown`,
/// `placeAddr`, `placeLat/Lon`, `placeCity`) — на них смотрят карточка, свет и
/// погода, которым незачем разбирать маршрут.
public struct FormPlace: Equatable, Sendable {
    public var name = ""
    public var town = ""
    public var address = ""
    public var latitude: Double?
    public var longitude: Double?
    /// Рядом город — засветка: звёздам это помеха.
    public var isCity = false
    /// Город набран руками — геокодер его больше не перебивает (веб `townTyped`).
    public var townTyped = false

    public init(name: String = "", town: String = "", address: String = "",
                latitude: Double? = nil, longitude: Double? = nil, isCity: Bool = false) {
        self.name = name
        self.town = town
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.isCity = isCity
    }

    /// Город в запись — только у названного места (веб `placeTownOut`).
    var townOut: String {
        latitude != nil || townTyped || !name.trimmingCharacters(in: .whitespaces).isEmpty ? town : ""
    }
}

/// Слова дня для подсказок в пустых точках (веб `GENRE_SCENES`, `SCENES_DEFAULT`):
/// ключи `scene.*` словаря. Порядок — порядок дня; точек больше — идут по кругу.
public enum SceneHints {
    public static func keys(_ g: Genre) -> [String] {
        switch g {
        case .wedding: ["gathering", "registry", "walk", "banquet", "dance", "fireworks"]
        case .party: ["guestsArrive", "toasts", "table", "cake", "dancing"]
        case .lovestory: ["meeting", "walk", "cafe", "sunset"]
        case .family: ["gathering", "walk", "play", "groupShot"]
        case .portrait: ["start", "changeLook", "street", "finale"]
        case .animals: ["start", "play", "street", "finale"]
        case .report: ["guestsArrive", "opening", "mainPart", "finale"]
        case .product: ["unboxing", "shooting", "changeBg", "details"]
        case .ad: ["prep", "heroShot", "changeScene", "takes"]
        case .architecture: ["wideShot", "facade", "interior", "eveningLight"]
        case .landscape: ["departure", "viewpoint", "goldenHour", "blueHour"]
        case .street: ["route", "point", "light", "finale"]
        }
    }

    /// Подсказка точки `i`.
    public static func key(_ g: Genre, _ i: Int) -> String {
        let k = keys(g)
        return k[i % k.count]
    }
}

// MARK: - Точки дня в форме

extension EventForm {
    /// Предел точек (веб `#fRouteAdd`: `fRoute.length >= 10`).
    public static let maxStops = 10

    /// Три пустых точки жанра дня (веб `seedRoute`): в них только подсказки,
    /// и нетронутые при сохранении отбрасываются.
    static func seededRoute() -> [RoutePoint] {
        Array(repeating: RoutePoint(start: nil, name: ""), count: 3)
    }

    /// Точка без часа и без имени, без места — пустая (веб `routeFromEditor`, фильтр).
    static func kept(_ r: RoutePoint) -> Bool {
        (r.start != nil && !r.name.isEmpty) || r.spotId != nil || r.studioId != nil || !r.placeText.isEmpty
    }

    /// Маршрут в запись: имена и места обрезаны, пустые точки отброшены. Порядок — фотографа.
    public var routeOut: [RoutePoint] {
        route.map { r in
            var o = r
            o.name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
            o.placeText = r.placeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if o.spotId?.isEmpty == true { o.spotId = nil }
            if o.studioId?.isEmpty == true { o.studioId = nil }
            if o.hallId?.isEmpty == true { o.hallId = nil }
            return o
        }.filter(Self.kept)
    }

    /// Маршрут из записи в порядке фотографа, с точками без часа (веб L30437–30463).
    /// Запись, заведённая до того, как место стало первой точкой, держит его
    /// своими полями — оно встаёт первым пунктом дня с часами аренды или съёмки.
    mutating func loadRoute(_ s: Session) {
        route = s.route
        sessionPlace = FormPlace(name: s.place, town: s.placeTown, address: s.placeAddress,
                                 latitude: s.latitude, longitude: s.longitude, isCity: s.placeIsCity)
        if !s.place.isEmpty || s.studioId != nil || s.latitude != nil {
            let head = route.first?.placeText ?? ""
            let already = !head.isEmpty && !s.place.isEmpty && head.hasPrefix(s.place)
            if !already {
                let h0 = s.rentFrom ?? s.start
                let h1 = s.rentTo ?? s.end ?? (s.start + (s.duration ?? 60))
                route.insert(RoutePoint(start: h0, end: h1, name: "", placeText: s.place,
                                        studioId: s.studioId, hallId: s.hallId), at: 0)
            }
        }
    }

    /// Новая точка в конце (веб `#fRouteAdd`); `false` — предел.
    @discardableResult
    public mutating func addStop() -> Bool {
        guard route.count < Self.maxStops else { return false }
        route.append(RoutePoint(start: nil, name: ""))
        return true
    }

    /// Точку убрали крестиком; первая — место съёмки пересчитывается.
    public mutating func removeStop(_ i: Int, spots: [Spot], studios: [Studio], home: RepeatHome? = nil) {
        guard route.indices.contains(i) else { return }
        route.remove(at: i)
        routeSeeded = false
        if i == 0 { syncHeadPlace(spots: spots, studios: studios, home: home) }
    }

    /// Правка точки руками: точки перестают быть «нашими».
    public mutating func editStop(_ i: Int, spots: [Spot] = [], studios: [Studio] = [], home: RepeatHome? = nil,
                                   _ change: (inout RoutePoint) -> Void) {
        guard route.indices.contains(i) else { return }
        change(&route[i])
        routeSeeded = false
        if i == 0 { syncHeadPlace(spots: spots, studios: studios, home: home) }
    }

    /// Час, на который встаёт колесо пустой клетки (веб `stopTimeSeed`): начало —
    /// через полчаса после конца (или начала) предыдущей точки, у первой — начало
    /// съёмки; конец — час после начала.
    public func stopTimeSeed(_ i: Int, end: Bool, step: Int = 5) -> Int {
        if end { return (route.indices.contains(i) ? route[i].start : nil).map { $0 + 60 } ?? stopTimeSeed(i, end: false, step: step) + 60 }
        var j = i - 1
        while j >= 0 {
            if let e = route[j].end { return Self.snap(e + 30, step: step) }
            if let s = route[j].start { return Self.snap(s + 30, step: step) }
            j -= 1
        }
        return start
    }

    /// Час клетки назначен колесом. Имени у точки нет — оно берётся у подсказки:
    /// точка с часом, но без имени, при сохранении пропала бы.
    public mutating func setStopTime(_ i: Int, end: Bool, minute m: Int, hint: String) {
        guard route.indices.contains(i) else { return }
        if end { route[i].end = m } else { route[i].start = m }
        if route[i].name.trimmingCharacters(in: .whitespaces).isEmpty { route[i].name = hint }
        routeSeeded = false
    }

    /// Часы, по которым ходит колесо точки (веб `fillStopHours`): через все дни
    /// съёмки и ещё по суткам с краёв; `lo...hi` — часы самой съёмки, остальные
    /// видны приглушёнными и не выбираются.
    public var stopHours: (all: ClosedRange<Int>, lo: Int, hi: Int) {
        let lo = start / 60, hi = (start + duration) / 60
        let days = (start + duration) / 1440 + 1
        return (-24...((days + 1) * 24 - 1), lo, hi)
    }

    /// Место с листа «Где снимаем» пришло в точку (веб `#locDone`, `locTarget === "stop"`).
    public mutating func setStopPlace(_ i: Int, spot: Spot, spots: [Spot], studios: [Studio]) {
        editStop(i, spots: spots, studios: studios) {
            $0.spotId = spot.id; $0.studioId = nil; $0.hallId = nil; $0.placeText = spot.name
        }
    }

    /// Студия в точку: зал сбрасывается, у безымянной точки имя — «Фотостудия».
    public mutating func setStopStudio(_ i: Int, studio: Studio, studioWord: String, spots: [Spot], studios: [Studio]) {
        editStop(i, spots: spots, studios: studios) {
            $0.studioId = studio.id; $0.spotId = nil; $0.hallId = nil; $0.placeText = studio.name
            if $0.name.trimmingCharacters(in: .whitespaces).isEmpty { $0.name = studioWord }
        }
    }

    /// Зал колесом (веб `onHallWheel`): строка места едет за колесом — «Люмен, зал Белый».
    /// `hall == nil` — просто студия.
    public mutating func setStopHall(_ i: Int, hall: Studio.Hall?, label: (String, String) -> String,
                                     spots: [Spot], studios: [Studio]) {
        guard route.indices.contains(i), let st = Stops.studio(route[i].studioId, in: studios) else { return }
        editStop(i, spots: spots, studios: studios) {
            $0.hallId = hall?.id
            $0.placeText = hall.map { label(st.name, $0.name) } ?? st.name
        }
    }

    /// Место съёмки за первой точкой (веб `syncHeadPlace`). Точку стёрли — места
    /// нет: имя и адрес пусты, координаты — опоры (`home`), город остаётся.
    public mutating func syncHeadPlace(spots: [Spot], studios: [Studio], home: RepeatHome? = nil) {
        let r = route.first
        let pl = r.flatMap { Stops.place(of: $0, spots: spots, studios: studios) }
        guard let r, pl != nil || !r.placeText.trimmingCharacters(in: .whitespaces).isEmpty else {
            sessionPlace.name = ""; sessionPlace.address = ""
            sessionPlace.latitude = home?.latitude; sessionPlace.longitude = home?.longitude
            return
        }
        if let pl, sessionPlace.latitude != pl.point.latitude || sessionPlace.longitude != pl.point.longitude {
            sessionPlace.latitude = pl.point.latitude
            sessionPlace.longitude = pl.point.longitude
            sessionPlace.name = r.placeText.isEmpty ? pl.name : r.placeText
            sessionPlace.address = pl.address
            if let sp = Stops.spot(r.spotId, in: spots), !sp.town.isEmpty { sessionPlace.town = sp.town }
            if let st = Stops.studio(r.studioId, in: studios), !st.town.isEmpty { sessionPlace.town = st.town }
            return
        }
        // Координаты те же — сменилось имя: зал выбрали или строку поправили.
        sessionPlace.name = r.placeText.isEmpty ? (pl?.name ?? "") : r.placeText
        if let pl { sessionPlace.address = pl.address }
    }

    /// Студия первой точки (веб `headStudio`): её зал и часы — поля записи.
    func headStudio(studios: [Studio]) -> (id: String, hall: String?, from: Int?, to: Int?)? {
        guard let r = route.first, let st = Stops.studio(r.studioId, in: studios) else { return nil }
        return (st.id, r.hallId, r.start, r.end)
    }

    /// Раскрыт ли ряд трёх путей к месту (веб `renderRouteHead`): у первой точки
    /// без места — всегда, у другой — пока её о месте спросили.
    public func placeWaysShown(askedStop: Int?) -> Bool {
        guard mode != .meet else { return false }
        if let a = askedStop, route.indices.contains(a) { return true }
        guard let head = route.first else { return true }
        return head.spotId == nil && head.studioId == nil && head.placeText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Город набран руками (веб `#fCity`): съёмка в другом городе, а точки ещё нет.
    public mutating func setCity(_ v: String) {
        sessionPlace.town = v.trimmingCharacters(in: .whitespaces)
        sessionPlace.townTyped = true
    }

    // MARK: - Пожелания

    /// Чип пожелания (веб `renderWishes`): «Неважно» — пустой список, остальные — сами по себе.
    public mutating func toggle(wish w: Wish) {
        if w == .any { wishes = []; return }
        if let i = wishes.firstIndex(of: w) { wishes.remove(at: i) } else { wishes.append(w) }
    }

    public func wishOn(_ w: Wish) -> Bool { w == .any ? wishes.isEmpty : wishes.contains(w) }
}

// MARK: - Замысел против прогноза

/// Небо дня для проверки пожеланий: всё, что веб спрашивает у `qualityOf`,
/// `dayWeather`, `computeSun`, `moonPhase` и `moonVsStars`.
public struct WishSky: Sendable, Equatable {
    public var quality: DayQuality
    /// Закатный балл прогноза; `nil` — прогноза нет.
    public var sunsetScore: Int?
    /// Есть астрономическая ночь (солнце ниже −18°).
    public var astroNight: Bool
    /// Помеха луны звёздам: 0, 1, 2 и процент освещённости.
    public var moonLevel: Int?
    public var moonPercent: Int?
    /// Освещённая доля диска в 22:00 (веб `moonPhase(d, 1320)`).
    public var moonFraction: Double

    public init(quality: DayQuality, sunsetScore: Int?, astroNight: Bool, moonLevel: Int?,
                moonPercent: Int?, moonFraction: Double) {
        self.quality = quality
        self.sunsetScore = sunsetScore
        self.astroNight = astroNight
        self.moonLevel = moonLevel
        self.moonPercent = moonPercent
        self.moonFraction = moonFraction
    }
}

/// Предупреждение ключами словаря: `wc.<key>T` — заголовок, `wc.<key>M` — текст.
public struct WishClash: Sendable, Equatable {
    public var key: String
    public var params: [String: String]
    /// Слово неба в тексте: `qualSky.<q>` строчными.
    public var sky: DayQuality?
    /// Слово пожелания в тексте: `wish.<w>` строчными.
    public var wish: Wish?
}

public enum WishCheck {
    /// Чего ждёт пожелание от неба (веб `WANT`).
    static let want: [Wish: DayQuality] = [.clear: .excellent, .cloudy: .good, .fog: .fog]

    /// Сходится ли пожелание с прогнозом (веб `wishCheck`). `nil` — сходится.
    public static func check(_ w: Wish, sky: WishSky, city: Bool) -> WishClash? {
        let q = sky.quality
        switch w {
        case .any: return nil
        case .stars:
            if !sky.astroNight { return WishClash(key: "whiteNight", params: [:]) }
            if q != .excellent { return WishClash(key: "noStars", params: [:], sky: q) }
            if city { return WishClash(key: "cityGlow", params: [:]) }
            let pct = String(sky.moonPercent ?? 0)
            if sky.moonLevel == 2 { return WishClash(key: "moonWash", params: ["pct": pct]) }
            if sky.moonLevel == 1 { return WishClash(key: "moonDim", params: ["pct": pct]) }
            return nil
        case .sunset:
            if let s = sky.sunsetScore {
                if s < 50 { return WishClash(key: "dullSunset", params: ["score": String(s)]) }
            } else if q == .poor { return WishClash(key: "noSunset", params: [:], sky: q) }
            return nil
        case .rain:
            return q != .poor ? WishClash(key: "noRain", params: [:], sky: q) : nil
        case .moon:
            if sky.moonFraction < 0.25 {
                return WishClash(key: "newMoon", params: ["pct": String(Int((sky.moonFraction * 100).rounded()))])
            }
            return q == .poor ? WishClash(key: "moonCloud", params: [:], sky: q) : nil
        case .clear, .cloudy, .fog:
            return q != want[w] ? WishClash(key: "wrongWx", params: [:], sky: q, wish: w) : nil
        }
    }

    /// Первое несбывшееся пожелание (веб `wishesCheck`).
    public static func first(_ wishes: [Wish], sky: WishSky, city: Bool) -> WishClash? {
        for w in wishes { if let c = check(w, sky: sky, city: city) { return c } }
        return nil
    }
}
