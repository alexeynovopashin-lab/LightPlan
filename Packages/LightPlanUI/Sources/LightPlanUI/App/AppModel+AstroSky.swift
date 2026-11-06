import LightPlanDomain
import LightPlanData

/// Что из неба видно на экранах, по переключателям «Астро» (опись 30г.2 § 2). Правило одно — `AppSettings.sees`;
/// здесь оно только переводится на язык экранов: слои «Карты» и AR, плитки пожеланий формы, пожелания карточки.
/// Данные не меняются: слой, выключенный переключателем, в файле остаётся как был, пожелания «Луна» и «Звёзды» в съёмке —
/// тоже, их только не показывают (30г.6: «Луны нет в «Про»» значит «не показываем», а не «выключили»).
extension AppModel {

    /// Переключатель «Луна» (30г.6): только «Астро» и только включённый. Экраны «Света», «Карты» и AR читают копию
    /// в `LightScreenModel.moon`, ставит её `applySettings` из того же правила.
    var seesMoon: Bool { settings.sees(.moon) }

    /// Переключатель «Звёзды» (30г.7): слои звёзд, созвездий и планет в AR, пожелание «Звёзды» с его окном Млечного Пути
    /// в карточке, плиткой и всплывашкой в форме, небо на нажатии «Астро» (опись № 3, 106, 146, 147, 166, 200, 203).
    /// Звёзды на куполе он не прячет (№ 57, ответ 6).
    var seesStars: Bool { settings.sees(.stars) }

    /// Переключатель «Млечный Путь» (30г.7): слой «Карты» с его сводом и группой «Подробно», слой AR с «Как в тёмном месте»
    /// (опись № 74, 96, 105).
    var seesMilkyWay: Bool { settings.sees(.milkyWay) }

    /// Слои «Карты», которые рисуются сейчас: то, что включено в меню слоёв, без того, что прячет переключатель.
    /// Слой «Луна» — только с «Луной» (опись № 73), «Млечный Путь» — только с «Млечным Путём» (№ 74).
    var mapLayersShown: MapLayers {
        var l = mapLayers
        if !seesMoon { l.moon = false }
        if !seesMilkyWay { l.mw = false }
        return l
    }

    /// Пункты меню слоёв «Карты»: без переключателя строки его слоя нет вовсе (опись № 73, 74).
    var mapLayerKeys: [MapLayers.Key] {
        MapLayers.Key.allCases.filter { k in
            switch k {
            case .moon: seesMoon
            case .mw: seesMilkyWay
            case .sun, .compass, .spots: true
            }
        }
    }

    /// Слои неба AR, которые разрешают переключатели: каждый — по своему (`SunARSkyLayer.astroSwitch`; опись № 104–106).
    /// Пусто — нет и кнопки «Слои» (№ 103).
    var arSkyLayers: Set<SunARSkyLayer> {
        Set(SunARSkyLayer.allCases.filter { settings.sees($0.astroSwitch) })
    }

    /// Пожелания, о которых экраны говорят: без «Луны» молчит «Луна», без «Звёзд» — «Звёзды» (опись № 147, 203),
    /// в записи обе остаются.
    func shownWishes(_ wishes: [Wish]) -> [Wish] {
        wishes.filter { w in Self.astroSwitch(of: w).map(settings.sees) ?? true }
    }

    /// Какой переключатель прячет пожелание; `nil` — пожелание видно всегда.
    static func astroSwitch(of w: Wish) -> AstroSwitch? {
        switch w {
        case .moon: .moon
        case .stars: .stars
        default: nil
        }
    }

    /// Плитки «Нужна погода» в форме: без «Луны» и «Звёзд» семь из девяти (опись № 165, 166).
    var wishTiles: [Wish] { shownWishes(Wish.allCases) }
}

extension SunARSkyLayer {
    /// Переключатель «Астро», под которым слой: планеты и созвездия идут под «Звёзды» — шестого переключателя нет
    /// (опись 30г.2 § 3, «Что я решил сам»).
    var astroSwitch: AstroSwitch {
        switch self {
        case .moon: .moon
        case .milkyWay: .milkyWay
        case .stars, .constellations, .planets: .stars
        }
    }
}
