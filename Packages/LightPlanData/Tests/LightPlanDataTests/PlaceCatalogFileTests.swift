import Foundation
import Testing
@testable import LightPlanData
import LightPlanDomain

/// 30е.1: отдаваемый файл ядра, формат версии 1 (`event_os:16_Place_Registry.md`).
/// Пример выдуман по формату, кроме Томсона; реальных данных списка в репозитории нет.
@Suite struct PlaceCatalogFileTests {
    static let sample = #"""
    {"format":1,"etag":7,"asOf":"2026-11-05","count":5,"places":[
     {"placeId":"pl100001","name":"Томсон","names":[{"from":"2026-11-04","to":null,"value":"Томсон"}],
      "address":"Томск, ул. Красноармейская, 101а, 3 этаж, офисы 304, 305, 311","city":"Томск","timezone":"Asia/Tomsk",
      "halls":[{"number":1,"name":"Эдисон","windows":true,"azimuth":225,"archived":null},
               {"number":2,"name":"Старый","windows":null,"azimuth":null,"archived":"2026-11-01"}],
      "life":"действует","catalog":"подключена","verification":"проверена человеком","links":[],"updatedAt":"2026-11-04"},
     {"placeId":"pl900002","name":"Улыбка","names":[],"address":null,"city":"Томск","timezone":"Mars/Olympus",
      "halls":[],"hallsCount":3,"life":"закрыта","catalog":"не подключена","verification":"из сбора",
      "note":"тот же дом, что studiogo:1","links":[],"updatedAt":"2026-11-04"},
     {"placeId":"pl900003","name":"Ромашка","address":"Новосибирск, ул. Примерная, 1","city":"Новосибирск","timezone":null,
      "halls":[{"number":4,"name":"Белый"}],"life":"действует","verification":"спорная","mergedInto":"pl900002"},
     {"placeId":"pl900004","name":"Новая пометка","city":"Томск","life":"действует","verification":"что-то новое"},
     {"placeId":"x5","name":"Без номера места","city":"Томск"}
    ]}
    """#

    @Test func readsFormatOne() throws {
        let c = try #require(PlaceCatalogFile.decode(Data(Self.sample.utf8)))
        #expect(c.etag == 7 && c.asOf == "2026-11-05")
        #expect(c.places.map(\.id) == ["pl100001", "pl900002", "pl900003", "pl900004"])
        let t = c.places[0]
        #expect(t.check == .verified && !t.closed && t.timezone == "Asia/Tomsk")
        #expect(t.halls == [CatalogPlace.Hall(number: 1, name: "Эдисон")])   // архивный зал не предлагается
        let u = c.places[1]
        #expect(u.closed && u.check == .collected && u.address.isEmpty)
        #expect(u.halls.isEmpty)          // hallsCount без названий — залов нет
        #expect(u.timezone == nil)        // неизвестный пояс отброшен
        #expect(c.places[2].check == .disputed && c.places[2].mergedInto == "pl900002")
    }

    @Test func unknownVerificationIsNeverShownAsVerified() throws {
        let c = try #require(PlaceCatalogFile.decode(Data(Self.sample.utf8)))
        #expect(c.places[3].check == .collected)
    }

    @Test func anotherFormatOrGarbageIsNoList() {
        #expect(PlaceCatalogFile.decode(Data(#"{"format":2,"places":[]}"#.utf8)) == nil)
        #expect(PlaceCatalogFile.decode(Data(#"{"places":[]}"#.utf8)) == nil)
        #expect(PlaceCatalogFile.decode(Data("not json".utf8)) == nil)
        #expect(PlaceCatalogFile.decode(Data(#"{"format":1,"places":[{"name":"без номера"}]}"#.utf8)) == nil)
    }

    @Test func sourceWithoutBytesGivesNoList() async {
        #expect(await FixedPlaceCatalog(nil).load() == nil)
        #expect(await FixedPlaceCatalog(Data(Self.sample.utf8)).load()?.places.count == 4)
    }

    @Test func bundleWithoutTheFileGivesNoList() async {
        // Пакет тестов не несёт `places_served.json`: так выглядит сборка из чистого git.
        #expect(await BundledPlaceCatalog(bundle: Bundle(for: Probe.self)).data() == nil)
    }
    private final class Probe {}

    /// Настоящий файл ядра, если указан (`LP_PLACES_FILE=…/places_served_*.json swift test`): в git его
    /// нет, поэтому без переменной проверка молчит. Числа не зашиты — файл меняется.
    @Test func realServedFileReadsWhole() throws {
        guard let path = ProcessInfo.processInfo.environment["LP_PLACES_FILE"] else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let c = try #require(PlaceCatalogFile.decode(data))
        let head = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(c.places.count == (head?["count"] as? Int))
        #expect(c.places.filter { $0.check == .verified }.allSatisfy { !$0.closed })
        #expect(c.places.first { $0.id == "pl100001" }?.name == "Томсон")
        print("real file: \(c.places.count) places, closed \(c.places.filter(\.closed).count), verified \(c.places.filter { $0.check == .verified }.count), disputed \(c.places.filter { $0.check == .disputed }.count)")
    }
}
