import Foundation
import LightPlanCore

/// Обход «прогноз переменился» (веб `wxAnnounce`, итерация 30, шаг 30.6): какие съёмки сказать вслух и что запомнить.
///
/// Один и тот же обход у двух каналов — баннера при запуске и возврате в приложение и уведомления из фона.
/// Единственная память обоих — `wxTold` снимка: сказал один канал — второй молчит, пока прогноз не ушёл дальше.
/// Правило — функция данных: снимки неба на входе, решения на выходе, без часов, сети и системы уведомлений.
public enum WeatherWatch {

    /// Съёмка, за которой следим и у которой есть настоящий прогноз якоря (веб `wxWatched` + `wxSnap`).
    public struct Item: Sendable, Equatable {
        public let id: String
        public let day: CivilDate
        public let now: SkySnap

        public init(id: String, day: CivilDate, now: SkySnap) {
            self.id = id
            self.day = day
            self.now = now
        }
    }

    /// Что сказать про одну съёмку: насколько разошлось, с чем сравнивали и куда.
    public struct Say: Sendable, Equatable {
        public let id: String
        public let day: CivilDate
        public let gap: Int
        public let was: SkySnap
        public let now: SkySnap
        public var isUp: Bool { WeatherShift.isUp(was, now) }
    }

    public struct Pass: Sendable, Equatable {
        /// Первое знакомство: записать в `wxSeen` молча — числа, которого человек не видел, он не мог и потерять.
        public var seed: [String: SkySnap] = [:]
        /// Сказать вслух — самое тяжёлое и ближнее первым (веб `say.sort`). `wxTold[id] = now` пишет тот, кто сказал.
        public var say: [Say] = []
        /// Отметки записей, которых больше нет: стереть из `wxSeen` и `wxTold`.
        public var dead: [String] = []

        /// Обход что-то меняет в памяти, даже если говорить нечего.
        public var writes: Bool { !seed.isEmpty || !dead.isEmpty }
    }

    /// Обход целиком. `alive` — id всех записей снимка (не только тех, за кем следим): отметку живой съёмки,
    /// ушедшей из окна прогноза, не стираем — она вернётся в окно с той же памятью.
    public static func pass(items: [Item], alive: Set<String>,
                            seen: [String: SkySnap], told: [String: SkySnap],
                            memoryIds: Set<String> = []) -> Pass {
        var out = Pass()
        out.dead = memoryIds.subtracting(alive).sorted()
        for it in items {
            guard let was = seen[it.id] else { out.seed[it.id] = it.now; continue }
            let w = WeatherShift.gap(was, it.now)
            guard w > 0 else { continue }
            // Об этом уже говорили. Но если прогноз ушёл дальше — это новость снова.
            if let t = told[it.id], WeatherShift.gap(t, it.now) == 0 { continue }
            out.say.append(Say(id: it.id, day: it.day, gap: w, was: was, now: it.now))
        }
        out.say.sort { a, b in a.gap != b.gap ? a.gap > b.gap : a.day.ordinal < b.day.ordinal }
        return out
    }
}

/// Очередь баннеров (веб `notifQueued`): место у баннера одно, а поводов бывает несколько разом. Потолок — два
/// показа подряд, остальные считаются числом «И ещё N» у последнего показанного (решение Алексея, 8 сентября 2026).
public struct NoticeQueue: Sendable, Equatable {
    public struct Notice: Sendable, Equatable {
        public let title: String
        public let text: String
        /// Запись, которую открывает нажатие; `nil` — баннер ничего не открывает.
        public let sessionId: String?

        public init(title: String, text: String, sessionId: String?) {
            self.title = title
            self.text = text
            self.sessionId = sessionId
        }
    }

    public static let cap = 2

    public private(set) var items: [Notice] = []
    /// Сколько поводов не влезло: дописывается к последнему показанному.
    public private(set) var more = 0

    public init() {}

    /// Поставить повод; `more` — сколько ещё таких же он представляет (обход сказал одну съёмку из пяти).
    /// `true` — очередь была пуста, показ надо начать.
    @discardableResult
    public mutating func push(_ n: Notice, more extra: Int = 0) -> Bool {
        more += max(0, extra)
        guard items.count < Self.cap else { more += 1; return false }
        items.append(n)
        return items.count == 1
    }

    /// Тот, что на экране.
    public var current: Notice? { items.first }

    /// «И ещё N» живёт у последнего из показанных: хвост есть, только когда за текущим никого.
    public var tail: Int { items.count == 1 ? more : 0 }

    /// Текущий показан до конца — следующий; очередь опустела — счёт сброшен.
    public mutating func advance() {
        if !items.isEmpty { items.removeFirst() }
        if items.isEmpty { more = 0 }
    }
}
