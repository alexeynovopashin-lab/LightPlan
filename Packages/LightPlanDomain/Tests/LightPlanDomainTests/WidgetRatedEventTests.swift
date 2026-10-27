import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Шаг 30б.2в-6: что оценивает средний виджет — рассвет или закат — и откуда берётся балл (слова Алексея 27.10: «виджет до конца утреннего
/// золотого часа показывает рассвет, потом закат, после заката — завтрашний рассвет»).
struct WidgetRatedEventTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private func tsk(_ h: Int, _ m: Int = 0, day d: Int = 25) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private let ratings = [
        WidgetFeed.Rating(day: "2026-10-25", score: 62, quality: .good, sunrise: 81),
        WidgetFeed.Rating(day: "2026-10-26", score: 30, quality: .plain, sunrise: 44),
    ]
    private func feed(_ r: [WidgetFeed.Rating]? = nil) -> WidgetFeed { WidgetFeed(place: tomsk, forecast: r ?? ratings) }

    // MARK: Файл

    @Test func anOldRatingWithoutASunriseStillLoadsAndShowsNoSunriseNumber() throws {
        let old = Data(#"{"place":{"name":"Томск","latitude":56.5,"longitude":85,"zone":"Asia/Tomsk"},"forecast":[{"day":"2026-10-25","score":62,"quality":"good"}]}"#.utf8)
        let f = try #require(WidgetFeed.decode(old))
        #expect(f.forecast.first?.sunrise == nil && f.forecast.first?.score == 62)
        let morning = f.frame(at: tsk(5))
        let e = try #require(BraunIdle.ratedEvent(morning))
        #expect(e.kind == .sunrise && e.score == nil && e.quality == nil, "рассвет есть, балла и слова нет — не выдумываем")
        #expect(BraunIdle.ratingWord(morning) == nil)
        #expect(BraunIdle.ratedEvent(f.frame(at: tsk(14)))?.score == 62, "закат из старого файла читается как раньше")
    }

    @Test func theSunriseScoreRoundTrips() {
        let f = feed()
        #expect(WidgetFeed.decode(f.encoded()) == f)
        #expect(WidgetFeed.decode(f.encoded())?.forecast.first?.sunrise == 81)
    }

    // MARK: Правило переключения

    @Test func theWidgetRatesTheSunriseUntilTheMorningGoldenHourEndsThenTheSunsetThenTomorrowsSunrise() throws {
        let f = feed()
        let l = try #require(f.frame(at: tsk(12)).day)
        let rise = try #require(l.sunrise), end = try #require(l.goldenEnd), set = try #require(l.sunset)
        #expect(rise < end && end < set && end.timeIntervalSince(rise) > 30 * 60 && end.timeIntervalSince(rise) < 2 * 3600, "утренний золотой час: \(end.timeIntervalSince(rise) / 60) мин")
        func ev(_ t: Date) throws -> BraunIdle.RatedEvent { try #require(BraunIdle.ratedEvent(f.frame(at: t))) }
        // 05:00, до рассвета, — рассвет сегодня.
        let night = try ev(tsk(5))
        #expect(night.kind == .sunrise && !night.tomorrow && night.at == rise && night.score == 81 && night.quality == .excellent)
        // Сразу после восхода и за минуту до конца золотого часа — тот же рассвет.
        #expect(try ev(rise.addingTimeInterval(60)).kind == .sunrise)
        #expect(try ev(end.addingTimeInterval(-60)).kind == .sunrise)
        // С конца золотого часа — закат сегодня, до самого заката.
        let day = try ev(end)
        #expect(day.kind == .sunset && !day.tomorrow && day.at == set && day.score == 62 && day.quality == .good)
        #expect(try ev(tsk(14)).kind == .sunset && ev(set.addingTimeInterval(-60)).kind == .sunset)
        // С заката — завтрашний рассвет и его оценка.
        let eve = try ev(set)
        #expect(eve.kind == .sunrise && eve.tomorrow)
        #expect(eve.score == 44 && eve.quality == SunsetScore.category(44))
        #expect(eve.at == f.frame(at: set).tomorrow?.sunrise)
        #expect(try ev(tsk(21)).tomorrow)
    }

    @Test func midnightDoesNotFlipTheRatedEvent() throws {
        let f = feed()
        let before = try #require(BraunIdle.ratedEvent(f.frame(at: tsk(23, 59))))
        let after = try #require(BraunIdle.ratedEvent(f.frame(at: tsk(0, 1, day: 26))))
        #expect(before.kind == .sunrise && after.kind == .sunrise && before.at == after.at, "тот же завтрашний рассвет, теперь он сегодняшний")
        #expect(before.tomorrow && !after.tomorrow)
        #expect(before.score == after.score && before.score == 44, "и тот же балл: завтрашняя запись стала сегодняшней")
    }

    @Test func thereIsNothingToRateInThePolarDayAndNight() {
        let tromso = WidgetFeed.Spot(name: "Tromsø", latitude: 69.6496, longitude: 18.956, zone: "Europe/Oslo")
        func utc(_ m: Int, _ d: Int, _ h: Int) -> Date {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
            return c.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
        }
        let june = WidgetFeed(place: tromso).frame(at: utc(6, 21, 12)), dec = WidgetFeed(place: tromso).frame(at: utc(12, 21, 12))
        #expect(BraunIdle.ratedEvent(june) == nil && BraunIdle.ratingWord(june) == nil, "полярный день: ни восхода, ни заката")
        #expect(BraunIdle.ratedEvent(dec) == nil, "полярная ночь тоже")
    }

    @Test func aSunThatNeverReachesSixDegreesIsRatedUntilItsSunrise() throws {
        var f = feed().frame(at: tsk(8, 30))
        var day = try #require(f.day)
        let rise = try #require(day.sunrise)
        day.goldenEnd = nil
        f.day = day
        f.now = rise.addingTimeInterval(-60)
        #expect(BraunIdle.ratedEvent(f)?.kind == .sunrise)
        f.now = rise.addingTimeInterval(60)
        #expect(BraunIdle.ratedEvent(f)?.kind == .sunset, "золотого часа нет — после восхода уже закат")
    }

    // MARK: Слово оценки

    @Test func theSunriseWordComesFromItsOwnScoreAndTheMorningFog() throws {
        func word(_ r: WidgetFeed.Rating, at: Date) -> String? { BraunIdle.ratingWord(feed([r]).frame(at: at)) }
        let day = "2026-10-25"
        #expect(word(.init(day: day, score: 20, quality: .poor, sunrise: 90), at: tsk(6)) == "отличный", "рассвет судят по его баллу, не по закату")
        #expect(word(.init(day: day, score: 90, quality: .excellent, sunrise: 20), at: tsk(6)) == "плохой")
        #expect(word(.init(day: day, score: 90, quality: .fog, sunrise: 90), at: tsk(6)) == "туман", "утренний туман перебивает балл")
        #expect(word(.init(day: day, score: 62, quality: .good, sunrise: nil), at: tsk(6)) == nil, "рассветного балла нет — слова нет")
        #expect(word(.init(day: day, score: 62, quality: .good, sunrise: 10), at: tsk(14)) == "хороший", "закат — категория дня, как было")
        #expect(word(.init(day: day, score: nil, quality: .plain, sunrise: 10), at: tsk(14)) == "обычный")
    }

    @Test func theLabelIsTheWordOfTheEvent() throws {
        let f = feed()
        let words = f.words
        #expect(BraunIdle.ratingLabel(try #require(BraunIdle.ratedEvent(f.frame(at: tsk(5)))), words) == "Рассвет")
        #expect(BraunIdle.ratingLabel(try #require(BraunIdle.ratedEvent(f.frame(at: tsk(14)))), words) == "Закат")
        #expect(BraunIdle.ratingLabel(try #require(BraunIdle.ratedEvent(f.frame(at: tsk(21)))), words) == "Рассвет")
    }

    // MARK: Лента

    @Test func theTimelineHasTheMomentTheWidgetSwitchesFromSunriseToSunset() throws {
        let f = feed()
        let now = tsk(5)
        let end = try #require(f.frame(at: now).day?.goldenEnd)
        let line = f.timeline(from: now).dates
        #expect(line.contains(end), "конец утреннего золотого часа — момент ленты: виджет переключается при закрытом приложении")
        let before = f.frame(at: end.addingTimeInterval(-1)), after = f.frame(at: end)
        #expect(BraunIdle.ratedEvent(before)?.kind == .sunrise && BraunIdle.ratedEvent(after)?.kind == .sunset)
        // Завтрашний конец золотого часа тоже в окне 36 часов.
        let tomorrowEnd = try #require(f.frame(at: tsk(12, day: 26)).day?.goldenEnd)
        #expect(f.timeline(from: tsk(21)).dates.contains(tomorrowEnd))
    }
}
