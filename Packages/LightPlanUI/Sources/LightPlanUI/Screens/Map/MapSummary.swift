import Foundation
import LightPlanCore

/// Свод карты под строкой показания (порт заполнения `.map-fold` в
/// `renderMap` веба, итерация 20б): строки момента, пять строк Млечного Пути
/// и группы «Подробно».
///
/// Строка, которой нечего сказать, не пишет прочерк, а отсутствует: веб
/// прячет её `hidden`. Строки «только астро» (`pro-only`) в обычном режиме
/// тоже отсутствуют. Чистая функция: окно Млечного Пути, помеха луны и погода
/// над окном считаются снаружи — это триста шагов астрономии, их кэширует
/// экран.
public struct MapSummary: Equatable, Sendable {

    /// Цвет значения.
    public enum Tone: Equatable, Sendable {
        /// Цвет строки по умолчанию (`.t-value` без своего цвета — `--ink`).
        case ink
        case ink2
        case ink4
        case terra
        /// `#C6AAE8` — окно Млечного Пути открыто.
        case violet
        /// `#E2A44C` — точка освещается, тёплое ближайшее событие.
        case warm
        /// `#8A8478` — точка в тени.
        case shade
    }

    public struct Row: Equatable, Sendable {
        /// Ключ словаря подписи — он же имя строки в снимке пары.
        public let label: String
        public let text: String
        public let tone: Tone
    }

    public let rows: [Row]
    public let pro: [LightTelemetry.ProGroup]

    /// Млечный Путь этих суток — только когда слой включён.
    public struct MilkyWayInput {
        public let window: MilkyWayWindow
        public let moon: MoonVsStars
        public let sky: MilkyWaySky?
        public let nextDark: () -> CivilDate?
    }

