import Testing
import Foundation
@testable import LightPlanDomain

/// 30е.1: выбор студии из общего списка (схема `docs/30e1_studio_list/index.html`,
/// «Да, A везде» — DECISIONS 07.11). Места выдуманы, кроме Томсона.
struct StudioCatalogTests {

    private let tomson = CatalogPlace(id: "pl100001", name: "Томсон",
                                      address: "Томск, ул. Красноармейская, 101а, 3 этаж, офисы 304, 305, 311",
                                      city: "Томск", timezone: "Asia/Tomsk",
                                      halls: [.init(number: 1, name: "Эдисон"), .init(number: 2, name: "Сфера"), .init(number: 3, name: "Вегас")],
                                      check: .verified)
    private let smile = CatalogPlace(id: "pl900002", name: "Улыбка", address: "Томск, пр. Выдуманный, 12", city: "Томск",
                                     halls: [.init(number: 1, name: "Белый"), .init(number: 2, name: "Лофт")])
    private let smileDup = CatalogPlace(id: "pl900003", name: "Улыбка", address: "Томск, ул. Примерная, 7", city: "Томск",
                                        check: .disputed)
    private let closed = CatalogPlace(id: "pl900004", name: "Ушедшая улыбка", address: "Томск, ул. Примерная, 9",
                                      city: "Томск", closed: true)
    private let daisy = CatalogPlace(id: "pl900005", name: "Ромашка", address: "Новосибирск, ул. Примерная, 1", city: "Новосибирск")
    private let merged = CatalogPlace(id: "pl900006", name: "Улыбка-старая", city: "Томск", mergedInto: "pl900002")

    private var catalog: PlaceCatalog {
        PlaceCatalog(etag: 1, asOf: "2026-11-07", places: [tomson, smile, smileDup, closed, daisy, merged])
    }

    @Test func oneLetterSearchesNothingTwoLettersSearch() {
        #expect(StudioCatalog.search("у", in: catalog, town: "Томск", mine: []).isEmpty)
        #expect(!StudioCatalog.search("ул", in: catalog, town: "Томск", mine: []).isEmpty)
    }

    @Test func closedAndMergedPlacesAreNeverOffered() {
        let ids = StudioCatalog.search("улыбка", in: catalog, town: "Томск", mine: []).here.map(\.place.id)
        #expect(ids == ["pl900002", "pl900003"])
        #expect(StudioCatalog.count(town: "Томск", in: catalog) == 3)
    }

    @Test func shootCityFirstOtherCitiesApart() {
        let h = StudioCatalog.search("примерная", in: catalog, town: "Томск", mine: [])
        #expect(h.here.map(\.place.id) == ["pl900003"])
        #expect(h.other.map(\.place.id) == ["pl900005"])
        // Город съёмки не известен — всё одним разделом, «других городов» нет.
        let all = StudioCatalog.search("примерная", in: catalog, town: "", mine: [])
        #expect(all.here.count == 2 && all.other.isEmpty)
    }

    @Test func englishCityNameIsTheSameCity() {
        #expect(StudioCatalog.sameCity("Tomsk", "Томск"))
        #expect(StudioCatalog.search("томсон", in: catalog, town: "Tomsk", mine: []).here.map(\.place.id) == ["pl100001"])
        #expect(!StudioCatalog.sameCity("Томск", "Новосибирск"))
    }

    @Test func searchFindsByHallStreetAndWordsInAnyOrderIgnoringCaseAndYo() {
        #expect(StudioCatalog.search("эдисон", in: catalog, town: "Томск", mine: []).here.first?.place.id == "pl100001")
        #expect(StudioCatalog.search("101а красноармейская", in: catalog, town: "Томск", mine: []).here.first?.place.id == "pl100001")
        #expect(StudioCatalog.search("ТОМСОН", in: catalog, town: "Томск", mine: []).here.count == 1)
        let yo = CatalogPlace(id: "pl900007", name: "Ёлка", city: "Томск")
        let c = PlaceCatalog(etag: 1, asOf: "", places: [yo])
        #expect(StudioCatalog.search("елка", in: c, town: "Томск", mine: []).here.count == 1)
    }

    @Test func nameStartingWithQueryComesFirst() {
        let a = CatalogPlace(id: "pl900010", name: "Студия Свет", city: "Томск")
        let b = CatalogPlace(id: "pl900011", name: "Свет и тень", city: "Томск")
        let c = PlaceCatalog(etag: 1, asOf: "", places: [a, b])
        #expect(StudioCatalog.search("свет", in: c, town: "Томск", mine: []).here.map(\.place.id) == ["pl900011", "pl900010"])
    }

