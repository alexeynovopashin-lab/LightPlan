import Testing
import Foundation
@testable import LightPlanCore

/// Потребители `SolarDay`, переехавшие на точное Солнце (шаг 29.8в.25): окно Млечного Пути, «Луна против звёзд»,
/// «бывает ли ночь −18°». Каждый идёт по `.iau` через вход приложения и остаётся на `.web` в ядре сверки с вебом.
struct SolarDayConsumersTests {

    static let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID(fixedOffsetHours: 7))
    static let cases: [(Place, CivilDate)] = [
        (tomsk, CivilDate(year: 2026, month: 8, day: 30)),
        (tomsk, CivilDate(year: 2026, month: 5, day: 20)),
        (Place(latitude: -33.9249, longitude: 18.4241, zone: ZoneID(fixedOffsetHours: 2)), CivilDate(year: 2026, month: 7, day: 25)),
        (Place(latitude: 69.6492, longitude: 18.9553, zone: ZoneID(fixedOffsetHours: 2)), CivilDate(year: 2026, month: 9, day: 23)),
        (Place(latitude: 21.3069, longitude: -157.8583, zone: ZoneID(fixedOffsetHours: -10)), CivilDate(year: 2026, month: 3, day: 20)),
    ]

    @Test("Окно Млечного Пути: вход приложения = .iau, ядро сверки = .web; тёмная часть окна лежит внутри ночи точного Солнца")
    func milkyWayWindow() {
        for (place, date) in Self.cases {
            let offset = place.zone.utcOffsetHours(on: date)
            let app = MilkyWayWindow(date: date, place: place)
            #expect(app == MilkyWayWindow(date: date, place: place, time: .iau))
            #expect(app == MilkyWayWindow(date: date, latitude: place.latitude, longitude: place.longitude,
                                          utcOffsetHours: offset, time: .iau))
            let sun = SolarDay(date: date, place: place)
            #expect(app.dark == (sun.astroA != nil))
            // Любая минута окна — под −18° по тому же Солнцу, что показывает «Свет» (шаг окна 5 минут, поэтому с запасом шага).
            for span in app.spans {
                #expect(sun.elevation(at: span.from) <= -18 + 1e-9)
                #expect(sun.elevation(at: span.to) <= -18 + 1e-9)
            }
        }
    }

    @Test("Окно Млечного Пути: границы тёмного, посчитанные веб-Солнцем, уходят от точных на минуты — вот зачем переезд")
    func webWindowDiffersFromExact() {
        var moved = 0.0
        for (place, date) in Self.cases {
            let offset = place.zone.utcOffsetHours(on: date)
            let web = SolarDay(date: date, latitude: place.latitude, longitude: place.longitude, utcOffsetHours: offset)
            let exact = SolarDay(date: date, place: place)
            if let a = web.astroB, let b = exact.astroB { moved = max(moved, abs(a - b)) }
        }
        #expect(moved > 0.3, "граница вечерней темноты сдвинулась только на \(moved) мин")
    }

    @Test("Луна против звёзд: вход приложения = .iau; тёмная часть ночи — между астрономическими сумерками точного Солнца")
    func moonVsStars() {
        for (place, date) in Self.cases {
            let offset = place.zone.utcOffsetHours(on: date)
            let app = MoonVsStars(date: date, place: place)
            #expect(app == MoonVsStars(date: date, latitude: place.latitude, longitude: place.longitude,
                                       utcOffsetHours: offset, time: .iau))
            #expect(app.dark == (SolarDay(date: date, place: place).astroB != nil && SolarDay(date: date, place: place).astroA != nil))
        }
    }

    @Test("Бывает ли ночь −18°: .iau совпадает с границами ночи точного Солнца на всех широтах и датах года")
    func astroNight() {
        var disagreements = 0, checked = 0
        for lat in stride(from: -80.0, through: 80, by: 5) {
            for day in stride(from: 0, to: 365, by: 7) {
                let date = CivilDate(year: 2026, month: 1, day: 1).adding(days: day)
                let exact = SolarDay(date: date, latitude: lat, longitude: 30, utcOffsetHours: 2, time: .iau)
                checked += 1
                if AstroNight.has(on: date, latitude: lat, utcOffsetHours: 2, time: .iau) != (exact.astroA != nil) { disagreements += 1 }
            }
        }
        #expect(disagreements == 0, "\(disagreements) из \(checked)")
        // «Следующая ночь» из Мурманска в июне: и веб-модель, и точная находят её, но день начала может отличаться.
        let web = AstroNight.next(after: CivilDate(year: 2026, month: 6, day: 21), latitude: 68.97, utcOffsetHours: 3)
        let exact = AstroNight.next(after: CivilDate(year: 2026, month: 6, day: 21), latitude: 68.97, utcOffsetHours: 3, time: .iau)
        #expect(web != nil && exact != nil)
        if let web, let exact { #expect(abs(web.daysSince1970 - exact.daysSince1970) <= 3, "\(web) и \(exact) разошлись больше чем на 3 дня") }
    }
}
