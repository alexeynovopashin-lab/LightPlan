import Testing
import Foundation
@testable import LightPlanData
import LightPlanCore
import LightPlanDomain

/// Шаг 30.6: память «прогноз переменился» в снимке — общий файл с вебом, ключи `wxSeen` / `wxTold`.
struct WeatherMemoryTests {

    private func snap(_ q: DayQuality, _ sc: Int?) -> SkySnap { SkySnap(quality: q, sunset: sc) }

    @Test func roundTripKeepsTheWebShape() {
        var s = Snapshot()
        WeatherMemory.write(WeatherMemory.seenKey, ["a": snap(.good, 60), "b": snap(.fog, nil)], in: &s)
        #expect(s.extra["wxSeen"] == .object(["a": .object(["q": .string("good"), "sc": .number(60)]),
                                              "b": .object(["q": .string("fog"), "sc": .null])]))
        #expect(WeatherMemory.read(WeatherMemory.seenKey, in: s) == ["a": snap(.good, 60), "b": snap(.fog, nil)])
    }

    /// Отметка, которую натив не прочёл (другая версия веба), не стирается чужой записью.
    @Test func unreadableMarksSurviveAWrite() {
        var s = Snapshot()
        s.extra["wxTold"] = .object(["x": .string("future-format")])
        WeatherMemory.write(WeatherMemory.toldKey, ["a": snap(.poor, 5)], in: &s)
        guard case .object(let o)? = s.extra["wxTold"] else { Issue.record("нет ключа"); return }
        #expect(o["x"] == .string("future-format"))
        #expect(WeatherMemory.ids(WeatherMemory.toldKey, in: s) == ["a", "x"])
    }

    /// Обход: знакомство — в `wxSeen`, сказанное — в `wxTold`, несказанное (система не приняла) — никуда,
    /// ушедшие записи — из обоих.
    @Test func applyWritesOnlyWhatWasTold() {
        var s = Snapshot()
        WeatherMemory.write(WeatherMemory.seenKey, ["a": snap(.excellent, 90), "b": snap(.good, 60), "gone": snap(.good, 1)], in: &s)
        WeatherMemory.write(WeatherMemory.toldKey, ["gone": snap(.good, 1)], in: &s)
        let say = WeatherWatch.pass(items: [.init(id: "a", day: CivilDate(year: 2026, month: 10, day: 24), now: snap(.poor, 10)),
                                            .init(id: "b", day: CivilDate(year: 2026, month: 10, day: 25), now: snap(.poor, 10)),
                                            .init(id: "c", day: CivilDate(year: 2026, month: 10, day: 25), now: snap(.good, 50))],
                                    alive: ["a", "b", "c"],
                                    seen: WeatherMemory.read(WeatherMemory.seenKey, in: s), told: [:],
                                    memoryIds: ["a", "b", "gone"])
        #expect(say.say.map(\.id) == ["a", "b"])
        WeatherMemory.apply(say, told: say.say.filter { $0.id == "a" }, in: &s)
        let seen = WeatherMemory.read(WeatherMemory.seenKey, in: s), told = WeatherMemory.read(WeatherMemory.toldKey, in: s)
        #expect(told == ["a": snap(.poor, 10)])
        #expect(seen["c"] == snap(.good, 50))
        #expect(seen["gone"] == nil)
        #expect(seen["a"] == snap(.excellent, 90))      // `wxSeen` меняет только закрытие карточки
    }
}
