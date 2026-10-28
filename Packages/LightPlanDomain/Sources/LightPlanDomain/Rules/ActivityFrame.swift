import Foundation
import LightPlanCore

/// Экран активности на заблокированном телефоне и в Dynamic Island (30б.3; слова Алексея 25–26.10).
///
/// Вид — плитка дня карточки без числа слева: строка состояния, диапазон времени и горизонтальная лента точек (знак над точкой,
/// время и слово под ней). Лента всегда на виду, и в студии тоже: студия — та же лента плюс выход из зала и две кнопки.
///
/// **Состояние живёт в самой активности** и обновляется только приложением (платного Push на бесплатной команде нет, замер
/// 30б.3а): всё, что идёт само, — это системные часы (`Text(timerInterval:)`) и полоса (`ProgressView(timerInterval:)`), поэтому
/// каждой из них нужны только моменты. Что меняется шагом — строка состояния, подсвеченная точка, режим — обновляется при
/// открытии приложения и может отставать (решение Алексея 25.10). Число точек и слов ограничено: система держит состояние
/// и свойства активности до 4 КБ (`ActivityFrame.limit`).
///
/// Правило и сборка здесь, в Domain (только Foundation): собирает приложение, рисует расширение, видит тест — одним кодом.
public struct ActivityFrame: Codable, Hashable, Sendable {

    /// Лента (маршрут дня) или студия: лента + выход из зала + кнопки «Позвонить админу» и «Плейлист».
    public enum Mode: String, Codable, Hashable, Sendable { case route, studio }

    /// Точка ленты: что и когда. Время — готовой строкой по часам места съёмки (расширение пояса и привычки «12 или 24 часа» не знает).
    public struct Point: Codable, Hashable, Sendable {
        /// Момент начала, миллисекунды от 1970 (как `Moment`).
        public var at: Int64
        /// «14:30» по часам места.
        public var time: String
        /// Первое слово имени (на ленте помещается одно): «Сборы жениха» → «Сборы».
        public var word: String
        /// Имя знака (`PointSign.name`, считает приложение; `WidgetIcons.generated.swift` рисует). `nil` — кружок.
        public var sign: String?
        /// Не точка маршрута, а начало золотого часа (как «Золотой» на ленте карточки).
        public var gold: Bool

        public init(at: Int64, time: String, word: String, sign: String? = nil, gold: Bool = false) {
            self.at = at
            self.time = time
            self.word = word
            self.sign = sign
            self.gold = gold
        }

        public var date: Date { Moment(milliseconds: at).date }

        private enum CodingKeys: String, CodingKey { case at = "a", time = "t", word = "w", sign = "s", gold = "g" }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            at = try c.decode(Int64.self, forKey: .at)
            time = try c.decode(String.self, forKey: .time)
            word = try c.decode(String.self, forKey: .word)
            sign = try c.decodeIfPresent(String.self, forKey: .sign)
            gold = try c.decodeIfPresent(Bool.self, forKey: .gold) ?? false
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(at, forKey: .at)
            try c.encode(time, forKey: .time)
            try c.encode(word, forKey: .word)
            try c.encodeIfPresent(sign, forKey: .sign)
            if gold { try c.encode(true, forKey: .gold) }
        }
    }

    /// Системные часы: подпись и момент, до которого они считают (идут сами, без обновлений).
    public struct Countdown: Codable, Hashable, Sendable {
        public var label: String
        public var to: Int64

        public init(label: String, to: Int64) {
            self.label = label
            self.to = to
        }

        public var date: Date { Moment(milliseconds: to).date }
        private enum CodingKeys: String, CodingKey { case label = "l", to = "t" }
    }

    public var mode: Mode
    public var shootId: String
    /// «Сейчас: Прогулка», «Скоро: Сборы», «Идёт съёмка», «Съёмка закончена» — как была на момент сборки.
    public var status: String
    /// «12:00 – 22:00 · 10 ч».
    public var range: String
    public var points: [Point]
    /// Подсвеченная точка — последняя из начатых (индекс в `points`, золотой час не считается); `-1` — ни одной.
    public var current: Int
    /// Часы «до <следующей точки>»; после последней — до конца съёмки; `nil` — считать нечего.
    public var next: Countdown?
    /// Выход из зала: аренда идёт или ждёт впереди (время аренды известно заранее, поэтому часы стоят на ленте сразу).
    public var exit: Countdown?
    /// Аренда идёт сейчас: только тогда студийный режим держится.
    public var rentActive: Bool
    /// Подпись студии у выхода («Томсон»); пусто — без неё.
    public var studio: String
    /// Подписи кнопок студийного режима; `nil` — кнопки нет (нет номера админа / нет плейлиста / режим не студийный).
    public var call: String?
    public var playlist: String?
    /// Часы свёрнутого острова: до следующей точки, а за час до золотого часа — до него (решение оркестратора 26.10, обратимо).
    public var island: Countdown?
    /// Конец съёмки, мс; `nil` — незакрытая вручную (идёт, пока не нажмут «Завершить»).
    public var endsAt: Int64?
    /// Когда собрано, мс: по нему видно, насколько кадр отстал.
    public var asOf: Int64

    public init(mode: Mode, shootId: String, status: String, range: String, points: [Point], current: Int, next: Countdown?,
                exit: Countdown?, rentActive: Bool, studio: String, call: String?, playlist: String?, island: Countdown?,
                endsAt: Int64?, asOf: Int64) {
        self.mode = mode
        self.shootId = shootId
        self.status = status
        self.range = range
        self.points = points
        self.current = current
        self.next = next
        self.exit = exit
        self.rentActive = rentActive
        self.studio = studio
        self.call = call
        self.playlist = playlist
        self.island = island
        self.endsAt = endsAt
        self.asOf = asOf
    }

    private enum CodingKeys: String, CodingKey {
        case mode = "m", shootId = "id", status = "st", range = "r", points = "p", current = "c", next = "n", exit = "x"
        case rentActive = "ra", studio = "sn", call = "cl", playlist = "pl", island = "i", endsAt = "e", asOf = "o"
    }

    /// Потолок системы на состояние и свойства активности вместе (ActivityKit, документация Apple; не мерено).
    public static let limit = 4096
    /// Точек на ленте не больше: пересчёт на 4 КБ (`ActivityFrameTests.sixteenPointsFitTheSystemLimit`); лишние отбрасываются с краёв дня.
    public static let maxPoints = 16

    public var endsDate: Date? { endsAt.map { Moment(milliseconds: $0).date } }
    public var asOfDate: Date { Moment(milliseconds: asOf).date }
    public var startDate: Date? { points.first?.date }

    /// Кадр в JSON — тем, что система кладёт в активность (размер для проверки потолка).
    public var encodedSize: Int { (try? JSONEncoder().encode(self).count) ?? 0 }
}

