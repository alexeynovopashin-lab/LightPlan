import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
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

    // MARK: - AR на той же шкале и 12-часовые цифры

    @Test("AR ходит по той же календарной шкале: окно −60…1500, цифры и риски те же")
    func arUsesTheCalendarScale() {
        let place = Place(latitude: 53.35, longitude: 83.77, zone: ZoneID("Asia/Barnaul")!)
        let m = SunARModel(target: SunARTarget(place: place, moment: Moment(ISO8601DateFormatter().date(from: "2026-09-23T06:00:00Z")!)),
                           source: nil)
        #expect(m.timebar.scale == .calendar && m.timebar.scaleStart == -60 && m.timebar.scaleEnd == 1500)
        #expect(RulerDigits.labels(m.timebar.scaleMarks) == ["0", "3", "6", "9", "12", "15", "18", "21", "24"])
        // Поля: ручка уходит в −60 и 1500, день не меняется; Солнце и Луна считаются без падения.
        m.set(minutes: -40); #expect(m.minutes == -40 && m.day == m.timebar.machine.selectedDate)
        _ = m.sun; _ = m.moonPicked
        m.set(minutes: 1480); #expect(m.minutes == 1480)
        _ = m.sun; _ = m.moonPicked; _ = m.eventNote
    }

    @Test("цифры шкалы в 12 часах: 12AM, 3, 6, 9, 12PM, 3, 6, 9, 12AM; в 24 часах — 0, 3, … 24")
    func twelveHourDigits() {
        let marks = DayScale.calendar.marks(start: -60, end: 1500)
        func labels(_ c: ClockText) -> [String] { marks.compactMap { m in m.hour.map { c.scaleLabel(hour: $0) } } }
        let h12 = labels(ClockText(language: "en", preference: .h12))
        #expect(h12 == ["12AM", "3", "6", "9", "12PM", "3", "6", "9", "12AM"], "\(h12)")
        #expect(labels(ClockText(language: "en", preference: .h24)) == ["0", "3", "6", "9", "12", "15", "18", "21", "24"])
        // Правило то же, что у остальных часов: настройка, а без неё — привычка языка.
        #expect(ClockText(language: "en", preference: .auto).scaleLabel(hour: 12) == "12PM")
        #expect(ClockText(language: "ru", preference: .auto).scaleLabel(hour: 12) == "12")
        let ru12 = labels(ClockText(language: "ru", preference: .h12))
        #expect(ru12[1] == "3" && ru12[0].hasPrefix("12") && ru12[0].count > 2 && ru12[4].hasPrefix("12") && ru12[0] != ru12[4], "\(ru12)")
    }

    // MARK: - Цифры везде слушаются «Часов» (заход 3)

    private func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ") }

    @Test("час сетки «Съёмок»: 24 часа — «07:00», 12 часов — «7 AM»; полночь и 24-й час одинаковы")
    func gridHourLine() {
        let h24 = ClockText(language: "ru", preference: .h24)
        #expect(h24.hourLine(7) == "07:00" && h24.hourLine(0) == "00:00" && h24.hourLine(24) == "00:00" && h24.hourLine(18) == "18:00")
        let h12 = ClockText(language: "en", preference: .h12)
        #expect(plain(h12.hourLine(7)) == "7 AM" && plain(h12.hourLine(12)) == "12 PM" && plain(h12.hourLine(0)) == "12 AM")
        #expect(plain(h12.hourLine(24)) == "12 AM" && plain(h12.hourLine(23)) == "11 PM")
        // По-русски в 12 часах — слова платформы, но без «:00».
        let ru12 = ClockText(language: "ru", preference: .h12)
        for h in 0...24 { #expect(!ru12.hourLine(h).contains(":"), "\(h): \(ru12.hourLine(h))") }
        // Привычка языка, когда выбор «Как в языке».
        #expect(plain(ClockText(language: "en", preference: .auto).hourLine(15)) == "3 PM")
        #expect(ClockText(language: "ru", preference: .auto).hourLine(15) == "15:00")
    }

    @Test("лента дней: 6, 12, 18 в 24 часах, 6, 12PM, 6 в 12 часах — как шкала")
    func ribbonDigitsFollowTheClock() {
        let m = app()
        m.update { $0.clock = .h24 }
        #expect([6, 12, 18].map { m.light.timebar.hourLabel($0) } == ["6", "12", "18"])
        m.update { $0.clock = .h12 }
        #expect([6, 12, 18].map { m.light.timebar.hourLabel($0) } == ["6", "12PM", "6"], "\([6, 12, 18].map { m.light.timebar.hourLabel($0) })")
        #expect(m.light.timebar.hourLabel(12) == m.light.timebar.scaleMarks.compactMap { mk in mk.hour == 12 ? m.light.timebar.scaleLabel(mk) : nil }.first)
    }

    @Test("цифры часов на дуге прибора «Карты»: «03» в 24 часах, 12AM / 3 / 12PM в 12 часах")
    func mapInstrumentHourDigits() {
        let sun = SolarDay(date: Self.day, place: Self.moscow)
        func numbers(_ label: ((Int) -> String)?) -> [String] {
            var input = MapInstrument.Input(date: Self.day, minute: sun.solarNoon - 120, solar: sun, place: Self.moscow, layers: MapLayers(),
                                            pro: true, azimuths: false, lightTheme: false, chip: nil,
                                            clock: { ClockText(language: "en", preference: .h12).fmt($0) }, cardinals: ["N", "E", "S", "W"])
            if let label { input.hourLabel = label }
            let scene = MapInstrument.scene(input, day: MapInstrument.Day(date: Self.day, place: Self.moscow, solar: sun))
            return scene.elements.compactMap { if case .text(let str, _, let size, _, _, _, _, _) = $0, size == 9 { return str } else { return nil } }
        }
        let c12 = ClockText(language: "en", preference: .h12)
        let old = numbers(nil), new = numbers { c12.scaleLabel(hour: $0) }
        #expect(!old.isEmpty && old.allSatisfy { $0.count == 2 }, "\(old)")
        #expect(old.count == new.count)
        #expect(new.allSatisfy { ["12AM", "3", "6", "9", "12PM"].contains($0) }, "\(new)")
    }

    #if canImport(UIKit)
    @Test("12AM / 12PM не налезают на соседей и не режутся по краям: iPhone 14 (390) и 17 Pro Max (440)")
    func twelveHourDigitsFit() {
        let font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        var table = ""
        for (name, W) in [("17 Pro Max", 440.0), ("iPhone 14", 390.0)] {
            let canvas = W - 48                                           // ширина слоя цифр: плашка 8 + поле 16 с каждой стороны
            let track = canvas - 26
            for lang in ["en", "ru"] {
                let clock = ClockText(language: lang, preference: .h12)
                var prevRight = -Double.infinity
                for mark in DayScale.calendar.marks(start: -60, end: 1500) {
                    guard let h = mark.hour else { continue }
                    let text = clock.scaleLabel(hour: h)
                    let width = Double((text as NSString).size(withAttributes: [.font: font]).width)
                    let centre = 13 + DayScale.fraction(of: mark.minute, start: -60, end: 1500) * track
                    let left = centre - width / 2, right = centre + width / 2
                    table += String(format: "%@ %@ %@ x=%.1f w=%.1f [%.1f…%.1f] gap=%.1f\n", name, lang, text, centre + 24, width, left + 24, right + 24, left - prevRight)
                    #expect(left >= 0 && right <= canvas, "\(name) \(lang) \(text) режется: \(left)…\(right) из \(canvas)")
                    if prevRight > -Double.infinity { #expect(left - prevRight >= 6, "\(name) \(lang) \(text) вплотную к соседу: \(left - prevRight)") }
                    prevRight = right
                }
            }
        }
        print("SCALE12 \n" + table)
    }
    #endif
}
