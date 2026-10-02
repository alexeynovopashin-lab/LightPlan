import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Выборки разделов «Документов», числа справа, поиск (шаг 28д, § 3 и § 5).
@Suite struct DocSectionsTests {
    typealias Att = LightPlanDomain.Attachment
    static let today = CivilDate(year: 2026, month: 10, day: 1)
    static func day(_ n: Int) -> CivilDate { today.adding(days: n) }

    static func doc(_ id: String, _ kind: DocKind? = nil, title: String? = nil, at: Int64? = nil, date: CivilDate? = nil) -> Att {
        Att(source: .link, url: "https://x.io/\(id)", kind: kind, title: title, date: date, id: id, at: at)
    }

    static func shoot(_ id: String, _ n: Int, org: String? = nil, client: String = "", docs: [Att]) -> Session {
        var s = Session(id: id, kind: .shoot, day: day(n), start: 600, end: 720, duration: 120, genre: .product)
        s.orgId = org; s.contact = client; s.docs = docs
        s.pay = nil
        return s
    }

    /// Две организации, пять съёмок (две впереди, три позади), три «Мои», две в корзине.
    static func lib() -> DocLibrary {
        var yar = Org(id: "y", name: "Яр"); yar.docs = [doc("y-dog", .contract, at: 50)]
        var alfa = Org(id: "a", name: "Альфа"); alfa.requisiteFiles = [Att(source: .img, name: "rek.png", id: "a-req")]
        let sessions = [
            shoot("far", 20, org: "y", docs: [doc("f-act", .act, title: "Акт", at: 10)]),
            shoot("near", 2, org: "a", docs: [doc("n-b", .invoice, title: "Б", at: 90), doc("n-a", .contract, title: "А", at: 80), doc("n-brief", .brief, at: 70)]),
            shoot("p1", -3, client: "Мария", docs: [doc("p1-x", .act, at: 60)]),
            shoot("p9", -9, docs: [doc("p9-x", .receipt)]),
            shoot("empty", 1, docs: []),
        ]
        var l = DocLibrary(sessions: sessions, orgs: [yar, alfa],
                           myDocs: [doc("m-new", title: "Счёт на софт", at: 100, date: day(-1)), doc("m-old", date: day(-30)), doc("m-nodate", at: 20)])
        l.trashedDocs = [TrashedDoc(doc: doc("t1"), from: .mine, index: 0, deletedAt: 5), TrashedDoc(doc: doc("t2"), from: .mine, index: 0, deletedAt: 9)]
        return l
    }

    @Test func recentIsLastTwentyByStampThenUnstampedInShelfOrder() {
        let l = Self.lib()
        let r = DocSections.recent(l).map(\.doc.id)
        #expect(Array(r.prefix(8)) == ["m-new", "n-b", "n-a", "n-brief", "p1-x", "y-dog", "m-nodate", "f-act"], "по `at`, новые сверху, мои — тоже")
        #expect(Set(r.suffix(3)) == ["a-req", "p9-x", "m-old"], "без `at` — после, реквизиты тоже бумага полки")
        #expect(r.count == 11 && Set(r).count == 11)
    }

    @Test func recentStopsAtTwenty() {
        var l = DocLibrary()
        l.myDocs = (0..<25).map { Self.doc("d\($0)", at: Int64($0)) }
        let r = DocSections.recent(l)
        #expect(r.count == 20 && r.first?.doc.id == "d24" && r.last?.doc.id == "d5")
        l.myDocs += [Self.doc("unstamped")]
        #expect(DocSections.recent(l).count == 20 && !DocSections.recent(l).map(\.doc.id).contains("unstamped"), "двадцать — всего, а не только с `at`")
    }

    @Test func mineIsByDateNewestFirstUndatedLast() {
        #expect(DocSections.mine(Self.lib()).map(\.doc.id) == ["m-new", "m-old", "m-nodate"])
    }

    @Test func binIsNewestDeletionFirst() {
        #expect(DocSections.bin(Self.lib()).map(\.doc.id) == ["t2", "t1"])
    }

    @Test func orgKindMonthAreaLeavesMineOut() {
        let l = Self.lib()
        let area = DocSections.areaWithoutMine(l)
        #expect(area.count == 8 && !area.contains { $0.isMine }, "«Мои» в разделах 4–6 не показываются")
        #expect(DocSections.shelf(l).count == 11 && DocSections.shelf(l).filter(\.isMine).count == 3)
        #expect(DocSections.area(for: .byKind, l).count == 8 && DocSections.area(for: .mine, l).count == 3)
        #expect(DocSections.area(for: .attention, l).isEmpty && DocSections.area(for: .bin, l).isEmpty, "это не полка")
    }

    @Test func bySessionHasNearestFirstPastLastNoEmptyShoots() {
        let g = DocSections.bySession(Self.lib(), practice: .ru, today: Self.today)
        #expect(g.map(\.session.id) == ["near", "far", "p1", "p9"], "ближайшие по возрастанию, прошедшие — по убыванию дня; «empty» не показана")
        #expect(g[0].docs.map(\.doc.id) == ["n-a", "n-b", "n-brief"], "по виду практики: договор, счёт, ТЗ")
    }