    /// - Parameters:
    ///   - date: выбранные сутки (`selDate`); `t` может уйти за 1440.
    ///   - utcOffset: пояс места сейчас (`TZ` веба — `tzAt(…, new Date())`).
    ///   - glow: засветка места (`glowVal`).
    ///   - mw: окно, луна и погода над окном; `nil` — слой выключен.
    public static func build(
        date: CivilDate, t: Minutes, sun: SolarDay, place: Place, utcOffset: Double, pro: Bool,
        glow: Double?, mw: MilkyWayInput?, dateShort: (CivilDate) -> String,
        lexicon: Lexicon, clock: ClockText
    ) -> MapSummary {
        func dir(_ a: Degrees) -> String { LightTelemetry.dirOf(a, lexicon: lexicon) }
        func signed(_ d: Degrees) -> String { (d >= 0 ? "+" : "−") + String(format: "%.1f", abs(d)) + "°" }
        func azDir(_ a: Degrees) -> String {
            lexicon.t("mpro.azDir", ["az": String(format: "%.1f", a), "dir": dir(a)])
        }

        let e = sun.elevation(at: t), az = sun.azimuth(at: t), sh = sun.shadowRatio(at: t)
        let moonNow = MoonSample(date: date, minutes: t, place: place)
        let moonArc = MoonDay(date: date, place: place).arc(at: t)
        let lit = Int((moonNow.phase.fraction * 100 + 0.5).rounded(.down))
        var rows: [Row] = []

        // Свет идёт — пока солнце светит или есть зарево (до −12°).
        if pro, e > -12 {
            let key = e > 0 ? "map.dirFrom" : "map.glowFrom"
            rows.append(Row(label: "map.lightFrom",
                            text: lexicon.t(key, ["dir": dir(az), "az": String(format: "%.0f", az)]), tone: .ink))
        }
        if pro { rows.append(Row(label: "map.sunElev", text: signed(e), tone: .ink)) }
        if pro, let sh, sh != 0 {
            let n = sh < 10 ? String(format: "%.1f", sh) : String(Int((sh + 0.5).rounded(.down)))
            rows.append(Row(label: "map.shadow",
                            text: lexicon.t("map.shadowTo", ["n": n, "dir": dir((az + 180).truncatingRemainder(dividingBy: 360))]),
                            tone: .ink))
        }

        // Окна света: время и азимут — куда смотреть, а не только когда.
        func window(_ a: Minutes?, _ b: Minutes?) -> String {
            guard let a, let b else { return "—" }
            return lexicon.t("map.rangeDir", ["range": clock.range(a, b), "dir": dir(sun.azimuth(at: a))])
        }
        rows.append(Row(label: "map.golden", text: window(sun.goldenB, sun.blueB), tone: .ink))
        rows.append(Row(label: "map.blue", text: window(sun.blueB, sun.civilB), tone: .ink))

        let moonText: String
        if moonNow.altitude > 0 {
            moonText = pro
                ? lexicon.t("map.moonPro", ["dir": dir(moonNow.azimuth), "alt": String(format: "%.0f", moonNow.altitude), "pct": "\(lit)"])
                : lexicon.t("map.moonLit", ["pct": "\(lit)"])
                    + (moonArc.map { lexicon.t("map.moonSetsAt", ["t": clock.fmt($0.set)]) } ?? "")
        } else if let arc = moonArc {
            moonText = lexicon.t("map.moonBelow", ["t": clock.fmt(arc.rise)])
        } else {
            moonText = lexicon.t("map.moonNoRise")
        }
        rows.append(Row(label: "map.moon", text: moonText, tone: .ink))

        // «В тени» ночью — не ответ: в тени ночью всё.
        if e > -4 {
            rows.append(Row(label: "map.spot", text: lexicon.t(e > 0 ? "map.spotLit" : "map.spotShade"),
                            tone: e > 0 ? .warm : .shade))
        }

        if let nx = nextEvent(sun: sun, t: t, lexicon: lexicon) {
            rows.append(Row(label: "map.next",
                            text: lexicon.t("map.nextIn", ["name": nx.name, "gap": gap(nx.minute - t, lexicon: lexicon)]),
                            tone: nx.warm ? .warm : .ink2))
        }

        if pro, let twi = twilight(sun: sun, t: t, lexicon: lexicon, clock: clock) {
            rows.append(Row(label: "map.twilight", text: twi, tone: .ink))
        }

        let viewDate = date.adding(days: Int((t / 1440).rounded(.down)))
        if let ecl = EclipseTable.on(viewDate) {
            rows.append(Row(label: "map.eclipse",
                            text: lexicon.t("ecl.line", ["kind": lexicon.t(ecl.kind.rawValue), "where": lexicon.t(ecl.whereKey)]),
                            tone: .terra))
        }

        if let mw {
            let mwRows = MapMilkyWayRows.build(sun: sun, window: mw.window, moon: mw.moon, glow: glow, sky: mw.sky,
                                               nextDark: mw.nextDark, dateShort: dateShort, lexicon: lexicon, clock: clock)
            rows += mwRows.rows.map { Row(label: $0.label, text: $0.text, tone: tone($0.tone)) }
        }

        // «Подробно».
        func g(_ icon: String, _ title: String, _ items: [(String, String)]) -> LightTelemetry.ProGroup {
            LightTelemetry.ProGroup(iconName: icon, title: lexicon.t(title),
                                    rows: items.map { LightTelemetry.ProRow(label: lexicon.t($0.0), value: $0.1) })
        }
        func azAtOpt(_ m: Minutes?) -> Degrees? { m.map { sun.azimuth(at: $0) } }
        let riseAz = azAtOpt(sun.rise), setAz = azAtOpt(sun.set)
        var pro: [LightTelemetry.ProGroup] = [
            g("sun", "pro.sunNow", [
                ("pro.azimuth", azDir(az)),
                ("pro.altitude", signed(e)),
                ("pro.shadowLen", sh.flatMap { $0 != 0 ? $0 : nil }.map {
                    lexicon.t("pro.shadowOf", ["n": String(format: $0 < 10 ? "%.2f" : "%.1f", $0)]) } ?? "—"),
                ("mpro.shadowFalls", azDir((az + 180).truncatingRemainder(dividingBy: 360))),
            ]),
            g("compass", "mpro.dayAzimuths", [
                ("pro.rise", riseAz.map(azDir) ?? "—"),
                ("pro.sunset", setAz.map(azDir) ?? "—"),
                ("mpro.sector", riseAz.flatMap { r in setAz.map { String(format: "%.0f", abs($0 - r)) + "°" } } ?? "—"),
            ]),
            g("compass", "mpro.place", [
                ("mpro.lat", String(format: "%.4f", abs(place.latitude)) + "° " + (place.latitude >= 0 ? "N" : "S")),
                ("mpro.lon", String(format: "%.4f", abs(place.longitude)) + "° " + (place.longitude >= 0 ? "E" : "W")),
                ("mpro.tz", lexicon.t("mpro.tzGuess", ["off": (utcOffset >= 0 ? "+" : "") + jsNumber(utcOffset)])),
            ]),
        ]

        if let mw {
            let w = mw.window
            let core = MilkyWay.corePosition(date: date, minutes: t, place: place)
            let workLo = String(Int(MilkyWay.workLow)), workHi = String(Int(MilkyWay.workHigh))
            let verdict = w.best.altitude >= MilkyWay.workHigh ? "mpro.reaches"
                : w.best.altitude >= MilkyWay.workLow ? "mpro.barely" : "mpro.reachesNot"
            var items: [(String, String)] = [
                ("mpro.coreAz", azDir(core.azimuth)),
                ("mpro.coreAlt", signed(core.altitude)),
                ("mpro.maxDay", w.best.altitude < 0 ? lexicon.t("mpro.noRise")
                    : lexicon.t("mpro.altAt", ["alt": String(format: "%.1f", w.best.altitude), "t": clock.fmt(w.best.minute)])),
                ("mpro.workAlt", lexicon.t("mpro.workRange", ["lo": workLo, "hi": workHi, "verdict": lexicon.t(verdict)])),
                // Нет ночи — особое слово, как у `proHTML` веба.
                ("pro.astroNight", w.dark && sun.astroB != nil && sun.astroA != nil
                    ? clock.range(sun.astroB, sun.astroA! + 1440) : lexicon.t("pro.whiteNight")),
                ("mpro.moonNow", moonNow.altitude > 0
                    ? lexicon.t("mpro.moonUp", ["alt": String(format: "%.0f", moonNow.altitude), "pct": "\(lit)"])
                    : lexicon.t("mpro.moonDown")),
                ("mpro.window", w.from != nil ? clock.range(w.from, w.to)
                    : (w.dark && w.moonBlocks ? lexicon.t("mpro.windowMoon") : "—")),
            ]
            if let sky = mw.sky { items.append(("mpro.skyHum", "\(sky.humidity)%")) }
            if let glow {
                let ratio = glow < 10 ? String(format: "%.2f", glow) : String(Int((glow + 0.5).rounded(.down)))
                items.append(("mpro.glow", lexicon.t("mpro.glowVal",
                                                     ["ratio": ratio, "mag": String(format: "%.1f", Glow.magnitude(glow))])))
            }
            pro.append(g("stars", "mpro.mw", items))
        }

        // Ближайшее затмение — последний пункт.
        if let ecl = EclipseTable.next(from: date) {
            let days = ecl.date.ordinal - date.ordinal
            let when = days == 0 ? lexicon.t("mpro.eclToday")
                : lexicon.t("mpro.eclIn", ["date": dateShort(ecl.date), "year": String(ecl.date.year),
                                           "days": lexicon.count("unit.day", days)])
            pro.append(g("sun", "mpro.nextEcl", [
                ("mpro.when", when),
                ("mpro.kind", lexicon.t(ecl.kind.rawValue)),
                ("mpro.whereSeen", lexicon.t(ecl.whereKey)),
            ]))
        }

        return MapSummary(rows: rows, pro: pro)
    }

