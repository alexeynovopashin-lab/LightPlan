import Foundation
import LightPlanCore
import LightPlanData

/// Данные экрана «Свет» на одну минуту одних суток: порт `renderToday` и
/// `renderPro` из `light_plan:Light_Plan/beta/index.html` в чистую функцию —
/// без DOM, без SwiftUI, без побочных эффектов. `LightScreenModel` зовёт
/// `build(...)` на каждую минуту, `LightScreenView` только рисует то, что
/// вышло.
///
/// Слова приходят из словаря (`Lexicon`, итерация 14) уже готовыми строками —
/// `ProRow` хранит только текст, не ключ: единственное исключение, строка
/// астрономической ночи, разбирается прямо в строителе (`proAstroNight`).
public struct LightTelemetry: Equatable, Sendable {

    // MARK: - Шапка

    public struct Header: Equatable, Sendable {
        /// Погода шапки — виджет Apple: знак, градусы, состояние, мин/макс.
        public struct Weather: Equatable, Sendable {
            public let iconName: String
            public let temperature: String
            public let condition: String
            public let low: String
            public let high: String
        }
        public let locationName: String
        public let dateLabel: String
        public let note: String
        /// `nil` — настоящего прогноза на этот день нет: вместо погоды экран
        /// пишет `forecastNote`. Выдумка (28ж, слово Алексея 02.10) не рисуется.
        public let weather: Weather?
    }

    // MARK: - Показание купола (только для солнца — веб не трогает эти узлы
    // в лунном режиме, оставляя прежний текст; нативный `View` строится
    // заново каждый раз, поэтому честнее скрыть показание целиком, чем
    // держать текст солнца под изображением луны).

    public struct Readout: Equatable, Sendable {
        public let time: String
        public let phase: String
        public let sense: String
    }

    // MARK: - Тон состояния (делит цвет между «Условиями» и «что дальше»)

    public enum Gauge: Equatable, Sendable { case level(Int), stars }

    public struct Condition: Equatable, Sendable {
        public let gauge: Gauge
        public let text: String
    }

    public enum SunsetTone: Equatable, Sendable { case brass, green, ink, blue, muted }

    public struct Sunset: Equatable, Sendable {
        public let text: String
        public let tone: SunsetTone
    }

    public struct SkyRow: Equatable, Sendable {
        public let iconName: String
        public let text: String
    }

    public struct NextLightInfo: Equatable, Sendable {
        public let label: String
        public let value: String
        /// Тренд облачности — из прогноза; без прогноза `nil`, искры и слова нет.
        public let trend: [Double]?
        public let trendWord: String?
    }

    public struct ProRow: Equatable, Sendable {
        public let label: String
        public let value: String   // «—» или текст уже подставлен строителем
    }

    /// Плашка палитры предсказанного неба (`skySwatch` веба): градиент от зенита
    /// к горизонту и слово балла заката. Стоит над группой «Прогноз заката» и
    /// есть ровно тогда, когда есть сама группа: у обеих одно условие веба —
    /// у дня настоящий балл заката и ярусы облаков, время суток не смотрится.
    public struct Swatch: Equatable, Sendable {
        public let palette: SkyPalette
        public let word: String
    }

    public struct ProGroup: Equatable, Sendable {
        public let iconName: String
        public let title: String
        public let rows: [ProRow]
        public let swatch: Swatch?

        public init(iconName: String, title: String, swatch: Swatch? = nil, rows: [ProRow]) {
            self.iconName = iconName
            self.title = title
            self.rows = rows
            self.swatch = swatch
        }
    }

