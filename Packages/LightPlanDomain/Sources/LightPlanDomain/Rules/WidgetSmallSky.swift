import Foundation
import LightPlanCore

/// Малый виджет «окно неба» (30и.15, вариант Н2 листа `docs/30i13_big_widget.html` § 12; выбор Алексея 16.11 «Н2, в код»).
///
/// Слова Алексея 16.11: «мы делаем не часы, мы вдохновляемся этим дизайном… его задача не показывать текущее время и дату… окошко календаря —
/// сильный визуальный элемент». С часов взяты два приёма: окно неба с двумя холмами и окошко календаря с красным указателем.
/// - Небо: днём Солнце идёт от левого холма (восход) к правому (закат); ночью Луна стоит по возрасту, как на часах с лунной фазой:
///   новолуние спрятано за левым холмом, полная — в середине, убывающая уходит за правый.
/// - Холмы подписаны: левый — восход, правый — закат, под ними балл из 100.
/// - Окошко: дата ближайшей съёмки недели (соседние числа уходят за край, как на колесе), день, время, имена; съёмок на неделе нет —
///   закаты трёх следующих дней с баллом, указатель на лучшем.
/// Чистые функции от `WidgetFrame`; вид только рисует. Идущую съёмку малый показывает по-прежнему кольцом (`SmallLiveView`).
public enum SmallSky {

    // MARK: Небо

    public enum Sky: Equatable, Sendable { case day, twilight, night }

    public struct Look: Equatable, Sendable {
        public var sky: Sky
        /// Путь Солнца между холмами: 0 — центр диска на кромке левого холма (восход), 1 — правого (закат); за 0…1 диск уходит за холм.
        /// `nil` — Солнца в окне нет (ночь).
        public var sun: Double?
        /// Луна: положение в цикле 0…1, освещённая доля 0…1, растёт ли. Мест без координат — новолуние (Луны не видно).
        public var moonCycle: Double
        public var moonFraction: Double
        public var moonWaxing: Bool
    }

    /// Граница неба по высоте Солнца: выше +6° — день, от −6° до +6° — закатное небо (золотой и синий час), ниже −6° — ночь.
    public static let dayAbove: Degrees = 6
    public static let nightBelow: Degrees = -6
    /// Дальше этой доли за холм Солнце не уводится: с края окна оно всё равно не видно.
    public static let sunReach = 0.3

    public static func look(_ f: WidgetFrame) -> Look {
        let rise = f.day?.sunrise, set = f.day?.sunset
        var path: Double? = nil
        if let rise, let set, set > rise {
            let p = f.now.timeIntervalSince(rise) / set.timeIntervalSince(rise)
            path = min(1 + sunReach, max(-sunReach, p))
        } else if f.day?.polar == .day {
            path = 0.5
        }
        guard let sky = BigWidget.sky(f) else {
            // Файл без координат: небо по восходу и закату, Луны нет.
            let up = rise.map { f.now >= $0 } == true && set.map { f.now < $0 } == true || f.day?.polar == .day
            return Look(sky: up ? .day : .night, sun: up ? path : nil, moonCycle: 0, moonFraction: 0, moonWaxing: true)
        }
        let e = sky.sunElevation
        let kind: Sky = e >= dayAbove ? .day : e >= nightBelow ? .twilight : .night
        return Look(sky: kind, sun: kind == .night ? nil : (path ?? 0.5),
                    moonCycle: sky.moonCycle, moonFraction: sky.moonFraction, moonWaxing: sky.moonWaxing)
    }

    /// «60 %» — освещённая доля Луны целым процентом.
    public static func moonPercent(_ l: Look) -> String { "\(Int((l.moonFraction * 100).rounded())) %" }

    // MARK: Холмы

    public struct Hill: Equatable, Sendable {
        /// «08:56»; полярные сутки или нет места — «—».
        public var time: String
        /// Балл 0…100; `nil` — часа в прогнозе нет: число не выдумывается.
        public var score: Int?
    }

