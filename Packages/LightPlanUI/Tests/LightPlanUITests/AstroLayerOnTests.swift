import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
import LightPlanData
@testable import LightPlanUI

/// 30г.7а: ответ 4 Алексея (05.11, DECISIONS): «Включённый в «Астро» переключатель сразу показывает слой на карте и в AR;
/// слой, убранный на месте, остаётся убран, пока переключатель не включат заново». «Луна» — луна на «Карте» и в AR,
/// «Звёзды» — звёзды, созвездия и планеты в AR, «Млечный Путь» — Млечный Путь на «Карте» и в AR. Выключение и переход
/// в «Астро» слоёв не трогают; «Термины» и «Азимуты» слоёв не имеют.
@MainActor
struct AstroLayerOnTests {

    // MARK: - Подставные источники

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

    /// Переключатели со слоями и их слои: на «Карте» и в «Слоях» AR.
    struct Owned: CustomStringConvertible {
        let sw: AstroSwitch
        let map: [MapLayers.Key]
        let ar: [SunARSkyLayer]
        var description: String { sw.rawValue }
        static let all: [Owned] = [
            Owned(sw: .moon, map: [.moon], ar: [.moon]),
            Owned(sw: .stars, map: [], ar: [.stars, .constellations, .planets]),
            Owned(sw: .milkyWay, map: [.mw], ar: [.milkyWay]),
        ]
    }

    private static let skyMapKeys: [MapLayers.Key] = [.moon, .mw]

