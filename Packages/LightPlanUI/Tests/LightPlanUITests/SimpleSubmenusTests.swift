import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
import LightPlanData
@testable import LightPlanUI

/// 30г.9: «Просто» вне настроек. Ответ 3 Алексея (05.11): цветное небо есть, ленты суток нет. Ответ 2: в «Просто» на «Карте»
/// нет меню слоёв, солнце, компас и «Мои места» горят всегда, какой бы выбор ни стоял в «Про»; сам выбор в файле не трогается.
@MainActor
struct SimpleSubmenusTests {

    private struct NoWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func model(_ mode: AppMode, _ snap: Snapshot = Snapshot()) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), now: { now })
        app.update { $0.mode = mode; for sw in AstroSwitch.allCases { $0.astro[sw] = true } }
        return app
    }

    private static let fixed: [MapLayers.Key] = [.sun, .compass, .spots]

    // MARK: - «Карта»

    /// В «Про» выключил солнце, компас и места; в «Просто» они горят, а в файле и в памяти остаются выключенными.
    @Test func simpleLightsSunCompassAndSpotsWhateverProChose() {
        let app = model(.pro)
        for k in Self.fixed { app.setMapLayer(k, false) }
        for k in Self.fixed { #expect(!app.mapLayersShown[k], "Про: \(k) выключен человеком") }

        app.update { $0.mode = .simple }
        for k in Self.fixed {
            #expect(app.mapLayersShown[k], "Просто: \(k) горит всегда")
            #expect(!app.mapLayers[k], "Просто: выбор \(k) в памяти не тронут")
            #expect(app.snapshot.mapLayers?[k.rawValue] == false, "Просто: выбор \(k) в файле не тронут")
        }

        app.update { $0.mode = .pro }
        for k in Self.fixed { #expect(!app.mapLayersShown[k], "снова Про: \(k) — как выбрал человек") }
    }

    /// В «Просто» луна и Млечный Путь по-прежнему не видны (их прячут переключатели «Астро», 30г.6–7), даже если в файле включены.
    @Test func simpleShowsNoMoonAndNoMilkyWay() {
        let app = model(.astro)
        app.setMapLayer(.moon, true)
        app.setMapLayer(.mw, true)
        app.update { $0.mode = .simple }
        #expect(!app.mapLayersShown.moon)
        #expect(!app.mapLayersShown.mw)
    }

    /// В «Астро» и «Про» выбор человека действует как раньше.
    @Test(arguments: [AppMode.pro, .astro])
    func proAndAstroKeepThePersonsLayers(_ mode: AppMode) {
        let app = model(mode)
        for k in Self.fixed {
            app.setMapLayer(k, false)
            #expect(!app.mapLayersShown[k])
            app.setMapLayer(k, true)
            #expect(app.mapLayersShown[k])
        }
        #expect(app.settings.look.mapLayersMenu)
    }

    // MARK: - «Свет» и «Карта»: небо и лента

    /// Экраны читают правило из `LightScreenModel.look`; его ставит смена режима.
    @Test(arguments: AppMode.allCases)
    func lightModelFollowsTheMode(_ mode: AppMode) {
        let app = model(mode == .simple ? .pro : .simple)
        app.update { $0.mode = mode }
        #expect(app.light.look == ModeLook(mode))
        #expect(app.light.look.domeSky)
        #expect(app.light.look.dayRibbon == (mode != .simple))
    }

    /// При запуске правило стоит сразу, без смены режима.
    @Test func lightModelIsSetAtLaunch() {
        var snap = Snapshot()
        AppMode.pro.write(to: &snap)
        let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), now: { now })
        #expect(app.settings.mode == .pro)
        #expect(app.light.look == ModeLook(.pro))
    }

    // MARK: - Карточка

    /// Режим перестановки, открытый в «Про», закрывается при переходе в «Просто»: кнопки выхода там нет.
    @Test func simpleClosesCardTuning() {
        let app = model(.pro)
        app.toggleCardTuning()
        #expect(app.cardTuning)
        app.update { $0.mode = .simple }
        #expect(!app.cardTuning)
    }

    /// В «Про» и «Астро» смена других настроек перестановку не закрывает.
    @Test(arguments: [AppMode.pro, .astro])
    func proAndAstroKeepCardTuning(_ mode: AppMode) {
        let app = model(mode)
        app.toggleCardTuning()
        app.update { $0.tempUnit = .f }
        #expect(app.cardTuning)
    }
}