    public let header: Header
    public let readout: Readout?
    /// Тон состояния света уже с поправкой на непогоду (веб: пасмурно топит
    /// экспонометр в самый низ) — общий для «Условий» и «что дальше».
    public let tone: LightTone
    /// Цвет состояния — тот же `st.c`, каким купол красит зарево; для
    /// «отличного» тона именно он идёт в качестве акцента строк.
    public let stateColor: SkyColor
    public let condition: Condition
    public let sunset: Sunset
    public let golden: String
    public let light: String
    public let shadow: String
    /// Строки неба и ветра — из прогноза; без него `nil`, строк на экране нет.
    public let sky: SkyRow?
    public let wind: String?
    /// «Прогноз недоступен» / «Прогноз загружается…»; `nil`, пока у дня есть прогноз.
    public let forecastNote: String?
    /// `nil` скрывает строку «Воздух» целиком — прозрачный воздух не новость.
    public let air: String?
    public let next: NextLightInfo
    public let actionSubtitle: String
    public let proGroups: [ProGroup]

    // MARK: - Сборка

    /// - Parameters:
    ///   - moon: снимок луны на эту минуту — нужен только для первой группы
    ///     спойлера в лунном режиме (веб: спойлер отвечает тому же вопросу,
    ///     что и купол). `nil` в солнечном режиме — луну спойлер не показывает
    ///     вовсе, как и веб.
    public static func build(
        sun: SolarDay, t: Minutes, moon moonMode: Bool, moonSnapshot: MoonSnapshot?,
        weather: WeatherDay?, weatherStatus: WeatherStatus, air: AirSample?,
        headerLocationName: String, headerDateLabel: String, headerNote: String,
        lexicon: Lexicon, clock: ClockText, fahrenheit: Bool = false
    ) -> LightTelemetry {
        let raw = sun.state(at: t)
        let quality = weather?.quality
        // Прогноза нет — одна астрономия; об этом пишем словами, а не рисуем выдуманное.
        let forecastNote: String? = weather == nil
            ? lexicon.t(weatherStatus == .loading ? "wx.loading" : "wx.unavailable") : nil

        // Плохая погода перебивает свет: небо закрыто — экспонометр падает в
        // самый низ (веб: `if (q === "poor") st = {...}`). Веб заменяет объект
        // `st` целиком, а не поле за полем — вместе с рекомендацией, делением
        // и тоном пропадает и `stars`: даже ночью в тумане прибор показывает
        // деления, а не звёздный знак. Цвет и слово состояния не задеты.
        let tone: LightTone = quality == .poor ? .neutral : raw.tone
        let stars = quality == .poor ? false : raw.stars
        let level = quality == .poor ? 1 : (raw.level ?? 1)
        let recText = quality == .poor ? lexicon.t("sun.overcast.rec") : lexicon.t("sun.\(raw.code.rawValue).rec")

        let gauge: Gauge = stars ? .stars : .level(level)
        let condition = Condition(gauge: gauge, text: recText)

        // Заголовок: как виджет Apple — иконка, температура, состояние, мин/макс.
        let header = Header(
            locationName: headerLocationName, dateLabel: headerDateLabel, note: headerNote,
            weather: weather.map { w in
                Header.Weather(
                    iconName: w.quality.signIconName,
                    temperature: "\(tempOut(w.temperatureBase, t, fahrenheit))°",
                    condition: lexicon.t("qualCond.\(w.quality.rawValue)"),
                    low: "↓ \(tempOut(w.temperatureBase, 240, fahrenheit))°",
                    high: "↑ \(tempOut(w.temperatureBase, 960, fahrenheit))°")
            }
        )

        let readout: Readout? = moonMode ? nil : Readout(
            time: clock.fmt(t),
            phase: lexicon.t("sun.\(raw.code.rawValue).label"),
            sense: lexicon.t("sun.\(raw.code.rawValue).sense")
        )

        // Закат — главная фича, вынесена наверх: не искать её в астро-деталях.
        let sunset: Sunset
        if let score = weather?.sunset {
            sunset = Sunset(text: "\(sunsetWord(score, short: true, lexicon: lexicon)) · \(score) / 100",
                             tone: score >= 75 ? .brass : score >= 50 ? .green : score >= 28 ? .ink : .blue)
        } else {
            // Прогноза нет вовсе — честная надпись; прогноз есть, а часа заката в нём нет — «нет данных на этот день».
            sunset = Sunset(text: forecastNote ?? lexicon.t("card.noDataDay"), tone: .muted)
        }

        // Золотой час — окно, не момент: чтобы не спутать его с закатом.
        let golden: String
        if let goldenB = sun.goldenB, let set = sun.set {
            golden = lexicon.t("tele.goldenTill", ["range": clock.range(goldenB, sun.blueB), "t": clock.fmt(set)])
        } else {
            golden = "—"
        }

        let sky = weather.map {
            SkyRow(iconName: $0.quality.signIconName, text: "\(lexicon.t("qualSky.\($0.quality.rawValue)")) · \($0.cloud)%")
        }
        let wind = weather.map { windLine($0, lexicon: lexicon) }

        let next = buildNextLight(sun: sun, t: t, weather: weather, lexicon: lexicon)

        let actionSubtitle: String = tone == .stars
            ? (sun.astroB != nil ? clock.range(sun.astroB, (sun.astroA ?? 0) + 1440) : lexicon.t("sun.whiteNight"))
            : clock.range(sun.goldenB, sun.blueB)

        let proGroups = buildProGroups(
            sun: sun, t: t, weather: weather, weatherStatus: weatherStatus,
            moonSnapshot: moonMode ? moonSnapshot : nil, lexicon: lexicon, clock: clock,
            fahrenheit: fahrenheit
        )

        return LightTelemetry(
            header: header, readout: readout, tone: tone, stateColor: raw.color, condition: condition,
            sunset: sunset, golden: golden, light: lexicon.t("sun.\(raw.code.rawValue).light"),
            shadow: lexicon.t("shadow.\(sun.shadowWord(at: t).rawValue)"), sky: sky, wind: wind,
            forecastNote: forecastNote,
            air: Weather.airWord(air).map { lexicon.t($0.rawValue) },
            next: next, actionSubtitle: actionSubtitle, proGroups: proGroups
        )
    }

