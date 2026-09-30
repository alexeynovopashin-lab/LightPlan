import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 28, шаг 6: организации в хозяине приложения — черновик, пустая не остаётся,
/// связь съёмка ↔ организация, строка списка, бумаги, удаление, открытие съёмки.
@MainActor
struct OrgStateTests {

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

    private func shoot(_ id: String, _ d: Int, org: String?, rate: Decimal? = nil, prepay: Decimal = 0) -> Session {
        var s = Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 10, day: d), start: 600, end: 720, duration: 120, genre: .wedding)
        s.orgId = org
        if let rate { s.pay = .flat; s.rate = rate }
        s.prepay = prepay
        return s
    }

    private func model(orgs: [Org] = [], sessions: [Session] = []) -> AppModel {
        var snap = Snapshot()
        snap.orgs = orgs
        snap.sessions = sessions
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func named(_ id: String, _ name: String) -> Org { var o = Org(id: id); o.name = name; return o }

    // MARK: пустая организация не остаётся (ошибка веба 24)

    @Test func plusOrgOpensADraftAndLeavesTheDataUntouched() {
        let app = model()
        app.newOrg()
        #expect(app.org.cardId != nil && app.org.draft?.id == app.org.cardId)
        #expect(app.orgs.isEmpty, "пока ничего не введено, в данных ничего нет")
    }

    @Test func closingAnUntouchedDraftLeavesNoOrgBehind() {
        let app = model()
        app.newOrg()
        app.closeOrgCard()
        #expect(app.orgs.isEmpty && app.org.draft == nil && app.org.cardId == nil)
    }

    @Test func spacesAreNotAnEntryEither() {
        let app = model()
        app.newOrg()
        let id = app.org.cardId!
        app.editOrg(id) { $0.name = "   " }
        app.closeOrgCard()
        #expect(app.orgs.isEmpty)
    }

    @Test func firstWordMovesTheDraftIntoDataOnceAndItStays() {
        let app = model()
        app.newOrg()
        let id = app.org.cardId!
        app.editOrg(id) { $0.name = "О" }
        app.editOrg(id) { $0.name = "Ромашка" }
        #expect(app.orgs.map(\.name) == ["Ромашка"] && app.org.draft == nil, "одна запись, не по записи на каждую букву")
        #expect(app.orgs[0].modifiedAt != nil, "правка помечена для слияния")
        app.closeOrgCard()
        #expect(app.orgs.map(\.name) == ["Ромашка"])
    }

    @Test func wipingAnExistingOrgWithoutShootsRemovesItButOneWithShootsStays() {
        let app = model(orgs: [named("a", "Пустеющая"), named("b", "Держится")],
                        sessions: [shoot("s1", 5, org: "b")])
        app.openOrgCard(id: "a"); app.editOrg("a") { $0.name = "" }; app.closeOrgCard()
        app.openOrgCard(id: "b"); app.editOrg("b") { $0.name = "" }; app.closeOrgCard()
        #expect(app.orgs.map(\.id) == ["b"], "за «b» числится съёмка: заказчика не теряем")
    }

    @Test func aRemovedEmptyOrgIsBuriedSoAnotherDeviceDoesNotReturnIt() {
        let app = model(orgs: [named("a", "X")])
        app.openOrgCard(id: "a"); app.editOrg("a") { $0.name = "" }; app.closeOrgCard()
        guard case .array(let graves)? = app.snapshot.extra["graves"] else { Issue.record("нет могил"); return }
        #expect(graves.contains { if case .object(let o) = $0 { o["id"] == .string("a") } else { false } })
    }

    // MARK: связь съёмка ↔ организация

    @Test func listLineShowsPersonShootCountAndIncome() {
        var o = named("o1", "Агентство"); o.person = "Ольга Титова"
        let app = model(orgs: [o], sessions: [shoot("a", 24, org: "o1", rate: 100_000), shoot("b", 21, org: "o1", rate: 83_000), shoot("c", 3, org: nil, rate: 5)])
        let line = app.orgSubtitle(o)
        #expect(line.hasPrefix("Ольга Титова · 2 съёмки · "), "лицо · число съёмок · суммы: \(line)")
        #expect(line.contains("183") && line.contains("₽"))
        #expect(app.orgSubtitle(named("empty", "")) == app.lexicon.t("org.noReq"), "ничего не задано — «реквизиты не заполнены»")
        #expect(app.orgTitle(Org(id: "x")) == app.lexicon.t("org.noName"))
    }

    @Test func shootMoneyLineShowsSumAndPrepayOnlyIfSmaller() {
        let app = model(orgs: [named("o1", "A")])
        #expect(app.orgShootMoney(shoot("a", 1, org: "o1")) == app.lexicon.t("org.noSum"))
        let part = app.orgShootMoney(shoot("b", 2, org: "o1", rate: 50_000, prepay: 20_000))
        #expect(part.contains("50") && part.contains("внесено") && part.contains("20"), "сумма и «внесено N»: \(part)")
        let full = app.orgShootMoney(shoot("c", 3, org: "o1", rate: 50_000, prepay: 50_000))
        #expect(!full.contains("внесено"), "предоплата не меньше суммы — не показываем")
    }

    @Test func deletingAnOrgKeepsShootsButDropsTheLinkAndBuriesTheKey() {
        var s = shoot("a", 24, org: "o1"); s.contact = "Ольга"
        let app = model(orgs: [named("o1", "A"), named("o2", "B")], sessions: [s, shoot("b", 25, org: "o2")])
        app.openOrgCard(id: "o1")
        #expect(app.orgShootCount("o1") == 1)
        app.deleteOrg("o1")
        #expect(app.orgs.map(\.id) == ["o2"] && app.org.cardId == nil)
        #expect(app.sessions.first { $0.id == "a" }?.orgId == nil && app.sessions.first { $0.id == "a" }?.contact == "Ольга")
        #expect(app.sessions.first { $0.id == "b" }?.orgId == "o2")
        guard case .array(let graves)? = app.snapshot.extra["graves"] else { Issue.record("нет могил"); return }
        #expect(graves.count == 1)
    }

    @Test func tappingAShootOfTheOrgClosesBothLayersAndOpensItsCard() {
        let app = model(orgs: [named("o1", "A")], sessions: [shoot("a", 24, org: "o1")])
        app.openOrgs(); app.openOrgCard(id: "o1")
        app.openOrgShoot("a")
        #expect(!app.org.listOpen && app.org.cardId == nil && app.card?.id == "a")
    }

    // MARK: карточка

    @Test func phoneIsCombedWhileTyping() {
        let app = model(orgs: [named("o1", "A")])
        app.setOrgPhone("o1", "9234443322")
        #expect(app.orgs[0].phone == "8 923 444-33-22" || app.orgs[0].phone == "+7 923 444-33-22", "номер причёсан: \(app.orgs[0].phone)")
    }

    @Test func docLinkTakesTheChosenKindAndOwnPaperCanBeRemoved() {
        let app = model(orgs: [named("o1", "A")])
        app.org.docKind = .invoice
        app.addOrgDocLink("o1", "disk.example.com/f1")
        app.org.docKind = nil
        app.addOrgDocLink("o1", "disk.example.com/dogovor")
        app.addOrgDocLink("o1", "  ")
        #expect(app.orgs[0].docs.map(\.kind) == [.invoice, .contract] && app.orgs[0].docs[0].url == "https://disk.example.com/f1")
        app.removeOrgDoc("o1", at: 0)
        #expect(app.orgs[0].docs.count == 1 && app.orgs[0].docs[0].kind == .contract)
    }

    @Test func aLinkOnADraftMakesItARealOrg() {
        let app = model()
        app.newOrg()
        let id = app.org.cardId!
        app.addOrgDocLink(id, "example.com/dogovor")
        #expect(app.orgs.count == 1 && app.orgs[0].docs.count == 1, "бумага — тоже содержимое")
    }

    // MARK: лист выбора в форме (слово Алексея 4-3)

    @Test func orgAddedFromTheShortSheetIsChosenAndOpensAsACard() {
        let app = model()
        app.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        let o = app.addOrg(name: "Ромашка")
        app.setFormOrg(o)
        #expect(app.form?.orgId == o.id && app.orgs.map(\.name) == ["Ромашка"])
        app.openOrgCard(id: o.id)
        #expect(app.org.cardId == o.id, "«Открыть карточку» находит только что заведённую организацию")
        app.settleOrg(o.id)
        #expect(app.orgs.count == 1, "именованная организация карточкой не теряется")
    }

    @Test func kindChoiceAndShelfKindStartClearAndSurviveCardChange() {
        let app = model(orgs: [named("o1", "A"), named("o2", "B")])
        app.org.docKind = .act
        app.openOrgCard(id: "o2")
        #expect(app.org.docKind == nil, "вид не переезжает в чужую карточку")
        app.openOrgs()
        app.org.shelfKind = .invoice
        app.closeOrgs()
        #expect(app.org.shelfKind == nil && app.org.tab == .orgs)
    }

    // MARK: ревью GPT к a456d3d

    @Test func deletingTheChosenOrgClearsItFromTheOpenForm() {
        let app = model(orgs: [named("o1", "A")], sessions: [shoot("a", 24, org: "o1")])
        app.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        app.setFormOrg(app.orgs[0])
        #expect(app.form?.orgId == "o1")
        app.deleteOrg("o1")
        #expect(app.form?.orgId == nil, "иначе форма запишет ключ удалённой организации в съёмку")
    }

    @Test func wipingTheChosenOrgInTheSheetCardClearsItFromTheForm() {
        let app = model()
        app.openForm(day: CivilDate(year: 2026, month: 10, day: 3))
        let o = app.addOrg(name: "Ромашка")
        app.setFormOrg(o)
        app.editOrg(o.id) { $0.name = "" }
        app.settleOrg(o.id)
        #expect(app.orgs.isEmpty && app.form?.orgId == nil)
    }

    @Test func kindPickedInASheetCardDoesNotLeakIntoTheNextOne() {
        let app = model(orgs: [named("o1", "A")])
        app.org.docKind = .invoice
        app.settleOrg("o1")
        #expect(app.org.docKind == nil, "закрыли карточку из листа формы — вид не остаётся для следующей")
    }
}
