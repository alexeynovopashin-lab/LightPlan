import Testing
import Foundation
import LightPlanCore

/// Сверка положения солнца в слое AR с независимым эталоном — SunCalc 2.0.1 из `sun_compass:index.html`
/// (другой алгоритм, чем NOAA-модель приложения). Три места × три момента, абсолютное время UTC.
/// Строки таблицы получены `node` из тех же функций, что работают в «Солнечном компасе»; азимут — как там:
/// от севера по часовой, `(az·180/π + 180) mod 360`.
///
/// Допуск — не бит в бит: модели разные. NOAA-упрощение веба берёт склонение и уравнение времени на сутки
/// целиком, SunCalc — на момент. Измеренное расхождение — в отчёте шага; допуск здесь с запасом ровно такой,
/// чтобы 1° порчи его не пролезал: 0,5° по азимуту и по высоте.
struct SunTrackReferenceTests {

    struct Row {
        let name: String
        let lat: Double, lon: Double, zone: String
        let iso: String
        let az: Double, alt: Double
    }

    static let rows: [Row] = [
        Row(name: "Москва", lat: 55.7558, lon: 37.6173, zone: "Europe/Moscow", iso: "2026-06-21T09:30:00Z", az: 179.35574618080693, alt: 57.68209021583911),
        Row(name: "Москва", lat: 55.7558, lon: 37.6173, zone: "Europe/Moscow", iso: "2026-12-21T07:00:00Z", az: 146.42963675490228, alt: 4.821903181130053),
        Row(name: "Москва", lat: 55.7558, lon: 37.6173, zone: "Europe/Moscow", iso: "2026-09-23T15:00:00Z", az: 265.35172323207325, alt: 3.0869193726280666),
        Row(name: "Томск", lat: 56.4977, lon: 84.9744, zone: "Asia/Tomsk", iso: "2026-06-21T02:00:00Z", az: 96.67464350835098, alt: 32.79769903659936),
        Row(name: "Томск", lat: 56.4977, lon: 84.9744, zone: "Asia/Tomsk", iso: "2026-03-20T06:00:00Z", az: 171.6181458466108, alt: 32.89926497115669),
        Row(name: "Томск", lat: 56.4977, lon: 84.9744, zone: "Asia/Tomsk", iso: "2026-12-21T10:00:00Z", az: 229.1364165593642, alt: -2.5400430930425664),
        Row(name: "Сидней", lat: -33.8688, lon: 151.2093, zone: "Australia/Sydney", iso: "2026-01-15T01:00:00Z", az: 52.623314607053885, alt: 70.94100102026788),
        Row(name: "Сидней", lat: -33.8688, lon: 151.2093, zone: "Australia/Sydney", iso: "2026-06-21T22:00:00Z", az: 53.153606272597415, alt: 9.620100179558095),
        Row(name: "Сидней", lat: -33.8688, lon: 151.2093, zone: "Australia/Sydney", iso: "2026-10-14T06:00:00Z", az: 277.7296185307073, alt: 25.48674129178745),
    ]

    static func circular(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    @Test("AR-солнце против SunCalc: 3 места × 3 момента, расхождение по азимуту и высоте в пределах 0,5°")
    func againstSunCalc() throws {
        var worstAz = 0.0, worstAlt = 0.0
        for r in Self.rows {
            let date = try #require(ISO8601DateFormatter().date(from: r.iso))
            let place = Place(latitude: r.lat, longitude: r.lon, zone: try #require(ZoneID(r.zone)))
            let s = SunTrack.sample(at: Moment(date), in: place)
            let dAz = Self.circular(s.azimuth, r.az), dAlt = abs(s.altitude - r.alt)
            print(String(format: "SUNREF %@ %@ az %.3f / %.3f (Δ %.3f°)  alt %.3f / %.3f (Δ %.3f°)",
                         r.name, r.iso, s.azimuth, r.az, dAz, s.altitude, r.alt, dAlt))
            worstAz = max(worstAz, dAz); worstAlt = max(worstAlt, dAlt)
            #expect(dAz < 0.5, "\(r.name) \(r.iso): азимут \(s.azimuth) против \(r.az)")
            #expect(dAlt < 0.5, "\(r.name) \(r.iso): высота \(s.altitude) против \(r.alt)")
        }
        print(String(format: "SUNREF worst Δaz %.3f° Δalt %.3f°", worstAz, worstAlt))
    }
}