    // MARK: - «Что дальше» и спарклайн тренда

    private static func buildNextLight(sun: SolarDay, t: Minutes, weather: WeatherDay?, lexicon: Lexicon) -> NextLightInfo {
        let nl = sun.nextLight(at: t)
        let label = lexicon.t("next.\(nl.key.rawValue)")
        let value: String
        if let minutes = nl.minutes {
            value = durShort(minutes, lexicon: lexicon)
        } else {
            value = lexicon.t(sun.polar == .day ? "sun.noSet" : "sun.noRise")
        }
        guard let weather else { return NextLightInfo(label: label, value: value, trend: nil, trendWord: nil) }
        let c0 = weather.trend.first ?? 0
        let c1 = weather.trend.last ?? 0
        let trendWord = c1 < c0 - 12 ? lexicon.t("trend.clearing")
            : c1 > c0 + 12 ? lexicon.t("trend.closing") : lexicon.t("trend.same")
        return NextLightInfo(label: label, value: value, trend: weather.trend, trendWord: trendWord)
    }

    // MARK: - Спойлер «Подробно»

    private static func buildProGroups(
        sun: SolarDay, t: Minutes, weather: WeatherDay?, weatherStatus: WeatherStatus,
        moonSnapshot: MoonSnapshot?, lexicon: Lexicon, clock: ClockText, fahrenheit: Bool
    ) -> [ProGroup] {
        var groups: [ProGroup] = []

        if let mo = moonSnapshot {
            groups.append(ProGroup(iconName: "moon", title: lexicon.t("pro.moonNow"), rows: [
                ProRow(label: lexicon.t("pro.phase"),
                       value: "\(lexicon.t(mo.phase.name.rawValue)) · \(Int((mo.phase.fraction * 100).rounded()))%"),
                ProRow(label: lexicon.t("pro.azimuth"), value: "\(deg1(mo.azimuth))° · \(dirOf(mo.azimuth, lexicon: lexicon))"),
                ProRow(label: lexicon.t("pro.altitude"), value: signedDeg1(mo.altitude)),
                ProRow(label: lexicon.t("pro.rise"),
                       value: mo.arc.map { "\(clock.fmt($0.rise)) · \(deg0(mo.riseAzimuth ?? 0))°" } ?? "—"),
                ProRow(label: lexicon.t("pro.set"),
                       value: mo.arc.map { "\(clock.fmt($0.set)) · \(deg0(mo.setAzimuth ?? 0))°" } ?? "—"),
                ProRow(label: lexicon.t("pro.distance"), value: lexicon.t("pro.distKm", ["n": groupedNumber(mo.distance)])),
            ]))
        }

        let e = sun.elevation(at: t)
        let az = sun.azimuth(at: t)
        let shadow = sun.shadowRatio(at: t)
        groups.append(ProGroup(iconName: "sun", title: lexicon.t("pro.sunNow"), rows: [
            ProRow(label: lexicon.t("pro.azimuth"), value: "\(deg1(az))° · \(dirOf(az, lexicon: lexicon))"),
            ProRow(label: lexicon.t("pro.altitude"), value: signedDeg1(e)),
            ProRow(label: lexicon.t("pro.shadowLen"),
                   value: shadow.map { lexicon.t("pro.shadowOf", ["n": $0 < 10 ? String(format: "%.2f", $0) : String(format: "%.1f", $0)]) } ?? "—"),
        ]))

        let dayLenParts = sun.rise.flatMap { rise in sun.set.map { set in clock.fmt(set - rise) } }?.split(separator: ":") ?? []
        let dayLenH = dayLenParts.first.map(String.init) ?? "0"
        let dayLenM = dayLenParts.count > 1 ? String(dayLenParts[1]) : "00"
        groups.append(ProGroup(iconName: "clock", title: lexicon.t("pro.dayCourse"), rows: [
            ProRow(label: lexicon.t("pro.rise"), value: sun.rise.map { "\(clock.fmt($0)) · \(deg0(sun.azimuth(at: $0)))°" } ?? "—"),
            ProRow(label: lexicon.t("pro.solarNoon"), value: "\(clock.fmt(sun.solarNoon)) · \(String(format: "%.1f", sun.maxElevation))°"),
            ProRow(label: lexicon.t("pro.sunset"), value: sun.set.map { "\(clock.fmt($0)) · \(deg0(sun.azimuth(at: $0)))°" } ?? "—"),
            ProRow(label: lexicon.t("pro.dayLen"), value: lexicon.t("pro.dayLenFmt", ["h": dayLenH, "m": dayLenM])),
        ]))

        groups.append(ProGroup(iconName: "sunset", title: lexicon.t("pro.goldenBlue"), rows: [
            ProRow(label: lexicon.t("pro.goldenAM"), value: clock.range(sun.blueA, sun.goldenA)),
            ProRow(label: lexicon.t("pro.goldenPM"), value: clock.range(sun.goldenB, sun.blueB)),
            ProRow(label: lexicon.t("pro.blueAM"), value: clock.range(sun.civilA, sun.blueA)),
            ProRow(label: lexicon.t("pro.bluePM"), value: clock.range(sun.blueB, sun.civilB)),
        ]))

        // Астрономическая ночь: прочерк с особым словом «белая ночь», а не
        // просто «—» — единственная строка спойлера, где отсутствие значения
        // говорит не «нет данных», а «у этих суток нет темноты вовсе».
        let astroNightValue: String
        if let astB = sun.astroB { astroNightValue = clock.range(astB, (sun.astroA ?? 0) + 1440) }
        else { astroNightValue = lexicon.t("pro.whiteNight") }
        groups.append(ProGroup(iconName: "moon", title: lexicon.t("pro.twilight"), rows: [
            ProRow(label: lexicon.t("pro.civil"), value: clock.range(sun.set, sun.civilB)),
            ProRow(label: lexicon.t("pro.nautical"), value: clock.range(sun.civilB, sun.nauticalB)),
            ProRow(label: lexicon.t("pro.astro"),
                   value: sun.astroB != nil ? clock.range(sun.nauticalB, sun.astroB) : clock.range(sun.nauticalB, (sun.nauticalA ?? 0) + 1440)),
            ProRow(label: lexicon.t("pro.astroNight"), value: astroNightValue),
        ]))

        // «Источник» говорит честно, откуда прогноз: сам Open-Meteo, наш сервер или «нет прогноза».
        let sourceRow = ProRow(label: lexicon.t("pro.source"), value: lexicon.t(Self.sourceKey(weatherStatus)))
        if let weather {
            groups.append(ProGroup(iconName: "cloud", title: lexicon.t("pro.weather"), rows: [
                ProRow(label: lexicon.t("pro.sky"), value: lexicon.t("qualSky.\(weather.quality.rawValue)")),
                ProRow(label: lexicon.t("pro.cloud"), value: "\(weather.cloud)%"),
                // Спойлер пишет единицу буквой («°C»), не голым знаком градуса —
                // в шапке и телеметрии её нет, там единица подразумевается,
                // здесь веб называет её явно (`tempOut(...) + " " + unitLabel()`).
                ProRow(label: lexicon.t("pro.temp"), value: "\(tempOut(weather.temperatureBase, t, fahrenheit)) \(fahrenheit ? "°F" : "°C")"),
                ProRow(label: lexicon.t("pro.wind"), value: windLine(weather, lexicon: lexicon)),
                sourceRow,
            ]))
        } else {
            groups.append(ProGroup(iconName: "cloud", title: lexicon.t("pro.weather"), rows: [sourceRow]))
        }

        // Прогноз заката по ярусам — только когда есть настоящие данные.
        if let weather, let score = weather.sunset, let layers = weather.layers {
            let swatch = SkyPalette(weather: weather).map {
                Swatch(palette: $0, word: sunsetWord(score, short: false, lexicon: lexicon))
            }
            groups.append(ProGroup(iconName: "sunset", title: lexicon.t("pro.sunsetForecast"), swatch: swatch, rows: [
                ProRow(label: lexicon.t("pro.score"), value: lexicon.t("pro.scoreOf", ["n": "\(score)", "word": sunsetWord(score, short: false, lexicon: lexicon)])),
                ProRow(label: lexicon.t("pro.layerLow"), value: lexicon.t("pro.pctNote", ["n": "\(Int(layers.low.rounded()))", "note": lexicon.t("pro.layerLowNote")])),
                ProRow(label: lexicon.t("pro.layerMid"), value: lexicon.t("pro.pctNote", ["n": "\(Int(layers.mid.rounded()))", "note": lexicon.t("pro.layerMidNote")])),
                ProRow(label: lexicon.t("pro.layerHigh"), value: lexicon.t("pro.pctNote", ["n": "\(Int(layers.high.rounded()))", "note": lexicon.t("pro.layerHighNote")])),
                ProRow(label: lexicon.t("pro.humidity"), value: "\(Int(layers.humidity.rounded()))%"),
            ]))
        }

        return groups
    }

