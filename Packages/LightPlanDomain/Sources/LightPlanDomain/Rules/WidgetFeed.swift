import Foundation
import LightPlanCore

/// Что приложение оставляет виджету в общей папке (итерация 30б, `docs/30b_widget_cut.md` § «Data»).
///
/// Виджет сам считает свет (`SolarDay` в расширении), а то, чего не вычислит, берёт из одного маленького файла
/// `widget.json` в `group.<адрес приложения>`: место «Света», съёмки ближайших семи дней и несколько слов на языке
/// приложения. Правило и формат здесь, в Domain (только Foundation): пишет приложение (`make`), читает расширение
/// (`frame(at:)`) — одним кодом, поэтому тест видит то же, что экран.
///
/// Съёмки идут с названием жанра; имена клиентов («Анна+Игорь») в файле есть, но показывают их только малый, средний и большой
/// виджеты «Домой», на экране блокировки имён нет (Алексей, 25.10; раньше, 24.10, их не было нигде — виджет виден на заблокированном телефоне).
public struct WidgetFeed: Codable, Sendable, Equatable {
    public static let fileName = "widget.json"
    /// На сколько дней вперёд приложение кладёт съёмки: дальше этого виджет без приложения не заглядывает.
    public static let horizonDays = 7
    /// Сколько дней (сегодня и дальше) получают оценку заката: средний показывает сегодняшнюю, большой дальше.
    public static let ratingDays = 3

    /// Место «Света»: имя для подписи, координаты и зона IANA (или `fixed:<секунды>` — запасная зона без сети).
    public struct Spot: Codable, Sendable, Equatable {
        public var name: String
        public var latitude: Double
        public var longitude: Double
        public var zone: String

        public init(name: String, latitude: Double, longitude: Double, zone: String) {
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.zone = zone
        }

        public init(name: String, place: Place) {
            self.init(name: name, latitude: place.latitude, longitude: place.longitude, zone: place.zone.identifier)
        }
    }

    /// Точка маршрута дня со временем (точка без часа в виджет не идёт).
    public struct Stop: Codable, Sendable, Equatable {
        /// Момент начала, миллисекунды от 1970 (как `Moment`).
        public var at: Int64
        public var name: String
        public var place: String
        /// Имя знака точки в библиотеке (`PointSign.name`, считает приложение): у расширения правил подбора нет, у него
        /// только нарисованные знаки. Нет в файле старого вида — кружок.
        public var sign: String?

        public init(at: Int64, name: String, place: String = "", sign: String? = nil) {
            self.at = at
            self.name = name
            self.place = place
            self.sign = sign
        }

        public var date: Date { Moment(milliseconds: at).date }
    }

    /// Окно аренды студии: из него считается студийный час (дедлайн выхода — `RentWindow.deadline`).
    public struct Rent: Codable, Sendable, Equatable {
        public var from: Int64
        public var to: Int64
        public var deadline: Int64
        public var studio: String

        public var fromDate: Date { Moment(milliseconds: from).date }
        public var deadlineDate: Date { Moment(milliseconds: deadline).date }

        public init(from: Int64, to: Int64, deadline: Int64, studio: String) {
            self.from = from
            self.to = to
            self.deadline = deadline
            self.studio = studio
        }
    }

    public struct Shoot: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        /// Начало и конец — моменты (миллисекунды от 1970). Конец — записанный, а у закрытой кнопкой — минута закрытия.
        public var start: Int64
        public var end: Int64
        /// Съёмку закрывают руками (настройка «Завершение съёмки»), и она ещё не закрыта: идёт, пока не нажмут.
        public var open: Bool
        /// Название жанра («Свадьба», «Фотосъёмка») — не имя клиента.
        public var title: String
        /// Место одной строкой.
        public var place: String
        /// Откуда смотреть небо и какие у места часы; `nil` — место приложения.
        public var spot: Spot?
        /// Съёмке нужен закат: Алексей 24.10 — «свет, если съемке он нужен»; это пожелание «Закат» в карточке.
        public var wantsSunset: Bool
        public var rents: [Rent]
        public var stops: [Stop]
        /// Код жанра (`wedding`): по нему подписи берут «до конца свадьбы», а не «съёмки». Нет в файле старого вида — общее слово.
        public var genre: String?
        /// Кого снимаем, как в шапке карточки («Анна+Игорь»); виджет показывает имена только на «Домой» (малый, средний,
        /// большой), на экране блокировки их нет (Алексей, 25.10). Номеров и прочего из записи клиента в файле нет.
        public var names: String?

