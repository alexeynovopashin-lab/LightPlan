import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Шаг 30д: время новой записи и всплывашки в живой модели приложения.
/// Москва, 10.11.2026: золотой час с 15:31, закат 16:32, синий до 16:57 (замер 04.11, модель приложения).
@MainActor
struct FormShootTimeFlowTests {
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
    private final class Disk: DraftStoring, @unchecked Sendable {
        var data: Data?
        func load() -> Data? { data }
        func save(_ data: Data?) { self.data = data }
    }

    private let day = CivilDate(year: 2026, month: 11, day: 10)

    private func app(_ sessions: [Session] = []) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00+03:00")!
        var snap = Snapshot()
        snap.sessions = sessions
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather(),
                           now: { now })
        app.draftStore = Disk()
        return app
    }

    private func golden(_ app: AppModel) throws -> Int {
        Int(try #require(SolarDay(date: day, place: app.place.place).goldenB).rounded())
    }

    private func shoot(_ id: String, _ from: Int, _ to: Int) -> Session {
        Session(id: id, kind: .shoot, day: day, start: from, end: to, duration: to - from, genre: .portrait)
    }

    @Test("первая съёмка дня — полдень, следующая — сразу после предыдущей")
    func defaultTime() {
        let a = app()
        a.openForm(day: day)
        #expect(a.form?.start == 720 && a.form?.timeIsProposed == true)
        let b = app([shoot("x", 720, 780)])
        b.openForm(day: day)
        #expect(b.form?.start == 780)
    }

    @Test("смена дня двигает непредложенное время за днём")
    func dayChangeFollows() {
        let a = app([shoot("x", 720, 780)])
        a.openForm(day: day.adding(days: 1))
        #expect(a.form?.start == 720)
        a.pickFormDay(day)
        #expect(a.form?.start == 780 && a.formTimeAsk == nil)
    }

    @Test("«Закат» на непредложенном времени — сразу золотой час с подсветкой")
    func proposedFollowsSunset() throws {
        let a = app()
        let g = try golden(a)
        a.openForm(day: day)
        a.toggleFormWish(.sunset)
        #expect(a.form?.start == g && a.form?.timeShifted == true && a.formTimeAsk == nil)
        a.toggleFormWish(.sunset)
        #expect(a.form?.start == 720 && a.form?.timeShifted == false)
    }

    @Test("15:00 и «Закат»: всплывашка; сдвинули — золотой час")
    func namedAsks() throws {
        let a = app()
        let g = try golden(a)
        a.openForm(day: day, start: 840, fromLight: false)
        a.toggleFormWish(.sunset)
        let ask = try #require(a.formTimeAsk)
        #expect(ask.to == g && ask.keep == 840 && a.form?.start == 840)
        let w = a.formTimeAskWords(ask)
        #expect(w.title.hasPrefix("Закат в ") && w.question.contains("Сдвинуть начало на") && w.keep == "Оставить 14:00")
        a.answerFormTime(ask, move: true)
        #expect(a.form?.start == g && a.formTimeAsk == nil && a.form?.timeShifted == false)
    }

    @Test("«Оставить» — больше не спрашивает, пока «Закат» не нажат заново")
    func keepIsRemembered() throws {
        let a = app()
        a.openForm(day: day, start: 840, fromLight: false)
        a.toggleFormWish(.sunset)
        a.answerFormTime(try #require(a.formTimeAsk), move: false)
        a.form?.setStart(minute: 800)
        a.formTimeSettled()
        #expect(a.formTimeAsk == nil && a.form?.start == 800)
    }

    @Test("после заката — сдвиг без вопроса и подсветка")
    func lateShifts() throws {
        let a = app()
        let g = try golden(a)
        a.openForm(day: day, start: 21 * 60, fromLight: false)
        a.toggleFormWish(.sunset)
        #expect(a.formTimeAsk == nil && a.form?.start == g && a.form?.timeShifted == true)
    }

    @Test("наложение: «Занято до 13:00», ставим на конец занятого")
    func overlapAsks() throws {
        let a = app([shoot("x", 720, 780)])
        a.openForm(day: day, start: 750, fromLight: false)
        a.formTimeSettled()
        let ask = try #require(a.formTimeAsk)
        let w = a.formTimeAskWords(ask)
        #expect(w.title == "Занято до 13:00" && w.question == "Поставить на 13:00?" && w.keep == "Оставить 12:30")
        a.answerFormTime(ask, move: true)
        #expect(a.form?.start == 780)
    }

    @Test("жанр удлинил названную съёмку до чужой записи — спрашивает; длительность та же — молчит")
    func genreDurationAsks() throws {
        let a = app([shoot("x", 840, 900)])
        a.openForm(day: day, start: 720, fromLight: false)
        a.pickFormGenre(.wedding)                               // 12:00–20:00 накрывает 14:00–15:00
        #expect(a.form?.start == 720)
        let ask = try #require(a.formTimeAsk)
        #expect(ask.kind == .busy && ask.at == 900)
        let b = app([shoot("x", 840, 900)])
        b.openForm(day: day, start: 720, fromLight: false)
        b.pickFormGenre(.portrait, sub: nil)                    // жанр тот же: вопроса нет
        #expect(b.formTimeAsk == nil)
    }

    @Test("следующий вопрос встаёт только над той же формой")
    func nextAskStaysWithItsForm() async throws {
        let spot = try golden(app())
        let a = app([shoot("x", spot, spot + 60)])
        a.openForm(day: day, start: 840, fromLight: false)
        a.toggleFormWish(.sunset)
        a.answerFormTime(try #require(a.formTimeAsk), move: true)
        try await Task.sleep(for: .milliseconds(100))           // отложенный вопрос встал в очередь главного актора раньше
        #expect(a.formTimeAsk?.kind == .busy)                   // та же форма: вопрос о наложении дошёл

        let b = app([shoot("x", spot, spot + 60)])
        b.openForm(day: day, start: 840, fromLight: false)
        b.toggleFormWish(.sunset)
        b.answerFormTime(try #require(b.formTimeAsk), move: true)
        b.closeForm()                                           // за этот такт форму закрыли и открыли другую
        b.draftStore.save(nil)
        b.openForm(day: day.adding(days: 1))
        try await Task.sleep(for: .milliseconds(100))           // отложенный вопрос встал в очередь главного актора раньше
        #expect(b.formTimeAsk == nil)
    }

    @Test("запись при правке сама с собой не спорит")
    func editingIgnoresItself() {
        let a = app([shoot("x", 720, 780)])
        a.openForm(editing: "x")
        a.form?.setStart(minute: 730)
        a.formTimeSettled()
        #expect(a.formTimeAsk == nil)
    }

    @Test("рассвет и звёзды говорят своими словами на всех языках")
    func wordsExist() throws {
        for lang in ["ru", "en", "es", "ja", "zh"] {
            let a = AppModel(snapshot: Snapshot(), store: nil, language: lang, zone: TimeZone(identifier: "Europe/Moscow")!,
                             locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
            for k in ["wish.sunrise", "wc.noSunriseT", "wc.noSunriseM", "time.sunsetT", "time.sunriseT", "time.starsT", "time.moveQ",
                      "time.move", "time.keep", "time.busyT", "time.busyQ", "time.busyGo"] {
                #expect(a.lexicon.t(k) != k, "\(lang) \(k)")
            }
        }
    }
}
