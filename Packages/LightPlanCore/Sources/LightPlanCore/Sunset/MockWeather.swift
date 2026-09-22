import Foundation

/// Погода дня без сети: выдумка, но устойчивая — один и тот же день всегда
/// даёт один и тот же прогноз (порт `mulberry32`, `qualityOf`, `dayWeather`).
/// Настоящий прогноз перекрывает мок по тому же ключу дня — это делает
/// вызывающий (веб `wxReal[key] || mock`), здесь только сама выдумка.
public enum MockWeather {
    /// PRNG `mulberry32` веба — не криптография, а способ превратить дату в
    /// одно и то же число снова и снова. Побитовая арифметика JS (`|0`,
    /// `>>>`) переносится через `UInt32`, не через `Int`.
    static func mulberry32(_ seed: UInt32) -> () -> Double {
        var a = seed
        return {
            a = a &+ 0x6D2B_79F5
            var t = a
            t = multiplyLow(t ^ (t >> 15), t | 1)
            t = t ^ (t &+ multiplyLow(t ^ (t >> 7), t | 61))
            return Double((t ^ (t >> 14))) / 4_294_967_296
        }
    }

    /// `Math.imul` веба: младшие 32 бита произведения, со знаком отброшенным —
    /// ровно то, что делает `UInt32` умножение с переполнением.
    private static func multiplyLow(_ a: UInt32, _ b: UInt32) -> UInt32 { a &* b }

    /// Ключ мока — тот же, что ключ дня везде в продукте (веб `dkey`):
    /// год-месяц(с нуля)-число, без ведущих нулей.
    private static func seed(for date: CivilDate, factor a: Int, b: Int, c: Int) -> UInt32 {
        UInt32(bitPattern: Int32(date.year * a + date.month * b + date.day * c))
    }

    /// Категория дня (веб `qualityOf`).
    public static func quality(for date: CivilDate) -> DayQuality {
        let r = mulberry32(seed(for: date, factor: 10_000, b: 100, c: 1))()
        return r > 0.80 ? .excellent : r > 0.62 ? .good : r > 0.38 ? .plain
            : r > 0.22 ? .fog : .poor
    }

    /// Полный день выдумки: температура, ветер, тренд облачности (веб
    /// `dayWeather`). `real: false` — это не настоящий прогноз.
    public static func day(for date: CivilDate) -> WeatherDay {
        let quality = quality(for: date)
        let rng = mulberry32(seed(for: date, factor: 131, b: 17, c: 1))
        let tempBase = 15 + Int(Sky.jsRound(rng() * 12))          // 15…27 °C — дневной ориентир
        let wind = Int(Sky.jsRound(rng() * 8))                     // 0…8 м/с
        let cloudBase = quality.mockCloud
        let direction = rng() > 0.55 ? -1.0 : 1.0
        var trend: [Double] = []
        for i in 0..<6 {
            let value = cloudBase + direction * (Double(i) - 3) * 7 + (rng() - 0.5) * 8
            trend.append(min(100, max(3, Sky.jsRound(value))))
        }
        return WeatherDay(quality: quality, cloud: Int(cloudBase), sunset: nil, layers: nil,
                           temperatureBase: tempBase, wind: wind, windDirection: nil, gust: 0,
                           trend: trend, real: false)
    }
}