        public init(id: String, start: Int64, end: Int64, open: Bool = false, title: String, place: String = "",
                    spot: Spot? = nil, wantsSunset: Bool = false, rents: [Rent] = [], stops: [Stop] = [],
                    genre: String? = nil, names: String? = nil) {
            self.id = id
            self.start = start
            self.end = end
            self.open = open
            self.title = title
            self.place = place
            self.spot = spot
            self.wantsSunset = wantsSunset
            self.rents = rents
            self.stops = stops
            self.genre = genre
            self.names = names
        }

        public var startDate: Date { Moment(milliseconds: start).date }
        public var endDate: Date { Moment(milliseconds: end).date }
    }

    /// Оценка заката одного дня (30б.2в-5): то, что приложение знает из настоящего прогноза и чего не вычислит расширение.
    /// Прогноза на день нет — записи нет, и виджет молчит: числа не выдумываются (слово Алексея 02.10, 28ж).
    public struct Rating: Codable, Sendable, Equatable {
        /// День места «Света» (`ГГГГ-ММ-ДД`).
        public var day: String
        /// Закатный балл 0…100 (`SunsetScore`); `nil` — часа заката в прогнозе нет, есть только категория дня.
        public var score: Int?
        /// Код `DayQuality`. Строкой: незнакомый код из будущего файла не должен ронять весь файл.
        public var quality: String

        public init(day: String, score: Int?, quality: DayQuality) {
            self.day = day
            self.score = score
            self.quality = quality.rawValue
        }

        public var category: DayQuality? { DayQuality(rawValue: quality) }

        /// Ключ дня, как его пишет приложение и читает виджет.
        public static func key(_ d: CivilDate) -> String { String(format: "%04d-%02d-%02d", d.year, d.month, d.day) }
    }

    /// Несколько слов виджета на языке приложения: словарь приложения у расширения под рукой не лежит.
    /// Запасные — русские: файл старого вида или пустое слово не оставляют плашку без подписи.
    public struct Words: Codable, Sendable, Equatable {
        public enum Key: String, CaseIterable, Sendable {
            case sunrise, sunset, golden, next, today, tomorrow, polarDay, polarNight, studio, shoot, route
            // 30б.2в: подписи колец и большого; `more` и `until` — шаблоны с `{n}` и `{t}`: порядок слов у языков разный.
            case untilPoint, untilShoot, untilWedding, wedding, point, points, hourShort, minShort, dayLength, more, until
            // 30б.2в-5: оценка заката словом (по `DayQuality`) и строка пустой недели; `noShootsUntil` — шаблон с `{d}` («сб 31»).
            case rateExcellent, rateGood, ratePlain, ratePoor, rateFog, noShootsUntil
        }

        public static let fallback: [Key: String] = [
            .sunrise: "Рассвет", .sunset: "Закат", .golden: "Золотой час", .next: "Дальше",
            .today: "Сегодня", .tomorrow: "Завтра", .polarDay: "Полярный день", .polarNight: "Полярная ночь",
            .studio: "Студийный час", .shoot: "съёмка", .route: "Маршрут дня",
            .untilPoint: "до конца точки", .untilShoot: "до конца съёмки", .untilWedding: "до конца свадьбы",
            .wedding: "свадьба", .point: "точка", .points: "точек", .hourShort: "ч", .minShort: "мин",
            .dayLength: "День", .more: "и ещё {n}", .until: "до {t}",
            .rateExcellent: "отличный", .rateGood: "хороший", .ratePlain: "обычный", .ratePoor: "плохой", .rateFog: "туман",
            .noShootsUntil: "до {d} съёмок нет",
        ]

        public var table: [String: String]

        public init(_ table: [Key: String] = [:]) {
            self.table = Dictionary(uniqueKeysWithValues: table.map { ($0.key.rawValue, $0.value) })
        }

        public subscript(key: Key) -> String {
            if let w = table[key.rawValue], !w.isEmpty { return w }
            return Self.fallback[key] ?? key.rawValue
        }

        /// «через 3 дня»: падеж зависит от числа и языка, а у расширения словаря нет, поэтому приложение кладёт готовые фразы
        /// на 2…`horizonDays` дней (ключи `inDays.N`). Нет фразы (файл старого вида) — русская с правильным падежом.
        public func inDays(_ n: Int) -> String {
            if let w = table["inDays.\(n)"], !w.isEmpty { return w }
            let last = n % 10, teen = n % 100 / 10 == 1
            let word = (last == 1 && !teen) ? "день" : ((2...4).contains(last) && !teen) ? "дня" : "дней"
            return "через \(n) \(word)"
        }

        /// Слово оценки заката по категории дня (`DayQuality`).
        public func rating(_ q: DayQuality) -> String {
            switch q {
            case .excellent: self[.rateExcellent]
            case .good: self[.rateGood]
            case .plain: self[.ratePlain]
            case .poor: self[.ratePoor]
            case .fog: self[.rateFog]
            }
        }

        public init(from decoder: Decoder) throws {
            table = (try? decoder.singleValueContainer().decode([String: String].self)) ?? [:]
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(table)
        }
    }

    public var place: Spot
    public var shoots: [Shoot]
    public var words: Words
    /// Оценки заката ближайших дней места «Света» (`horizonRatingDays`); пусто — прогноза нет.
    public var forecast: [Rating]
    /// Код языка приложения (`ru`, `en-GB`…): им виджет пишет день недели.
    public var lang: String
    /// Часы на 12 или 24 — как в приложении (настройка «Часы»).
    public var clock12: Bool

    public init(place: Spot, shoots: [Shoot] = [], words: Words = Words(), forecast: [Rating] = [], lang: String = "ru", clock12: Bool = false) {
        self.place = place
        self.shoots = shoots
        self.words = words
        self.forecast = forecast
        self.lang = lang
        self.clock12 = clock12
    }

    private enum CodingKeys: String, CodingKey { case place, shoots, words, forecast, lang, clock12 }

    /// Файл заглушки 30б.1 (одно `place`) читается: съёмок в нём просто нет.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        place = try c.decode(Spot.self, forKey: .place)
        shoots = try c.decodeIfPresent([Shoot].self, forKey: .shoots) ?? []
        words = try c.decodeIfPresent(Words.self, forKey: .words) ?? Words()
        forecast = try c.decodeIfPresent([Rating].self, forKey: .forecast) ?? []
        lang = try c.decodeIfPresent(String.self, forKey: .lang) ?? "ru"
        clock12 = try c.decodeIfPresent(Bool.self, forKey: .clock12) ?? false
    }

    /// Общая папка приложения и его виджета: адрес расширения — адрес приложения + `.Widget` (`Config/Widget.xcconfig`).
    public static func groupID(bundleID: String) -> String {
        let suffix = ".Widget"
        let app = bundleID.hasSuffix(suffix) ? String(bundleID.dropLast(suffix.count)) : bundleID
        return "group." + app
    }

    /// Основной «Light Plan» (адрес `Novopashin.LightPlan[.Widget]`) — виджет чистый; слот и ветка носят латунную «α»,
    /// как значок (`Tools/app_icon_alpha.py`): два виджета на одном экране должны различаться.
    public static func isMainApp(bundleID: String) -> Bool {
        let suffix = ".Widget"
        let app = bundleID.hasSuffix(suffix) ? String(bundleID.dropLast(suffix.count)) : bundleID
        return app == "Novopashin.LightPlan"
    }

    /// Нажатие на виджет: съёмка — её карточка (та же ссылка, что у события в Календаре), свободный день — этот день.
    public static func shootURL(_ id: String) -> URL {
        var c = URLComponents()
        c.scheme = "lightplan"
        c.host = "shoot"
        c.path = "/" + id
        return c.url ?? URL(string: "lightplan://shoot")!
    }

    public static func dayURL(_ day: CivilDate) -> URL {
        URL(string: String(format: "lightplan://day/%04d-%02d-%02d", day.year, day.month, day.day))!
    }

    /// День из `lightplan://day/ГГГГ-ММ-ДД`; чужая ссылка и несуществующая дата — `nil`.
    public static func day(in url: URL) -> CivilDate? {
        guard url.scheme == "lightplan", url.host == "day" else { return nil }
        let p = url.path.dropFirst().split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
        let d = CivilDate(year: p[0], month: p[1], day: p[2])
        return d.adding(days: 0) == d && CivilDate(daysSince1970: d.daysSince1970) == d ? d : nil
    }

    /// Оценка заката дня `day`; `nil` — прогноза на этот день в файле нет.
    public func rating(on day: CivilDate) -> Rating? {
        let key = Rating.key(day)
        return forecast.first { $0.day == key }
    }

    public func encoded() -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(self)) ?? Data()
    }

    /// `nil` — файла нет или он чужого вида: виджет тогда показывает пустую плашку, а не падает.
    public static func decode(_ data: Data) -> WidgetFeed? {
        try? JSONDecoder().decode(WidgetFeed.self, from: data)
    }
}