    // MARK: - Мелкие помощники (порт мелких функций веба)

    /// Ключ слова строки «Источник» (28ж): есть прогноз — по пути, нет — «нет прогноза».
    static func sourceKey(_ status: WeatherStatus) -> String {
        switch status {
        case .live(.direct): "pro.srcLive"
        case .live(.proxy): "pro.srcProxy"
        case .loading, .unavailable: "pro.srcNone"
        }
    }

    /// `tempAt`+`tempOut` веба. Прогноз всегда приходит в Цельсии; Фаренгейт
    /// считается из неокруглённого значения, как `tempShow` веба.
    static func tempOut(_ base: Int, _ t: Minutes, _ fahrenheit: Bool = false) -> Int {
        let c = Double(base) + 5 * sin((t - 600) / 1440 * 2 * .pi)
        return Int((fahrenheit ? c * 9 / 5 + 32 : c).rounded())
    }

    static func windLine(_ w: WeatherDay, lexicon: Lexicon) -> String {
        var out = lexicon.t("tele.windVal", ["n": "\(w.wind)"]) + " · " + windWord(w.wind, lexicon: lexicon)
        if let dir = w.windDirection, w.wind > 1 {
            out += " · " + lexicon.t("wind.from", ["dir": dirOf(dir, lexicon: lexicon)])
        }
        if w.gust >= w.wind + 3 {
            out += " · " + lexicon.t("wind.gust", ["n": "\(w.gust)"])
        }
        return out
    }

