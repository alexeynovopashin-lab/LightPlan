import Testing
import Foundation
import LightPlanCore
@testable import LightPlanUI

/// 30г.4: переключатель «Термины» (`docs/30g2_modes_table.md` § 2, ответ 6 Алексея). Без терминов купол говорит
/// «Глубокие сумерки» и «Ночь», группы «Сумерки» в «Подробно» «Света» нет, на «Карте» нет ступени сумерек и строки
/// «Астрономическая ночь». Под `swift test` словарь отдаёт ключи — сравнения через `lexicon.t` верны и там.
struct TermsSwitchTests {
    let lexicon = Lexicon("ru")
    let clock = ClockText(language: "ru", preference: .h24)

    /// Барнаул, самая длинная ночь: есть и астрономические сумерки, и астрономическая ночь.
    let sun = SolarDay(date: CivilDate(year: 2026, month: 12, day: 21), latitude: 53.3481, longitude: 83.7798, utcOffsetHours: 7)

    private func light(_ t: Minutes, terms: Bool) -> LightTelemetry {
        LightTelemetry.build(sun: sun, t: t, moon: false, moonSnapshot: nil, weather: nil, weatherStatus: .loading, air: nil,
                             headerLocationName: "Барнаул", headerDateLabel: "", headerNote: "",
                             lexicon: lexicon, clock: clock, terms: terms)
    }

    /// Без терминов меняются ровно три слова из пятнадцати: астрономические сумерки утром и вечером и астрономическая ночь.
    @Test func onlyAstronomicalPhasesChangeTheirWord() {
        for code in LightCode.allCases {
            #expect(LightTelemetry.phaseKey(code, terms: true) == "sun.\(code.rawValue).label")
            let plain = LightTelemetry.phaseKey(code, terms: false)
            switch code {
            case .astroDawn, .astroDusk: #expect(plain == "sun.deepDusk.label")
            case .astroNight: #expect(plain == "sun.night.label")
            default: #expect(plain == "sun.\(code.rawValue).label", "\(code)")
            }
        }
    }

    @Test func domeWordAndTwilightGroupFollowTheSwitch() throws {
        let dusk = (try #require(sun.nauticalB) + (try #require(sun.astroB))) / 2
        let dawn = (try #require(sun.astroA) + (try #require(sun.nauticalA))) / 2
        let night = sun.mint + 60
        let cases: [(Minutes, LightCode, String)] = [(dusk, .astroDusk, "sun.deepDusk.label"),
                                                     (dawn, .astroDawn, "sun.deepDusk.label"),
                                                     (night, .astroNight, "sun.night.label")]
        for (t, code, plain) in cases {
            #expect(sun.state(at: t).code == code)
            #expect(light(t, terms: true).readout?.phase == lexicon.t("sun.\(code.rawValue).label"))
            #expect(light(t, terms: false).readout?.phase == lexicon.t(plain))
        }
        let twilight = lexicon.t("pro.twilight")
        #expect(light(dusk, terms: true).proGroups.contains { $0.title == twilight })
        #expect(!light(dusk, terms: false).proGroups.contains { $0.title == twilight })
        // Прочие группы «Подробно» те же.
        #expect(light(dusk, terms: false).proGroups == light(dusk, terms: true).proGroups.filter { $0.title != twilight })
    }

    @Test func mapLosesTwilightStepAndAstroNightRow() throws {
        let place = Place(latitude: 55.75, longitude: 37.62, zone: ZoneID(fixedOffsetHours: 3))
        let date = CivilDate(year: 2026, month: 9, day: 23)
        let day = SolarDay(date: date, place: place)
        func map(_ t: Minutes, terms: Bool) -> MapSummary {
            MapSummary.build(date: date, t: t, sun: day, place: place, utcOffset: 3, pro: true, terms: terms, glow: nil,
                             mw: MapSummary.MilkyWayInput(window: MilkyWayWindow(date: date, place: place),
                                                          moon: MoonVsStars(date: date, place: place), sky: nil, nextDark: { nil }),
                             dateShort: { "\($0.day).\($0.month)" }, lexicon: lexicon, clock: clock)
        }
        let mid = (try #require(day.nauticalB) + (try #require(day.astroB))) / 2
        let on = map(mid, terms: true), off = map(mid, terms: false)
        #expect(on.rows.contains { $0.label == "map.twilight" })
        #expect(off.rows.filter { $0.label != "map.twilight" } == off.rows)
        #expect(off.rows == on.rows.filter { $0.label != "map.twilight" })
        let mw = lexicon.t("mpro.mw"), astroNight = lexicon.t("pro.astroNight")
        let groupOn = try #require(on.pro.first { $0.title == mw })
        let groupOff = try #require(off.pro.first { $0.title == mw })
        #expect(groupOn.rows.map(\.label).filter { $0 != astroNight } == groupOff.rows.map(\.label))
        #expect(groupOn.rows.contains { $0.label == astroNight })
        #expect(!groupOff.rows.contains { $0.label == astroNight })
    }

    /// Слова на шести языках: «Ночь» новое, «Глубокие сумерки» — слово веба у навигационных сумерек.
    @Test(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
    func wordsInSixLanguages() {
        let night = ["ru": "Ночь", "en": "Night", "en-US": "Night", "es": "Noche", "ja": "夜", "zh": "夜晚"]
        let deep = ["ru": "Глубокие сумерки", "en": "Deep dusk", "en-US": "Deep dusk", "es": "Crepúsculo profundo",
                    "ja": "深い薄暮", "zh": "深黄昏"]
        let terms = ["ru": "Термины", "en": "Terms", "en-US": "Terms", "es": "Términos", "ja": "用語", "zh": "术语"]
        for (code, word) in night {
            let t = Lexicon(code)
            #expect(t.t("sun.night.label") == word, "\(code)")
            #expect(t.t("sun.deepDusk.label") == deep[code], "\(code)")
            #expect(t.t("set.astro.terms") == terms[code], "\(code)")
            #expect(t.t("sun.astroNight.label") != word, "\(code): термин остаётся термином")
            for sw in ["moon", "stars", "azimuths", "milkyWay", "waiting"] {
                #expect(t.t("set.astro." + sw) != "set.astro." + sw, "\(code) \(sw)")
            }
        }
    }
}
