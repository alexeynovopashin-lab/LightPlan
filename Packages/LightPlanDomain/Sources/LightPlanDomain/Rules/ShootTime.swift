import Foundation
import LightPlanCore

/// Свет, под который заказали съёмку (шаг 30д, слово Алексея 04.11): рассвет, закат или звёзды этого дня.
/// Минуты — от полуночи дня съёмки.
public struct LightGoal: Sendable, Equatable {
    public let wish: Wish
    /// Минута, которую называет всплывашка: сам закат, рассвет, начало темноты.
    public let event: Int
    /// Окно света: съёмка, которая его касается, не трогается.
    public let from: Int
    public let to: Int
    /// Звёзды: темнота прошлой ночи ещё идёт до этой минуты утра.
    public let darkUntil: Int?

    public init(wish: Wish, event: Int, from: Int, to: Int, darkUntil: Int? = nil) {
        self.wish = wish
        self.event = event
        self.from = from
        self.to = to
        self.darkUntil = darkUntil
    }

    /// Окно по солнцу дня. Закат — от начала золотого часа до конца синего, рассвет — наоборот, от начала синего
    /// до конца золотого. Нет такого света (полярные сутки, белая ночь) или он за пределами дня — предлагать нечего.
    public static func of(_ w: Wish, sun: SolarDay) -> LightGoal? {
        func m(_ v: Double) -> Int { Int(v.rounded()) }
        let goal: LightGoal?
        switch w {
        case .sunset:
            guard let a = sun.goldenB, let e = sun.set, let b = sun.blueB else { return nil }
            goal = LightGoal(wish: w, event: m(e), from: m(a), to: m(b))
        case .sunrise:
            guard let a = sun.blueA, let e = sun.rise, let b = sun.goldenA else { return nil }
            goal = LightGoal(wish: w, event: m(e), from: m(a), to: m(b))
        case .stars:
            guard let a = sun.astroB else { return nil }
            goal = LightGoal(wish: w, event: m(a), from: m(a), to: m(sun.astroA ?? 0) + 1440, darkUntil: sun.astroA.map(m))
        default:
            return nil
        }
        guard let goal, (0..<1440).contains(goal.from) else { return nil }
        return goal
    }
}

/// Что делать со временем съёмки под заказанный свет.
public enum TimeNudge: Sendable, Equatable {
    /// Съёмка касается света — не вмешиваемся.
    case keep
    /// Съёмка раньше света: может быть, с запасом на дорогу и сборы. Спросить всплывашкой.
    case ask(to: Int)
    /// Свет уже прошёл: сдвинуть без всплывашки и подсветить время.
    case shift(to: Int)
}

public enum ShootTime {
    /// Первая съёмка дня без заказанного света (ответ Алексея 1А).
    public static let noon = 720

    /// Куда начало съёмки просится под этот свет (ответ 3А): начало окна; съёмка длиннее окна кончается вместе с ним.
    public static func target(duration: Int, goal g: LightGoal) -> Int {
        if duration > g.to - g.from, g.to - duration >= 0 { return g.to - duration }
        return g.from
    }

    /// Правило Алексея: 15:00 при закате в 20:00 — спросить, 21:00 — сдвинуть без вопроса; пока съёмка касается окна — молчим (ответ 4А).
    public static func nudge(start: Int, duration: Int, goal g: LightGoal) -> TimeNudge {
        let end = start + duration
        if touches(start: start, end: end, goal: g) { return .keep }
        let to = target(duration: duration, goal: g)
        if end <= g.from { return to == start ? .keep : .ask(to: to) }
        return to == start ? .keep : .shift(to: to)
    }

    static func touches(start: Int, end: Int, goal g: LightGoal) -> Bool {
        if start < g.to && end > g.from { return true }
        if let d = g.darkUntil, start < d { return true }
        return false
    }

    /// Вверх до шага времени, чтобы новая запись не въезжала в конец прошлой.
    static func stepUp(_ m: Int, step: Int) -> Int {
        step > 0 ? Int((Double(m) / Double(step)).rounded(.up)) * step : m
    }

    /// Время новой записи, которой минуту не назвали (ответы 1А и 2Б): первая на день — в полдень, следующая — сразу
    /// после конца последней записи дня. Занятость «весь день» времени не двигает, у неё своя плашка. Места до полуночи
    /// нет — последний шаг дня: день, выбранный человеком, молча не меняем.
    public static func defaultStart(day: CivilDate, sessions: [Session], blocks: [Block], eventsLayer: Bool, step: Int) -> Int {
        var last: Int?
        var spill = 0                    // хвост вчерашней записи, ушедшей за полночь
        func took(_ d: CivilDate, end: Int) {
            if d == day { last = max(last ?? 0, end) } else if d == day.adding(days: -1) { spill = max(spill, end - 1440) }
        }
        for s in sessions where s.isShown(eventsLayer: eventsLayer) { took(s.day, end: s.endMinute) }
        for b in blocks where !b.allDay { took(b.from, end: (b.start ?? 0) + (b.duration ?? 0)) }
        let start: Int
        if let last { start = max(last, spill) } else { start = max(noon, spill) }
        let up = stepUp(start, step: step)
        return up < 1440 ? up : 1440 - max(step, 1)
    }

