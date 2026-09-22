import Foundation
import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Модель времени (`docs/16`) и матрёшка: то, что в бете живёт внутри формы и
/// ленты, а не отдельной функцией, поэтому сверяется здесь, по записанным
/// правилам и числам документа.
struct TimeAndNestTests {

    /// День ↔ номер дня: обратный ход сходится на всех днях двух веков, включая
    /// 29 февраля и 1900 / 2100, которые не високосные.
    @Test func civilDaysRoundTrip() {
        let from = CivilDate(year: 1900, month: 1, day: 1).daysSince1970
        let to = CivilDate(year: 2100, month: 12, day: 31).daysSince1970
        var prev: CivilDate?
        for z in from...to {
            let d = CivilDate(daysSince1970: z)
            #expect(d.daysSince1970 == z)
            if let prev { #expect(prev < d) }
            prev = d
        }
        #expect(to - from + 1 == 73_414)
        #expect(CivilDate(daysSince1970: 0) == CivilDate(year: 1970, month: 1, day: 1))
        #expect(CivilDate(year: 2028, month: 2, day: 28).adding(days: 1) == CivilDate(year: 2028, month: 2, day: 29))
        #expect(CivilDate(year: 2100, month: 2, day: 28).adding(days: 1) == CivilDate(year: 2100, month: 3, day: 1))
        #expect(CivilDate(year: 2026, month: 1, day: 1).days(since: CivilDate(year: 2025, month: 12, day: 31)) == 1)
    }

    /// Пример `docs/16`: 10:00 в Томске и 12:00 в Москве — не два часа зазора, а
    /// шесть. Зоны настоящие, из базы системы.
    @Test func tomskAndMoscowAreSixHoursApart() {
        let day = CivilDate(year: 2026, month: 9, day: 10)
        let tomsk = WallTime(day: day, minutes: 600).moment(in: ZoneID("Asia/Tomsk")!)
        let moscow = WallTime(day: day, minutes: 720).moment(in: ZoneID("Europe/Moscow")!)
        #expect(moscow.minutes(since: tomsk) == 360)
        /// Перелёт из Томска в 09:00 садится в Москве в 09:00 — и в пути четыре часа.
        let takeoff = WallTime(day: day, minutes: 540).moment(utcOffsetHours: 7)
        let landing = WallTime(day: day, minutes: 540).moment(utcOffsetHours: 3)
        #expect(landing.minutes(since: takeoff) == 240)
    }

    /// Дробные пояса не сдвигаются на четверть часа: Катманду 5:45, Дели 5:30.
    @Test func fractionalZones() {
        let day = CivilDate(year: 2026, month: 9, day: 10)
        let utcNoon = WallTime(day: day, minutes: 720).moment(utcOffsetHours: 0)
        #expect(WallTime(day: day, minutes: 720 + 345).moment(in: ZoneID("Asia/Kathmandu")!) == utcNoon)
        #expect(WallTime(day: day, minutes: 720 + 330).moment(in: ZoneID("Asia/Kolkata")!) == utcNoon)
        #expect(WallTime(moment: utcNoon, utcOffsetHours: 5.75) == WallTime(day: day, minutes: 1065))
    }

    /// Момент → настенные часы места → тот же момент (с точностью до минуты),
    /// в том числе через полночь и западнее Гринвича.
    @Test func wallClockRoundTrip() {
        let day = CivilDate(year: 2026, month: 3, day: 1)
        for off in [-11.0, -3.5, 0, 3, 5.75, 12.75, 14] {
            for m in stride(from: -1500, through: 3000, by: 37) {
                let moment = WallTime(day: day, minutes: m).moment(utcOffsetHours: off)
                let wall = WallTime(moment: moment, utcOffsetHours: off)
                #expect((0..<1440).contains(wall.minutes))
                #expect(wall.moment(utcOffsetHours: off) == moment, "\(off) \(m)")
            }
        }
        /// Секунды отбрасываются: «сейчас 10:00» длится всю минуту.
        let almost = Moment(milliseconds: WallTime(day: day, minutes: 601).moment(utcOffsetHours: 0).milliseconds - 1)
        #expect(WallTime(moment: almost, utcOffsetHours: 0).minutes == 600)
    }

    /// Минуты между моментами округляются как `Math.round` веба: половина — вверх.
    @Test func minutesRoundLikeJavaScript() {
        let a = Moment(milliseconds: 0)
        #expect(Moment(milliseconds: 30_000).minutes(since: a) == 1)
        #expect(Moment(milliseconds: -30_000).minutes(since: a) == 0)
        #expect(Moment(milliseconds: -90_000).minutes(since: a) == -1)
        #expect(Moment(milliseconds: 89_999).minutes(since: a) == 1)
    }

    /// Матрёшка: оболочку держат только точки с часом; растянуть можно, сузить
    /// уже содержимого нельзя; переносить целиком — только пустую.
    @Test func nestRules() {
        let day = CivilDate(year: 2026, month: 9, day: 12)
        var s = Session(id: "w", day: day, start: 600, end: 1200, duration: 600, genre: .wedding)
        #expect(s.movesWhole, "без точек со временем съёмка пустая")
        s.route = [RoutePoint(start: nil, name: "Сборы"), RoutePoint(start: 700, end: 760, name: "ЗАГС"),
                   RoutePoint(start: 1100, name: "Банкет")]
        let span = Nest.span(of: s)!
        #expect(span == NestSpan(start: 700, end: 1100))
        #expect(!s.movesWhole)
        #expect(span.fits(start: 600, end: 1200), "шире содержимого — можно")
        #expect(span.fits(start: 700, end: 1100), "вровень — можно")
        #expect(!span.fits(start: 701, end: 1200), "начало заходит внутрь — нельзя")
        #expect(!span.fits(start: 600, end: 1099), "конец заходит внутрь — нельзя")
        #expect(span.clampStart(720) == 700 && span.clampStart(650) == 650, "ручка начала встаёт на первую точку")
        #expect(span.clampEnd(1000) == 1100 && span.clampEnd(1300) == 1300, "ручка конца — на последнюю")
        /// Часы студии записи старого вида держат оболочку так же, как ячейка дня.
        var old = Session(id: "o", day: day, start: 600, end: 700)
        old.studioId = "st"; old.rentFrom = 560; old.rentTo = 720
        #expect(Nest.span(of: old) == NestSpan(start: 560, end: 720))
        old.studioId = nil
        #expect(Nest.span(of: old) == nil, "без студии часы аренды ничего не держат")
    }

    /// Пересечение времени симметрично при любом взаимном положении двух съёмок
    /// одного места: если A спорит с B, то и B с A, и род тот же.
    @Test func overlapIsSymmetricOverAllPositions() {
        let day = CivilDate(year: 2026, month: 9, day: 10)
        let ctx = ClashContext(zones: DomainOracle.Zones(), appOffsetHours: 3, travel: { _, _ in .pending },
                               travelThreshold: 40, eventsLayer: true)
        var checked = 0
        for aDur in [30, 60, 240, 900] {
            for bDur in [15, 60, 180, 700] {
                for off in stride(from: -1000, through: 1000, by: 5) where 600 + off >= 0 {
                    var a = Session(id: "a", day: day, start: 600, end: 600 + aDur)
                    var b = Session(id: "b", day: day, start: 600 + off, end: 600 + off + bDur)
                    a.place = "Лобня"; b.place = "Лобня"
                    let list = [a, b]
                    let ab = Overlaps.clashes(ofSessionAt: 0, sessions: list, blocks: [], context: ctx).map(\.kind)
                    let ba = Overlaps.clashes(ofSessionAt: 1, sessions: list, blocks: [], context: ctx).map(\.kind)
                    let intersects = 600 < 600 + off + bDur && 600 + off < 600 + aDur
                    #expect(ab == ba)
                    #expect(ab == (intersects ? [.overlap] : []), "a \(aDur), b \(off)+\(bDur)")
                    checked += 1
                }
            }
        }
        #expect(checked > 5000)
    }

    /// Съёмка, которую прислали без жанра или с незнакомым жанром, получает
    /// умолчания веба, а не падает.
    @Test func unknownGenreProfile() {
        let p = GenreProfile(nil)
        #expect(p.group == .people && p.spec == .fallback && p.deliveryDays == 7)
        #expect(p.refTags == RefTag.defaults && p.persons.isEmpty && !p.hasRoute && p.routeOptional)
        #expect(!Genre.portrait.allows(.stars) && Genre.landscape.allows(.stars) && !Genre.street.allows(nil))
    }
}
