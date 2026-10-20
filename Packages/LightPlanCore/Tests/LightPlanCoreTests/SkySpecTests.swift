import Testing
import Foundation
import LightPlanCore

/// Шаг 29.8в.18: слои неба рисуются всегда, видимость — справка (`SkyEyeNote`); затемняющая маска над кадром камеры (`SkyMask`).
struct SkySpecTests {

    // MARK: - Маска

    @Test("темнота неба: ноль при −6° и выше, единица при −18° и ниже, между — гладкая ступень, ровно половина на −12°")
    func darknessEdges() {
        #expect(SkyMask.darkness(sunAltitude: 60) == 0)
        #expect(SkyMask.darkness(sunAltitude: 0) == 0)
        #expect(SkyMask.darkness(sunAltitude: -5.99) < 1e-5, "гладко от нуля, без скачка")
        #expect(SkyMask.darkness(sunAltitude: -6) == 0)
        #expect(abs(SkyMask.darkness(sunAltitude: -12) - 0.5) < 1e-12)
        #expect(SkyMask.darkness(sunAltitude: -18) == 1)
        #expect(SkyMask.darkness(sunAltitude: -40) == 1)
        var last = 0.0
        for tenth in stride(from: -60, through: -180, by: -1) {
            let d = SkyMask.darkness(sunAltitude: Double(tenth) / 10)
            #expect(d >= last, "темнота упала на \(Double(tenth) / 10)°"); last = d
        }
        // Без излома на краях: шаг 0,1° у границ меньше 0,01.
        #expect(SkyMask.darkness(sunAltitude: -6.1) < 0.01 && 1 - SkyMask.darkness(sunAltitude: -17.9) < 0.01)
    }

    @Test("сила маски: день и день — 0; выбрана ночь при светлом небе — 1; настоящая ночь гасит маску; сумерки — между")
    func strengthCases() {
        // Днём в ползунке и днём в жизни: маски нет.
        #expect(SkyMask.strength(pickedSun: 40, nowSun: 35) == 0)
        // Выбрана глубокая ночь, настоящее небо — день: полная сила.
        #expect(SkyMask.strength(pickedSun: -30, nowSun: 35) == 1)
        #expect(SkyMask.strength(pickedSun: -18, nowSun: 0) == 1)
        // Настоящая ночь: маска не появляется, что бы ни выбрали.
        #expect(SkyMask.strength(pickedSun: -30, nowSun: -30) == 0)
        #expect(SkyMask.strength(pickedSun: -18, nowSun: -18) == 0)
        #expect(SkyMask.strength(pickedSun: 20, nowSun: -30) == 0)
        // Края порогов: выбранное −6° ещё день для маски, −18° — полная глубина; настоящее −6° — небо светлое, −18° — тёмное.
        #expect(SkyMask.strength(pickedSun: -6, nowSun: 35) == 0)
        #expect(SkyMask.strength(pickedSun: -18, nowSun: -6) == 1)
        #expect(SkyMask.strength(pickedSun: -30, nowSun: -18) == 0)
        // Сумерки: произведение двух гладких ступеней — на −12° в обоих местах 0,5 × 0,5.
        #expect(abs(SkyMask.strength(pickedSun: -12, nowSun: 35) - 0.5) < 1e-12)
        #expect(abs(SkyMask.strength(pickedSun: -30, nowSun: -12) - 0.5) < 1e-12)
        #expect(abs(SkyMask.strength(pickedSun: -12, nowSun: -12) - 0.25) < 1e-12)
    }

    @Test("непрозрачность маски — сила × потолок; потолок оставляет кадру заметную долю яркости, чтобы контуры зданий читались")
    func opacityCeiling() {
        #expect(SkyMask.opacity(pickedSun: -30, nowSun: 35) == SkyMask.maxOpacity)
        #expect(SkyMask.opacity(pickedSun: 30, nowSun: 35) == 0)
        #expect(abs(SkyMask.opacity(pickedSun: -12, nowSun: 35) - 0.5 * SkyMask.maxOpacity) < 1e-12)
        // Не до чёрного: слева остаётся от четверти до трети яркости кадра (слова Алексея: контуры зданий угадываются).
        let left = 1 - SkyMask.maxOpacity
        #expect(left >= 0.25 && left <= 0.40, "остаётся \(left)")
        for picked in stride(from: -40.0, through: 60.0, by: 2.5) {
            for now in stride(from: -40.0, through: 60.0, by: 2.5) {
                let a = SkyMask.opacity(pickedSun: picked, nowSun: now)
                #expect(a >= 0 && a <= SkyMask.maxOpacity)
            }
        }
    }

    // MARK: - Справка о видимости

    @Test("справка: день — одна причина с высотой солнца; сумерки — «сумерки»; глубокая ночь на тёмном небе — пусто")
    func noteBySun() {
        #expect(SkyEyeNote.causes(sunAltitude: 35, glow: nil) == [.daylight(sun: 35)])
        #expect(SkyEyeNote.causes(sunAltitude: 60, glow: 0.2) == [.daylight(sun: 60)])
        #expect(SkyEyeNote.causes(sunAltitude: -6, glow: nil) == [.daylight(sun: -6)])
        #expect(SkyEyeNote.causes(sunAltitude: -6.1, glow: nil) == [.twilight(sun: -6.1)])
        #expect(SkyEyeNote.causes(sunAltitude: -17.9, glow: nil) == [.twilight(sun: -17.9)])
        #expect(SkyEyeNote.causes(sunAltitude: -18, glow: nil).isEmpty)
        #expect(SkyEyeNote.causes(sunAltitude: -30, glow: 0.4).isEmpty, "тёмное небо — ничто не мешает")
    }

    @Test("справка: засветка атласа — ступень и число; тёмное небо и молчащий атлас причины не дают")
    func noteByGlow() {
        #expect(SkyEyeNote.causes(sunAltitude: -30, glow: 4) == [.glow(.faint, value: 4)])
        #expect(SkyEyeNote.causes(sunAltitude: -30, glow: 12) == [.glow(.city, value: 12)])
        #expect(SkyEyeNote.causes(sunAltitude: -30, glow: 40) == [.glow(.none, value: 40)])
        #expect(SkyEyeNote.causes(sunAltitude: -30, glow: nil).isEmpty)
        // Сумерки и засветка вместе: обе причины, сумерки первыми.
        #expect(SkyEyeNote.causes(sunAltitude: -10, glow: 12) == [.twilight(sun: -10), .glow(.city, value: 12)])
        // Днём засветка не пишется: одной причины «день» хватает.
        #expect(SkyEyeNote.causes(sunAltitude: 10, glow: 40) == [.daylight(sun: 10)])
    }
}
