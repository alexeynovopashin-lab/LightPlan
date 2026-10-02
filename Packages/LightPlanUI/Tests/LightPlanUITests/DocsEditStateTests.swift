import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 28д, шаг 4: быстрое «+», правка, перенос, удаление в корзину, возврат, вопросы корзины.
/// Правила переходов проверены в домене (`DocLibrary`); здесь — что хозяин приложения связывает их
/// со снимком, плашкой «Вернуть» / «Отменить» и экраном бумаги.
@MainActor
struct DocsEditStateTests {

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

    private func draft(_ url: String = "", kind: DocKind? = nil, title: String = "", owner: LightPlanDomain.DocOwner = .mine) -> DocDraft {
        var d = DocDraft(kind: kind, title: title, owner: owner)
        d.setURL(url)
        if kind != nil { d.kind = kind }
        return d
    }

    private func two(_ today: CivilDate) -> (sessions: [Session], orgs: [Org], mine: [LightPlanDomain.Attachment], bin: [TrashedDoc]) {
        var org = Org(id: "o1", name: "Яр")
        org.docs = [link("x.io/o", title: "Орг")]
        return ([shoot("a", today.adding(days: 3), org: "o1", docs: [link("x.io/a", kind: .contract, title: "Дог")])], [org],
                [link("x.io/m", title: "Моя")], [])
    }

    // MARK: быстрое «+»

    @Test func newPaperWithoutOwnerIsAtOnceInMineWithAddedBar() {
        let app = model(two)
        let id = app.addDoc(draft("x.io/new", kind: .invoice, title: "Счёт на софт"))
        #expect(id != nil)
        #expect(app.docArea(.mine).first?.doc.id == id, "бумага без привязки видна в «Мои» сразу, в начале")
        #expect(app.docCounts().mine == 2 && app.docCounts().total == app.docCounts().byOrg + 2)
        #expect(app.undo?.what == .docAdded(id: id!) && app.undo?.actionKey == "doc.undo")
        #expect(app.undo?.text == "Добавлено: Счёт на софт")
    }

    @Test func linkIsOptionalButEmptyPaperIsNotAdded() {
        let app = model(two)
        #expect(app.addDoc(draft()) == nil, "ни ссылки, ни названия, ни вида — нечего добавлять")
        #expect(app.docArea(.mine).count == 1 && app.undo == nil)
        let id = app.addDoc(draft(title: "Только название"))
        #expect(id != nil && app.docArea(.mine).first?.doc.url == nil)
    }

    @Test func kindIsGuessedFromLinkUntilPickedByHand() {
        var d = DocDraft()
        d.setURL("https://x.io/dogovor-12")
        #expect(d.kind == .contract)
        d.pickKind(nil)
        d.setURL("https://x.io/akt-3")
        #expect(d.kind == nil, "«Без вида», выбранный рукой, ссылка не перебивает")
        var e = DocDraft(); e.pickKind(.receipt); e.setURL("x.io/dogovor")
        #expect(e.kind == .receipt)
    }

    @Test func newPaperGoesToChosenShootOrOrgAndTitleAndDateAreNotInvented() {
        let app = model(two)
        let s = app.addDoc(draft("x.io/s", kind: .act, owner: .session("a")))!
        #expect(app.docLibrary.sessions[0].docs.last?.id == s && app.docLibrary.sessions[0].docs.last?.date == nil)
        let o = app.addDoc(draft("x.io/o2", owner: .org("o1")))!
        let doc = app.docLibrary.orgs[0].docs.last!
        #expect(doc.id == o && doc.title == nil && doc.date == nil, "название и дату за человека не подставляем")
        #expect(app.addDoc(draft("x.io/ghost", owner: .org("нет"))) == nil, "хозяина нет — бумага не создаётся")
    }

    @Test func addedBarUndoRemovesThePaperWithoutTheBin() {
        let app = model(two)
        let id = app.addDoc(draft("x.io/new", title: "N"))!
        app.takeUndo()
        #expect(app.docLibrary.locate(id) == nil && app.docLibrary.trashedDocs.isEmpty && app.undo == nil)
    }

    @Test func sheetIsOpenedAndClosedByAddAndByEdit() {
        let app = model(two)
        app.openDocAdd()
        #expect(app.docsNav.sheet == .add)
        app.addDoc(draft(title: "T"))
        #expect(app.docsNav.sheet == nil, "после «Добавить» лист закрыт")
        let id = app.docLibrary.myDocs[1].id
        app.openDocEdit(id)
        #expect(app.docsNav.sheet == .edit(id: id))
        #expect(app.docDraft(for: .edit(id: id))?.title == "Моя" && app.docDraft(for: .edit(id: id))?.owner == .mine)
        app.openDocEdit("нет")
        #expect(app.docsNav.sheet == .edit(id: id), "бумаги нет — лист не открывается заново")
    }

    // MARK: правка и перенос