    private static func windWord(_ w: Int, lexicon: Lexicon) -> String {
        w <= 1 ? lexicon.t("wind.calm") : w <= 3 ? lexicon.t("wind.light")
            : w <= 6 ? lexicon.t("wind.moderate") : lexicon.t("wind.strong")
    }

    static func durShort(_ m: Minutes, lexicon: Lexicon) -> String {
        let whole = max(0, Int(m.rounded()))
        if whole < 60 { return lexicon.t("durS.minutes", ["m": "\(whole)"]) }
        let h = whole / 60, mm = whole % 60
        return mm != 0 ? lexicon.t("durS.hoursMins", ["h": "\(h)", "m": "\(mm)"]) : lexicon.t("durS.hours", ["h": "\(h)"])
    }

    /// Короткое и длинное слово закатного балла (веб `sunsetShort`/`sunsetWord`).
    static func sunsetWord(_ s: Int, short: Bool, lexicon: Lexicon) -> String {
        let prefix = short ? "sunsetS" : "sunsetW"
        return s >= 75 ? lexicon.t("\(prefix).beautiful") : s >= 50 ? lexicon.t("\(prefix).color")
            : s >= 28 ? lexicon.t("\(prefix).calm") : lexicon.t("\(prefix).none")
    }

    /// Румб по азимуту — ключ `dirs` несёт все 16 через запятую, как в вебе.
    static func dirOf(_ az: Degrees, lexicon: Lexicon) -> String {
        let dirs = lexicon.t("dirs").split(separator: ",")
        guard !dirs.isEmpty else { return "" }
        let idx = Int((az / 22.5).rounded()) % dirs.count
        return String(dirs[idx >= 0 ? idx : idx + dirs.count])
    }

