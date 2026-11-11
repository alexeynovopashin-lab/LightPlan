import Testing
@testable import LightPlanData

/// 30г.9: что режим показывает вне настроек — опись 30г.2, столбец «Просто», ответы Алексея 05.11 (2 и 3).
struct ModeLookTests {

    /// Вся таблица по трём режимам: строка описи → есть ли в режиме.
    @Test(arguments: AppMode.allCases)
    func everyRowInEveryMode(_ mode: AppMode) {
        let l = ModeLook(mode)
        let full = mode != .simple
        #expect(l.domeSky, "№ 55: цветное небо во всех режимах (ответ 3)")
        #expect(l.dayRibbon == full, "№ 68, 87: ленты суток в «Просто» нет (ответ 3)")
        #expect(l.mapLayersMenu == full, "№ 71: меню слоёв")
        #expect(l.cardTuning == full, "№ 131–134: «Настроить карточку»")
        #expect(l.myGenres == full, "№ 150–151: «Мои жанры»")
        #expect(l.binAutoClean == full, "№ 179: «Самоочистка»")
    }

    /// Ответ 2, исключение: без меню солнце, компас и «Мои места» горят всегда; луна и Млечный Путь — дело переключателей.
    @Test func simpleKeepsSunCompassAndSpotsOn() {
        #expect(ModeLook(.simple).alwaysOnMapLayers == ["sun", "compass", "spots"])
        #expect(ModeLook(.pro).alwaysOnMapLayers.isEmpty)
        #expect(ModeLook(.astro).alwaysOnMapLayers.isEmpty)
    }

    /// Правило читается из настроек и меняется вместе с режимом.
    @Test func settingsAnswerForTheirMode() {
        var s = AppSettings()
        #expect(s.mode == .simple)
        #expect(s.look == ModeLook(.simple))
        s.mode = .pro
        #expect(s.look == ModeLook(.pro))
        s.mode = .astro
        #expect(s.look.mapLayersMenu)
    }
}
