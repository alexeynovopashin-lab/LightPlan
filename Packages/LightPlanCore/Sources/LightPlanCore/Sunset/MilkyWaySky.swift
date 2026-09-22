import Foundation

/// Прозрачность неба для Млечного Пути — своя оценка, не от стороннего
/// сервиса (порт `mwSkyAt`): считается по окну съёмки (`MilkyWayWindow`), не
/// по суткам целиком — небо в обед ядру не касается. Нет реальной погоды на
/// эти часы (мок, дата дальше 16-суточного горизонта) — окна нет вовсе, и это
/// не ошибка, экран просто не покажет строку (как и с воздухом).
public struct MilkyWaySky: Sendable, Equatable {
    public let score: Int
    public let look: DayQuality
    public let word: AirCondition?
    public let cloud: Int
    public let humidity: Int
    public let air: AirSample?

    public init(score: Int, look: DayQuality, word: AirCondition?, cloud: Int, humidity: Int, air: AirSample?) {
        self.score = score
        self.look = look
        self.word = word
        self.cloud = cloud
        self.humidity = humidity
        self.air = air
    }

    /// - Parameters:
    ///   - hourly: почасовые записи по суткам — `hourly` из
    ///     `WeatherDay.buildDays(from:place:air:)`, ключ — тот же день, что
    ///     несёт запись.
    ///   - air: аэрозоль и пыль по суткам и часам, тем же ключом.
    public static func over(
        date: CivilDate, window: MilkyWayWindow,
        hourly: [CivilDate: [Int: HourRecord]], air: [CivilDate: [Int: AirSample]]
    ) -> MilkyWaySky? {
        guard window.dark, !window.spans.isEmpty else { return nil }

        var cloudSum = 0.0, humiditySum = 0.0, sampleCount = 0
        var aodMax = -1.0, dustMax = -1.0
        // По настоящим отрезкам, а не по оболочке from–to: между ними бывает
        // час, когда луна взошла или ядро просело, и погода того часа к
        // съёмке отношения не имеет.
        for span in window.spans {
            var x = span.from
            while x <= span.to {
                let dayOffset = Int((x / 1440).rounded(.down))
                let day = date.adding(days: dayOffset)
                let wrapped = x.truncatingRemainder(dividingBy: 1440)
                let minuteOfDay = wrapped < 0 ? wrapped + 1440 : wrapped
                let hour = Int((minuteOfDay / 60).rounded(.down))

                // Пропуск в прогнозе — «не знаю», а не «ноль»: час без числа
                // просто не участвует в среднем.
                if let record = Weather.nearHour(hourly[day] ?? [:], hour) {
                    cloudSum += record.cloud
                    humiditySum += record.humidity
                    sampleCount += 1
                }
                if let sample = Weather.nearHour(air[day] ?? [:], hour) {
                    if let aod = sample.aod, aod.isFinite { aodMax = max(aodMax, aod) }
                    if let dust = sample.dust, dust.isFinite { dustMax = max(dustMax, dust) }
                }
                x += 15
            }
        }
        guard sampleCount > 0 else { return nil }

        let cloud = cloudSum / Double(sampleCount)
        let humidity = humiditySum / Double(sampleCount)
        // Сплошная облачность гасит небо целиком — прямая шкала, без ярусов:
        // ядро не горизонтальный источник, ему всё равно, на какой высоте муть.
        var score = 100 - cloud
        if humidity > 70 { score -= (humidity - 70) * 0.7 }
        if aodMax > 0.35 { score -= (aodMax - 0.35) * 90 }
        if dustMax >= 20 { score -= 15 }
        let scoreInt = Int(min(100, max(0, Sky.jsRound(score))))

        let air: AirSample? = (aodMax >= 0 || dustMax >= 0)
            ? AirSample(aod: aodMax >= 0 ? aodMax : 0, dust: dustMax >= 0 ? dustMax : 0)
            : nil
        // Слово и балл — про разное: облака называют облака, а всё остальное,
        // что съело прозрачность, — дымку (веб, комментарий у `mwSkyAt`).
        let word = Weather.airWord(air)
        let look: DayQuality = cloud >= 70 ? .poor : cloud >= 35 ? .good
            : (scoreInt < 75 || word != nil) ? .plain : .excellent

        return MilkyWaySky(score: scoreInt, look: look, word: word,
                            cloud: Int(Sky.jsRound(cloud)), humidity: Int(Sky.jsRound(humidity)), air: air)
    }
}
