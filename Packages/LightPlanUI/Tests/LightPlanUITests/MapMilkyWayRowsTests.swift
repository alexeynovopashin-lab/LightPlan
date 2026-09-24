import Foundation
import Testing
import LightPlanCore
@testable import LightPlanUI

/// Пять строк Млечного Пути сводки карты (итерация 20б, `renderMwRows` веба):
/// порядок причин в вердикте и строки, которые молчат без данных.
struct MapMilkyWayRowsTests {
    let lexicon = Lexicon("ru")
    let clock = ClockText(language: "ru", preference: .h24)

    func rows(_ iso: String, lat: Double, lon: Double, tz: Double, glow: Double?) -> MapMilkyWayRows {
        let p = iso.split(separator: "-").map { Int($0)! }
        let date = CivilDate(year: p[0], month: p[1], day: p[2])
        let place = Place(latitude: lat, longitude: lon, zone: ZoneID(fixedOffsetHours: tz))
        let sun = SolarDay(date: date, place: place)
        return MapMilkyWayRows.build(
            sun: sun, window: MilkyWayWindow(date: date, place: place), moon: MoonVsStars(date: date, place: place),
            glow: glow, sky: nil,
            nextDark: { AstroNight.next(after: date, latitude: lat, utcOffsetHours: tz) },
            dateShort: { "\($0.day).\($0.month)" }, lexicon: lexicon, clock: clock)
    }

    func verdict(_ r: MapMilkyWayRows) -> MapMilkyWayRows.Row { r.rows.last! }

    @Test("Белая ночь: темноты нет — вердикт «нет темноты», ночь — когда вернётся, приглушённо")
    func whiteNight() {
        let r = rows("2026-06-21", lat: 60, lon: 30, tz: 3, glow: 0.5)
        #expect(r.rows.first?.label == "map.night")
        #expect(r.rows.first?.tone == .ink4)
        let back = AstroNight.next(after: CivilDate(year: 2026, month: 6, day: 21), latitude: 60, utcOffsetHours: 3)!
        #expect(r.rows.first?.text == lexicon.t("mw.nightUntil", ["date": "\(back.day).\(back.month)"]))
        #expect(!r.rows.contains { $0.label == "map.moonGlare" })       // без темноты про луну не говорим
        #expect(verdict(r).text == lexicon.t("mw.noDark"))
        #expect(verdict(r).tone == .ink4)
    }

    @Test("Зарево города называется раньше луны и окна")
    func glowFirst() {
        // 45° с. ш., 15 августа 2026: ядро выше рабочей высоты, ночь тёмная.
        let city = rows("2026-08-15", lat: 45, lon: 37, tz: 3, glow: 166)
        let glowRow = city.rows.first { $0.label == "map.glow" }
        #expect(glowRow?.text == lexicon.t("glow.none") + " · ×166")
        #expect(glowRow?.tone == .terra)
        #expect(verdict(city).text == lexicon.t("mw.glowKills"))

        let dark = rows("2026-08-15", lat: 45, lon: 37, tz: 3, glow: 0.59)
        #expect(dark.rows.first { $0.label == "map.glow" }?.text == lexicon.t("glow.dark") + " · ×0.6")
        #expect(verdict(dark).text != lexicon.t("mw.glowKills"))
    }

    @Test("Нет атласа — нет строки засветки, вердикт от неё не зависит")
    func noAtlas() {
        let r = rows("2026-08-15", lat: 45, lon: 37, tz: 3, glow: nil)
        #expect(!r.rows.contains { $0.label == "map.glow" })
        #expect(!r.rows.contains { $0.label == "map.sky" })             // прогноза на эти часы нет
        #expect(r.rows.first?.tone == .ink2)
    }

    @Test("Ядро ниже рабочей высоты: вердикт называет высоту и порог")
    func coreLow() {
        // 60° с. ш. в январе: темно, ядро днём и низко.
        let r = rows("2026-01-15", lat: 60, lon: 30, tz: 3, glow: 0.5)
        let w = MilkyWayWindow(date: CivilDate(year: 2026, month: 1, day: 15),
                               place: Place(latitude: 60, longitude: 30, zone: ZoneID(fixedOffsetHours: 3)))
        #expect(w.dark)
        #expect(w.best.altitude < MilkyWay.workLow)
        #expect(verdict(r).text == lexicon.t("mw.coreLow", ["alt": String(format: "%.0f", w.best.altitude), "need": "10"]))
    }
}
