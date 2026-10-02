import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 28д, шаг 3а: полоса «Документы» на «Съёмках» и экран верхнего уровня — цифры, слои,
/// слова разделов, выборки разделов. Правила (`DocSections`, `DocAttention`) проверены в домене;
/// здесь — что хозяин приложения отдаёт их экрану как есть.
@MainActor
struct DocsScreenStateTests {

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

    private func link(_ url: String, kind: DocKind? = nil, title: String? = nil, at: Int64? = nil) -> LightPlanDomain.Attachment {
        var a = LightPlanDomain.Attachment(source: .link, url: url, kind: kind, title: title)
        a.at = at
        return a
    }

    /// Приложение «сегодня» по его собственному дню; съёмки считаются от него.
    private func model(_ build: (CivilDate) -> (sessions: [Session], orgs: [Org], mine: [LightPlanDomain.Attachment], bin: [TrashedDoc])) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        func make(_ snap: Snapshot) -> AppModel {
            AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                     locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                     weatherSource: NoWeather(), now: { now })
        }
        let probe = make(Snapshot())
        let b = build(probe.today)
        var snap = Snapshot()
        snap.sessions = b.sessions; snap.orgs = b.orgs; snap.myDocs = b.mine; snap.trashedDocs = b.bin
        return make(snap)
    }

    private func shoot(_ id: String, _ day: CivilDate, org: String? = nil, docs: [LightPlanDomain.Attachment] = []) -> Session {
        var s = Session(id: id, kind: .shoot, day: day, start: 600, end: 720, duration: 120, genre: .product)
        s.orgId = org
        s.docs = docs
        return s
    }

    // MARK: полоса — цифры

    @Test func stripCountsAreShelfPlusMineAndShootsNeedingAttention() {
        let app = model { today in
            let soon = shoot("a", today.adding(days: 3), docs: [link("x.io/a", kind: .invoice)])
            let far = shoot("b", today.adding(days: 40), docs: [link("x.io/b", kind: .contract)])
            return ([soon, far], [], [link("x.io/m1"), link("x.io/m2")], [])
        }
        let c = app.docCounts()
        #expect(c.total == 4, "всего = бумаги полки (2) + «Мои» (2); корзина не считается")
        #expect(c.attention == 1, "требуют внимания — съёмок, а не причин: через 3 дня нет договора")
        #expect(c.mine == 2 && c.bin == 0)
    }

    @Test func emptyShelfStripHasNothingToCount() {
        let app = model { _ in ([], [], [], []) }
        let c = app.docCounts()
        #expect(c.total == 0 && c.attention == 0)
    }

    @Test func binDoesNotChangeTheStripTotal() {
        let app = model { _ in
            ([], [], [link("x.io/m")], [TrashedDoc(doc: link("x.io/gone"), from: .mine, index: 0, deletedAt: 1_000)])
        }
        #expect(app.docCounts().total == 1)
        #expect(app.docCounts().bin == 1)
    }

    // MARK: слои

    @Test func screenOpensAtTheListOfSectionsAndGoesBackStepByStep() {
        let app = model { _ in ([], [], [], []) }
        #expect(!app.docsNav.isOpen)
        app.openDocs()
        #expect(app.docsNav.isOpen && app.docsNav.section == nil, "открывается на списке разделов")
        app.openDocSection(.mine)
        #expect(app.docsNav.section == .mine)
        app.org.shelfKind = .invoice
        app.closeDocSection()
        #expect(app.docsNav.isOpen && app.docsNav.section == nil && app.org.shelfKind == nil,
                "из раздела — назад в список; чип вида не переезжает в другой раздел")
        app.closeDocs()
        #expect(!app.docsNav.isOpen)
    }

    // MARK: слова и порядок разделов

    @Test func eightSectionsNamedAsInThePlanInThisOrder() {
        let app = model { _ in ([], [], [], []) }
        #expect(DocSection.allCases.map(app.docSectionTitle) ==
                ["Требуют внимания", "Недавние", "По съёмкам", "По организациям", "По видам", "По месяцам", "Мои", "Корзина"])
        #expect(Set(DocSection.allCases.map { AppModel.docSectionIcon($0) }).count == 8, "у каждого раздела свой знак")
    }

    @Test func attentionTimingIsInWordsAndSitsBesideTheReason() {
        let app = model { today in
            ([shoot("soon", today.adding(days: 5)), shoot("now", today), shoot("past", today.adding(days: -4))], [], [], [])
        }
        let byId = Dictionary(uniqueKeysWithValues: app.docAttention().map { ($0.session.id, $0) })
        #expect(app.docAttentionTiming(byId["soon"]!) == "через 5 дн.")
        #expect(app.docAttentionTiming(byId["now"]!) == "сегодня")
        #expect(app.docAttentionTiming(byId["past"]!) == "4 дн. назад")
        #expect(app.docReasonWord(byId["soon"]!.primary) == "Нет договора")
        #expect(app.docReasonWord(byId["past"]!.primary) == "Нет акта", "в России закрывающая бумага — акт")
        #expect(app.docReasonWord(.noPay) == "Нет оплаты")
    }

    // MARK: выборки разделов

    @Test func recentKeepsTimeOrderAndMineSortsByDate() {
        let app = model { today in
            let s = shoot("a", today.adding(days: 40), docs: [link("x.io/old", title: "Старая", at: 100), link("x.io/new", title: "Свежая", at: 900)])
            return ([s], [], [link("x.io/m", title: "Моя", at: 500)], [])
        }
        #expect(app.docFlatRows(for: .recent).map(\.title) == ["Свежая", "Моя", "Старая"], "«Недавние» — по времени правки, новые сверху")
        #expect(app.docFlatRows(for: .mine).map(\.title) == ["Моя"])
        #expect(app.docTableRows(for: .recent).map(\.title) == ["Свежая", "Моя", "Старая"], "в таблице «Недавних» порядок тот же: сортировка колонки не действует")
    }

    @Test func areaOfOrgKindMonthSectionsLeavesMineOut() {
        let app = model { today in
            let s = shoot("a", today.adding(days: 40), docs: [link("x.io/a", kind: .contract)])
            return ([s], [], [link("x.io/m")], [])
        }
        for sec in [DocSection.byOrg, .byKind, .byMonth] {
            #expect(app.docArea(sec).count == 1, "«Мои» в разделы 4–6 не входят: \(sec)")
        }
        #expect(app.docGroups(for: .byKind).map(\.label) == ["Договор"], "группировку задаёт раздел, а не запомненная")
        #expect(app.docGroups(for: .byMonth).count == 1)
    }

    @Test func bySessionTitlesCarryDateGenreAndClient() {
        let app = model { today in
            var s = shoot("a", today.adding(days: 40), docs: [link("x.io/a", kind: .act)])
            s.contact = "Мария +7 916 000-00-00"
            return ([s, shoot("empty", today.adding(days: 41))], [], [], [])
        }
        let g = app.docSessionGroups()
        #expect(g.count == 1, "съёмки без бумаг не показываются")
        #expect(g[0].title.hasSuffix(" · Мария"), "заголовок: дата · жанр · клиент — \(g[0].title)")
        #expect(g[0].rows.map(\.title) == ["Акт"])
    }

    @Test func binRowsNewestFirstAndDeletedWordSaysWhen() {
        let t1 = TrashedDoc(doc: link("x.io/1", title: "Первая"), from: .mine, index: 0, deletedAt: 1_000)
        let t2 = TrashedDoc(doc: link("x.io/2", title: "Вторая"), from: .mine, index: 0, deletedAt: 9_000)
        let app = model { _ in ([], [], [], [t1, t2]) }
        #expect(app.docBinRows().map(\.row.title) == ["Вторая", "Первая"])
        #expect(app.docDeletedText(t2).hasPrefix("удалена "))
    }

    // MARK: поиск (шаг 3б)

    private func searchApp() -> AppModel {
        model { today in
            var alfa = Org(id: "a", name: "Альфа")
            alfa.docs = [link("x.io/a1", kind: .contract, title: "Рамочный договор")]
            var s1 = shoot("s1", today.adding(days: 40), org: "a", docs: [link("x.io/s1", kind: .invoice)])
            s1.contact = "Мария"
            var s2 = shoot("s2", today.adding(days: 41), docs: [link("x.io/s2", kind: .act, title: "Акт про Ёлку")])
            s2.contact = "Пётр"
            let gone = TrashedDoc(doc: link("x.io/g", title: "Секретный договор"), from: .mine, index: 0, deletedAt: 1)
            return ([s1, s2], [alfa], [link("x.io/m", title: "Счёт на софт")], [gone])
        }
    }

    @Test func searchFindsByTitleOrganizationAndClientAcrossTheWholeShelf() {
        let app = searchApp()
        app.openDocs()
        app.docsNav.query = "альфа"
        let byOrg = app.docSearchRows()
        #expect(byOrg.count == 2 && byOrg.map(\.title).contains("Рамочный договор") && byOrg.contains { $0.title.hasPrefix("Счёт · Альфа") },
                "организация находит и её бумагу, и бумагу её съёмки — \(byOrg.map(\.title))")
        app.docsNav.query = "мария"
        #expect(app.docSearchRows().count == 1, "клиент съёмки находит бумагу этой съёмки")
        app.docsNav.query = "про елку"
        #expect(app.docSearchRows().map(\.title) == ["Акт про Ёлку"], "ё = е, слова в любом порядке")
        app.docsNav.query = "счёт"
        #expect(app.docSearchRows().count == 2, "слово вида и своё название: «Счёт на софт» из «Мои» и счёт съёмки")
    }

    @Test func searchSkipsTheBinAndWhitespaceIsNoSearch() {
        let app = searchApp()
        app.docsNav.query = "секретный"
        #expect(app.docSearching && app.docSearchRows().isEmpty, "корзина не ищется — «ничего не найдено»")
        app.docsNav.query = "   "
        #expect(!app.docSearching, "одни пробелы — не запрос: разделы остаются на месте")
        app.docsNav.query = ""
        #expect(!app.docSearching)
    }

    @Test func titleMatchesComeBeforeOthers() {
        let app = searchApp()
        app.docsNav.query = "договор"
        let titles = app.docSearchRows().map(\.title)
        #expect(titles.first == "Рамочный договор", "совпало в названии — первым: \(titles)")
    }

    @Test func closingTheScreenForgetsTheQueryAndThePaper() {
        let app = searchApp()
        app.openDocs()
        app.docsNav.query = "мария"
        app.openDocPaper(app.docSearchResults()[0])
        #expect(app.docsNav.paper != nil)
        app.closeDocs()
        #expect(app.docsNav.query.isEmpty && app.docsNav.paper == nil)
    }

    // MARK: экран бумаги (шаг 3б)

    @Test func paperOfAShootShowsItsOwnerAndItsLinkInTheDealChain() {
        let app = searchApp()
        let d = DocSections.shelf(app.docLibrary).first { $0.sessionId == "s1" }!
        let p = app.docPaper(d)
        #expect(p.owner == .session && p.sessionId == "s1")
        #expect(p.ownerText.hasSuffix(" · Альфа"), "съёмка организации называется по организации — \(p.ownerText)")
        #expect(p.step == .invoice, "счёт закрывает звено «Счёт» цепочки")
        #expect(p.deal?.links.first { $0.step == .invoice }?.done == true, "звено у съёмки с этим счётом закрыто")
        #expect(p.deal?.links.first { $0.step == .contract }?.done == false, "договора нет — звено открыто")
        #expect(p.url == nil, "адрес без схемы не открывается браузером")
    }

    @Test func paperOfOrgRequisitesAndMineHasNoDeal() {
        let app = searchApp()
        let shelf = DocSections.shelf(app.docLibrary)
        let org = app.docPaper(shelf.first { $0.orgId == "a" && $0.sessionId == nil }!)
        #expect(org.owner == .org && org.ownerText == "Альфа" && org.deal == nil && org.step == .contract)
        let mine = app.docPaper(shelf.first { $0.isMine }!)
        #expect(mine.owner == .mine && mine.ownerText == "Мои" && mine.deal == nil && mine.sessionId == nil)
        #expect(mine.headline == "Счёт на софт", "свой заголовок — название бумаги")
    }

    @Test func paperWithoutAnOwnTitleIsHeadedByItsKindAndAReceiptHasNoStep() {
        let app = model { _ in ([], [], [link("https://x.io/r", kind: .receipt)], []) }
        let p = app.docPaper(DocSections.shelf(app.docLibrary)[0])
        #expect(p.headline == "Чек" && p.step == nil)
        #expect(p.url?.absoluteString == "https://x.io/r")
    }

    @Test func paperNavigationKeepsTheSectionAndFileShowsAMessage() {
        let app = searchApp()
        app.openDocs()
        app.openDocSection(.mine)
        app.openDocPaper(DocSections.shelf(app.docLibrary).first { $0.isMine }!)
        #expect(app.docsNav.section == .mine && app.docsNav.paper != nil, "бумага ложится поверх раздела")
        app.noteDocNotOpened()
        #expect(app.docsNav.paperNote == app.lexicon.t("doc.openFail"))
        app.closeDocPaper()
        #expect(app.docsNav.paper == nil && app.docsNav.paperNote == nil && app.docsNav.section == .mine,
                "назад — в тот же раздел, сообщение не остаётся")
    }
}