    /// Какие сутки подписаны на холмах: до сегодняшнего заката — сегодняшние восход и закат с оценками; после заката — завтрашние
    /// (впереди уже только они, как у среднего после заката).
    public static func hills(_ f: WidgetFrame) -> (rise: Hill, set: Hill) {
        let after = f.day?.sunset.map { f.now >= $0 } ?? false
        let day = after ? f.tomorrow : f.day
        let rating = after ? f.tomorrowRating : f.rating
        func time(_ d: Date?) -> String { d.map { f.clock($0, in: f.zone) } ?? "—" }
        return (Hill(time: time(day?.sunrise), score: rating?.sunrise), Hill(time: time(day?.sunset), score: rating?.score))
    }

    // MARK: Окошко календаря

    public struct ShootCell: Equatable, Sendable {
        public var id: String
        /// Число дня съёмки по часам её места и соседние числа колеса.
        public var day: Int
        public var before: Int
        public var after: Int
        /// «вс · 12:00».
        public var line: String
        /// Имена клиента (на «Домой» разрешены), нет — название съёмки.
        public var names: String
        public var genre: String?
    }

    public struct SunsetCell: Equatable, Sendable {
        /// «вс».
        public var day: String
        /// Балл заката.
        public var score: Int?
        /// Балл рассвета (31.7).
        public var dawn: Int? = nil

        public init(day: String, score: Int?, dawn: Int? = nil) { self.day = day; self.score = score; self.dawn = dawn }
    }

    /// Какой из шести баллов окошка лучший: день и событие.
    public struct Best: Equatable, Sendable {
        public var day: Int
        public var event: SkyEvent

        public init(day: Int, event: SkyEvent) { self.day = day; self.event = event }
    }

    public enum Window: Equatable, Sendable {
        case shoot(ShootCell)
        /// Три следующих дня парой «рассвет · закат» (31.7, Алексей 19.11, вопрос 1 «А»; до 31.7 — одни закаты); `best` — лучший из шести
        /// баллов (у ничьей — ранний: день раньше, в дне рассвет раньше заката), `nil` — баллов нет. Над ним — красный флажок.
        case sunsets([SunsetCell], best: Best?)
    }

    public static func window(_ f: WidgetFrame) -> Window {
        if let s = f.week.first {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = s.zone
            let start = s.shoot.startDate
            func num(_ off: Int) -> Int { cal.component(.day, from: cal.date(byAdding: .day, value: off, to: start) ?? start) }
            let named = (s.shoot.names ?? "").trimmingCharacters(in: .whitespaces)
            return .shoot(ShootCell(id: s.id, day: num(0), before: num(-1), after: num(1),
                                    line: "\(f.weekday(start, in: s.zone).lowercased()) · \(f.clock(start, in: s.zone))",
                                    names: named.isEmpty ? s.shoot.title : named, genre: s.shoot.genre))
        }
        let cells = f.ahead.map { SunsetCell(day: f.weekday($0.noon, in: f.zone).lowercased(), score: $0.rating?.score, dawn: $0.rating?.sunrise) }
        let six = cells.flatMap { [$0.dawn, $0.score] }
        return .sunsets(cells, best: best(six).map { Best(day: $0 / 2, event: $0 % 2 == 0 ? .dawn : .sunset) })
    }

    /// Индекс наибольшего балла; у ничьей — ранний день; баллов нет — `nil`.
    public static func best(_ scores: [Int?]) -> Int? {
        var at: Int? = nil
        for (i, s) in scores.enumerated() { if let s, at.map({ s > (scores[$0] ?? -1) }) ?? true { at = i } }
        return at
    }

    /// Плашка малого без идущей съёмки рисуется окном неба, когда приложение оставило место; места нет — прежний вид («—»).
    public static func shows(_ f: WidgetFrame) -> Bool { f.kind != .live && f.kind != .blank }
}
