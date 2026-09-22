import Foundation

/// Один час прогноза (веб — запись `byHour[hh]` внутри `buildWx`).
///
/// `low`/`mid`/`high`/`humidity` уже несут запасное значение, если Open-Meteo
/// не прислал соответствующий ряд вовсе (веб `has(k)`, проверка на весь ряд,
/// не на час): `low` — общая облачность, `mid`/`high` — ноль, влажность — 50.
/// Отдельные часы с `null` внутри присутствующего ряда — редкий случай API,
/// не измеренный в проде (замер 22 сентября 2026: 504 часа основного прогноза
/// и 120 часов воздуха, ни одного `null`); не переносится, см. DECISIONS
/// «Погода — null внутри присутствующего ряда» (итерация 10).
public struct HourRecord: Sendable, Equatable {
    public let cloud: Double
    public let code: Int
    public let temperature: Double
    public let low: Double
    public let mid: Double
    public let high: Double
    public let humidity: Double
    public let windSpeed: Double
    public let windDirection: Double?
    public let windGusts: Double?

    public init(cloud: Double, code: Int, temperature: Double, low: Double, mid: Double, high: Double,
                humidity: Double, windSpeed: Double, windDirection: Double?, windGusts: Double?) {
        self.cloud = cloud
        self.code = code
        self.temperature = temperature
        self.low = low
        self.mid = mid
        self.high = high
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.windGusts = windGusts
    }
}

/// Почасовой ответ Open-Meteo `/v1/forecast`, как есть — сырые ряды одной
/// длины на `time`. Поля, которые веб читает через `has(k)` (весь ряд есть
/// или его нет вовсе), — необязательные массивы; `cloud`, `temperature`,
/// `windSpeed`, `precipitation`, `weatherCode` веб читает без проверки, и
/// здесь они обязательны той же логикой (§ 4.6 плана).
public struct HourlyWeather: Sendable, Equatable {
    /// Местное время часа, как отдаёт `timezone=auto`: `"yyyy-MM-ddTHH:mm"`.
    /// Не парсится в `Date` — календарная дата и час читаются из строки, как
    /// в вебе (`dt.slice(0,10)`, `+dt.slice(11,13)`).
    public let time: [String]
    public let cloud: [Double]
    public let cloudLow: [Double]?
    public let cloudMid: [Double]?
    public let cloudHigh: [Double]?
    public let humidity: [Double]?
    public let temperature: [Double]
    public let windSpeed: [Double]
    public let windDirection: [Double]?
    public let windGusts: [Double]?
    public let precipitation: [Double]
    public let weatherCode: [Int]

    public init(time: [String], cloud: [Double], cloudLow: [Double]? = nil, cloudMid: [Double]? = nil,
                cloudHigh: [Double]? = nil, humidity: [Double]? = nil, temperature: [Double],
                windSpeed: [Double], windDirection: [Double]? = nil, windGusts: [Double]? = nil,
                precipitation: [Double], weatherCode: [Int]) {
        self.time = time
        self.cloud = cloud
        self.cloudLow = cloudLow
        self.cloudMid = cloudMid
        self.cloudHigh = cloudHigh
        self.humidity = humidity
        self.temperature = temperature
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.windGusts = windGusts
        self.precipitation = precipitation
        self.weatherCode = weatherCode
    }
}

/// Прогноз одних суток, собранный из почасового ответа (порт `buildWx`).
public struct WeatherDay: Sendable, Equatable {
    public let quality: DayQuality
    public let cloud: Int
    /// Закатный балл с поправкой на аэрозоль; `nil` — часа заката в прогнозе нет.
    public let sunset: Int?
    /// Час заката целиком — сунсет-панель читает температуру и ветер отсюда,
    /// а не синусоиду от суточного среднего (веб: замер мазал на 4.7–6.3°).
    public let layers: HourRecord?
    public let temperatureBase: Int
    public let wind: Int
    /// Градусы, откуда дует; `nil` — направления нет (ветер переменился со
    /// всех сторон за сутки), не округляется — как в вебе.
    public let windDirection: Double?
    public let gust: Int
    /// Облачность часов 16…21 — тренд к окну съёмки, не округляется.
    public let trend: [Double]
    /// `false` — это выдумка (`MockWeather`), не настоящий прогноз.
    public let real: Bool

    public init(quality: DayQuality, cloud: Int, sunset: Int?, layers: HourRecord?, temperatureBase: Int,
                wind: Int, windDirection: Double?, gust: Int, trend: [Double], real: Bool) {
        self.quality = quality
        self.cloud = cloud
        self.sunset = sunset
        self.layers = layers
        self.temperatureBase = temperatureBase
        self.wind = wind
        self.windDirection = windDirection
        self.gust = gust
        self.trend = trend
        self.real = real
    }
}

extension WeatherDay {
    /// Разбирает `"yyyy-MM-ddTHH:mm"` без `DateFormatter`: строка всегда
    /// местная и в этом виде, как её отдаёт Open-Meteo при `timezone=auto`.
    /// `public` — тем же приёмом пользуется слой Data, раскладывая ответ
    /// воздуха по суткам и часам (`OpenMeteoSource`).
    public static func parse(_ time: String) -> (date: CivilDate, hour: Int)? {
        guard time.utf8.count >= 13,
              let y = Int(time.prefix(4)), let m = Int(time.dropFirst(5).prefix(2)),
              let d = Int(time.dropFirst(8).prefix(2)), let hh = Int(time.dropFirst(11).prefix(2))
        else { return nil }
        return (CivilDate(year: y, month: m, day: d), hh)
    }

