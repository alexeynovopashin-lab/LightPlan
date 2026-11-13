import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 30з.4: шкала «Света» — календарные сутки и по часу живого времени с каждой стороны (−60…1500). Что видно на экране и каждый
/// читатель минуты, у которого теперь бывает отрицательное значение или значение выше 1440.
@MainActor
struct Scale30z4Tests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }
    private final class Disk: DraftStoring, @unchecked Sendable {
        var data: Data?
        func load() -> Data? { data }
        func save(_ data: Data?) { self.data = data }
    }

    private static let now = ISO8601DateFormatter().date(from: "2026-11-13T12:00:00+03:00")!
    private static let moscow = Place(latitude: 55.75, longitude: 37.62, zone: ZoneID("Europe/Moscow")!)
    private static let day = CivilDate(year: 2026, month: 11, day: 13)

    private func app(language: String = "ru") -> AppModel {
        let now = Self.now
        let app = AppModel(snapshot: Snapshot(), store: nil, language: language, zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather(),
                           now: { now })
        app.draftStore = Disk()
        app.light.timebar.setPlace(Self.moscow)
        app.light.timebar.show(day: Self.day, minute: 720)
        return app
    }

    // MARK: - Что показывает шкала

    @Test("приложение ходит по календарной шкале: окно −60…1500 в Москве и в Томске")
    func appUsesTheCalendarScale() {
        let app = app()
        #expect(app.light.timebar.scale == .calendar)
        #expect(app.light.timebar.scaleStart == -60 && app.light.timebar.scaleEnd == 1500)
        app.light.timebar.setPlace(Place(latitude: 56.49, longitude: 84.95, zone: ZoneID("Asia/Tomsk")!))
        #expect(app.light.timebar.scaleStart == -60 && app.light.timebar.scaleEnd == 1500)
    }

    @Test("цифры над треком — 0, 3, … 24; каждая стоит ровно над своей риской")
    func digitsStandOverTheirTicks() {
        let marks = app().light.timebar.scaleMarks
        #expect(RulerDigits.labels(marks) == ["0", "3", "6", "9", "12", "15", "18", "21", "24"])
        // x цифры и x риски — одна формула на одной метке: ширина трека w, поле 13 с каждого края.
        for w in [361.0, 392.0] {                                   // iPhone 14: плашка 390−16·2 −…, 17 Pro Max: шире
            for m in marks {
                let tick = DayScale.fraction(of: m.minute, start: -60, end: 1500) * (w - 26) + 13
                if m.digit != nil {
                    let digit = RulerDigits.inset + DayScale.fraction(of: m.minute, start: -60, end: 1500) * (w - 2 * RulerDigits.inset)
                    #expect(abs(tick - digit) < 1e-9)
                }
            }
        }
        // Ярусы по длине: длинная выше средней, средняя выше короткой.
        #expect(RulerView.height(of: .long) > RulerView.height(of: .medium) && RulerView.height(of: .medium) > RulerView.height(of: .short))
    }

    @Test("рельс красится по окну шкалы: от −60 до 1500, высота солнца вчерашней ночью и завтрашним утром считается честно")
    func railGradientCoversTheScale() {
        let app = app()
        let day = app.light.timebar.solarDay
        let g = PathStops.railGradient(day: day, from: -60, to: 1500)
        #expect(g.stops.first?.location == 0 && g.stops.last?.location == 1)
        #expect(g.stops.count == 157)                               // каждые 10 минут, 1560 / 10 + 1
        #expect(g.stops.map(\.location) == g.stops.map(\.location).sorted())
    }

    // MARK: - Щелчки: счёт часа

    @Test("час для щелчка: −30 — это час −1, а не 0; переход через 00:00 слева щёлкает")
    func hourIndexFloorsNegativeMinutes() {
        #expect(TimebarState.hourIndex(-60) == -1 && TimebarState.hourIndex(-1) == -1)
        #expect(TimebarState.hourIndex(0) == 0 && TimebarState.hourIndex(59.9) == 0)
        #expect(TimebarState.hourIndex(60) == 1 && TimebarState.hourIndex(1439) == 23)
        #expect(TimebarState.hourIndex(1440) == 24 && TimebarState.hourIndex(1500) == 25)
    }

    // MARK: - Экран в полях шкалы: часы, шапка, лента

    private func telemetry(_ app: AppModel, at minute: Double) -> LightTelemetry {
        app.light.timebar.show(day: Self.day, minute: minute)
        return app.light.telemetry
    }

    @Test("23:20 в левом поле: часы 23:20, дата в шапке — вчерашняя, день под ползунком остаётся выбранным")
    func leftMargin() {
        let app = app()
        let t = telemetry(app, at: -40)
        #expect(app.light.timebar.machine.selectedDate == Self.day && app.light.timebar.machine.viewMinute == -40)
        #expect(t.readout?.time == "23:20")
        #expect(t.header.dateLabel.contains("12"), "шапка: \(t.header.dateLabel)")      // четверг 12 ноября
        #expect(!(t.readout?.phase.isEmpty ?? true))
    }

    @Test("00:00 и 24:00 внутри шкалы: 00:00 — дата выбранного дня, 24:00 — уже следующего")
    func midnightsOnTheScale() {
        let app = app()
        let zero = telemetry(app, at: 0)
        #expect(zero.readout?.time == "00:00" && zero.header.dateLabel.contains("13"))
        let end = telemetry(app, at: 1440)
        #expect(end.readout?.time == "00:00" && end.header.dateLabel.contains("14"))
    }

    @Test("00:40 в правом поле: часы 00:40, дата в шапке — следующая, «условия» считаются по солнцу этих суток")
    func rightMargin() {
        let app = app()
        let t = telemetry(app, at: 1480)
        #expect(t.readout?.time == "00:40" && t.header.dateLabel.contains("14"))
        #expect(app.light.timebar.machine.selectedDate == Self.day)
    }

    @Test("«Запланировать съёмку» в полях: день соседних суток, время по часам места")
    func planShootInTheMargins() {
        let app = app()
        app.light.timebar.show(day: Self.day, minute: -40)
        #expect(app.light.planShoot.day == Self.day.adding(days: -1) && app.light.planShoot.start == 1400)
        app.light.timebar.show(day: Self.day, minute: 1480)
        #expect(app.light.planShoot.day == Self.day.adding(days: 1) && app.light.planShoot.start == 40)
        #expect(app.light.planShootTime == "00:40")
    }

    @Test("температура на шкале: −40 и 1400 минут — одна и та же температура (суточная кривая периодична)")
    func temperatureIsPeriodic() {
        for base in [-5, 4, 20] {
            #expect(LightTelemetry.tempOut(base, -40) == LightTelemetry.tempOut(base, 1400))
            #expect(LightTelemetry.tempOut(base, 1500) == LightTelemetry.tempOut(base, 60))
        }
    }

    // MARK: - Купол и ползунок приходят в одну минуту

    @Test("палец на куполе: минута не выходит из окна шкалы и совпадает с дугой светила")
    func domeFingerLandsInsideTheScale() {
        let app = app()
        let size = CGSize(width: 390, height: DomeView.height)
        let sun = app.light.timebar.solarDay
        var seen: [Minutes] = []
        for x in stride(from: 20.0, through: 370.0, by: 25) {
            guard let t = app.light.domeMinute(at: CGPoint(x: x, y: 150), in: size) else { continue }
            seen.append(t)
            #expect(t >= -60 && t <= 1500 && t >= sun.arcA.rounded() - 1 && t <= sun.arcB.rounded() + 1)
        }
        #expect(seen.count > 5 && seen == seen.sorted())
        // Тот же момент, что у ручки: dragDome кладёт минуту в машину как есть, ручка стоит на её доле окна.
        app.light.timebar.dragDome(to: 1490)
        #expect(app.light.timebar.machine.viewMinute == 1490)
        app.light.timebar.dragDome(to: -999)
        #expect(app.light.timebar.machine.viewMinute == -60)
    }

    @Test("Луна в полях: снимок для «Подробно» и дуга считаются без падения")
    func moonInTheMargins() {
        let app = app()
        app.light.moon = true
        app.light.moonMode = true
        for m in [-60.0, -40, 1480, 1500] {
            let t = telemetry(app, at: m)
            #expect(t.readout == nil)                               // в лунном режиме показание купола — луна
            #expect(!t.proGroups.isEmpty)
        }
    }

    @Test("«что дальше» и тень в полях: слова на месте, падения нет")
    func nextLightAndShadowInTheMargins() {
        let app = app()
        for m in [-60.0, -40, 1480, 1500] {
            let t = telemetry(app, at: m)
            #expect(!t.shadow.isEmpty && !t.next.label.isEmpty)
        }
    }
}
