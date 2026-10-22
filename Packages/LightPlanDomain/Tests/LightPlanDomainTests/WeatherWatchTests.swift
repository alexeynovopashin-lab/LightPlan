import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Шаг 30.6: обход «прогноз переменился» (веб `wxAnnounce`) и очередь баннеров (веб `notifQueued`).
struct WeatherWatchTests {

    private func snap(_ q: DayQuality, _ sc: Int?) -> SkySnap { SkySnap(quality: q, sunset: sc) }
    private func day(_ d: Int) -> CivilDate { CivilDate(year: 2026, month: 10, day: d) }
    private func item(_ id: String, _ d: Int, _ now: SkySnap) -> WeatherWatch.Item { .init(id: id, day: day(d), now: now) }

    /// Первое знакомство — не смена: пишется в `wxSeen` молча, сказать нечего.
    @Test func firstSightIsSilentSeed() {
        let p = WeatherWatch.pass(items: [item("a", 24, snap(.good, 60))], alive: ["a"], seen: [:], told: [:])
        #expect(p.say.isEmpty)
        #expect(p.seed == ["a": snap(.good, 60)])
    }

    @Test func changeAgainstSeenIsSaid() {
        let p = WeatherWatch.pass(items: [item("a", 24, snap(.poor, 10))], alive: ["a"],
                                  seen: ["a": snap(.excellent, 85)], told: [:])
        #expect(p.say.map(\.id) == ["a"])
        #expect(p.say.first?.gap == 3)
        #expect(p.say.first?.isUp == false)
        #expect(p.seed.isEmpty)
    }

    @Test func noChangeIsNotSaid() {
        let p = WeatherWatch.pass(items: [item("a", 24, snap(.good, 60))], alive: ["a"],
                                  seen: ["a": snap(.good, 70)], told: [:])
        #expect(p.say.isEmpty)
    }

    /// Уже сказали ровно это (другой канал или прошлый заход) — молчим; прогноз ушёл дальше — снова новость.
    @Test func toldIsTheSingleMemoryOfBothChannels() {
        let seen = ["a": snap(.excellent, 85)]
        let told = ["a": snap(.poor, 10)]
        let same = WeatherWatch.pass(items: [item("a", 24, snap(.poor, 12))], alive: ["a"], seen: seen, told: told)
        #expect(same.say.isEmpty)
        let further = WeatherWatch.pass(items: [item("a", 24, snap(.good, 60))], alive: ["a"], seen: seen, told: told)
        #expect(further.say.map(\.id) == ["a"])
    }

    /// Самое тяжёлое первым, при равном весе — ближнее.
    @Test func heaviestThenNearestFirst() {
        let seen = ["a": snap(.good, 60), "b": snap(.good, 60), "c": snap(.good, 60)]
        let p = WeatherWatch.pass(items: [item("a", 26, snap(.plain, 60)),      // 2
                                          item("b", 25, snap(.poor, 60)),       // 3
                                          item("c", 24, snap(.plain, 60))],     // 2
                                  alive: ["a", "b", "c"], seen: seen, told: [:])
        #expect(p.say.map(\.id) == ["b", "c", "a"])
    }

    /// Отметки ушедших записей стираются; живой, но вышедшей из окна прогноза — остаются.
    @Test func deadMarksAreCleaned() {
        let p = WeatherWatch.pass(items: [], alive: ["a"], seen: ["a": snap(.good, 1), "gone": snap(.good, 1)],
                                  told: [:], memoryIds: ["a", "gone"])
        #expect(p.dead == ["gone"])
        #expect(p.writes)
    }

    // MARK: - Очередь

    private func n(_ t: String) -> NoticeQueue.Notice { .init(title: t, text: t, sessionId: t) }

    /// Потолок два: третий и дальше считаются числом у последнего показанного.
    @Test func queueCapsAtTwoAndCountsTheRest() {
        var q = NoticeQueue()
        #expect(q.push(n("1")) == true)
        #expect(q.push(n("2")) == false)
        q.push(n("3"))
        q.push(n("4"), more: 2)
        #expect(q.items.map(\.title) == ["1", "2"])
        #expect(q.more == 4)
        #expect(q.tail == 0)          // за первым стоит второй — хвост не у него
        q.advance()
        #expect(q.current?.title == "2")
        #expect(q.tail == 4)
        q.advance()
        #expect(q.current == nil)
        #expect(q.more == 0)
    }

    /// Одна новость про одну съёмку из трёх: «И ещё 2» у неё же.
    @Test func singleNoticeCarriesItsOwnMore() {
        var q = NoticeQueue()
        q.push(n("1"), more: 2)
        #expect(q.tail == 2)
    }
}