    @Test func capLeavesTheRestAsANumber() {
        let many = (0..<40).map { CatalogPlace(id: "pl9\($0)", name: "Кадр \($0)", city: "Томск") }
        let h = StudioCatalog.search("кадр", in: PlaceCatalog(etag: 1, asOf: "", places: many), town: "Томск", mine: [])
        #expect(h.here.count == StudioCatalog.cap && h.moreHere == 40 - StudioCatalog.cap)
    }

    @Test func everyRowButTheVerifiedSaysHowSureWeAre() {
        let h = StudioCatalog.search("томск", in: catalog, town: "Томск", mine: [])
        let marks = Dictionary(uniqueKeysWithValues: h.here.map { ($0.place.id, StudioCatalog.mark($0)) })
        #expect(marks["pl100001"] == .verified)
        #expect(marks["pl900002"] == .unverified)
        #expect(marks["pl900003"] == .disputed)
    }

    @Test func placeAlreadyInMyStudiosIsMarkedYours() {
        var own = Studio(id: "st1", name: "Томсон (мой)", latitude: 56.47, longitude: 84.97)
        own.catalogId = "pl100001"
        let row = StudioCatalog.search("томсон", in: catalog, town: "Томск", mine: [own]).here[0]
        #expect(row.mine == "st1" && StudioCatalog.mark(row) == .yours)
        #expect(StudioCatalog.placeId(of: own) == "pl100001")
    }

    @Test func handMadeCardWithTheSameNameIsNotGlued() {
        let hand = Studio(id: "st2", name: "Улыбка", latitude: 56.47, longitude: 84.97)
        let rows = StudioCatalog.search("улыбка", in: catalog, town: "Томск", mine: [hand]).here
        #expect(rows.allSatisfy { $0.mine == nil })
        #expect(StudioCatalog.placeId(of: hand) == nil)
    }

    @Test func cardTakesNameFullAddressCityHallsZoneAndCityCentre() {
        let c = StudioCatalog.card(tomson)
        #expect(c.catalogId == "pl100001" && c.name == "Томсон" && c.town == "Томск")
        #expect(c.address == "Томск, ул. Красноармейская, 101а, 3 этаж, офисы 304, 305, 311")
        #expect(c.halls == [Studio.Hall(id: "n1", name: "Эдисон"), Studio.Hall(id: "n2", name: "Сфера"), Studio.Hall(id: "n3", name: "Вегас")])
        #expect(c.zone == "Asia/Tomsk")
        #expect(c.latitude == CatalogCities.find("Томск")?.latitude)
        // Пояса в файле нет — пояс города из таблицы; залов нет — один зал с названием студии.
        let d = StudioCatalog.card(daisy)
        #expect(d.zone == "Asia/Novosibirsk" && d.halls.isEmpty)
        // Город не из таблицы — ни центра, ни пояса: дальше, как у ручной карточки.
        let far = StudioCatalog.card(CatalogPlace(id: "pl900020", name: "Где-то", city: "Неведомск"))
        #expect(far.latitude == nil && far.zone == nil)
    }

    @Test func foundAddressFarFromTheCityIsRejected() {
        // Красноармейская есть и в Томске, и в Москве.
        #expect(StudioCatalog.accepts(latitude: 56.47, longitude: 84.97, for: tomson))
        #expect(!StudioCatalog.accepts(latitude: 55.76, longitude: 37.62, for: tomson))
        #expect(StudioCatalog.accepts(latitude: 55.76, longitude: 37.62,
                                      for: CatalogPlace(id: "pl9", name: "Х", city: "Неведомск")))
    }

    @Test func mergedNumberLeadsToTheLivePlace() {
        #expect(catalog.place("pl900006")?.id == "pl900002")
        #expect(catalog.place("pl000000") == nil)
    }

    @Test func cityTableHasThirtyNineDistinctCitiesWithRealZones() {
        #expect(CatalogCities.all.count == 39)
        #expect(Set(CatalogCities.all.map(\.ru)).count == 39)
        for c in CatalogCities.all {
            #expect(TimeZone(identifier: c.zone) != nil, "\(c.ru)")
            #expect((41...61).contains(c.latitude) && (27...136).contains(c.longitude), "\(c.ru)")
        }
        #expect(CatalogCities.find("санкт петербург")?.ru == "Санкт-Петербург")
        #expect(CatalogCities.find("Rostov-on-Don")?.ru == "Ростов-на-Дону")
    }
}