    @Test func editSavesKindTitleLinkAndRefreshesTheOpenPaper() {
        let app = model(two)
        let id = app.docLibrary.myDocs[0].id
        app.openDocPaper(DocSections.shelf(app.docLibrary).first { $0.doc.id == id }!)
        var d = app.docDraft(for: id)!
        d.title = "Новое имя"; d.pickKind(.invoice); d.setURL("y.io/z")
        #expect(app.saveDoc(id, d))
        let doc = app.docLibrary.myDocs[0]
        #expect(doc.title == "Новое имя" && doc.kind == .invoice && doc.url == "https://y.io/z" && doc.id == id)
        #expect(app.docsNav.paper?.doc.title == "Новое имя", "экран бумаги показывает правку, а не старую копию")
        #expect(app.docPaper(app.docsNav.paper!).headline == "Новое имя")
    }

    @Test func editCanMoveBetweenMineShootAndOrgKeepingIdAndEdits() {
        let app = model(two)
        let id = app.docLibrary.myDocs[0].id
        var d = app.docDraft(for: id)!
        d.title = "Перенос"; d.owner = .org("o1")
        #expect(app.saveDoc(id, d))
        #expect(app.docLibrary.myDocs.isEmpty && app.docLibrary.orgs[0].docs.last?.id == id && app.docLibrary.orgs[0].docs.last?.title == "Перенос")
        var e = app.docDraft(for: id)!
        e.owner = .session("a")
        #expect(app.saveDoc(id, e))
        #expect(app.docLibrary.orgs[0].docs.map(\.id).contains(id) == false && app.docLibrary.sessions[0].docs.last?.id == id)
        var f = app.docDraft(for: id)!
        f.owner = .mine
        #expect(app.saveDoc(id, f))
        #expect(app.docLibrary.myDocs.first?.id == id, "и обратно в «Мои»")
    }

    @Test func movingOutOfShootKeepsTheDayPickedInTheFormNotTheShootDay() {
        let app = model(two)
        let id = app.docLibrary.sessions[0].docs[0].id
        let shootDay = app.docLibrary.sessions[0].day
        let picked = shootDay.adding(days: -9)
        var d = app.docDraft(for: id)!
        d.owner = .mine; d.date = picked
        #expect(app.saveDoc(id, d))
        #expect(app.docLibrary.myDocs.first { $0.id == id }?.date == picked, "выбранный день, не день съёмки")
        // Дату не трогали — день съёмки по-прежнему переезжает вместе с бумагой.
        var e = app.docDraft(for: app.docLibrary.orgs[0].docs[0].id)!
        e.owner = .session("a")
        let oid = app.docLibrary.orgs[0].docs[0].id
        #expect(app.saveDoc(oid, e))
        var f = app.docDraft(for: oid)!
        f.owner = .org("o1")
        #expect(app.saveDoc(oid, f))
        #expect(app.docLibrary.orgs[0].docs.first { $0.id == oid }?.date == shootDay, "без выбора — день съёмки")
    }

    @Test func movingOutOfShootToOrgKeepsThePickedDay() {
        let app = model(two)
        let id = app.docLibrary.sessions[0].docs[0].id
        let picked = app.docLibrary.sessions[0].day.adding(days: 4)
        var d = app.docDraft(for: id)!
        d.owner = .org("o1"); d.date = picked
        #expect(app.saveDoc(id, d))
        #expect(app.docLibrary.orgs[0].docs.first { $0.id == id }?.date == picked)
    }

    @Test func existingFileSavesWithoutKindTitleOrLink() {
        var d = DocDraft(kind: nil, title: "", url: "", date: nil, owner: .mine)
        d.linkEditable = false
        #expect(d.canSubmit(editing: true), "у существующего файла необязательных полей может не быть")
        #expect(!d.canSubmit(editing: false), "новую пустую бумагу по-прежнему не заводим")
        var l = DocDraft(owner: .mine)
        l.linkEditable = true
        #expect(!l.canSubmit(editing: false))
    }