    /// Куда уйти от наложения (пункт Г всплывашек): `busy` отвечает концом занятого, которое накрывает съёмку, или `nil`.
    /// Первое свободное место после него на этот же день; до полуночи места нет — предлагать нечего.
    public static func freeSpot(start: Int, duration: Int, step: Int, busy: (Int, Int) -> Int?) -> (until: Int, to: Int)? {
        guard let until = busy(start, duration) else { return nil }
        var to = stepUp(until, step: step)
        for _ in 0..<64 {
            guard to < 1440 else { return nil }
            guard let next = busy(to, duration) else { return (until, to) }
            guard next > to else { return nil }
            to = stepUp(next, step: step)
        }
        return nil
    }

    /// Конец занятого, что по времени накрывает кандидата: другая запись или занятость по часам.
    /// «Впритык» и выезд — не наложение, у них свои плашки; занятый целиком день отсюда не сдвинуть.
    public static func busyUntil(_ c: ClashCandidate, sessions: [Session], blocks: [Block], context: ClashContext) -> Int? {
        Overlaps.clashes(for: c, sessions: sessions, blocks: blocks, context: context)
            .filter { $0.kind == .overlap || $0.kind == .timeBusy }
            .compactMap(\.to).max()
    }
}

/// Всплывашка формы о времени. Ответ — `EventForm.answer`.
public struct TimeAsk: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case light(Wish)
        case busy
    }
    public let kind: Kind
    /// Минута в заголовке: закат, рассвет, начало темноты; у наложения — конец занятого.
    public let at: Int
    public let to: Int
    public let keep: Int
    public var id: String { "\(kind)-\(at)-\(to)-\(keep)" }

    public init(kind: Kind, at: Int, to: Int, keep: Int) {
        self.kind = kind
        self.at = at
        self.to = to
        self.keep = keep
    }
}

extension EventForm {
    /// Что про время знает приложение, а форма нет: свет дня и записи этого дня.
    public struct TimeFacts {
        /// Окна заказанного света в порядке пожеланий формы.
        public var goals: [LightGoal]
        public var defaultStart: Int
        public var step: Int
        /// Конец занятого, что накрывает съёмку с такими началом и длительностью.
        public var busy: (Int, Int) -> Int?

        public init(goals: [LightGoal], defaultStart: Int, step: Int, busy: @escaping (Int, Int) -> Int?) {
            self.goals = goals
            self.defaultStart = defaultStart
            self.step = step
            self.busy = busy
        }
    }

    /// Время никто не называл: оно следует за правилами сразу и без вопросов.
    /// С заказанным светом — под него с подсветкой, без него — время по умолчанию.
    public mutating func followProposal(_ facts: TimeFacts) {
        guard timeIsProposed else { return }
        if mode != .meet, let g = facts.goals.last {
            let to = ShootTime.target(duration: duration, goal: g)
            if to != start { moveStart(to: to); timeShifted = true }
            timeIsProposed = true
            timeFromLight = true
        } else {
            if facts.defaultStart != start { moveStart(to: facts.defaultStart) }
            timeShifted = false
            timeIsProposed = true
            timeFromLight = false
        }
    }

    /// Время встало (закрылось колесо, выбран день, нажато пожелание): что делать дальше.
    /// Возвращает всплывашку, если нужно спросить. Свет спрашивается раньше наложения.
    public mutating func settleTime(_ facts: TimeFacts) -> TimeAsk? {
        guard !dayUnset else { return nil }
        if timeIsProposed {
            followProposal(facts)
        } else if mode != .meet, !facts.goals.contains(where: { ShootTime.nudge(start: start, duration: duration, goal: $0) == .keep }),
                  let g = facts.goals.last {
            switch ShootTime.nudge(start: start, duration: duration, goal: g) {
            case .keep: break
            case .shift(let to):
                moveStart(to: to)
                timeFromLight = true
                timeShifted = true
            case .ask(let to):
                if !timeAsksDeclined.contains(.light(g.wish)) {
                    return TimeAsk(kind: .light(g.wish), at: g.event, to: to, keep: start)
                }
            }
        }
        return busyAsk(facts)
    }

    private func busyAsk(_ facts: TimeFacts) -> TimeAsk? {
        guard !timeAsksDeclined.contains(.busy),
              let spot = ShootTime.freeSpot(start: start, duration: duration, step: facts.step, busy: facts.busy) else { return nil }
        return TimeAsk(kind: .busy, at: spot.until, to: spot.to, keep: start)
    }

    /// Чип пожелания со временем: только что заказанный свет спрашивает заново, даже если раньше ответили «Оставить».
    public mutating func toggleWish(_ w: Wish, facts: (EventForm) -> TimeFacts) -> TimeAsk? {
        toggle(wish: w)
        let f = facts(self)
        if timeIsProposed { return settleTime(f) }
        guard wishOn(w), f.goals.contains(where: { $0.wish == w }) else { return nil }
        timeAsksDeclined.remove(.light(w))
        return settleTime(f)
    }

    /// Ответ на всплывашку: сдвинуть или оставить. «Оставить» — в этой форме про то же больше не спрашиваем (ответ 5А).
    /// После ответа про свет может спросить про наложение.
    public mutating func answer(_ ask: TimeAsk, move: Bool, facts: (EventForm) -> TimeFacts) -> TimeAsk? {
        if move {
            moveStart(to: ask.to)
            timeFromLight = { if case .light = ask.kind { true } else { false } }()
            timeShifted = false
        } else {
            timeAsksDeclined.insert(ask.kind)
        }
        if case .busy = ask.kind { return nil }
        return busyAsk(facts(self))
    }

    /// Начало меняет правило, а не человек: часы точек дня едут за ним так же, как при правке руками.
    private mutating func moveStart(to m: Int) {
        setStart(minute: m)
    }
}