/// Слова экрана активности на языке приложения: у расширения словаря нет, кадр несёт готовые строки (шаблоны: `{name}`).
public struct ActivityWords: Codable, Equatable, Sendable {
    public var nowAt = "Сейчас: {name}"
    public var soonAt = "Скоро: {name}"
    public var running = "Идёт съёмка"
    public var done = "Съёмка закончена"
    public var untilName = "Далее: {name}"
    public var untilGolden = "до золотого часа"
    public var exit = "Выход из зала"
    public var callAdmin = "Позвонить админу"
    public var playlist = "Плейлист"
    public var hourShort = "ч"
    public var minShort = "мин"

    public init() {}
}

/// Чем можно ответить кнопками студии: нет номера администратора — нет «Позвонить админу», нет плейлиста — нет «Плейлист»
/// (как на карточке: «нет номера — нет кнопки»). Сами номер и ссылка кадр не несёт — их знает только приложение.
public struct ActivityReach: Equatable, Sendable {
    public var admin: Bool
    public var playlist: Bool

    public init(admin: Bool = false, playlist: Bool = false) {
        self.admin = admin
        self.playlist = playlist
    }
}

extension ActivityFrame {

    /// За сколько до золотого часа свёрнутый остров считает до него (слово оркестратора 26.10: «за час до золотого часа»).
    public static let goldenLead: TimeInterval = 3600

