import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 31.8 (DECISIONS 18.11 «Звёзды: остатки — шаг 31.8»): строка карточки «Ожидались звёзды» говорит о тех часах, что судит.
/// Съёмка мимо темноты (днём, в сумерки) судится облаками своих часов — «Прогноз на время съёмки», а не «на эту ночь».
/// Помощники — из `DawnRest6cTests` (облака 78 % в темноте или вне её, пояса мест в снимке).
@MainActor
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct StarsRest8Tests {
    typealias T = DawnRest6cTests

    func cardLine(_ src: T.NightSky, _ c: T.City, day: CivilDate, start: Int) async throws -> String? {
        let app = T.app(src, city: c, day: day, sessions: [T.shoot("s", c, day: day, start: start, wishes: [.stars])])
        await app.light.weather.settled()
        app.openCard(id: "s")
        await app.pointWeather.settled()
        let s = try #require(app.sessions.first { $0.id == "s" })
        return app.cardWishMissed(s, phase: .before)
    }

    /// Днём облака 78 %, ночью ясно: карточка судит часы съёмки (как форма со временем человека) и так и говорит.
    @Test("«Звёзды» днём (Томск 13:00, Тромсё в полярную ночь 12:00, Сидней 13:00): «Прогноз на время съёмки — затянуто»")
    func daytimeShootSaysShootHours() async throws {
        for c in [T.tomsk, T.tromso, T.sydney] {
            let line = try await cardLine(T.NightSky(dark: 0, light: 78), c, day: T.winter, start: c.name == "Тромсё" ? 12 * 60 : 13 * 60)
            #expect(line == "Ожидались звёзды. Прогноз на время съёмки — затянуто.", "\(c.name): \(String(describing: line))")
        }
    }

    /// Сумерки до темноты: Томск 21.12, темнота с 19:08 — съёмка 17:30–18:30 её не касается.
    @Test("«Звёзды» в сумерки до темноты (Томск 17:30): тоже «на время съёмки»")
    func twilightShootSaysShootHours() async throws {
        let line = try await cardLine(T.NightSky(dark: 0, light: 78), T.tomsk, day: T.winter, start: 17 * 60 + 30)
        #expect(line == "Ожидались звёзды. Прогноз на время съёмки — затянуто.", "\(String(describing: line))")
    }

    /// Ночная съёмка — вечером своих суток и под утро (хвост прошлой ночи): «на эту ночь», как было.
    @Test("«Звёзды» ночью (Томск 23:00 и 02:00, Алматы 23:00 в июле): «Прогноз на эту ночь — затянуто»")
    func nightShootSaysThisNight() async throws {
        let july = CivilDate(year: 2027, month: 7, day: 4)
        for (c, d, start) in [(T.tomsk, T.winter, 23 * 60), (T.tomsk, T.winter, 2 * 60), (T.almaty, july, 23 * 60)] {
            let line = try await cardLine(T.NightSky(), c, day: d, start: start)
            #expect(line == "Ожидались звёзды. Прогноз на эту ночь — затянуто.", "\(c.name) \(start): \(String(describing: line))")
        }
    }

    @Test("слова «… на время съёмки» на пяти языках: без сырых слотов, не те же, что «на эту ночь»")
    func shootHoursWords() {
        for lang in ["ru", "en", "es", "ja", "zh"] {
            let lex = Lexicon(lang)
            let args = ["wish": lex.t("wish.was.stars"), "cond": lex.t("mwSky.poor").lowercased()]
            let t = lex.t("card.starsMissedShoot", args)
            #expect(!t.contains("{") && t != "card.starsMissedShoot", "\(lang): «\(t)»")
            #expect(t != lex.t("card.starsMissed", args), "\(lang)")
        }
    }
}
