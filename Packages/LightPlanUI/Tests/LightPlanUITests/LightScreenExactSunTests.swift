import Testing
import Foundation
import LightPlanCore
import LightPlanData
@testable import LightPlanUI

/// Шаг 29.8в.25: экран «Свет» идёт по точному Солнцу (`SolarDay(.iau)`), а не по NOAA-модели веба. Тест строит ту же
/// телеметрию на Барнауле 23 сентября 2026 — сценарий `make shots` (13:00, 18:50, 23:00, 06:05) — двумя Солнцами и
/// печатает, какие строки экрана сдвинулись и насколько. Сдвиг ограничен замером шага (закат ≤ 2,2 мин, золотой час
/// ≤ 2 мин), чтобы никто не принял разницу в 20 минут за «точнее».
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct LightScreenExactSunTests {

    static let lexicon = Lexicon("ru")
    static let clock = ClockText(language: "ru")
    static let date = CivilDate(year: 2026, month: 9, day: 23)
    static let moments: [(String, Minutes)] = [("13:00", 780), ("18:50", 1130), ("23:00", 1380), ("06:05", 365)]

    static func telemetry(_ sun: SolarDay, _ t: Minutes) -> LightTelemetry {
        LightTelemetry.build(
            sun: sun, t: t, moon: false, moonSnapshot: nil, weather: nil, weatherStatus: .loading, air: nil,
            headerLocationName: "Барнаул", headerDateLabel: "СР · 23 сен", headerNote: "", lexicon: lexicon, clock: clock)
    }

    /// Все строки экрана, которые зависят от Солнца, в виде «подпись: значение».
    static func lines(_ tel: LightTelemetry) -> [String] {
        var out = ["время: \(tel.readout?.time ?? "—")", "фаза: \(tel.readout?.phase ?? "—")",
                   "золотой час: \(tel.golden)", "кнопка: \(tel.actionSubtitle)", "свет: \(tel.light)", "тень: \(tel.shadow)",
                   "дальше: \(tel.next.label) \(tel.next.value)"]
        for g in tel.proGroups { for r in g.rows { out.append("\(g.title) / \(r.label): \(r.value)") } }
        return out
    }

    @Test("«Свет», Барнаул 23.09.2026: строки экрана до (веб-Солнце) и после (точное); сдвиг события ≤ 2,5 мин")
    func screenNumbersMoved() throws {
        let place = Place(latitude: 53.3481, longitude: 83.7798, zone: ZoneID(fixedOffsetHours: 7))
        let web = SolarDay(date: Self.date, place: place, time: .web)
        let exact = SolarDay(date: Self.date, place: place)
        func clock(_ m: Minutes?) -> String { m.map(Self.clock.fmt) ?? "—" }
        print("Свет, Барнаул 23.09.2026 — события (минуты → часы:минуты, до / после, разница в секундах):")
        var worst = 0.0
        for (name, a, b) in [("восход", web.rise, exact.rise), ("полдень", web.solarNoon, exact.solarNoon), ("закат", web.set, exact.set),
                              ("золотой с", web.goldenB, exact.goldenB), ("синий до", web.blueB, exact.blueB),
                              ("гражданские до", web.civilB, exact.civilB), ("навигационные до", web.nauticalB, exact.nauticalB),
                              ("астро-ночь с", web.astroB, exact.astroB), ("астро-ночь до", web.astroA, exact.astroA)] {
            guard let a, let b else { continue }
            worst = max(worst, abs(a - b))
            print(String(format: "  %-18@ %@ → %@  %+5.0f с", name as NSString, clock(a) as NSString, clock(b) as NSString, (b - a) * 60))
        }
        #expect(worst > 0.2 && worst <= 2.5, "наибольший сдвиг события \(worst) мин")
        var changed = 0, total = 0
        for (label, t) in Self.moments {
            let old = Self.lines(Self.telemetry(web, t)), new = Self.lines(Self.telemetry(exact, t))
            #expect(old.count == new.count)
            for (a, b) in zip(old, new) {
                total += 1
                if a != b { changed += 1; print("  \(label)  было: \(a)\n         стало: \(b)") }
            }
        }
        print("Строк экрана, зависящих от Солнца: \(total), изменилось текстом: \(changed)")
        #expect(changed > 0)
    }
}