    // MARK: - Помощники (`nextLightEvent`, `gapLabel`, `twilightLabel`)

    struct Event { let minute: Minutes; let name: String; let warm: Bool }

    /// Ближайшее событие света. Прошедшее сегодня повторится завтра в то же
    /// время — за полночью именно оно и есть ближайшее.
    static func nextEvent(sun: SolarDay, t: Minutes, lexicon: Lexicon) -> Event? {
        let ev: [(Minutes?, String, Bool)] = [
            (sun.astroA, "ev.dawn", false), (sun.blueA, "ev.blue", false),
            (sun.rise, "ev.rise", true), (sun.goldenA, "ev.day", false),
            (sun.goldenB, "ev.golden", true), (sun.set, "ev.sunset", true),
            (sun.blueB, "ev.blue", false), (sun.astroB, "ev.dark", false),
        ]
        var best: Event?
        for (m0, key, warm) in ev {
            guard let m0 else { continue }
            let m = m0 > t ? m0 : m0 + 1440
            if best == nil || m < best!.minute { best = Event(minute: m, name: lexicon.t(key), warm: warm) }
        }
        return best
    }

    /// «через 4:12» для часов, «18 мин» в пределах часа.
    static func gap(_ d0: Minutes, lexicon: Lexicon) -> String {
        let d = max(0, Int((d0 + 0.5).rounded(.down)))
        if d < 60 { return lexicon.t("gap.minutes", ["m": "\(d)"]) }
        return "\(d / 60):" + (d % 60 < 10 ? "0" : "") + "\(d % 60)"
    }

    /// Какая ступень сумерек идёт и до которого часа; днём и глубокой ночью — `nil`.
    static func twilight(sun: SolarDay, t: Minutes, lexicon: Lexicon, clock: ClockText) -> String? {
        let e = sun.elevation(at: t)
        if e > -0.833 || e < -18 { return nil }
        let step: (String, Minutes?, Minutes?) = e > -6 ? (lexicon.t("twi.civil"), sun.civilB, sun.civilA)
            : e > -12 ? (lexicon.t("twi.nautical"), sun.nauticalB, sun.nauticalA)
            : (lexicon.t("twi.astro"), sun.astroB, sun.astroA)
        // Вечером — до нижней границы, утром — до верхней.
        guard let edge = t > sun.solarNoon ? step.1 : step.2 else { return step.0 }
        let to = edge > t ? edge : edge + 1440
        return lexicon.t("twi.till", ["step": step.0, "t": clock.fmt(edge.truncatingRemainder(dividingBy: 1440)),
                                      "gap": gap(to - t, lexicon: lexicon)])
    }

    /// Число, как его печатает JS: целое без дробной части.
    static func jsNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    private static func tone(_ t: MapMilkyWayRows.Tone) -> Tone {
        switch t {
        case .ink2: .ink2
        case .ink4: .ink4
        case .terra: .terra
        case .violet: .violet
        }
    }
}
