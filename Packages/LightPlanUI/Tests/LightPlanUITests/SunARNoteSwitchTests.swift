import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore

/// 30г.10, расхождение 2 сверки: справки AR под слоями («Звёзды», «Созвездия», «Планеты», «Млечный Путь») читают
/// переключатели. Без «Азимутов» — без градусов высоты солнца; без «Терминов» — вместо «сумерки» слово купола «Просто»/«Про»;
/// без «Луны» справка о луне в строке Млечного Пути остаётся: там луна — причина невидимости (решение 11.11).
struct SunARNoteSwitchTests {

    private let languages = ["ru", "en", "en-US", "es", "ja", "zh"]
    private let noAzimuths = SunARNoteLook(azimuths: false, terms: true)
    private let noTerms = SunARNoteLook(azimuths: true, terms: false)
    private let neither = SunARNoteLook(azimuths: false, terms: false)

    private func hasDigit(_ s: String) -> Bool { s.contains { $0.isNumber } }

    private func milkyWay(sun: Double, moon: Double = -10, fraction: Double = 0, glow: Double? = nil) -> MilkyWayLook.EyeNote {
        MilkyWayLook.eyeNote(sunAltitude: sun, moonAltitude: moon, moonFraction: fraction, glow: glow, coreAltitude: 30)
    }

    // MARK: «Азимуты»

    @Test("без «Азимутов» справки слоёв без градусов высоты солнца: «днём не видно», «сумерки» — на шести языках")
    func noAzimuthsDropsSunDegrees() {
        #expect(SunARSkyNotes.eyeLine([.daylight(sun: 24)], Lexicon("ru"), look: noAzimuths) == "днём не видно")
        #expect(SunARSkyNotes.eyeLine([.twilight(sun: -7)], Lexicon("ru"), look: noAzimuths) == "сумерки")
        #expect(SunARSkyNotes.eyeLine([.twilight(sun: -7), .glow(.city, value: 12)], Lexicon("ru"), look: noAzimuths)
                == "сумерки · город, засветка 12")
        #expect(SunARMilkyWayNotes.eyeLine(milkyWay(sun: 24), Lexicon("ru"), look: noAzimuths) == "днём не видно")
        for code in languages {
            let t = Lexicon(code)
            for look in [noAzimuths, neither] {
                let day = SunARSkyNotes.eyeLine([.daylight(sun: 24)], t, look: look)!
                let tw = SunARSkyNotes.eyeLine([.twilight(sun: -7)], t, look: look)!
                let mwDay = SunARMilkyWayNotes.eyeLine(milkyWay(sun: 24), t, look: look)
                for line in [day, tw, mwDay] {
                    #expect(!hasDigit(line) && !line.contains("°") && !line.contains("{"), "\(code): \(line)")
                }
                // Твилайт Млечного Пути: процент видимости остаётся, градуса солнца нет.
                let mw = SunARMilkyWayNotes.eyeLine(milkyWay(sun: -9), t, look: look)
                #expect(!mw.contains("−9") && !mw.contains("°") && !mw.contains("{"), "\(code): \(mw)")
            }
        }
    }

    @Test("с «Азимутами» и «Терминами» справки прежние: «днём не видно: солнце +24°», «сумерки, солнце −7°»")
    func fullLookKeepsOldLines() {
        let t = Lexicon("ru")
        #expect(SunARSkyNotes.eyeLine([.daylight(sun: 24)], t, look: .full) == "днём не видно: солнце +24°")
        #expect(SunARSkyNotes.eyeLine([.twilight(sun: -7)], t, look: .full) == "сумерки, солнце −7°")
        #expect(SunARSkyNotes.eyeLine([.twilight(sun: -7)], t) == SunARSkyNotes.eyeLine([.twilight(sun: -7)], t, look: .full))
    }

    // MARK: «Термины»

    @Test("без «Терминов» вместо «сумерки» слово купола «Просто»: «глубокие сумерки» и при −7°, и при −14° — на шести языках")
    func noTermsUsesDomeWord() {
        #expect(SunARSkyNotes.eyeLine([.twilight(sun: -7)], Lexicon("ru"), look: noTerms) == "глубокие сумерки, солнце −7°")
        #expect(SunARSkyNotes.eyeLine([.twilight(sun: -14)], Lexicon("ru"), look: noTerms) == "глубокие сумерки, солнце −14°")
        #expect(SunARSkyNotes.eyeLine([.twilight(sun: -14)], Lexicon("ru"), look: neither) == "глубокие сумерки")
        for code in languages {
            let t = Lexicon(code)
            for sun in [-6.5, -11.0, -13.0, -17.5] {
                for morning in [false, true] {
                    // Слово то же, что у купола без «Терминов» в эту минуту.
                    let key = LightTelemetry.phaseKey(LightState(elevation: sun, morning: morning).code, terms: false)
                    let dome = SunARNoteLook.lowerFirst(t.t(key))
                    var look = noTerms; look.morning = morning
                    let line = SunARSkyNotes.eyeLine([.twilight(sun: sun)], t, look: look)!
                    #expect(line.hasPrefix(dome) && !line.contains("{"), "\(code) \(sun): \(line)")
                    #expect(!line.contains(t.t("ar.mwEyeTwilightPlain")) || dome.contains(t.t("ar.mwEyeTwilightPlain")),
                            "\(code) \(sun): \(line)")
                    #expect(!line.lowercased().contains(t.t("sun.astroDusk.label").lowercased()), "\(code) \(sun): \(line)")
                    var both = neither; both.morning = morning
                    #expect(SunARSkyNotes.eyeLine([.twilight(sun: sun)], t, look: both) == dome, "\(code) \(sun)")
                }
            }
            let mw = SunARMilkyWayNotes.eyeLine(milkyWay(sun: -14), t, look: noTerms)
            #expect(mw.contains(SunARNoteLook.lowerFirst(t.t("sun.deepDusk.label"))), "\(code): \(mw)")
        }
    }

    // MARK: «Луна»

    @Test("справка Млечного Пути «Луна 62 % освещена» стоит при любых переключателях: луна здесь причина (решение 11.11)")
    func moonCauseStaysAtAnySwitch() {
        let note = milkyWay(sun: -30, moon: 30, fraction: 0.62)
        #expect(note.causes == [.moon(percent: 62)])
        for code in languages {
            let t = Lexicon(code)
            let full = SunARMilkyWayNotes.eyeLine(note, t, look: .full)
            #expect(full.contains("62"), "\(code): \(full)")
            for look in [noAzimuths, noTerms, neither] {
                #expect(SunARMilkyWayNotes.eyeLine(note, t, look: look) == full, "\(code)")
            }
        }
    }
}
