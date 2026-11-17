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
    /// Осадки за час, мм (31.2: окно осадков вокруг заката и выбранного момента, `WeatherDay.wet`). Веб их по часам не хранит.
    public let precipitation: Double

    public init(cloud: Double, code: Int, temperature: Double, low: Double, mid: Double, high: Double,
                humidity: Double, windSpeed: Double, windDirection: Double?, windGusts: Double?, precipitation: Double = 0) {
        self.precipitation = precipitation
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

/// Осадки по коду WMO часа (31.2, Томск 17.11: ночной снег назывался «Дождь»).
public enum Precip: String, Sendable, Equatable {
    case rain, snow

    /// 71–77 — снег и снежные зёрна, 85–86 — снегопад-ливень; прочее от 51 (морось, дождь, ледяной дождь, ливень, гроза) — дождь;
    /// до 51 (ясно, облачно, туман) — осадков нет.
    public static func of(code: Int) -> Precip? {
        guard code >= 51 else { return nil }
        return (71...77).contains(code) || (85...86).contains(code) ? .snow : .rain
    }
}

/// Прогноз одних суток, собранный из почасового ответа (порт `buildWx`).
public struct WeatherDay: Sendable, Equatable {
    /// Категория дня (31.2): туман утром, осадки в окне заката (`precip`) → `.poor`, иначе — категория закатного балла (`sky`).
    /// Осадки, кончившиеся за много часов до заката, её не портят — у веба (`webQuality`) их хватало на весь день.
    public let quality: DayQuality
    /// Небо без осадков: туман утром или категория закатного балла (без ярусов — по облачности дня). Из него `quality(at:)` берёт категорию
    /// момента, когда вокруг него сухо.
    public let sky: DayQuality
    /// Осадки в окне заката (±`wetWindowHours` от его часа); без заката (полярные сутки) — по суткам, как у веба. `nil` — сухо.
    public let precip: Precip?
    /// Категория по правилу веба (`buildWx`: осадки за сутки > 0,5 мм или код в 15 ч ≥ 51 → «плохо» на весь день) —
    /// только для сверки с вебом (`WeatherDayParityTests`); экраны читают `quality`.
    public let webQuality: DayQuality
    /// Часы суток 0…23 (местные), из которых собран день: температура и осадки на выбранный момент.
    public let hours: [Int: HourRecord]
    /// Температура в 00:00 следующих суток — чтобы между 23:00 и полуночью тоже была прямая, а не ступенька. `nil` — следующих суток нет.
    public let nextMidnight: Double?
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
    /// Рассветный балл (30б.2в-6, слова Алексея 27.10: «та же формула в час рассвета»): ярусы облаков и влажность в час восхода и аэрозоль
    /// того часа, та же `SunsetScore.score`, что у заката. `nil` — рассвета нет (полярные сутки, ночь) или часа восхода в прогнозе нет:
    /// число не выдумывается. Только средний виджет; на «Свете» оценки рассвета пока нет (ждёт рисунка Claude Design).
    public let sunrise: Int?

    public init(quality: DayQuality, cloud: Int, sunset: Int?, layers: HourRecord?, temperatureBase: Int,
                wind: Int, windDirection: Double?, gust: Int, trend: [Double], real: Bool, sunrise: Int? = nil,
                sky: DayQuality? = nil, precip: Precip? = nil, webQuality: DayQuality? = nil,
                hours: [Int: HourRecord] = [:], nextMidnight: Double? = nil) {
        self.sunrise = sunrise
        self.quality = quality
        self.sky = sky ?? quality
        self.precip = precip
        self.webQuality = webQuality ?? quality
        self.hours = hours
        self.nextMidnight = nextMidnight
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
    /// Полуширина окна осадков, часы (31.2): закат и выбранный момент судятся по часам `h − 2 … h + 2`. Почасовые осадки Open-Meteo —
    /// сумма за предыдущий час, так что окно видит примерно 3 часа до и 2 после. Два часа — это и сырой воздух с низкими облаками
    /// сразу после осадков, и ошибка прогноза по времени (час-два); дальше небо уже решают ярусы облаков часа заката, а их балл читает сам.
    public static let wetWindowHours = 2

    /// Осадки в окне вокруг часа: есть час с кодом ≥ 51 или сумма за окно > 0,5 мм (порог веба на сутки, здесь — на окно).
    /// Вид — по большинству часов с осадками (поровну — снег); сумма без кодов — дождь.
    public static func wet(_ hours: [Int: HourRecord], around hour: Int) -> Precip? {
        let window = (hour - wetWindowHours)...(hour + wetWindowHours)
        return wet(window.compactMap { hours[$0] })
    }

    static func wet(_ records: [HourRecord]) -> Precip? {
        let kinds = records.compactMap { Precip.of(code: $0.code) }
        let sum = records.reduce(0) { $0 + $1.precipitation }
        guard !kinds.isEmpty || sum > 0.5 else { return nil }
        let snow = kinds.filter { $0 == .snow }.count
        return !kinds.isEmpty && snow * 2 >= kinds.count ? .snow : .rain
    }

    /// Час суток для минуты, `0…23` (минуты за краем суток держат крайний час).
    static func hour(of minute: Double) -> Int { Int(min(23, max(0, (minute / 60).rounded()))) }

    /// Осадки около выбранной минуты (окно `wetWindowHours`); часов нет — осадки дня.
    public func precip(at minute: Double) -> Precip? {
        hours.isEmpty ? precip : Self.wet(hours, around: Self.hour(of: minute))
    }

    /// Категория неба на выбранную минуту: туман — как у дня; осадки рядом — `.poor`; сухо — небо дня без осадков (`sky`).
    public func quality(at minute: Double) -> DayQuality {
        if sky == .fog { return .fog }
        if hours.isEmpty { return quality }
        return precip(at: minute) != nil ? .poor : sky
    }

    /// Температура на минуту суток, °C, из часов прогноза: между часами — по прямой, за краем — ближайший час.
    /// `nil` — часов нет вовсе: число не выдумывается (Алексей 02.10, «без имитации»).
    public func temperature(at minute: Double) -> Double? {
        guard !hours.isEmpty else { return nil }
        let m = max(0, minute)
        let h0 = Int((m / 60).rounded(.down))
        let a = hours[h0]?.temperature
        let b = h0 + 1 == 24 ? nextMidnight : hours[h0 + 1]?.temperature
        switch (a, b) {
        case let (a?, b?): return a + (b - a) * (m / 60 - Double(h0))
        case let (a?, nil): return a
        default: return Weather.nearHour(hours, min(23, h0))?.temperature
        }
    }

    /// Минимум и максимум часов суток, °C; `nil` — часов нет.
    public var temperatureRange: (low: Double, high: Double)? {
        let t = hours.values.map(\.temperature)
        guard let low = t.min(), let high = t.max() else { return nil }
        return (low, high)
    }

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
        from hourly: HourlyWeather, place: Place, air: [CivilDate: [Int: AirSample]] = [:], time: SkyTime = .web
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
                windDirection: hourly.windDirection?[i], windGusts: hourly.windGusts?[i],
                precipitation: hourly.precipitation[i])
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
            let sun = SolarDay(date: date, place: place, time: time)
            var sunset: Int?
            var layers: HourRecord?
            var bareForQuality: Int?
            var setHourForWet: Int?
            if let setMinutes = sun.set {
                let setHour = Int(min(23, max(0, Sky.jsRound(setMinutes / 60))))
                setHourForWet = setHour
                if let lay = Weather.nearHour(bucket.byHour, setHour) {
                    let bare = SunsetScore.score(low: lay.low, mid: lay.mid, high: lay.high, humidity: lay.humidity)
                    let atSunset = Weather.nearHour(air[date] ?? [:], setHour)
                    sunset = SunsetScore.score(low: lay.low, mid: lay.mid, high: lay.high,
                                                humidity: lay.humidity, air: atSunset)
                    layers = lay
                    bareForQuality = bare
                }
            }

            // Рассвет — та же формула в час восхода (`Weather.nearHour` на округлённом часе, как у заката), воздух того же часа.
            var sunrise: Int?
            if let riseMinutes = sun.rise {
                let riseHour = Int(min(23, max(0, Sky.jsRound(riseMinutes / 60))))
                if let lay = Weather.nearHour(bucket.byHour, riseHour) {
                    sunrise = SunsetScore.score(low: lay.low, mid: lay.mid, high: lay.high, humidity: lay.humidity,
                                                 air: Weather.nearHour(air[date] ?? [:], riseHour))
                }
            }

            // Веб: дождь за сутки и туман перебивают категорию дня; иначе категория из балла. Хранится только для сверки с вебом.
            let wetDay = bucket.precipitation > 0.5 || code >= 51
            let webQuality: DayQuality
            if bucket.fogMorning {
                webQuality = .fog
            } else if wetDay {
                webQuality = .poor
            } else if let bare = bareForQuality {
                webQuality = SunsetScore.category(bare)
            } else {
                webQuality = SunsetScore.deriveQuality(cloud: cloud, code: code,
                                                        precipitation: bucket.precipitation, fogMorning: bucket.fogMorning)
            }
            // 31.2: небо без осадков — туман или балл; осадки — только в окне заката (без заката — за сутки, как у веба).
            let sky: DayQuality = bucket.fogMorning ? .fog
                : bareForQuality.map(SunsetScore.category)
                ?? SunsetScore.deriveQuality(cloud: cloud, code: 0, precipitation: 0, fogMorning: false)
            let precip: Precip?
            if let setHour = setHourForWet {
                precip = wet(bucket.byHour, around: setHour)
            } else {
                precip = wetDay ? (wet(Array(bucket.byHour.values)) ?? .rain) : nil
            }
            let quality: DayQuality = sky == .fog ? .fog : precip != nil ? .poor : sky

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
                windDirection: windDirection, gust: Int(Sky.jsRound(bucket.gust)), trend: trend, real: true, sunrise: sunrise,
                sky: sky, precip: precip, webQuality: webQuality,
                hours: bucket.byHour, nextMidnight: buckets[date.adding(days: 1)]?.byHour[0]?.temperature)
        }
        return (days, hourlyOut)
    }
}