    /// Кадр одной съёмки на момент `now`.
    ///
    /// - Parameters:
    ///   - mode: чего просят; студийный держится, только пока аренда идёт (`rentActive`), иначе кадр — лента.
    ///   - reach: что есть у кнопок студии; в ленте кнопок нет никогда.
    public static func make(feed: WidgetFeed, shoot s: WidgetFeed.Shoot, now: Date, mode: Mode = .route,
                            words w: ActivityWords = ActivityWords(), reach: ActivityReach = ActivityReach()) -> ActivityFrame {
        let spot = s.spot ?? feed.place
        let tz = spot.timeZone ?? feed.place.timeZone ?? .current
        func clock(_ d: Date) -> String { WidgetFrame.clock(d, in: tz, lang: feed.lang, clock12: feed.clock12) }
        func fill(_ template: String, _ name: String) -> String { template.replacingOccurrences(of: "{name}", with: name) }

        // Точки: маршрут по времени, золотой час встаёт после точек того же часа (как на ленте карточки).
        let stops = s.stops.sorted { $0.at < $1.at }
        var points = stops.map { Point(at: $0.at, time: clock($0.date), word: word($0.name), sign: $0.sign) }
        var names = stops.map(\.name)
        if s.wantsSunset, let g = spot.light(on: WidgetFeed.Spot.day(of: s.startDate, in: tz))?.golden {
            let ms = Moment(g).milliseconds
            if ms >= s.start, ms <= s.end {
                let i = points.firstIndex { $0.at > ms } ?? points.count
                points.insert(Point(at: ms, time: clock(g), word: feed.words[.golden].split(separator: " ").first.map(String.init) ?? feed.words[.golden],
                                    sign: "golden", gold: true), at: i)
                names.insert(feed.words[.golden], at: i)
            }
        }
        let nowMs = Moment(now).milliseconds
        var current = points.lastIndex { !$0.gold && $0.at <= nowMs } ?? -1
        if points.count > maxPoints {
            // Окно в `maxPoints` вокруг «сейчас»: система обрежет состояние сама и неизвестно где (из документации, не мерено), а лента,
            // что кончается раньше съёмки, молчала бы про остаток дня (ревью GPT к eedfc41). Подсвеченная точка и ближайшие вперёд — внутри.
            let lo = max(0, min(max(current, 0) - 4, points.count - maxPoints))
            points = Array(points[lo..<lo + maxPoints])
            names = Array(names[lo..<lo + maxPoints])
            current = current >= 0 ? current - lo : -1
            if current >= maxPoints { current = maxPoints - 1 }
        }
        let nextIndex = points.firstIndex { $0.at > nowMs }
        let finished = !s.open && s.endDate <= now
        names = names.map { clip($0) }

        let status: String
        if finished { status = w.done }
        else if current >= 0 { status = fill(w.nowAt, names[current]) }
        else if let first = points.firstIndex(where: { !$0.gold }) { status = fill(w.soonAt, names[first]) }
        else { status = w.running }

        var next: Countdown?
        if let i = nextIndex {
            next = Countdown(label: points[i].gold ? w.untilGolden : fill(w.untilName, names[i]), to: points[i].at)
        } else if !s.open, s.endDate > now {
            next = Countdown(label: s.genre == "wedding" ? feed.words[.untilWedding] : feed.words[.untilShoot], to: s.end)
        }

        // Аренда: идущая, а если нет — ближайшая впереди.
        let rents = s.rents.sorted { $0.from < $1.from }
        let active = rents.first { $0.from <= nowMs && $0.deadline > nowMs }
        let rent = active ?? rents.first { $0.from > nowMs }
        let exit = rent.map { Countdown(label: w.exit, to: $0.deadline) }
        let studioOn = mode == .studio && active != nil

        // Свёрнутый остров: за час до золотого часа — до него, иначе до следующей точки.
        var island = next
        if let g = points.first(where: { $0.gold }), Double(g.at - nowMs) / 1000 <= goldenLead, g.at > nowMs {
            island = Countdown(label: w.untilGolden, to: g.at)
        }

        var frame = ActivityFrame(
            mode: studioOn ? .studio : .route, shootId: s.id, status: status,
            range: range(s, tz: tz, clock: clock, words: w), points: points, current: current, next: next, exit: exit,
            rentActive: active != nil, studio: clip(rent?.studio ?? ""),
            call: studioOn && reach.admin ? w.callAdmin : nil, playlist: studioOn && reach.playlist ? w.playlist : nil,
            island: island, endsAt: s.open ? nil : s.end, asOf: nowMs)
        // Потолок системы на состояние: длинные слова клиента не должны молча лишить съёмку плашки — лента худеет с дальнего края.
        while frame.encodedSize + propertiesReserve > limit, frame.points.count > 2 {
            let dropFirst = frame.current > frame.points.count / 2
            if dropFirst { frame.points.removeFirst(); frame.current -= 1 } else { frame.points.removeLast(); frame.current = min(frame.current, frame.points.count - 1) }
        }
        return frame
    }

    /// Запас на свойства активности (id съёмки и момент запуска) и служебное системы.
    static let propertiesReserve = 300

    /// Имя в строке состояния и подписи часов: длинное название точки или студии режется (одна строка на плашке всё равно не больше).
    static func clip(_ s: String, _ n: Int = 40) -> String { s.count > n ? String(s.prefix(n - 1)) + "…" : s }

    /// «12:00 – 22:00 · 10 ч».
    static func range(_ s: WidgetFeed.Shoot, tz: TimeZone, clock: (Date) -> String, words w: ActivityWords) -> String {
        let minutes = max(0, Int((Double(s.end - s.start) / 60_000).rounded()))
        let h = minutes / 60, m = minutes % 60
        let length = h > 0 && m > 0 ? "\(h) \(w.hourShort) \(m) \(w.minShort)" : h > 0 ? "\(h) \(w.hourShort)" : "\(m) \(w.minShort)"
        return "\(clock(s.startDate)) – \(clock(s.endDate)) · \(length)"
    }

    /// На ленте помещается одно слово: «Сборы жениха» → «Сборы» (веб `laneWord`, `CardLane.word`).
    static func word(_ name: String) -> String {
        let w = name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return w.count > 11 ? String(w.prefix(10)) + "…" : w
    }
}

/// Ссылки кнопок экрана активности. Из плашки ссылка всегда ведёт в своё приложение (замер 30б.3а на телефоне: «Админ» и «Плейлист»
/// открыли приложение, а не звонилку и не плеер), поэтому приложение принимает её и передаёт дальше — набор номера и плеер.
public enum ActivityLink: String, Sendable, CaseIterable {
    case admin, playlist

    public var url: URL { URL(string: "lightplan://activity/\(rawValue)")! }

    /// `lightplan://activity/admin|playlist`; чужая ссылка — `nil`.
    public static func of(_ url: URL) -> ActivityLink? {
        guard url.scheme == "lightplan", url.host == "activity" else { return nil }
        return ActivityLink(rawValue: String(url.path.dropFirst()))
    }
}
