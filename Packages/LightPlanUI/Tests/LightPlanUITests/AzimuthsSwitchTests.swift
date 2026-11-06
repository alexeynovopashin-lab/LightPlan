import CoreGraphics
import Foundation
import Testing
import LightPlanCore
@testable import LightPlanUI

/// 30г.5: переключатель «Азимуты» (`docs/30g2_modes_table.md` № 66, 89, 90, 91, 95, 102, 107, 108 и § 2 «Азимуты»). Градусы
/// направления и высоты солнца, луны и ядра видны только в «Астро» с «Азимутами»; время, длина тени, сторона света буквами
/// и стрелка к светилу остаются. Под `swift test` словарь отдаёт ключи — сравнения через `lexicon.t` верны и там.
struct AzimuthsSwitchTests {
    let lexicon = Lexicon("ru")
    let clock = ClockText(language: "ru", preference: .h24)

    /// Барнаул, равноденствие: восход, полдень и закат есть, солнце в полдень высоко.
    let date = CivilDate(year: 2026, month: 9, day: 23)
    let place = Place(latitude: 53.3481, longitude: 83.7798, zone: ZoneID(fixedOffsetHours: 7))
    var sun: SolarDay { SolarDay(date: date, place: place) }

    // MARK: - «Свет» → «Подробно» (№ 66, § 2: луна)

    private func light(_ t: Minutes, azimuths: Bool, moon: MoonSnapshot? = nil) -> LightTelemetry {
        LightTelemetry.build(sun: sun, t: t, moon: moon != nil, moonSnapshot: moon, weather: nil, weatherStatus: .loading, air: nil,
                             headerLocationName: "Барнаул", headerDateLabel: "", headerNote: "",
                             lexicon: lexicon, clock: clock, azimuths: azimuths)
    }

    private func group(_ g: [LightTelemetry.ProGroup], _ key: String) throws -> LightTelemetry.ProGroup {
        try #require(g.first { $0.title == lexicon.t(key) }, "\(key)")
    }

    /// «Солнце в этот момент»: без «Азимутов» остаётся одна длина тени — та же строка, что и с ними.
    @Test func lightSunNowKeepsOnlyShadowLength() throws {
        let t = sun.solarNoon - 120
        let on = try group(light(t, azimuths: true).proGroups, "pro.sunNow")
        let off = try group(light(t, azimuths: false).proGroups, "pro.sunNow")
        #expect(on.rows.map(\.label) == ["pro.azimuth", "pro.altitude", "pro.shadowLen"].map { lexicon.t($0) })
        #expect(off.rows == [on.rows[2]])
    }

    /// «Ход дня»: у восхода, полудня и заката только время, длина дня та же.
    @Test func lightDayCourseKeepsTimeWithoutDegrees() throws {
        let t = sun.solarNoon
        let on = try group(light(t, azimuths: true).proGroups, "pro.dayCourse")
        let off = try group(light(t, azimuths: false).proGroups, "pro.dayCourse")
        let rise = try #require(sun.rise), set = try #require(sun.set)
        #expect(off.rows.map(\.value) == [clock.fmt(rise), clock.fmt(sun.solarNoon), clock.fmt(set), on.rows[3].value])
        #expect(on.rows.prefix(3).allSatisfy { $0.value.hasSuffix("°") })
        #expect(off.rows.map(\.label) == on.rows.map(\.label))
    }

    /// «Луна в этот момент» (сама группа — «Луна», 30г.6): без «Азимутов» нет строк азимута и высоты, у восхода и захода нет градусов.
    @Test func lightMoonLosesAzimuthAltitudeAndRiseDegrees() throws {
        let t = sun.solarNoon
        let mo = MoonSnapshot(phase: MoonPhase(date: date, minutes: t, utcOffsetHours: 7), azimuth: 120, altitude: 20,
                              distance: 384_000, arc: MoonArc(rise: 600, set: 1300), riseAzimuth: 95, setAzimuth: 265)
        let on = try group(light(t, azimuths: true, moon: mo).proGroups, "pro.moonNow")
        let off = try group(light(t, azimuths: false, moon: mo).proGroups, "pro.moonNow")
        let azimuth = lexicon.t("pro.azimuth"), altitude = lexicon.t("pro.altitude")
        #expect(on.rows.contains { $0.label == azimuth } && on.rows.contains { $0.label == altitude })
        #expect(off.rows.map(\.label) == on.rows.map(\.label).filter { $0 != azimuth && $0 != altitude })
        #expect(off.rows.first { $0.label == lexicon.t("pro.rise") }?.value == clock.fmt(600))
        #expect(off.rows.first { $0.label == lexicon.t("pro.set") }?.value == clock.fmt(1300))
        #expect(on.rows.first { $0.label == lexicon.t("pro.rise") }?.value == clock.fmt(600) + " · 95°")
    }

