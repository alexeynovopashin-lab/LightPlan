import Testing
import Foundation
@testable import LightPlanCore

/// 30з.4: шкала ползунка «Света» — календарные сутки и по часу живого времени с каждой стороны (−60…1500 минут).
struct DayScaleTests {

    private static let tomsk = Place(latitude: 56.49, longitude: 84.95, zone: ZoneID(fixedOffsetHours: 7))
    private static let moscow = Place(latitude: 55.75, longitude: 37.62, zone: ZoneID(fixedOffsetHours: 3))
    private static let tromso = Place(latitude: 69.65, longitude: 18.96, zone: ZoneID(fixedOffsetHours: 1))

    @Test("окно календарной шкалы одно в любом городе и в любое время года")
    func windowIsTheSameEverywhere() {
        let days = [CivilDate(year: 2026, month: 6, day: 21), CivilDate(year: 2026, month: 12, day: 21), CivilDate(year: 2026, month: 11, day: 13)]
        for place in [Self.tomsk, Self.moscow, Self.tromso] {
            for date in days {
                let w = DayScale.calendar.window(for: SolarDay(date: date, place: place))
                #expect(w.start == -60 && w.end == 1500)
            }
        }
        #expect(DayScale.calendarEnd - DayScale.calendarStart == 26 * 60)
    }

    @Test("солнечная шкала — прежнее окно истинного полудня ± 12 ч")
    func solarWindowIsUnchanged() {
        let day = SolarDay(date: CivilDate(year: 2026, month: 11, day: 12), place: Self.tomsk)
        let w = DayScale.solar.window(for: day)
        #expect(w.start == day.mint && w.end == day.maxt)
        #expect(w.end - w.start == 1440)
    }

    @Test("цифры над шкалой: 0, 3, 6, … 24 — над краевыми часами цифр нет")
    func digitsAreZeroTo24EveryThree() {
        let marks = DayScale.calendar.marks(start: -60, end: 1500)
        #expect(marks.compactMap(\.digit) == ["0", "3", "6", "9", "12", "15", "18", "21", "24"])
        #expect(marks.first?.digit == nil && marks.last?.digit == nil)
        #expect(marks.count == 27)                       // 23:00 … 01:00 включительно, через час
        #expect(marks.first?.minute == -60 && marks.last?.minute == 1500)
    }

