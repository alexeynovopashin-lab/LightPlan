import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Организации: связь со съёмкой, строка списка, пустая не остаётся, удаление, бумаги (итерация 28, шаг 6).
@Suite struct OrgBookTests {
    typealias Att = LightPlanDomain.Attachment
    static func day(_ d: Int, month: Int = 9) -> CivilDate { CivilDate(year: 2026, month: month, day: d) }

    static func shoot(_ id: String, _ d: CivilDate, start: Int = 600, org: String?, rate: Decimal? = nil,
                      docs: [Att] = []) -> Session {
        var s = Session(id: id, kind: .shoot, day: d, start: start, end: start + 120, duration: 120, genre: .wedding)
        s.orgId = org
        s.pay = rate == nil ? nil : .flat
        s.rate = rate
        s.docs = docs
        return s
    }

    static func doc(_ name: String, kind: DocKind? = nil) -> Att { Att(source: .doc, name: name, kind: kind) }

    @Test func shootsOfOrgAreFoundByOrgIdNewestFirst() {
        let all = [Self.shoot("a", Self.day(21, month: 8), org: "o1"), Self.shoot("b", Self.day(24), org: "o1"),
                   Self.shoot("c", Self.day(24), start: 900, org: "o1"), Self.shoot("d", Self.day(25), org: "o2"),
                   Self.shoot("e", Self.day(26), org: nil)]
        #expect(OrgBook.shoots(of: "o1", in: all).map(\.id) == ["c", "b", "a"], "по дате и по началу, от новых к старым")
        #expect(OrgBook.shoots(of: "o2", in: all).map(\.id) == ["d"])
        #expect(OrgBook.shoots(of: "none", in: all).isEmpty)
    }

    @Test func listLineCountsShootsAndSumsIncomeByCurrency() {
        var usd = Self.shoot("u", Self.day(3), org: "o1", rate: 100); usd.currency = .usd
        let all = [Self.shoot("a", Self.day(1), org: "o1", rate: 50_000), Self.shoot("b", Self.day(2), org: "o1", rate: 133_000),
                   usd, Self.shoot("x", Self.day(4), org: "o2", rate: 7), Self.shoot("free", Self.day(5), org: "o1")]
        let l = OrgBook.line(of: "o1", in: all, home: .rub)
        #expect(l.shootCount == 4)
        #expect(l.sums.map(\.currency) == [.rub, .usd] && l.sums.map(\.sum) == [183_000, 100], "домашняя валюта первой; съёмка без цены не в счёт")
        #expect(OrgBook.line(of: "o9", in: all, home: .rub) == OrgBook.Line(shootCount: 0, sums: []))
    }

    @Test func blankOrgIsNotKeptButNamedOrFilledOrReferencedIs() {
        var o = Org(id: "o1")
        #expect(OrgBook.isBlank(o) && !OrgBook.keeps(o, in: []))
        o.name = "   "; o.person = "\n"
        #expect(OrgBook.isBlank(o), "пробелы — не текст")
        o.requisites = "ИНН 7701"
        #expect(!OrgBook.isBlank(o) && OrgBook.keeps(o, in: []))
        o.requisites = ""
        o.docs = [Self.doc("dogovor.pdf")]
        #expect(!OrgBook.isBlank(o), "бумага — тоже содержимое")
        o.docs = []
        #expect(OrgBook.keeps(o, in: [Self.shoot("a", Self.day(1), org: "o1")]), "пустое имя у организации со съёмками — не повод терять заказчика")
        #expect(!OrgBook.keeps(o, in: [Self.shoot("a", Self.day(1), org: "other")]))
    }

    @Test func detachClearsOnlyThisOrgAndStampsTheTouchedRecords() {
        var a = Self.shoot("a", Self.day(1), org: "o1"); a.contact = "Ольга"; a.orderPhone = "8 913"
        let b = Self.shoot("b", Self.day(2), org: "o2")
        let out = OrgBook.detach("o1", from: [a, b], at: 5_000)
        #expect(out[0].orgId == nil && out[0].modifiedAt == 5_000, "связь снята, правка свежая")
        #expect(out[0].contact == "Ольга" && out[0].orderPhone == "8 913", "имя и телефон в записи остаются")
        #expect(out[1] == b && out[1].modifiedAt == nil, "чужая запись не тронута")
    }

