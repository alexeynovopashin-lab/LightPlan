import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 30е.1: студия из общего списка становится своей карточкой фотографа. Места
/// выдуманы, кроме Томсона; реального файла списка в тестах нет.
@MainActor
struct StudioCatalogFlowTests {

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
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }
    /// Карта отвечает одной точкой на любой адрес и помнит, что спросили.
    private final class OneSpot: PlaceSearch, @unchecked Sendable {
        var answer: GeoCoordinate?
        var asked: [String] = []
        init(_ c: GeoCoordinate?) { answer = c }
        func places(matching query: String) async throws -> [PlaceHit] {
            asked.append(query)
            return answer.map { [PlaceHit(name: "дом", area: "Томск, Томская область", coordinate: $0)] } ?? []
        }
    }

    private let tomson = CatalogPlace(id: "pl100001", name: "Томсон",
                                      address: "Томск, ул. Красноармейская, 101а, 3 этаж, офисы 304, 305, 311",
                                      city: "Томск", timezone: "Asia/Tomsk",
                                      halls: [.init(number: 1, name: "Эдисон"), .init(number: 2, name: "Сфера")],
                                      check: .verified)
    private let daisy = CatalogPlace(id: "pl900005", name: "Ромашка", address: "ул. Примерная, 1", city: "Новосибирск")

    private func model(_ search: OneSpot = OneSpot(nil), studios: [Studio] = []) -> AppModel {
        var s = Snapshot()
        s.studios = studios
        s.extra["me"] = .object(["city": .string("Томск"), "phone": .string("+7 913 111-22-33")])
        let app = AppModel(snapshot: s, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Tomsk")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           placeSearch: search, weatherSource: NoWeather())
        app.draftStore = MemoryDraftStore()
        return app
    }

    @Test func withoutTheFileTheSheetHasNoList() {
        let app = model()
        #expect(app.placeCatalog == nil)
        #expect(app.catalogHits("томсон", town: "Томск").isEmpty)
    }

    @Test func listArrivesFromTheSourceInTheBackground() async throws {
        let app = model()
        let json = #"{"format":1,"places":[{"placeId":"pl100001","name":"Томсон","city":"Томск","verification":"проверена человеком"}]}"#
        app.attachPlaceCatalog(FixedPlaceCatalog(Data(json.utf8)))
        for _ in 0..<100 where app.placeCatalog == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(app.catalogHits("томсон", town: "Томск").here.map(\.place.id) == ["pl100001"])
    }

    @Test func pickedPlaceBecomesMyOwnCardWithThePlaceNumber() throws {
        let app = model()
        app.usePlaceCatalog(PlaceCatalog(etag: 1, asOf: "", places: [tomson]))
        let row = try #require(app.catalogHits("томсон", town: "Томск").here.first)
        let d = app.catalogDraft(row)
        #expect(d.id == nil && d.catalogId == "pl100001" && d.phone.isEmpty && d.key.isEmpty)
        let st = app.saveStudio(d)
        #expect(st.name == "Томсон" && st.town == "Томск" && st.catalogId == "pl100001")
        #expect(st.address == "Томск, ул. Красноармейская, 101а, 3 этаж, офисы 304, 305, 311")
        #expect(st.halls.map(\.name) == ["Эдисон", "Сфера"] && st.halls.map(\.id) == ["n1", "n2"])
        #expect(st.key.isEmpty)                                       // «Связать с бронью» не появляется
        #expect(app.snapshot.studios.count == 1)
        // Центр Томска, пока адрес не найден; пояс из списка лёг в кэш.
        let c = try #require(CatalogCities.find("Томск"))
        #expect(abs((st.latitude ?? 0) - c.latitude) < 0.001 && abs((st.longitude ?? 0) - c.longitude) < 0.001)
        #expect(app.place.zones.zone(at: GeoCoordinate(latitude: c.latitude, longitude: c.longitude))?.identifier == "Asia/Tomsk")
    }

    @Test func secondPickOfTheSamePlaceGivesTheSameCard() throws {
        let app = model()
        app.usePlaceCatalog(PlaceCatalog(etag: 1, asOf: "", places: [tomson]))
        let first = app.saveStudio(app.catalogDraft(try #require(app.catalogHits("томсон", town: "Томск").here.first)))
        let row = try #require(app.catalogHits("томсон", town: "Томск").here.first)
        #expect(row.mine == first.id && StudioCatalog.mark(row) == .yours)
        let again = app.saveStudio(app.catalogDraft(row))
        #expect(again.id == first.id && app.snapshot.studios.count == 1)
    }

    @Test func myEditsStayAndTheNumberStays() throws {
        let app = model()
        app.usePlaceCatalog(PlaceCatalog(etag: 1, asOf: "", places: [tomson]))
        let st = app.saveStudio(app.catalogDraft(try #require(app.catalogHits("томсон", town: "Томск").here.first)))
        var d = StudioDraft(st, fallback: app.place.coordinate)
        d.phone = "+7 3822 00-00-00"; d.name = "Томсон, 3 этаж"
        let edited = app.saveStudio(d)
        #expect(edited.catalogId == "pl100001" && edited.phone == "+7 3822 00-00-00" && edited.name == "Томсон, 3 этаж")
    }

    @Test func handMadeCardIsNeverGluedToTheList() throws {
        let hand = Studio(id: "st9", name: "Томсон", latitude: 56.47, longitude: 84.97)
        let app = model(studios: [hand])
        app.usePlaceCatalog(PlaceCatalog(etag: 1, asOf: "", places: [tomson]))
        let row = try #require(app.catalogHits("томсон", town: "Томск").here.first)
        #expect(row.mine == nil)
        _ = app.saveStudio(app.catalogDraft(row))
        #expect(app.snapshot.studios.count == 2)
        #expect(app.snapshot.studios.first { $0.id == "st9" }?.catalogId == nil)
    }

    @Test func foundAddressInTheCityIsTakenFarOneIsNot() async {
        let near = OneSpot(GeoCoordinate(latitude: 56.4766, longitude: 84.9530))
        #expect(await model(near).locateCatalogPlace(tomson) == GeoCoordinate(latitude: 56.4766, longitude: 84.9530))
        #expect(near.asked == ["Томск, ул. Красноармейская, 101а, 3 этаж, офисы 304, 305, 311"])
        let moscow = OneSpot(GeoCoordinate(latitude: 55.76, longitude: 37.62))
        #expect(await model(moscow).locateCatalogPlace(tomson) == nil)
        // Адрес без города — город дописывается в запрос.
        let any = OneSpot(nil)
        #expect(await model(any).locateCatalogPlace(daisy) == nil)
        #expect(any.asked == ["Новосибирск, ул. Примерная, 1"])
    }
}
