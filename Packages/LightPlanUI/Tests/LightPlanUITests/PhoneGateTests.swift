import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг 30ж.1 (Алексей 05.11): «Свету» номер не нужен, планировщику обязателен. Первый запуск спрашивает только
/// город; на всех путях к съёмке стоит лист «Ваш номер»; записи без номера лежат на месте. Номера вымышленные.
@MainActor
struct PhoneGateTests {

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

    private static let mobile = "+7 900 000-00-00"
    private static let landline = "+7 495 000-00-00"
    private static let shootDay = CivilDate(year: 2026, month: 11, day: 20)

    /// Живое правило включено, как в `live()`. Россия: страну не угадываем по часовому поясу машины.
    private func model(_ snapshot: Snapshot = Snapshot(), gate: Bool = true) -> AppModel {
        var s = snapshot
        s.extra["telCountry"] = .string("RU")
        let app = AppModel(snapshot: s, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather(),
                           now: { ISO8601DateFormatter().date(from: "2026-11-05T12:00:00+07:00")! })
        app.plannerNeedsPhone = gate
        app.draftStore = MemoryDraftStore()          // черновик формы не должен пережить тест в UserDefaults
        return app
    }

    /// Человек с двумя записями (съёмка и встреча) и без номера.
    private func withRecords(_ extra: (inout Snapshot) -> Void = { _ in }) -> AppModel {
        var snap = Snapshot()
        snap.extra["me"] = .object(["met": .bool(true)])
        var shoot = Session(id: "s1", kind: .shoot, day: Self.shootDay, start: 720, end: 840, duration: 120, genre: .portrait)
        shoot.persons = [Person(name: "Ирина", phone: "+7 900 000-00-11")]
        snap.sessions = [shoot, Session(id: "m1", kind: .meet, day: Self.shootDay, start: 900, end: 960, duration: 60, genre: .wedding)]
        extra(&snap)
        return model(snap)
    }

