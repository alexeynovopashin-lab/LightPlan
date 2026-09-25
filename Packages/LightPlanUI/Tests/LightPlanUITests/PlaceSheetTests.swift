import Testing
import Foundation
@testable import LightPlanUI
@testable import LightPlanData
import LightPlanCore
import LightPlanDomain

/// Итерация 21в: лист «Где снимаем» — правила полей и «Готово», переезд
/// места до «Света» и «Карты» без перезапуска, «Мои места» из листа.
@MainActor
struct PlaceSheetTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }

    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }

    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }

    private final class Locator: DeviceLocating {
        let fix: DeviceFix
        let fresh: Bool
        init(fix: DeviceFix = .denied, fresh: Bool = false) { self.fix = fix; self.fresh = fresh }
        var needsPermission: Bool { fresh }
        func currentFix() async -> DeviceFix { fix }
    }

    private let barnaul = GeoCoordinate(latitude: 53.35481, longitude: 83.76982)
    private let elbrus = GeoCoordinate(latitude: 43.3499, longitude: 42.4453)

    private func model(_ snapshot: Snapshot = Snapshot(), locator: Locator = Locator()) -> AppModel {
        AppModel(snapshot: snapshot, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                 locator: locator, geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
    }

    // MARK: - Поля и «Готово»

    @Test func opensWithHereToFourDigits() {
        let f = PlaceSheetForm(here: barnaul)
        #expect(f.way == .fork)
        #expect(f.lat == "53.3548" && f.lon == "83.7698")        // `toFixed(4)`
        #expect(f.name.isEmpty && !f.save)
        #expect(f.answer() == .success(GeoCoordinate(latitude: 53.3548, longitude: 83.7698)))
    }

    @Test func doneNamesTheWrongField() {
        var f = PlaceSheetForm(here: barnaul)
        f.typeCoords(lat: "", lon: "")
        #expect(f.answer() == .failure(.init(key: "loc.errNone")))   // не выбрано, а не «широта неверна»
        f.typeCoords(lat: "abc", lon: "xyz")
        #expect(f.answer() == .failure(.init(key: "loc.errNone")))
        f.typeCoords(lat: "91", lon: "10")
        #expect(f.answer() == .failure(.init(key: "loc.errLat")))
        f.typeCoords(lat: "43,3499", lon: "181")
        #expect(f.answer() == .failure(.init(key: "loc.errLon")))
        f.typeCoords(lon: "42.4453")
        #expect(f.answer() == .success(elbrus))                       // запятая — десятичный знак
    }

    @Test func pickFillsNumbersAndNameUnlessTyped() {
        var f = PlaceSheetForm(here: barnaul)
        let hit = PlaceHit(name: "Лагерный сад", area: "Томск, Томская область",
                           coordinate: GeoCoordinate(latitude: 56.45361, longitude: 84.94889))
        f.pick(hit)
        #expect(f.lat == "56.4536" && f.lon == "84.9489" && f.name == "Лагерный сад" && f.fromHit)

        var typed = PlaceSheetForm(here: barnaul)
        typed.typeName("Мой сад")
        typed.pick(hit)
        #expect(typed.name == "Мой сад")                              // поиск не начальник набранному
    }

    @Test func handTypedNumbersDropForeignName() {
        var f = PlaceSheetForm(here: barnaul)
        f.pick(PlaceHit(name: "Лобня", area: "", coordinate: GeoCoordinate(latitude: 56.01, longitude: 37.48)))
        f.typeCoords(lat: "43.3499")
        #expect(f.name.isEmpty && !f.fromHit)                         // Эльбрус не подписан «Лобней»

        var typed = PlaceSheetForm(here: barnaul)
        typed.typeName("Приют")
        typed.typeCoords(lat: "43.3499")
        #expect(typed.name == "Приют")
    }

    @Test func wayWordsAndErrorReset() {
        var f = PlaceSheetForm(here: barnaul)
        #expect(f.titleKey == "loc.title" && f.subKey == "loc.sub")
        f.open(.geo)
        #expect(f.titleKey == "loc.wayGeo" && f.subKey == "loc.wayGeoSub")
        f.errorKey = "loc.errLat"
        f.open(.fork)
        #expect(f.errorKey == nil)
    }

    // MARK: - «Готово, когда»: смена места доезжает до «Света» и «Карты»

    @Test func moveReachesLightAndMapWithoutRestart() async {
        let app = model()
        let light = app.light
        app.movePlace(to: elbrus)
        // Камера карты берёт центр из `place.coordinate` (`MapScreenView`).
        #expect(app.place.coordinate == elbrus)
        for _ in 0..<100 where app.light.timebar.place.latitude != elbrus.latitude { await Task.yield() }
        #expect(app.light === light)
        #expect(app.light.timebar.place.latitude == elbrus.latitude)
        #expect(app.light.timebar.place.longitude == elbrus.longitude)
    }

    @Test func locateHereMovesOnlyOnFix() async {
        let denied = model(locator: Locator(fix: .denied))
        let before = denied.place.coordinate
        #expect(await denied.locateHere() == .denied)
        #expect(denied.place.coordinate == before)

        let fixed = model(locator: Locator(fix: .fix(elbrus)))
        #expect(await fixed.locateHere() == .fix(elbrus))
        #expect(fixed.place.coordinate == elbrus)
    }

    @Test func freshPermissionIsVisibleToSheet() {
        #expect(model(locator: Locator(fresh: true)).locationNeedsPermission)
        #expect(!model(locator: Locator(fresh: false)).locationNeedsPermission)
    }

    // MARK: - «Мои места» из листа

    @Test func saveSpotAddsFirstAndMergesNearby() {
        let app = model()
        let a = app.saveSpot(at: elbrus, name: "  Приют  ", address: "", fromHit: false)
        #expect(app.spots.first?.id == a.id)
        #expect(a.name == "Приют" && a.named == true && a.pinned == true)
        #expect(a.latitude == 43.3499 && a.longitude == 42.4453)

        // 30 м — та же точка: имя и адрес обновляются, двойника нет.
        let near = GeoCoordinate(latitude: 43.3501, longitude: 42.4453)
        let b = app.saveSpot(at: near, name: "", address: "Кабардино-Балкария", fromHit: true)
        #expect(app.spots.count == 1 && b.id == a.id)
        #expect(b.name == "Приют" && b.address == "Кабардино-Балкария")

        let c = app.saveSpot(at: barnaul, name: "", address: "", fromHit: true)
        #expect(app.spots.count == 2 && app.spots.first?.id == c.id)
        #expect(c.name == barnaul.text && c.named == false && c.pinned == false)   // полая булавка
    }

    @Test func editSpotKeepsEmptyName() {
        let app = model()
        let sp = app.saveSpot(at: elbrus, name: "Приют", address: "", fromHit: false)
        app.editSpot(id: sp.id, address: " Терскол ")
        #expect(app.spots[0].address == "Терскол")
        app.editSpot(id: sp.id, name: "")
        #expect(app.spots[0].name.isEmpty)            // строку тогда называют координаты
    }

    // MARK: - Поиск места

    @Test func searchHitsNameAreaAndCap() {
        let c = GeoCoordinate(latitude: 56.45, longitude: 84.95)
        let marks: [(name: String?, locality: String?, region: String?, coordinate: GeoCoordinate)] =
            [("Лагерный сад", "Томск", "Томская область", c),
             ("Лагерный сад", "Томск", "Томская область", c),          // дубль
             (nil, "Томск", "Томская область", c),                      // без имени — город
             ("  ", nil, nil, c)]                                       // пустое — мимо
            + (0..<8).map { ("Улица \($0)", "Томск", nil, c) }
        let hits = ApplePlaceSearch.hits(marks)
        #expect(hits.count == 6)
        #expect(hits[0] == PlaceHit(name: "Лагерный сад", area: "Томск, Томская область", coordinate: c))
        #expect(hits[1] == PlaceHit(name: "Томск", area: "Томская область", coordinate: c))
        #expect(hits[2].name == "Улица 0" && hits[2].area == "Томск")
    }
}