    @Test func pickerSearchFoldsYoLikeTheShelfSearch() {
        let app = model { today in
            var s = shoot("p", today, docs: [])
            s.contact = "Пётр"
            let org = Org(id: "e", name: "Ёлка")
            return ([s], [org], [], [])
        }
        for q in ["Пётр", "Петр", "петр"] { #expect(app.docSessionChoices(matching: q).map(\.id) == ["p"], "съёмка по «\(q)»") }
        for q in ["Ёлка", "Елка", "елк"] { #expect(app.docOrgChoices(matching: q).map(\.id) == ["e"], "организация по «\(q)»") }
    }

    @Test func requisiteFileCannotBeEditedButCanBeDeleted() {
        let app = model { t in
            var o = Org(id: "o1", name: "Яр")
            o.requisiteFiles = [LightPlanDomain.Attachment(source: .doc, name: "rek.pdf", id: "req")]
            return ([], [o], [], [])
        }
        app.openDocEdit("req")
        #expect(app.docsNav.sheet == nil && app.docDraft(for: "req") == nil)
        app.trashDoc("req")
        #expect(app.docLibrary.trashedDocs.map(\.doc.id) == ["req"])
    }

    // MARK: удаление и возврат

    @Test func deleteFromPaperGoesToBinCloseThePaperAndReturnBarRestoresIt() {
        let app = model(two)
        let sd = DocSections.shelf(app.docLibrary).first { $0.sessionId == "a" }!
        app.openDocPaper(sd)
        app.trashDoc(sd.doc.id)
        #expect(app.docsNav.paper == nil, "экран удалённой бумаги закрывается")
        #expect(app.docCounts().bin == 1 && app.docLibrary.sessions[0].docs.isEmpty)
        #expect(app.undo?.what == .docTrashed(id: sd.doc.id))
        app.takeUndo()
        #expect(app.docLibrary.sessions[0].docs.first?.id == sd.doc.id && app.docCounts().bin == 0, "полоса «Вернуть» возвращает на место")
    }

    @Test func restoreFromBinPutsPaperHomeAndDropsItsBar() {
        let app = model(two)
        let id = app.docLibrary.orgs[0].docs[0].id
        app.trashDoc(id)
        app.restoreDoc(id)
        #expect(app.docLibrary.orgs[0].docs.first?.id == id && app.docLibrary.trashedDocs.isEmpty)
        #expect(app.undo == nil, "плашка «Вернуть» этой бумаги погасла")
    }

    @Test func restoreWithoutOwnerGoesToMineAndSaysWho() {
        let app = model(two)
        let sd = DocSections.shelf(app.docLibrary).first { $0.sessionId == "a" }!.doc.id
        let od = app.docLibrary.orgs[0].docs[0].id
        app.trashDoc(sd); app.trashDoc(od)
        app.snapshot.sessions.removeAll { $0.id == "a" }
        app.snapshot.orgs.removeAll { $0.id == "o1" }
        app.restoreDoc(sd)
        #expect(app.docLibrary.myDocs.first?.id == sd)
        #expect(app.undo?.what == .notice && app.undo?.text == "Вернулась в «Мои»: съёмки больше нет")
        app.restoreDoc(od)
        #expect(app.docLibrary.myDocs.first?.id == od && app.undo?.text == "Вернулась в «Мои»: организации больше нет")
    }

    // MARK: вопросы корзины

    @Test func purgeForeverAsksFirstAndErasesOnlyOnConfirm() {
        let app = model(two)
        let id = app.docLibrary.myDocs[0].id
        app.trashDoc(id)
        app.askPurgeDoc(id)
        #expect(app.docsNav.binAsk == .purge(id: id) && app.docLibrary.trashedDocs.count == 1, "вопрос ничего не стирает")
        app.cancelBinAsk()
        #expect(app.docsNav.binAsk == nil && app.docLibrary.trashedDocs.count == 1, "«Отмена» оставляет бумагу")
        app.askPurgeDoc(id)
        app.confirmBinAsk()
        #expect(app.docLibrary.trashedDocs.isEmpty && app.docLibrary.locate(id) == nil && app.docsNav.binAsk == nil)
        app.confirmBinAsk()
        #expect(app.docLibrary.trashedDocs.isEmpty, "подтверждение без вопроса не делает ничего")
    }

    @Test func clearBinAsksFirstAndEmptiesOnlyOnConfirm() {
        let app = model(two)
        app.trashDoc(app.docLibrary.myDocs[0].id)
        app.trashDoc(app.docLibrary.orgs[0].docs[0].id)
        app.askClearDocBin()
        #expect(app.docLibrary.trashedDocs.count == 2 && app.docsNav.binAsk == .clear)
        app.cancelBinAsk()
        #expect(app.docLibrary.trashedDocs.count == 2)
        app.askClearDocBin(); app.confirmBinAsk()
        #expect(app.docLibrary.trashedDocs.isEmpty && app.docCounts().bin == 0)
        #expect(app.docLibrary.sessions[0].docs.count == 1, "живые бумаги не тронуты")
    }

    @Test func shootBinIsUntouchedByDocumentBin() {
        let app = model(two)
        app.trashSession(id: "a")
        let before = app.snapshot.trashed.count
        app.trashDoc(app.docLibrary.myDocs[0].id)
        app.askClearDocBin(); app.confirmBinAsk()
        #expect(app.snapshot.trashed.count == before, "корзина съёмок — в «Настройках», «Очистить» её не трогает")
    }

    // MARK: привязка в листе

    @Test func ownerWordsAndRecentChoicesComeFromTheLibrary() {
        let app = model(two)
        #expect(app.docOwnerText(.mine) == "Без привязки (Мои)")
        #expect(app.docOwnerText(.org("o1")) == "Яр")
        #expect(app.docRecentOrgs().map(\.id) == ["o1"])
        #expect(app.docRecentSessions().map(\.id) == ["a"])
        #expect(app.docOrgChoices(matching: "яр").count == 1 && app.docOrgChoices(matching: "zzz").isEmpty)
        #expect(app.docSessionChoices(matching: "").count == 1)
    }
}