    /// Прочие группы «Подробно» «Света» не меняются.
    @Test func lightOtherGroupsUntouched() {
        let t = sun.solarNoon
        let touched: Set<String> = ["pro.sunNow", "pro.dayCourse"].map { lexicon.t($0) }.reduce(into: []) { $0.insert($1) }
        let on = light(t, azimuths: true).proGroups.filter { !touched.contains($0.title) }
        let off = light(t, azimuths: false).proGroups.filter { !touched.contains($0.title) }
        #expect(on == off)
        #expect(light(t, azimuths: false).proGroups.map(\.title) == light(t, azimuths: true).proGroups.map(\.title))
    }

    // MARK: - «Карта» → свод и «Подробно» (№ 91, 95, § 2: ядро)

    private func map(_ t: Minutes, azimuths: Bool, pro: Bool = true, mw: Bool = true) -> MapSummary {
        MapSummary.build(date: date, t: t, sun: sun, place: place, utcOffset: 7, pro: pro, azimuths: azimuths, glow: nil,
                         mw: mw ? MapSummary.MilkyWayInput(window: MilkyWayWindow(date: date, place: place),
                                                           moon: MoonVsStars(date: date, place: place), sky: nil,
                                                           nextDark: { nil }) : nil,
                         dateShort: { "\($0.day).\($0.month)" }, lexicon: lexicon, clock: clock)
    }

    /// Свод: «Свет идёт с …», «Высота солнца», «Тень» есть только с «Азимутами»; «Золотой» и «Синий час» (№ 197) остаются.
    @Test func mapFoldLosesLightFromElevationAndShadow() {
        let t = sun.solarNoon - 180
        let on = map(t, azimuths: true), off = map(t, azimuths: false)
        let degreeRows: Set<String> = ["map.lightFrom", "map.sunElev", "map.shadow"]
        #expect(degreeRows.allSatisfy { k in on.rows.contains { $0.label == k } })
        #expect(!off.rows.contains { degreeRows.contains($0.label) })
        #expect(off.rows.map(\.label) == on.rows.map(\.label).filter { !degreeRows.contains($0) })
        for k in ["map.golden", "map.blue"] {
            #expect(off.rows.first { $0.label == k } == on.rows.first { $0.label == k }, "\(k)")
        }
    }