    @Test func bySessionSortsSameKindByTitleAndPutsUnkindedLast() {
        var s = Self.shoot("s", 1, docs: [Self.doc("z", .invoice, title: "Б"), Self.doc("y", nil, title: "Без вида"), Self.doc("x", .invoice, title: "А")])
        s.pay = nil
        var l = DocLibrary(); l.sessions = [s]
        #expect(DocSections.bySession(l, practice: .ru, today: Self.today)[0].docs.map(\.doc.id) == ["x", "z", "y"])
    }

    @Test func todayItselfCountsAsAhead() {
        var l = DocLibrary()
        l.sessions = [Self.shoot("past", -1, docs: [Self.doc("a")]), Self.shoot("now", 0, docs: [Self.doc("b")])]
        #expect(DocSections.bySession(l, practice: .ru, today: Self.today).map(\.session.id) == ["now", "past"])
    }

    @Test func countsMatchTheSections() {
        let c = DocSections.counts(Self.lib(), practice: .ru, today: Self.today)
        #expect(c.recent == 11 && c.bySession == 4 && c.byOrg == 8 && c.byKind == 8 && c.byMonth == 8)
        #expect(c.mine == 3 && c.bin == 2)
        #expect(c.total == 11, "всего в полосе = полка по разделу 4 + «Мои»; корзина не считается")
        #expect(c.count(of: .bin) == 2 && c.count(of: .mine) == 3)
    }

    @Test func attentionCountIsShootsNotReasons() {
        var l = Self.lib()
        // near — договор есть; p1 — акт есть; far — рано; p9 — прошла 9 дней назад без акта;
        // empty — через день, бумаг нет вовсе (нет договора).
        let c = DocSections.counts(l, practice: .ru, today: Self.today)
        #expect(c.attention == 2, "p9 и empty")
        l.sessions[3].docs.append(Self.doc("p9-inv", .invoice))
        l.sessions[3].pay = .flat; l.sessions[3].rate = 10
        #expect(DocSections.counts(l, practice: .ru, today: Self.today).attention == 2, "у p9 теперь две причины (нет акта, нет оплаты) — всё равно одна съёмка")
    }

    @Test func totalAndBinChangeAtOnce() {
        var l = Self.lib()
        let before = DocSections.counts(l, practice: .ru, today: Self.today)
        l.create(Self.doc("fresh"), now: 1)
        l.trash("m-old", now: 2)
        let after = DocSections.counts(l, practice: .ru, today: Self.today)
        #expect(after.total == before.total && after.mine == before.mine && after.bin == before.bin + 1)
        l.trash("p9-x", now: 3)
        #expect(DocSections.counts(l, practice: .ru, today: Self.today).total == before.total - 1)
    }

    // MARK: поиск

    static func words(_ l: DocLibrary) -> DocShelfWords {
        DocShelfTests.words(orgs: l.orgs, sessions: l.sessions)
    }

    static func find(_ q: String, _ l: DocLibrary = lib()) -> [String] {
        DocSearch.search(q, in: DocSections.shelf(l), orgs: l.orgs, sessions: l.sessions, words: words(l)).map(\.doc.id)
    }

    @Test func searchByTitleOrgAndClient() {
        #expect(Self.find("софт") == ["m-new"], "название")
        #expect(Set(Self.find("альфа")) == ["n-b", "n-a", "n-brief", "a-req"], "организация")
        #expect(Self.find("мария") == ["p1-x"], "клиент съёмки")
    }

    @Test func searchIgnoresCaseYoAndMatchesPartOfAWord() {
        var l = Self.lib()
        l.myDocs[0].title = "Счёт Ёлка"
        #expect(Self.find("СЧЕТ елка", l) == ["m-new"], "регистр и ё=е")
        #expect(Self.find("елк", l) == ["m-new"], "часть слова")
    }

    @Test func allWordsMustBeFoundAnywhereInAnyOrder() {
        #expect(Self.find("яр K-contract") == ["y-dog"], "организация + вид из собранного названия")
        #expect(Self.find("K-contract яр") == ["y-dog"], "порядок не важен")
        #expect(Self.find("яр софт").isEmpty, "одно слово не нашлось — нет")
    }

    @Test func kindWordFindsOnlyWhereTheTitleIsBuilt() {
        #expect(Self.find("K-act") == ["p1-x"], "у f-act своё название «Акт» — слово вида его не находит")
    }

    @Test func fileNameAndUrlTailAreNotSearched() {
        var l = Self.lib()
        l.myDocs.append(Att(source: .doc, name: "secretname.pdf", id: "m-file"))
        l.myDocs.append(Att(source: .link, url: "https://host.io/tailword", id: "m-link"))
        #expect(Self.find("secretname", l).isEmpty && Self.find("tailword", l).isEmpty)
    }

    @Test func titleMatchesComeFirstThenNewestDay() {
        let ids = Self.find("яр")
        #expect(ids == ["y-dog", "f-act"], "собранное название «вид · Яр» содержит слово — выше; у f-act своё название «Акт», совпало только по организации")
        let byTitle = Self.find("акт")
        #expect(byTitle.first == "f-act", "совпало в названии — выше всех")
    }

    @Test func emptyQueryIsNotASearch() {
        #expect(Self.find("   ").isEmpty && DocSearch.tokens("  ").isEmpty)
    }

    @Test func binIsNotSearched() {
        #expect(Self.find("t1").isEmpty, "корзина на полке не лежит")
    }
}