extension WidgetFeed.Spot {
    /// `nil`, если зоны нет ни в базе системы, ни в виде `fixed:<секунды>`.
    public var zoneID: ZoneID? {
        if let z = ZoneID(zone) { return z }
        guard zone.hasPrefix("fixed:"), let s = Double(zone.dropFirst("fixed:".count)) else { return nil }
        return ZoneID(fixedOffsetHours: s / 3600)
    }

    public var place: Place? {
        zoneID.map { Place(latitude: latitude, longitude: longitude, zone: $0) }
    }

    /// Сегодняшний день по часам места (не телефона): виджет в Москве про Томск показывает томское «сегодня».
    public func today(at now: Date) -> CivilDate? {
        guard let tz = timeZone else { return nil }
        return Self.day(of: now, in: tz)
    }

    static func day(of date: Date, in tz: TimeZone) -> CivilDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Минуты `SolarDay` (от полуночи дня по смещению зоны на начало дня — так их читают экраны) как момент.
    func moment(minutes: Double, on day: CivilDate, place: Place) -> Date {
        let offset = place.zone.utcOffsetHours(on: day)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: DateComponents(year: day.year, month: day.month, day: day.day))!
        return midnight.addingTimeInterval((minutes - offset * 60) * 60)
    }

    /// Свет суток `day` в этом месте: восход, начало золотого часа, закат; полярные сутки — без них.
    /// Солнце то же, что на экранах (`.iau`).
    public func light(on day: CivilDate) -> WidgetFeed.DayLight? {
        guard let place else { return nil }
        let sun = SolarDay(date: day, place: place)
        func at(_ m: Minutes?) -> Date? { m.map { moment(minutes: $0, on: day, place: place) } }
        return WidgetFeed.DayLight(day: day, sunrise: at(sun.rise), golden: at(sun.goldenB), sunset: at(sun.set), polar: sun.polar)
    }

    /// Начало вечернего золотого часа (солнце опускается до 6°) в день `day` по часам места; `nil` — в этот день
    /// солнце 6° сверху вниз не проходит (полярный день или ночь).
    public func goldenStart(on day: CivilDate) -> Date? { light(on: day)?.golden }

    /// Пояс для часов на плашке: те же правила, что у `ZoneID`.
    public var timeZone: TimeZone? {
        guard let zone = zoneID else { return nil }
        if zone.identifier.hasPrefix("fixed:"), let s = Int(zone.identifier.dropFirst("fixed:".count)) {
            return TimeZone(secondsFromGMT: s)
        }
        return TimeZone(identifier: zone.identifier)
    }
}

extension WidgetFeed {
    /// Свет одних суток одного места, моментами.
    public struct DayLight: Equatable, Sendable {
        public var day: CivilDate
        public var sunrise: Date?
        public var golden: Date?
        public var sunset: Date?
        public var polar: SolarDay.PolarState
    }
}
