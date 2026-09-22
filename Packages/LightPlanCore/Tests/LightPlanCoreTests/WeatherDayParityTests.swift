import Testing
import Foundation
@testable import LightPlanCore

/// Сверка сборки дня из прогноза (`buildWx` → `WeatherDay.buildDays`) и
/// погоды над окном Млечного Пути (`mwSkyAt` → `MilkyWaySky.over`) с вебом
/// (итерация 10). Вход — синтетический почасовой ответ, придуманный тем же
/// стендом (`Tools/parity/generate.js`, `syntheticHourly`): без сети и без
/// `Math.random`, только числа, которые сам генератор и посчитал. Фикстуры
/// несут этот вход целиком (`input`, `airInput`) — Swift кормится тем же, чем
/// кормили `buildWx`, а не второй копией генератора.
struct WeatherDayParityTests {

    private static func civilDate(iso: String) -> CivilDate {
        let p = iso.split(separator: "-").map { Int($0)! }
        return CivilDate(year: p[0], month: p[1], day: p[2])
    }

    /// `dkey` веба хранит месяц с нуля («2026-5-10» — 10 июня): переводим в
    /// обычный месяц `CivilDate`.
    private static func fromDkey(_ key: String) -> CivilDate {
        let p = key.split(separator: "-").map { Int($0)! }
        return CivilDate(year: p[0], month: p[1] + 1, day: p[2])
    }

    private static func hourly(_ raw: ParityFixtures.RawHourly) -> HourlyWeather {
        HourlyWeather(time: raw.time, cloud: raw.cloud_cover, cloudLow: raw.cloud_cover_low,
                      cloudMid: raw.cloud_cover_mid, cloudHigh: raw.cloud_cover_high,
                      humidity: raw.relative_humidity_2m, temperature: raw.temperature_2m,
                      windSpeed: raw.wind_speed_10m, windDirection: raw.wind_direction_10m,
                      windGusts: raw.wind_gusts_10m, precipitation: raw.precipitation, weatherCode: raw.weather_code)
    }

    private static func air(_ raw: ParityFixtures.RawAirByDay) -> [CivilDate: [Int: AirSample]] {
        var out: [CivilDate: [Int: AirSample]] = [:]
        for (dayKey, byHour) in raw {
            let date = civilDate(iso: dayKey)
            var hours: [Int: AirSample] = [:]
            for (hourKey, sample) in byHour { hours[Int(hourKey)!] = AirSample(aod: sample.aod, dust: sample.dust) }
            out[date] = hours
        }
        return out
    }

    private static func sameRecord(_ a: HourRecord?, _ b: ParityFixtures.HourRecord?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let x?, let y?):
            return x.cloud == y.cloud && x.code == y.code && x.temperature == y.temp
                && x.low == y.low && x.mid == y.mid && x.high == y.high && x.humidity == y.hum
                && x.windSpeed == y.wind && x.windDirection == y.wdir && x.windGusts == y.gust
        default: return false
        }
    }

    @Test("weather_day.json: категория, закатный балл, температура, ветер, тренд — строго")
    func buildDays() throws {
        let f = try ParityFixtures.load("weather_day.json", as: ParityFixtures.WeatherDayFile.self)
        var failures = 0
        var daysChecked = 0
        for c in f.cases {
            let place = Place(latitude: c.lat, longitude: c.lon, zone: ZoneID(fixedOffsetHours: c.tz))
            let built = WeatherDay.buildDays(from: Self.hourly(c.input), place: place, air: Self.air(c.airInput))

            for entry in c.days {
                daysChecked += 1
                let date = Self.fromDkey(entry.key)
                guard let day = built.days[date] else {
                    failures += 1
                    if failures <= 20 { Issue.record("\(c.name) \(entry.key): Swift не построил этот день") }
                    continue
                }
                let want = entry.v
                let same = day.quality.rawValue == want.q && day.cloud == want.cloud && day.sunset == want.sunset
                    && Self.sameRecord(day.layers, want.layers) && day.temperatureBase == want.tempBase
                    && day.wind == want.wind && day.windDirection == want.windDir && day.gust == want.gust
                    && day.trend == want.trend && day.real == want.real
                if !same {
                    failures += 1
                    if failures <= 20 {
                        Issue.record("""
                            \(c.name) \(entry.key): JS q=\(want.q) cloud=\(want.cloud) sunset=\(String(describing: want.sunset)) \
                            temp=\(want.tempBase) wind=\(want.wind) windDir=\(String(describing: want.windDir)) gust=\(want.gust) trend=\(want.trend); \
                            Swift q=\(day.quality.rawValue) cloud=\(day.cloud) sunset=\(String(describing: day.sunset)) \
                            temp=\(day.temperatureBase) wind=\(day.wind) windDir=\(String(describing: day.windDirection)) gust=\(day.gust) trend=\(day.trend)
                            """)
                    }
                }
            }

            for entry in c.hourly {
                let date = Self.fromDkey(entry.key)
                let got = built.hourly[date] ?? [:]
                for (hourString, want) in entry.hours {
                    let hour = Int(hourString)!
                    if !Self.sameRecord(got[hour], want) {
                        failures += 1
                        if failures <= 20 { Issue.record("\(c.name) \(entry.key) час \(hour): почасовая запись разошлась") }
                    }
                }
            }
        }
        print("buildDays: \(f.cases.count) сценариев, \(daysChecked) суток")
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }

    @Test("mwsky.json: погода над окном Млечного Пути — балл, взгляд, слово о воздухе — строго")
    func milkyWaySky() throws {
        let f = try ParityFixtures.load("mwsky.json", as: ParityFixtures.MilkyWaySkyFile.self)
        var failures = 0
        for c in f.cases {
            let place = Place(latitude: c.lat, longitude: c.lon, zone: ZoneID(fixedOffsetHours: c.tz))
            let date = Self.civilDate(iso: c.date)
            let window = MilkyWayWindow(date: date, latitude: c.lat, longitude: c.lon, utcOffsetHours: c.tz)

            let built = WeatherDay.buildDays(from: Self.hourly(c.input), place: place, air: Self.air(c.airInput))
            let got = MilkyWaySky.over(date: date, window: window, hourly: built.hourly, air: Self.air(c.airInput))

            let same: Bool
            switch (got, c.sky) {
            case (nil, nil): same = true
            case (let g?, let w?):
                same = g.score == w.score && g.look.rawValue == w.look && g.word?.rawValue == w.word
                    && g.cloud == w.cloud && g.humidity == w.hum
                    && g.air?.aod == w.air?.aod && g.air?.dust == w.air?.dust
            default: same = false
            }
            if !same {
                failures += 1
                Issue.record("\(c.why) (\(c.date)): JS \(String(describing: c.sky)), Swift \(String(describing: got))")
            }
        }
        print("mwSkyAt: \(f.cases.count) сценариев")
        #expect(failures == 0, "\(failures) расхождений с вебом")
    }
}