    @Test("три яруса: длинные 0/6/12/18/24, средние 3/9/15/21, короткие на остальных часах и на краях")
    func tiersRhymeWithTheDigits() {
        let marks = DayScale.calendar.marks(start: -60, end: 1500)
        func hours(_ tier: DayScale.Tier) -> [Int] { marks.filter { $0.tier == tier }.map { Int($0.minute) / 60 } }
        #expect(hours(.long) == [0, 6, 12, 18, 24])
        #expect(hours(.medium) == [3, 9, 15, 21])
        #expect(hours(.short) == [-1, 1, 2, 4, 5, 7, 8, 10, 11, 13, 14, 16, 17, 19, 20, 22, 23, 25])
        // Каждая цифра стоит над риской длинного или среднего яруса — своя метка, а не соседняя.
        for m in marks where m.digit != nil { #expect(m.tier != .short) }
        for m in marks where m.tier != .short { #expect(m.digit != nil) }
    }

    @Test("прежняя шкала AR: два яруса, цифры каждые три часа по модулю суток")
    func solarMarksAreTheOldOnes() {
        let day = SolarDay(date: CivilDate(year: 2026, month: 11, day: 12), place: Self.tomsk)
        let marks = DayScale.solar.marks(start: day.mint, end: day.maxt)
        #expect(marks.compactMap(\.digit) == ["3", "6", "9", "12", "15", "18", "21", "0"])
        #expect(marks.allSatisfy { $0.tier != .medium })
        #expect(marks.filter { $0.tier == .long }.map { Int($0.minute) / 60 } == [6, 12, 18, 24])
    }

    @Test("минута ↔ доля окна: −60, 0, 720, 1440, 1500")
    func minuteToFractionAndBack() {
        let s = DayScale.calendarStart, e = DayScale.calendarEnd
        #expect(DayScale.fraction(of: -60, start: s, end: e) == 0)
        #expect(DayScale.fraction(of: 0, start: s, end: e) == 60.0 / 1560)
        #expect(DayScale.fraction(of: 720, start: s, end: e) == 780.0 / 1560)       // полдень — ровно посередине шкалы
        #expect(DayScale.fraction(of: 720, start: s, end: e) == 0.5)
        #expect(DayScale.fraction(of: 1440, start: s, end: e) == 1500.0 / 1560)
        #expect(DayScale.fraction(of: 1500, start: s, end: e) == 1)
        #expect(DayScale.fraction(of: -500, start: s, end: e) == 0 && DayScale.fraction(of: 9000, start: s, end: e) == 1)
        for t in [-60.0, 0, 720, 1440, 1500] {
            #expect(abs(DayScale.minute(at: DayScale.fraction(of: t, start: s, end: e), start: s, end: e) - t) < 1e-9)
        }
    }

    // MARK: - Минуты за краями суток: Солнце и Луна — те же, что у соседнего дня

    @Test("Солнце в −40 минут этих суток = Солнце в 1400 минут предыдущих; в 1500 = в 60 следующих")
    func sunInTheMarginIsTheNeighboursSun() {
        for place in [Self.tomsk, Self.moscow, Self.tromso] {
            for d in [CivilDate(year: 2026, month: 11, day: 13), CivilDate(year: 2026, month: 6, day: 21), CivilDate(year: 2026, month: 3, day: 29)] {
                let today = SolarDay(date: d, place: place)
                let before = SolarDay(date: d.adding(days: -1), place: place)
                let after = SolarDay(date: d.adding(days: 1), place: place)
                // Часовой пояс и вчера, и завтра тот же (фиксированное смещение), поэтому минуты складываются ровно на 1440.
                for t in [-60.0, -40, -1] {
                    #expect(abs(today.elevation(at: t) - before.elevation(at: t + 1440)) < 0.02, "\(place.latitude) \(d) t=\(t)")
                }
                for t in [1441.0, 1470, 1500] {
                    #expect(abs(today.elevation(at: t) - after.elevation(at: t - 1440)) < 0.02, "\(place.latitude) \(d) t=\(t)")
                }
            }
        }
    }

    @Test("Луна в часе до полуночи и после — та же, что у соседнего дня")
    func moonInTheMarginIsTheNeighboursMoon() {
        let d = CivilDate(year: 2026, month: 11, day: 13)
        let a = MoonSample(date: d, minutes: -40, place: Self.moscow)
        let b = MoonSample(date: d.adding(days: -1), minutes: 1400, place: Self.moscow)
        #expect(abs(a.altitude - b.altitude) < 1e-6 && abs(a.azimuth - b.azimuth) < 1e-6)
        let c = MoonSample(date: d, minutes: 1500, place: Self.moscow)
        let e = MoonSample(date: d.adding(days: 1), minutes: 60, place: Self.moscow)
        #expect(abs(c.altitude - e.altitude) < 1e-6 && abs(c.phase.fraction - e.phase.fraction) < 1e-6)
        // Дуги Луны ищутся в −720…2900: оба края шкалы внутри.
        #expect(MoonDay(date: d, place: Self.moscow).arc(at: -60) != nil)
        #expect(MoonDay(date: d, place: Self.moscow).arc(at: 1500) != nil)
    }

    @Test("«что дальше» в часе до полуночи — до рассвета этих суток, в часе после — до рассвета следующих")
    func nextLightInTheMargins() {
        let d = SolarDay(date: CivilDate(year: 2026, month: 11, day: 13), place: Self.moscow)
        let rise = d.rise!
        let before = d.nextLight(at: -40)
        #expect(before.key == .toDawn && before.minutes == rise + 40)
        let after = d.nextLight(at: 1500)
        #expect(after.key == .toDawn && after.minutes == rise + 1440 - 1500)
        // Сумерки утром (до полудня) и вечером (после) называются по-разному: слева от полуночи ночь этих суток ещё не кончилась.
        let nightBefore = d.state(at: -40), nightAfter = d.state(at: 1500)
        #expect(nightBefore.stars == nightAfter.stars)
    }

    // MARK: - AR (30з.4, второй круг): слои неба в полях шкалы — те же, что у соседнего дня

    @Test("AR: Солнце, Луна, планеты, звёзды и Млечный Путь в −40 и 1480 минут = тем же слоям соседнего дня")
    func arLayersInTheMargins() {
        let place = Self.moscow
        let d = CivilDate(year: 2026, month: 11, day: 13)
        func close(_ a: Degrees, _ b: Degrees, _ tol: Degrees = 1e-6) -> Bool {
            let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
            return min(diff, 360 - diff) < tol
        }
        for (day, t, nDay, nT) in [(d, -40.0, d.adding(days: -1), 1400.0), (d, 1480.0, d.adding(days: 1), 40.0),
                                   (d, -60.0, d.adding(days: -1), 1380.0), (d, 1500.0, d.adding(days: 1), 60.0)] {
            let sun = SunTrack.sample(day: day, minutes: t, in: place), sunN = SunTrack.sample(day: nDay, minutes: nT, in: place)
            #expect(close(sun.altitude, sunN.altitude) && close(sun.azimuth, sunN.azimuth), "солнце \(t)")
            let moon = MoonTrack.sample(day: day, minutes: t, in: place), moonN = MoonTrack.sample(day: nDay, minutes: nT, in: place)
            #expect(close(moon.altitude, moonN.altitude) && close(moon.azimuth, moonN.azimuth) && moon.phase.fraction == moonN.phase.fraction, "луна \(t)")
            let pl = PlanetSkyAR.samples(day: day, minutes: t, in: place), plN = PlanetSkyAR.samples(day: nDay, minutes: nT, in: place)
            #expect(pl.count == plN.count && zip(pl, plN).allSatisfy { close($0.horizontal.altitude, $1.horizontal.altitude) && close($0.horizontal.azimuth, $1.horizontal.azimuth) }, "планеты \(t)")
            let st = StarSkyAR.horizontals(day: day, minutes: t, in: place), stN = StarSkyAR.horizontals(day: nDay, minutes: nT, in: place)
            #expect(st.count == stN.count && zip(st, stN).allSatisfy { close($0.altitude, $1.altitude) && close($0.azimuth, $1.azimuth) }, "звёзды \(t)")
            let core = MilkyWayAR.core(day: day, minutes: t, in: place), coreN = MilkyWayAR.core(day: nDay, minutes: nT, in: place)
            #expect(close(core.altitude, coreN.altitude) && close(core.azimuth, coreN.azimuth), "ядро \(t)")
            let band = MilkyWayAR.center(day: day, minutes: t, in: place), bandN = MilkyWayAR.center(day: nDay, minutes: nT, in: place)
            #expect(band.count == bandN.count && zip(band, bandN).allSatisfy { close($0.altitude, $1.altitude) && close($0.azimuth, $1.azimuth) }, "полоса \(t)")
        }
    }
}