    /// «Астро», все пять включены; слои — по умолчанию веба на карте (луна да, Млечный Путь нет), в AR все выключены.
    private func model(_ snap: Snapshot = Snapshot()) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), now: { now })
        app.update { $0.mode = .astro; for sw in AstroSwitch.allCases { $0.astro[sw] = true } }
        return app
    }

    /// Все слои неба — одним значением (карта и AR), чтобы видеть, что изменилось.
    private func layers(_ app: AppModel) -> [String: Bool] {
        var d: [String: Bool] = [:]
        for k in Self.skyMapKeys { d["map." + k.rawValue] = app.mapLayers[k] }
        for l in SunARSkyLayer.allCases { d["ar." + l.rawValue] = app.arBodies[l] }
        return d
    }

    private func setAll(_ app: AppModel, _ on: Bool) {
        for k in Self.skyMapKeys { app.setMapLayer(k, on) }
        for l in SunARSkyLayer.allCases { app.arBodies[l] = on }
    }

    // MARK: - Выкл → вкл

    /// Переключатель включили из выключенного: его слои на «Карте» и в AR сразу включены, в файле тоже; чужие слои
    /// остались как были.
    @Test(arguments: Owned.all)
    func offToOnTurnsItsLayersOn(_ o: Owned) {
        let app = model()
        app.update { $0.astro[o.sw] = false }
        setAll(app, false)
        let before = layers(app)
        app.update { $0.astro[o.sw] = true }
        let after = layers(app)
        for k in o.map {
            #expect(app.mapLayers[k], "\(o): слой карты \(k) не включился")
            #expect(app.snapshot.mapLayers?[k.rawValue] == true, "\(o): в файле \(k) не включён")
            #expect(app.mapLayersShown[k] && app.mapLayerKeys.contains(k), "\(o): \(k) не виден")
        }
        for l in o.ar {
            #expect(app.arBodies[l], "\(o): слой AR \(l) не включился")
            #expect(app.arSkyLayers.contains(l), "\(o): \(l) не разрешён")
        }
        let own = Set(o.map.map { "map." + $0.rawValue } + o.ar.map { "ar." + $0.rawValue })
        for (key, was) in before where !own.contains(key) {
            #expect(after[key] == was, "\(o): чужой слой \(key) изменился")
        }
    }

    /// Экран AR читает те самые флаги, что включает переключатель: после включения слой на небе и в «Слоях».
    @Test(arguments: Owned.all)
    func arScreenShowsTheLayerRightAfterTheSwitch(_ o: Owned) {
        let app = model()
        app.update { $0.astro[o.sw] = false }
        setAll(app, false)
        app.update { $0.astro[o.sw] = true }
        let ar = SunARScreen.model(app: app, target: tomskNight, source: nil)
        for l in o.ar {
            #expect(ar.isOn(l), "\(o): слой \(l) выключен на экране AR")
            #expect(ar.layersOn.contains(l), "\(o): \(l) не в «Слоях»")
        }
        #expect(Set(ar.layersOn) == Set(o.ar), "\(o): на экране AR включено не то: \(ar.layersOn)")
    }

    // MARK: - Вкл → выкл

    /// Выключение слоёв не трогает: ни в файле, ни во флагах AR — в обоих положениях слоёв.
    @Test(arguments: Owned.all)
    func onToOffLeavesTheLayersAsTheyWere(_ o: Owned) {
        for on in [true, false] {
            let app = model()
            setAll(app, on)
            let before = layers(app), file = app.snapshot.mapLayers
            app.update { $0.astro[o.sw] = false }
            #expect(layers(app) == before, "\(o), слои \(on): выключение тронуло слои")
            #expect(app.snapshot.mapLayers == file, "\(o), слои \(on): файл изменился")
            for k in o.map { #expect(!app.mapLayersShown[k], "\(o): \(k) виден без переключателя") }
            for l in o.ar { #expect(!app.arSkyLayers.contains(l), "\(o): \(l) разрешён без переключателя") }
        }
    }

    // MARK: - Убран на месте

    /// Слой, убранный в меню на месте (карта — меню слоёв, AR — «Слои»), остаётся убран: ни переход в другой режим и
    /// обратно, ни чужие переключатели, ни повторная запись того же значения его не возвращают. Возвращает только
    /// следующее включение своего переключателя.
    @Test(arguments: Owned.all)
    func layerRemovedOnTheSpotStaysRemovedUntilTheSwitchIsOnAgain(_ o: Owned) {
        let app = model()
        app.update { $0.astro[o.sw] = false }
        app.update { $0.astro[o.sw] = true }
        // Убрали на месте.
        for k in o.map { app.setMapLayer(k, false) }
        let screen = SunARScreen.model(app: app, target: tomskNight, source: nil)
        for l in o.ar { screen.set(l, on: false) }
        for l in o.ar { #expect(!app.arBodies[l], "\(o): «Слои» AR не записали флаг \(l)") }

        app.update { $0.mode = .pro }
        app.update { $0.mode = .simple }
        app.update { $0.mode = .astro }
        for other in AstroSwitch.allCases where other != o.sw {
            app.update { $0.astro[other] = false }
            app.update { $0.astro[other] = true }
        }
        app.update { $0.astro[o.sw] = true }
        for k in o.map { #expect(!app.mapLayers[k], "\(o): слой карты \(k) вернулся сам") }
        for l in o.ar { #expect(!app.arBodies[l], "\(o): слой AR \(l) вернулся сам") }

        app.update { $0.astro[o.sw] = false }
        app.update { $0.astro[o.sw] = true }
        for k in o.map { #expect(app.mapLayers[k], "\(o): после нового включения \(k) не вернулся") }
        for l in o.ar { #expect(app.arBodies[l], "\(o): после нового включения \(l) не вернулся") }
    }

    // MARK: - Что слоёв не трогает

    /// Повторный вход в «Астро» (из «Просто» и «Про») слоёв не трогает: они остаются такими, какими человек их оставил.
    @Test func enteringAstroAgainDoesNotTouchTheLayers() {
        for from in [AppMode.simple, .pro] {
            let app = model()
            app.update { $0.mode = from }
            for on in [false, true] {
                setAll(app, on)
                app.setMapLayer(.moon, !on)
                app.arBodies[.planets] = !on
                let before = layers(app), file = app.snapshot.mapLayers
                app.update { $0.mode = .astro }
                #expect(layers(app) == before, "\(from) → astro, слои \(on): слои изменились")
                #expect(app.snapshot.mapLayers == file, "\(from) → astro, слои \(on): файл изменился")
                app.update { $0.mode = from }
            }
        }
    }

    /// «Термины» и «Азимуты» слоёв не имеют: их включение ничего не включает.
    @Test func termsAndAzimuthsHaveNoLayers() {
        for sw in [AstroSwitch.terms, .azimuths] {
            let app = model()
            app.update { $0.astro[sw] = false }
            setAll(app, false)
            let before = layers(app), file = app.snapshot.mapLayers
            app.update { $0.astro[sw] = true }
            #expect(layers(app) == before, "\(sw): слои изменились")
            #expect(app.snapshot.mapLayers == file, "\(sw): файл изменился")
            #expect(AppModel.mapLayerKeys(of: sw).isEmpty && !SunARSkyLayer.allCases.contains { $0.astroSwitch == sw })
        }
    }

    /// «Как в тёмном месте» — способ показа Млечного Пути, не слой: включение переключателя его не трогает.
    @Test func milkyWayDarkIsNotALayer() {
        let key = SunARModel.milkyWayDarkKey
        let was = UserDefaults.standard.object(forKey: key)
        defer { if let was { UserDefaults.standard.set(was, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.set(false, forKey: key)
        let app = model()
        app.update { $0.astro[.milkyWay] = false }
        app.update { $0.astro[.milkyWay] = true }
        #expect(UserDefaults.standard.bool(forKey: key) == false)
    }

    /// Новый человек в «Просто» или «Про», в «Астро» ещё не был.
    private func fresh(_ mode: AppMode, memory: any AppModeMemory = InMemoryAppModeMemory(), snap: Snapshot = Snapshot()) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), modeMemory: memory, now: { now })
        if app.settings.mode != mode { app.update { $0.mode = mode } }
        return app
    }

    /// Первый вход в «Астро» (опись, вопрос 4, вариант А): все пять включены — это включение всех пяти, слои «Луны»,
    /// «Звёзд» и «Млечного Пути» включаются на «Карте» и в AR, как рукой. Небо в AR сразу полное.
    @Test func firstEntryIntoAstroTurnsTheSkyLayersOn() {
        for from in [AppMode.simple, .pro] {
            let app = fresh(from)
            #expect(app.settings.astro == .allOn && !app.modeMemory.astroEntered)
            #expect(!app.mapLayers.mw && SunARSkyLayer.allCases.allSatisfy { !app.arBodies[$0] }, "\(from): умолчания не те")
            app.update { $0.mode = .astro }
            #expect(app.mapLayers.moon && app.mapLayers.mw, "\(from): слои карты не включились")
            #expect(app.snapshot.mapLayers?["mw"] == true && app.snapshot.mapLayers?["moon"] == true, "\(from): файл")
            #expect(SunARSkyLayer.allCases.allSatisfy { app.arBodies[$0] }, "\(from): слои AR не включились")
            #expect(app.modeMemory.astroEntered, "\(from): первый вход не отмечен")
            let ar = SunARScreen.model(app: app, target: tomskNight, source: nil)
            #expect(ar.layersOn == SunARSkyLayer.allCases, "\(from): на экране AR \(ar.layersOn)")
        }
    }

    /// Кто был в «Астро» до обновления, не тронут: стоит в «Астро» (ключ режима или старая галочка `pro`), стоял в нём
    /// в прошлый запуск или выключал переключатель. Слои как были — и при запуске, и при следующем входе в «Астро».
    @Test func alreadyBeenInAstroIsNotTouched() {
        var flag = Snapshot(); flag.pro = true
        var key = Snapshot(); key.appMode = "astro"
        var pro = Snapshot(); pro.appMode = "pro"
        var offInPro = pro; offInPro.astroOff = ["stars"]
        let cases: [(String, Snapshot, any AppModeMemory)] = [
            ("галочка pro", flag, InMemoryAppModeMemory()),
            ("ключ astro", key, InMemoryAppModeMemory()),
            ("прошлый запуск в «Астро», файл в «Про»", pro, InMemoryAppModeMemory(.astro)),
            ("выключал переключатель", offInPro, InMemoryAppModeMemory()),
        ]
        for (why, snap, memory) in cases {
            let app = fresh(.pro, memory: memory, snap: snap)
            #expect(app.modeMemory.astroEntered, "\(why): не отмечен")
            let before = layers(app), file = app.snapshot.mapLayers
            app.update { $0.mode = .astro }
            app.update { $0.mode = .pro }
            app.update { $0.mode = .astro }
            #expect(layers(app) == before, "\(why): слои изменились")
            #expect(app.snapshot.mapLayers == file, "\(why): файл изменился")
        }
    }

    /// Отметка живёт в памяти телефона: после перезапуска повторный вход слоёв не включает.
    @Test func firstEntryIsRememberedOnThePhone() {
        let defaults = UserDefaults(suiteName: "astro-entered-\(UUID().uuidString)")!
        let memory = DeviceAppModeMemory(defaults: defaults)
        #expect(!memory.astroEntered)
        let first = fresh(.pro, memory: memory)
        first.update { $0.mode = .astro }
        #expect(defaults.bool(forKey: DeviceAppModeMemory.astroEnteredKey)
                && DeviceAppModeMemory.astroEnteredKey == "lightplan.native.app.astroEntered")
        first.update { $0.mode = .pro }
        // Новый запуск: файл в «Про», слои убраны; память та же.
        var snap = first.snapshot; snap.mapLayers = ["moon": false, "mw": false]
        let again = fresh(.pro, memory: DeviceAppModeMemory(defaults: defaults), snap: snap)
        let before = layers(again)
        again.update { $0.mode = .astro }
        #expect(layers(again) == before && !again.mapLayers.mw)
    }

    // MARK: - Память

    /// Флаги AR приложения — память телефона у людей: запись идёт в ключи, которые читает экран AR.
    @Test func memoryBodiesCopyTheDeviceFlags() {
        let defaults = UserDefaults(suiteName: "layer-on-\(UUID().uuidString)")!
        let device = DeviceBodiesSettings(defaults: defaults)
        device[.milkyWay] = true
        device[.planets] = true
        #expect(defaults.bool(forKey: DeviceBodiesSettings.milkyWayKey) && defaults.bool(forKey: DeviceBodiesSettings.planetsKey))
        let copy = MemoryBodiesSettings(copying: device)
        #expect(SunARSkyLayer.allCases.filter { copy[$0] } == [.milkyWay, .planets])
        copy[.moon] = true
        #expect(!device[.moon], "копия пишет в телефон")
    }

    private let tomskNight = SunARTarget(place: Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!),
                                         moment: Moment(ISO8601DateFormatter().date(from: "2026-10-19T20:00:00Z")!))
}