    @Test func orgDocsAreOwnFirstThenShootsNewestFirstWithoutIndex() {
        var o = Org(id: "o1")
        o.docs = [Self.doc("dogovor-god.pdf"), Self.doc("scan.png", kind: .invoice)]
        let all = [Self.shoot("old", Self.day(21, month: 8), org: "o1", docs: [Self.doc("akt.pdf", kind: .act)]),
                   Self.shoot("new", Self.day(24), org: "o1", docs: [Self.doc("schet.pdf", kind: .invoice)]),
                   Self.shoot("alien", Self.day(25), org: "o2", docs: [Self.doc("x.pdf")])]
        let list = OrgBook.docs(of: o, in: all, kind: nil)
        #expect(list.map(\.doc.name) == ["dogovor-god.pdf", "scan.png", "schet.pdf", "akt.pdf"])
        #expect(list.map(\.index) == [0, 1, nil, nil], "убрать можно только свои")
        #expect(list.map(\.sessionId) == [nil, nil, "new", "old"])
        #expect(OrgBook.docs(of: o, in: all, kind: .invoice).map(\.doc.name) == ["scan.png", "schet.pdf"])
        #expect(OrgBook.docs(of: o, in: all, kind: .contract).map(\.doc.name) == ["dogovor-god.pdf"], "вид угадан по имени файла")
        #expect(OrgBook.docCount(of: o, in: all, kind: .invoice) == 2)
    }

    @Test func linkJoinsOrgDocsWithSchemeAndGuessedKind() {
        var o = Org(id: "o1")
        #expect(OrgBook.addLink("  disk.example.com/dogovor-2026  ", kind: nil, to: &o))
        #expect(o.docs.last?.url == "https://disk.example.com/dogovor-2026" && o.docs.last?.kind == .contract)
        #expect(OrgBook.addLink("http://x.io/f", kind: .brief, to: &o) && o.docs.last?.kind == .brief, "выбранный вид главнее угаданного")
        #expect(!OrgBook.addLink("   ", kind: nil, to: &o) && o.docs.count == 2, "пустая ссылка не пишется")
        OrgBook.removeDoc(at: 0, from: &o)
        #expect(o.docs.count == 1 && o.docs[0].url == "http://x.io/f")
        OrgBook.removeDoc(at: 5, from: &o)
        #expect(o.docs.count == 1)
    }

    @Test func shelfCollectsAllPapersAndSortsByShootDateWithOrgPapersLast() {
        var o = Org(id: "o1", name: "A")
        o.docs = [Self.doc("dogovor.pdf")]
        o.requisiteFiles = [Att(source: .img, name: "rekvizity.png")]
        let sessions = [Self.shoot("old", Self.day(1), org: "o1", docs: [Self.doc("akt.pdf")]),
                        Self.shoot("new", Self.day(9), org: "o1", docs: [Self.doc("schet.pdf")])]
        let shelf = OrgBook.shelf(orgs: [o], sessions: sessions)
        #expect(shelf.map(\.doc.name) == ["schet.pdf", "akt.pdf", "dogovor.pdf", "rekvizity.png"])
        #expect(shelf.last?.isRequisite == true && shelf.last?.kind == nil)
        #expect(shelf.map(\.kind) == [.invoice, .act, .contract, nil])
    }

    @Test func shelfKindChipsShowOnlyKindsWithPapersOrSelectedInPracticeOrder() {
        let shelf = OrgBook.shelf(orgs: [], sessions: [
            Self.shoot("a", Self.day(1), org: nil, docs: [Self.doc("akt.pdf"), Self.doc("dogovor-1.pdf"), Self.doc("dogovor-2.pdf")])])
        let chips = OrgBook.shelfKinds(shelf, practice: .ru, selected: nil)
        #expect(chips.map(\.kind) == [.contract, .act] && chips.map(\.count) == [2, 1], "счёт и чек без бумаг — скрыты")
        #expect(OrgBook.shelfKinds(shelf, practice: .ru, selected: .invoice).map(\.kind) == [.contract, .invoice, .act], "выбранный виден, даже пустой")
        #expect(OrgBook.shelfKinds(shelf, practice: .us, selected: nil).map(\.kind) == [.contract], "у us акта в видах нет")
        #expect(OrgBook.filtered(shelf, kind: .act).count == 1 && OrgBook.filtered(shelf, kind: nil).count == 3)
    }

    @Test func practiceDecidesWhichKindsAreOffered() {
        #expect(Practice.us.docKinds.contains(.release) && !Practice.us.docKinds.contains(.act))
        #expect(Practice.uk.docKinds.contains(.release))
        #expect(Practice.eu.docKinds.contains(.acceptance) && !Practice.eu.docKinds.contains(.release))
        #expect(Practice.ru.docKinds.contains(.act))
    }
}