    /// Сборка дней из почасового ответа: категория, закатный балл, температура,
    /// ветер, тренд (порт `buildWx`). `air` — аэрозоль и пыль по суткам и часам
    /// (второй запрос Open-Meteo, itr 10), сводит их в поправку заката.
    ///
    /// Возвращает и сами дни, и почасовые записи — вторые нужны погоде над
    /// окном Млечного Пути (`MilkyWaySky`), как `wxByHour` веба.
    public static func buildDays(
        from hourly: HourlyWeather, place: Place, air: [CivilDate: [Int: AirSample]] = [:]
    ) -> (days: [CivilDate: WeatherDay], hourly: [CivilDate: [Int: HourRecord]]) {
        struct Bucket {
            var cloudSum = 0.0, cloudCount = 0
            var precipitation = 0.0
            var winds: [Double] = []
            var temperatures: [Double] = []
            var byHour: [Int: HourRecord] = [:]
            var fogMorning = false
            var dirX = 0.0, dirY = 0.0
            var gust = 0.0
        }

        var buckets: [CivilDate: Bucket] = [:]
        for i in 0..<hourly.time.count {
            guard let (date, hour) = parse(hourly.time[i]) else { continue }
            var bucket = buckets[date] ?? Bucket()
            let cloud = hourly.cloud[i]
            let code = hourly.weatherCode[i]
            if hour >= 8 && hour <= 20 {
                bucket.cloudSum += cloud
                bucket.cloudCount += 1
                bucket.winds.append(hourly.windSpeed[i])
                // Направление усредняется по составляющим — среднее между 350°
                // и 10° арифметически даёт юг, единичные векторы держат север.
                if let wdir = hourly.windDirection?[i] {
                    let a = Sky.rad(wdir)
                    bucket.dirX += cos(a)
                    bucket.dirY += sin(a)
                }
                if let gust = hourly.windGusts?[i] { bucket.gust = max(bucket.gust, gust) }
            }
            bucket.precipitation += hourly.precipitation[i]
            bucket.temperatures.append(hourly.temperature[i])
            bucket.byHour[hour] = HourRecord(
                cloud: cloud, code: code, temperature: hourly.temperature[i],
                low: hourly.cloudLow?[i] ?? cloud, mid: hourly.cloudMid?[i] ?? 0, high: hourly.cloudHigh?[i] ?? 0,
                humidity: hourly.humidity?[i] ?? 50, windSpeed: hourly.windSpeed[i],
                windDirection: hourly.windDirection?[i], windGusts: hourly.windGusts?[i])
            if hour >= 5 && hour <= 9 && (code == 45 || code == 48) { bucket.fogMorning = true }
            buckets[date] = bucket
        }

        var days: [CivilDate: WeatherDay] = [:]
        var hourlyOut: [CivilDate: [Int: HourRecord]] = [:]
        for (date, bucket) in buckets {
            hourlyOut[date] = bucket.byHour
            let cloud = bucket.cloudCount > 0 ? Sky.jsRound(bucket.cloudSum / Double(bucket.cloudCount)) : 50
            let code = bucket.byHour[15]?.code ?? bucket.byHour[12]?.code ?? 0

            // Ярусы облаков в час заката — там и решается, каким будет закат.
            let sun = SolarDay(date: date, latitude: place.latitude, longitude: place.longitude,
                                utcOffsetHours: place.zone.utcOffsetHours(on: date))
            var sunset: Int?
            var layers: HourRecord?
            var bareForQuality: Int?
            if let setMinutes = sun.set {
                let setHour = Int(min(23, max(0, Sky.jsRound(setMinutes / 60))))
                if let lay = Weather.nearHour(bucket.byHour, setHour) {
                    let bare = SunsetScore.score(low: lay.low, mid: lay.mid, high: lay.high, humidity: lay.humidity)
                    let atSunset = Weather.nearHour(air[date] ?? [:], setHour)
                    sunset = SunsetScore.score(low: lay.low, mid: lay.mid, high: lay.high,
                                                humidity: lay.humidity, air: atSunset)
                    layers = lay
                    bareForQuality = bare
                }
            }

            // Дождь и туман перебивают категорию дня; иначе категория из балла.
            let quality: DayQuality
            if bucket.fogMorning {
                quality = .fog
            } else if bucket.precipitation > 0.5 || code >= 51 {
                quality = .poor
            } else if let bare = bareForQuality {
                quality = SunsetScore.category(bare)
            } else {
                quality = SunsetScore.deriveQuality(cloud: cloud, code: code,
                                                     precipitation: bucket.precipitation, fogMorning: bucket.fogMorning)
            }

            let meanWind = bucket.winds.isEmpty ? 0 : bucket.winds.reduce(0, +) / Double(bucket.winds.count)
            let meanTemp = bucket.temperatures.isEmpty ? 0 : bucket.temperatures.reduce(0, +) / Double(bucket.temperatures.count)
            // Ноль длины вектора — не север, а «направления нет»: ветер за
            // день переменился со всех сторон.
            let windDirection: Double? = (bucket.dirX != 0 || bucket.dirY != 0)
                ? (Sky.deg(atan2(bucket.dirY, bucket.dirX)) + 360).truncatingRemainder(dividingBy: 360)
                : nil
            let trend = [16, 17, 18, 19, 20, 21].map { hh in bucket.byHour[hh]?.cloud ?? cloud }

            days[date] = WeatherDay(
                quality: quality, cloud: Int(cloud), sunset: sunset, layers: layers,
                temperatureBase: Int(Sky.jsRound(meanTemp)), wind: Int(Sky.jsRound(meanWind)),
                windDirection: windDirection, gust: Int(Sky.jsRound(bucket.gust)), trend: trend, real: true)
        }
        return (days, hourlyOut)
    }
}
