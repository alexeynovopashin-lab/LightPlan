import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 27, шаг 3: блок «Референсы» — только строка; документы открываются
/// из блока, ошибка «Файл не открылся» — в самой карточке (ошибка веба 22).
@MainActor
struct CardRefsTests {

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

    private static let day = CivilDate(year: 2026, month: 9, day: 20)

    private func wedding(docs: [LightPlanDomain.Attachment] = []) -> Session {
        var w = Session(id: "w", kind: .shoot, day: Self.day, start: 600, end: 1380, duration: 780, genre: .wedding)
        w.route = [RoutePoint(start: 660, end: 750, name: "Сборы"), RoutePoint(start: 1020, end: 1200, name: "Банкет")]
        w.docs = docs
        return w
    }

    private func shot(_ id: String) -> JSONValue { .object(["id": .string(id), "k": .string("img"), "im": .string(id)]) }
    private func board(_ kind: String, _ items: [String], sid: String? = nil, genre: String = "wedding") -> JSONValue {
        var o: [String: JSONValue] = ["kind": .string(kind), "genre": .string(genre),
                                      "items": .array(items.map { .string($0) })]
        if let sid { o["sid"] = .string(sid) }
        return .object(o)
    }

    private func model(_ s: Session, own: [String] = ["a", "b"], set: [String] = ["b", "c", "d"],
                       at iso: String = "2026-09-20T09:00:00+03:00") -> AppModel {
        var snap = Snapshot()
        snap.sessions = [s]
        snap.extra["shots"] = .array(["a", "b", "c", "d"].map(shot))
        var boards: [JSONValue] = []
        if !own.isEmpty { boards.append(board("shoot", own, sid: s.id)) }
        if !set.isEmpty { boards.append(board("tpl", set)) }
        snap.extra["boards"] = .array(boards)
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    // MARK: набор и строка

    @Test func rowCountsOwnPlusGenreSetOnce() {
        let s = wedding(); let app = model(s)
        // свои a, b + набор b, c, d: кадр b — один раз, всего 4
        #expect(app.cardRefs(s).map(\.id) == ["a", "b", "c", "d"])
        let r = app.cardRefsRow(app.sessions[0])!
        #expect(r.count == 4)
        #expect(r.sub == "4 кадра · набор жанра и съёмки")
        #expect(r.title == "Референсы")
    }

    @Test func rowNamesCurrentPointDuringShoot() {
        let s = wedding(); let app = model(s, at: "2026-09-20T18:00:00+03:00")
        #expect(app.cardRefsRow(s)!.title == "Референсы: Банкет")
    }

    @Test func blockIsThereOnlyWithFramesAndNotAfter() {
        let s = wedding()
        #expect(model(s).cardBlocks(s, phase: .before).contains(.refs))
        #expect(!model(s, own: [], set: []).cardBlocks(s, phase: .before).contains(.refs))
        #expect(model(s, own: [], set: []).cardRefsRow(s) == nil)
        #expect(!model(s).cardBlocks(s, phase: .after).contains(.refs))
    }

    @Test func emptyStatesOnlySetOnlyOwn() {
        let s = wedding()
        let onlySet = model(s, own: [], set: ["c", "d"])
        #expect(onlySet.cardRefsRow(s)!.count == 2)
        #expect(onlySet.cardRefs(s).allSatisfy { !$0.own })
        let onlyOwn = model(s, own: ["a"], set: [])
        #expect(onlyOwn.cardRefsRow(s)!.count == 1)
        #expect(onlyOwn.cardRefs(s).allSatisfy { $0.own })
    }

    @Test func otherGenreSetDoesNotLeakIn() {
        var s = wedding(); s.genre = .portrait
        let app = model(s, own: [], set: ["c"])   // набор лежит у «wedding»
        #expect(app.cardRefsRow(s) == nil)
    }

    // MARK: документы

    @Test func tapOnLinkDocumentOpensItsAddress() {
        let d = LightPlanDomain.Attachment(source: .link, name: "Договор", url: "https://disk.example.com/i/dogovor.pdf")
        let s = wedding(docs: [d]); let app = model(s)
        #expect(app.openCardDoc(d) == .url(URL(string: "https://disk.example.com/i/dogovor.pdf")!))
        #expect(app.cardDocMessage == nil)
    }

    @Test func tapOnCloudFileShowsMessageInCardAndNextTapClearsIt() {
        let file = LightPlanDomain.Attachment(source: .doc, path: "docs/smeta.xlsx", name: "смета.xlsx", size: 20480)
        let link = LightPlanDomain.Attachment(source: .link, url: "https://x.example.com/a")
        let s = wedding(docs: [file, link]); let app = model(s)
        #expect(app.openCardDoc(file) == .failed)
        #expect(app.cardDocMessage == "Файл не открылся: нет связи с Диском.")
        _ = app.openCardDoc(link)
        #expect(app.cardDocMessage == nil)
    }

    @Test func documentWithoutPathAndAddressDoesNothing() {
        let d = LightPlanDomain.Attachment(source: .doc, name: "пусто")
        let s = wedding(docs: [d]); let app = model(s)
        #expect(app.openCardDoc(d) == .none)
        #expect(app.cardDocMessage == nil)
    }

    @Test func messageGoesWhenCardCloses() {
        let file = LightPlanDomain.Attachment(source: .doc, path: "p", name: "a.pdf")
        let s = wedding(docs: [file]); let app = model(s)
        _ = app.openCardDoc(file)
        app.closeCard()
        #expect(app.cardDocMessage == nil)
    }
}