    private static func deg0(_ d: Degrees) -> String { String(format: "%.0f", d) }
    private static func deg1(_ d: Degrees) -> String { String(format: "%.1f", d) }
    private static func signedDeg1(_ d: Degrees) -> String { (d >= 0 ? "+" : "−") + String(format: "%.1f", abs(d)) + "°" }

    private static func groupedNumber(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v.rounded()))"
    }
}

/// Снимок луны на минуту `t` для купола-в-режиме-луны и первой группы
/// спойлера — собирается вызывающим (`LightScreenModel`), потому что нужен
/// `Place`, а `LightTelemetry.build` его не берёт: остальные 90% строк экрана
/// про луну не знают вовсе.
public struct MoonSnapshot: Sendable {
    public let phase: MoonPhase
    public let azimuth: Degrees
    public let altitude: Degrees
    public let distance: Double
    public let arc: MoonArc?
    public let riseAzimuth: Degrees?
    public let setAzimuth: Degrees?

    public init(phase: MoonPhase, azimuth: Degrees, altitude: Degrees, distance: Double,
                arc: MoonArc?, riseAzimuth: Degrees?, setAzimuth: Degrees?) {
        self.phase = phase
        self.azimuth = azimuth
        self.altitude = altitude
        self.distance = distance
        self.arc = arc
        self.riseAzimuth = riseAzimuth
        self.setAzimuth = setAzimuth
    }
}