    /// Свод, строка «Луна»: направление и высота — только с «Азимутами»; без них — как в «Просто».
    @Test func mapMoonRowLosesDirectionAndAltitude() throws {
        // Минута, когда луна над горизонтом.
        let up = try #require(stride(from: 0.0, to: 1440, by: 30).first {
            MoonSample(date: date, minutes: $0, place: place).altitude > 5 })
        let on = try #require(map(up, azimuths: true).rows.first { $0.label == "map.moon" })
        let off = try #require(map(up, azimuths: false).rows.first { $0.label == "map.moon" })
        let simple = try #require(map(up, azimuths: true, pro: false).rows.first { $0.label == "map.moon" })
        #expect(on.text.contains("°"))
        #expect(off == simple)
        #expect(!off.text.contains("°"))
    }

    /// «Подробно»: от «Солнца в этот момент» — длина тени, «Азимутов дня» нет, у ядра нет азимута и высоты.
    @Test func mapDetailsLoseSunAzimuthsAndCoreDegrees() throws {
        let t = sun.solarNoon - 180
        let on = map(t, azimuths: true).pro, off = map(t, azimuths: false).pro
        let sunOn = try #require(on.first { $0.title == lexicon.t("pro.sunNow") })
        let sunOff = try #require(off.first { $0.title == lexicon.t("pro.sunNow") })
        #expect(sunOn.rows.count == 4)
        #expect(sunOff.rows == sunOn.rows.filter { $0.label == lexicon.t("pro.shadowLen") })
        #expect(on.contains { $0.title == lexicon.t("mpro.dayAzimuths") })
        #expect(!off.contains { $0.title == lexicon.t("mpro.dayAzimuths") })
        let mwOn = try #require(on.first { $0.title == lexicon.t("mpro.mw") })
        let mwOff = try #require(off.first { $0.title == lexicon.t("mpro.mw") })
        let core: Set<String> = [lexicon.t("mpro.coreAz"), lexicon.t("mpro.coreAlt")]
        #expect(core.allSatisfy { c in mwOn.rows.contains { $0.label == c } })
        #expect(mwOff.rows == mwOn.rows.filter { !core.contains($0.label) })
        // «Место» (координаты) остаётся.
        #expect(off.first { $0.title == lexicon.t("mpro.place") } == on.first { $0.title == lexicon.t("mpro.place") })
    }

    // MARK: - «Карта» → прибор (№ 89, 90)

    private func scene(azimuths: Bool, chip: MapInstrument.Chip?) -> MapInstrument.Scene {
        var layers = MapLayers()
        layers.moon = true
        let input = MapInstrument.Input(date: date, minute: sun.solarNoon - 120, solar: sun, place: place, layers: layers,
                                        pro: true, azimuths: azimuths, lightTheme: false, chip: chip,
                                        clock: { clock.fmt($0) }, cardinals: ["С", "В", "Ю", "З"])
        return MapInstrument.scene(input, day: MapInstrument.Day(date: date, place: place, solar: sun))
    }

    private func ringNumbers(_ s: MapInstrument.Scene) -> [String] {
        // Часы на дуге солнца («06», «09», «15»…) — не градусы: кольцо пишет кратные 30 без ведущего нуля.
        s.elements.compactMap {
            if case .text(let str, _, _, _, _, _, _, _) = $0, let n = Int(str), n % 30 == 0, !str.hasPrefix("0") { return str }
            return nil
        }
    }

    private func chips(_ s: MapInstrument.Scene) -> [String] {
        s.elements.compactMap { if case .chip(let str, _, _, _, _, _) = $0 { return str } else { return nil } }
    }

    /// Кольцо: восемь чисел 30°…330° только с «Азимутами».
    @Test func compassRingNumbersOnlyWithAzimuths() {
        #expect(ringNumbers(scene(azimuths: true, chip: nil)) == ["30", "60", "120", "150", "210", "240", "300", "330"])
        #expect(ringNumbers(scene(azimuths: false, chip: nil)).isEmpty)
    }

    /// Тап по солнцу или луне и движение ползунка: чипа «азимут° +высота°» без «Азимутов» нет.
    @Test func bodyChipsOnlyWithAzimuths() {
        for chip in [MapInstrument.Chip.tapSun(az: 135, alt: 20), .tapMoon(az: 200, alt: 10), .drag] {
            #expect(!chips(scene(azimuths: true, chip: chip)).isEmpty, "\(chip)")
            #expect(chips(scene(azimuths: false, chip: chip)).isEmpty, "\(chip)")
        }
        #expect(chips(scene(azimuths: true, chip: .tapSun(az: 135, alt: 20))) == ["135°  +20°"])
    }

    // MARK: - AR (№ 102, 107, 108, § 2: ядро)

    @Test func arDegreesOnlyWithAzimuths() {
        #expect(SunARDegrees.pointer(azimuth: 359.7, altitude: -4.6, shown: true) == "0° · -5°")
        #expect(SunARDegrees.pointer(azimuth: 120, altitude: 12, shown: false) == "")
        #expect(SunARDegrees.heading(359.6, shown: true) == "0°")
        #expect(SunARDegrees.heading(42, shown: false) == nil)
        #expect(SunARDegrees.sunPosition(azimuth: 181.2, altitude: 22.4, shown: true, lexicon: lexicon)
                == "\(lexicon.t("pro.azimuth")) 181° · \(lexicon.t("pro.altitude")) +22°")
        #expect(SunARDegrees.sunPosition(azimuth: 181.2, altitude: 22.4, shown: false, lexicon: lexicon) == nil)
        #expect(SunARDegrees.coreEvent(rise: true, time: "22:40", azimuth: 195.4, shown: true, lexicon: lexicon)
                == lexicon.t("ar.coreRises", ["t": "22:40", "a": "195"]))
        #expect(SunARDegrees.coreEvent(rise: false, time: "04:10", azimuth: 262, shown: true, lexicon: lexicon)
                == lexicon.t("ar.coreSets", ["t": "04:10", "a": "262"]))
        #expect(SunARDegrees.coreEvent(rise: true, time: "22:40", azimuth: 195.4, shown: false, lexicon: lexicon)
                == lexicon.t("ar.coreRisesAt", ["t": "22:40"]))
        #expect(SunARDegrees.coreEvent(rise: false, time: "04:10", azimuth: 262, shown: false, lexicon: lexicon)
                == lexicon.t("ar.coreSetsAt", ["t": "04:10"]))
    }

    /// Стрелка без подписи держит место только под кружок — соседняя стрелка не отодвигается ради пустой плашки.
    @Test func arPointerWithoutLabelOccupiesOnlyTheCircle() {
        let screen = CGSize(width: 440, height: 956)
        let p = CGPoint(x: 30, y: 400)
        let bare = SunARPointerLayout.occupied(center: p, text: "", screen: screen, flipY: 800)
        let d = SunARInk.pointerDiameter
        #expect(bare == [CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)])
        #expect(SunARPointerLayout.occupied(center: p, text: "120° · +12°", screen: screen, flipY: 800).count == 2)
    }

    // MARK: - Слова на шести языках

    @Test(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
    func coreWordsWithoutDegreesInSixLanguages() {
        let waiting = ["ru": "Азимуты", "en": "Azimuths", "en-US": "Azimuths", "es": "Azimuts", "ja": "方位角", "zh": "方位角"]
        for (code, azimuths) in waiting {
            let t = Lexicon(code)
            for k in ["ar.coreRisesAt", "ar.coreSetsAt"] {
                let w = t.t(k, ["t": "22:40"])
                #expect(w != k && w.contains("22:40") && !w.contains("°"), "\(code) \(k): \(w)")
            }
            #expect(t.t("set.astro.waiting").contains(azimuths), "\(code)")
            #expect(t.t("set.astro.waiting").contains(t.t("set.astro.terms")), "\(code)")
        }
    }
}