    /// Ответ клиента в ссылке, как у `QuestSheetTests`.
    private static func questCode(_ obj: [String: String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Ввод в поле и «Готово»; лист ушёл с экрана.
    private func answer(_ app: AppModel, _ number: String = mobile) {
        #expect(app.phoneAskOpen, "лист должен быть открыт")
        app.setMyPhone(number)
        app.confirmPhoneAsk()
        #expect(!app.phoneAskOpen, "«Готово» с номером закрывает лист")
        app.phoneSheetGone()
    }

    /// Крестик; лист ушёл с экрана.
    private func cross(_ app: AppModel) {
        #expect(app.phoneAskOpen, "лист должен быть открыт")
        app.cancelPhoneAsk()
        #expect(!app.phoneAskOpen)
        app.phoneSheetGone()
    }

    // MARK: - Первый запуск: только город

    @Test func newPersonSeesOnlyTheCityAndThenLight() {
        let app = model()
        #expect(app.showStartSheet)
        #expect(!app.phoneAskOpen, "первый запуск номер не спрашивает")
        app.finishStart()
        #expect(!app.showStartSheet)
        #expect(!app.phoneAskOpen, "после города лист номера не появляется")
        #expect(app.tab == .light, "сразу «Свет»")
        #expect(app.myPhone.isEmpty)
    }

    @Test func startSubtitleSaysNothingAboutANumberInAnyLanguage() throws {
        let catalog = TrueStringsTests.catalog
        let sub = try TrueStringsTests.values(catalog, "start.sub")
        let number = ["ru": "номер", "en": "number", "es": "número", "ja": "電話", "zh": "电话"]
        #expect(Set(sub.keys).isSuperset(of: number.keys))
        for (lang, word) in number { #expect(sub[lang]?.contains(word) == false, "\(lang): \(sub[lang] ?? "")") }
        for key in ["phone.title", "phone.why"] {
            let v = try TrueStringsTests.values(catalog, key)
            #expect(Set(v.keys).isSuperset(of: number.keys), "\(key): не все языки")
        }
    }

    // MARK: - Вкладка

    @Test func plannerTabAsksAndNothingElseDoes() {
        let app = model()
        app.finishStart()
        for free in [AppTab.map, .settings, .light] {
            app.openTab(free)
            #expect(app.tab == free)
            #expect(!app.phoneAskOpen, "\(free) работает без номера")
        }
        app.openTab(.planner)
        #expect(app.tab == .light, "пока номера нет, вкладка не меняется")
        #expect(app.phoneAskOpen)
    }

    @Test func enteringTheNumberOpensThePlannerAndAsksNoMore() {
        let app = model()
        app.openTab(.map)
        app.openTab(.planner)
        answer(app)
        #expect(app.tab == .planner, "после «Готово» человек там, куда шёл")
        #expect(app.myPhone == Self.mobile)
        #expect(app.myAppId == "id79000000000")
        app.openTab(.settings)
        app.openTab(.planner)
        #expect(app.tab == .planner)
        #expect(!app.phoneAskOpen, "второй раз не спрашивает")
    }

    @Test func doneWorksOnlyWithANumber() {
        let app = model()
        app.openTab(.planner)
        app.confirmPhoneAsk()
        #expect(app.phoneAskOpen, "пустое поле: «Готово» не работает")
        for bad in ["+7 900", "+7 900 000-00", Self.landline] {
            app.setMyPhone(bad)
            app.confirmPhoneAsk()
            #expect(app.phoneAskOpen, "\(bad): «Готово» не работает")
        }
        app.setMyPhone(Self.mobile)
        app.confirmPhoneAsk()
        #expect(!app.phoneAskOpen)
    }

    @Test func crossReturnsToTheSameScreenAndWritesNothing() {
        let app = model()
        app.openTab(.map)
        app.openTab(.planner)
        app.setMyPhone("+7 900 00")
        cross(app)
        #expect(app.tab == .map, "крестик возвращает на прежний экран")
        #expect(app.myPhone.isEmpty, "набранное не остаётся")
        #expect(app.form == nil && app.cardId == nil)
        app.openTab(.planner)
        #expect(app.phoneAskOpen, "спросит снова")
    }

    /// Ответ на ревью GPT к b3c0fa3: страна на листе меняется сразу, отказ возвращает и её. Номер без кода читается
    /// по стране, поэтому оставшаяся чужая страна поменяла бы его смысл.
    @Test func crossRestoresTheCountryToo() {
        var snap = Snapshot()
        snap.extra["me"] = .object(["met": .bool(true), "phone": .string("495 000-00-00")])
        let app = model(snap)
        app.openTab(.planner)
        app.setTelCountry(TelCountry.of("GE")!)
        app.setMyPhone("+995 555 00 00 00")
        cross(app)
        #expect(app.telCountry.iso == "RU")
        #expect(app.myPhone == "495 000-00-00")

        app.snapshot.extra["telCountry"] = nil         // страна ещё не выбрана: так и остаётся
        app.openTab(.planner)
        app.setTelCountry(TelCountry.of("GE")!)
        cross(app)
        #expect(app.snapshot.extra["telCountry"] == nil)

        // «Готово» страну, наоборот, оставляет: номер теперь её.
        app.openTab(.planner)
        app.setTelCountry(TelCountry.of("GE")!)
        answer(app, "+995 555 00 00 00")
        #expect(app.telCountry.iso == "GE")
    }

    /// Смахивание листа без «Готово» (то же `phoneSheetGone`), даже с целым номером в поле, — отказ.
    @Test func swipingAwayWithAFullNumberIsARefusalToo() {
        let app = model()
        app.openTab(.planner)
        app.setMyPhone(Self.mobile)
        app.phoneAskOpen = false
        app.phoneSheetGone()
        #expect(app.tab == .light)
        #expect(app.myPhone.isEmpty)
    }

    // MARK: - Остальные пути к съёмке: каждый спрашивает, крестик никуда не ведёт, «Готово» доводит до места

    @Test func lightButtonKeepsItsTimeThroughTheSheet() {
        let app = withRecords()
        app.openForm(day: Self.shootDay, start: 17 * 60 + 30, fromLight: true)
        #expect(app.form == nil)
        #expect(app.phoneAskOpen)
        cross(app)
        #expect(app.form == nil)
        #expect(app.tab == .light)

        app.openForm(day: Self.shootDay, start: 17 * 60 + 30, fromLight: true)
        answer(app)
        #expect(app.form?.day == Self.shootDay)
        #expect(app.form?.start == 17 * 60 + 30, "время с ползунка «Света» дошло до формы")
        #expect(app.tab == .light, "кнопка «Света» вкладку не меняла и не меняет")
    }

    @Test func formWithDefaultsAndMeetingModeAsk() {
        let app = withRecords()
        app.openForm(day: Self.shootDay, start: 840, fromLight: false, mode: .meet)
        #expect(app.form == nil && app.phoneAskOpen)
        answer(app)
        #expect(app.form?.mode == .meet)
    }

    @Test func hourMenuAsks() {
        let app = withRecords()
        app.openFromSlot(.shoot, day: Self.shootDay, at: 600)
        #expect(app.form == nil && app.phoneAskOpen)
        answer(app)
        #expect(app.form?.start == 600)
    }

    @Test func mapRouteKeepsTheRouteUntilTheAnswer() {
        var snap = Snapshot()
        snap.extra["me"] = .object(["met": .bool(true)])
        let app = model(snap)
        var ids: [String] = []
        for (i, lat) in [53.3480, 53.3570].enumerated() {
            app.moveFromMap(latitude: lat, longitude: 83.7760)
            ids.append(app.routeAddHere(now: Date(timeIntervalSince1970: 1_790_000_000 + Double(i))).spot.id)
        }
        app.openTab(.map)
        app.lastFormGenre = .wedding
        var made = 0

        #expect(!app.makeRouteShoot(day: Self.shootDay, made: { made += 1 }))
        #expect(app.tab == .map && app.form == nil && app.phoneAskOpen)
        cross(app)
        #expect(made == 0 && app.form == nil)
        #expect(app.tab == .map, "«Карта» работает без номера, крестик возвращает на неё")
        #expect(app.mapRoute == ids, "маршрут цел")

        #expect(!app.makeRouteShoot(day: Self.shootDay, made: { made += 1 }))
        answer(app)
        #expect(made == 1, "режим маршрута закрывается только сейчас")
        #expect(app.form?.route.compactMap(\.spotId) == ids)
    }

    @Test func existingShootOpensOnlyThroughTheSheet() {
        let app = withRecords()
        app.openCard(id: "s1")
        #expect(app.cardId == nil && app.phoneAskOpen)
        cross(app)
        #expect(app.cardId == nil)
        app.openCard(id: "s1", stack: .debts)
        answer(app)
        #expect(app.cardId == "s1")
        #expect(app.cardStackMode == .debts, "стопка не потерялась")
    }

    @Test func editingAnExistingShootAsks() {
        let app = withRecords()
        app.openForm(editing: "s1")
        #expect(app.form == nil && app.phoneAskOpen)
        answer(app)
        #expect(app.form?.id == "s1")
    }

    /// Виджет и событие Календаря: `lightplan://shoot/<id>`. Ссылка своя, значит «обработано»: квесту не достаётся.
    @Test func shootLinkAsksAndStaysHandled() {
        let app = withRecords()
        #expect(app.openShootLink(WidgetFeed.shootURL("s1")))
        #expect(app.cardId == nil && app.phoneAskOpen)
        answer(app)
        #expect(app.cardId == "s1")
    }

    /// Виджет свободного дня: `lightplan://day/…`.
    @Test func dayLinkAsksAndKeepsTheScreen() {
        let app = model()
        app.finishStart()
        app.openTab(.map)
        let url = URL(string: "lightplan://day/2026-11-20")!
        #expect(app.openDayLink(url), "ссылка своя, дальше не идёт")
        #expect(app.tab == .map && app.phoneAskOpen)
        cross(app)
        #expect(app.tab == .map)
        #expect(app.openDayLink(url))
        answer(app)
        #expect(app.tab == .planner)
        #expect(app.planner.selected == Self.shootDay)
    }

    /// Нажатие на уведомление и баннер: `openFromNotice`.
    @Test func notificationAsks() {
        let app = withRecords()
        app.openFromNotice("s1")
        #expect(app.cardId == nil && app.phoneAskOpen)
        answer(app)
        #expect(app.cardId == "s1")
    }

    /// Ответ клиента по ссылке: ждёт в черновике, крестик его не теряет, после «Готово» ложится на запись.
    @Test func clientAnswerWaitsForTheNumber() {
        let app = withRecords()
        let answerCode = Self.questCode(["g": "Слава"])
        let url = URL(string: "lightplan://quest?ans=\(answerCode)&r=m1")!
        #expect(app.openQuestLink(url) == .held)
        #expect(app.form == nil && app.phoneAskOpen)
        cross(app)
        #expect(app.form == nil)
        #expect(app.questWaiting.map(\.recordId) == ["m1"], "ответ не потерян")
        #expect(app.openQuestLink(url) == .held)
        answer(app)
        #expect(app.form?.id == "m1")
    }

    /// Съёмка из списка «Контакты», карточки организации и клиента: сначала лист, слои стоят — крестик вернёт на них.
    @Test func contactsRowKeepsTheListUnderTheSheet() throws {
        let app = withRecords()
        app.openContacts()
        let row = try #require(app.contacts.flatMap(\.rows).first { if case .shoot = $0.card { true } else { false } })
        app.openContact(row)
        #expect(app.org.contactsOpen, "список на месте")
        #expect(app.cardId == nil && app.phoneAskOpen)
        cross(app)
        #expect(app.org.contactsOpen && app.cardId == nil)
        app.openContact(row)
        answer(app)
        #expect(!app.org.contactsOpen && app.cardId == "s1")
    }

    @Test func orgShootKeepsTheOrgUnderTheSheet() {
        let app = withRecords()
        app.openOrgs()
        app.openOrgShoot("s1")
        #expect(app.org.listOpen, "список на месте")
        #expect(app.cardId == nil && app.phoneAskOpen)
        answer(app)
        #expect(!app.org.listOpen && app.cardId == "s1")
    }

    @Test func clientShootKeepsTheClientsUnderTheSheet() {
        let app = withRecords()
        app.openClients()
        app.openClientShoot("s1")
        #expect(app.org.listOpen, "список на месте")
        #expect(app.cardId == nil && app.phoneAskOpen)
        cross(app)
        #expect(app.org.listOpen && app.cardId == nil)
    }

    /// Открытые листом два пути подряд: человек идёт туда, куда пошёл последним.
    @Test func theLastPathWins() {
        let app = withRecords()
        app.openTab(.planner)
        app.openCard(id: "s1")
        answer(app)
        #expect(app.cardId == "s1")
        #expect(app.tab == .light)
    }

    // MARK: - Записи без номера

    @Test func recordsStayExactlyAsTheyWereThroughAllOfIt() throws {
        let app = withRecords()
        let coder = JSONEncoder()
        coder.outputFormatting = .sortedKeys      // иначе порядок ключей у словарей плавает между вызовами
        let before = try coder.encode(app.snapshot.sessions)
        app.openCard(id: "s1")
        cross(app)
        #expect(try coder.encode(app.snapshot.sessions) == before, "крестик")
        app.openTab(.planner)
        answer(app)
        #expect(try coder.encode(app.snapshot.sessions) == before, "ввод номера")
        #expect(app.snapshot.sessions.count == 2)
        app.openCard(id: "s1")
        #expect(app.cardId == "s1", "после ввода всё как раньше")
        #expect(!app.phoneAskOpen)
    }

    // MARK: - Номер удалён, номер городской

    @Test func deletedNumberAsksAtTheNextEntry() {
        var snap = Snapshot()
        snap.extra["me"] = .object(["met": .bool(true), "phone": .string(Self.mobile)])
        let app = model(snap)
        app.openTab(.planner)
        #expect(app.tab == .planner && !app.phoneAskOpen, "номер есть, листа нет")

        app.openTab(.settings)                // «Профиль» живёт в «Настройках»
        app.setMyPhone("")
        app.commitMyPhone()
        #expect(!app.phoneAskOpen, "сам лист не вылезает, пока человек в настройках")
        app.openTab(.planner)
        #expect(app.tab == .settings && app.phoneAskOpen, "следующий вход спрашивает")
        answer(app, "+7 900 000-00-22")
        #expect(app.tab == .planner)
        #expect(app.myPhone == "+7 900 000-00-22")
    }

    @Test func landlineFromTheProfileIsOfferedAgainAndCrossKeepsIt() {
        var snap = Snapshot()
        snap.extra["me"] = .object(["met": .bool(true), "phone": .string(Self.landline)])
        let app = model(snap)
        app.openTab(.planner)
        #expect(app.phoneAskOpen, "из городского нет ID приложения")
        #expect(app.tab == .light)
        app.setMyPhone(Self.mobile)
        cross(app)
        #expect(app.myPhone == Self.landline, "крестик вернул то, что было")
        #expect(app.myPreviousIds.isEmpty, "смены номера не было")

        app.openTab(.planner)
        answer(app)
        #expect(app.myPhone == Self.mobile)
        #expect(app.tab == .planner)
    }

    /// «Готово» фиксирует номер как уход из поля в «Профиле»: смена с одного мобильного на другой оставляет прежний ID.
    @Test func doneCommitsLikeTheProfileField() {
        var snap = Snapshot()
        snap.extra["me"] = .object(["met": .bool(true), "phone": .string("+7 900 000")])
        let app = model(snap)
        app.openTab(.planner)
        answer(app)
        #expect(app.telSnap == Self.mobile, "номер зафиксирован")
    }

    // MARK: - Снимки и тесты без листа

    /// Снимки пар и засевы (`-LPShotSeed`) строят модель сами: правило выключено, в лист не упираются.
    @Test func gateIsOffUnlessLiveTurnsItOn() {
        let app = model(gate: false)
        #expect(!AppModel.init(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                               locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather()).plannerNeedsPhone)
        app.openTab(.planner)
        #expect(app.tab == .planner && !app.phoneAskOpen)
        app.openForm(day: Self.shootDay)
        #expect(app.form != nil && !app.phoneAskOpen)
    }

    /// Выпуск должен включать правило: `live()` не вызвать из теста (пишет в папку приложения), поэтому читаем его текст.
    @Test func liveTurnsTheGateOn() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LightPlanUI/App/AppModel.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let live = try #require(text.range(of: "public static func live() async -> AppModel"))
        let body = text[live.upperBound...].prefix(6000)
        #expect(body.contains("model.plannerNeedsPhone = true"))
    }
}
