import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Раздел «Документы»: название бумаги, группы, сортировки, запоминание (итерация 28, шаг 12а).
@Suite struct DocShelfTests {
    typealias Att = LightPlanDomain.Attachment
    typealias Words = DocShelfWords

    static func day(_ d: Int, month: Int = 9) -> CivilDate { CivilDate(year: 2026, month: month, day: d) }

    /// Слова-заглушки: организации и клиенты берутся из переданных списков.
    static func words(orgs: [Org] = [], sessions: [Session] = []) -> Words {
        Words(kindName: { k in "K-" + k.rawValue }, requisite: "Реквизиты", fileWord: "Файл",
              privateClients: "Частные клиенты", noDate: "Без даты",
              owner: { d in
                  if let s = sessions.first(where: { $0.id == d.sessionId }), s.orgId == nil {
                      return s.contact.isEmpty ? nil : .init(key: "c:" + s.contact, label: s.contact)
                  }
                  guard let id = d.orgId, let o = orgs.first(where: { $0.id == id }) else { return nil }
                  return .init(key: id, label: o.name)
              },
              dateText: { "\($0.day).\($0.month)" },
              monthLabel: { y, m in "\(m)/\(y)" })
    }

    static func shoot(_ id: String, _ d: CivilDate, org: String?, client: String = "", docs: [Att]) -> Session {
        var s = Session(id: id, kind: .shoot, day: d, start: 600, end: 720, duration: 120, genre: .wedding)
        s.orgId = org
        s.contact = client
        s.docs = docs
        return s
    }

    static func link(_ url: String, kind: DocKind? = nil, title: String? = nil) -> Att {
        Att(source: .link, url: url, kind: kind, title: title)
    }

    /// Организации «Яр» и «Альфа», съёмки с бумагами, бумага без организации и без клиента.
    static func fixture() -> (shelf: [OrgBook.ShelfDoc], words: Words) {
        var yar = Org(id: "y", name: "Яр"); yar.docs = [link("https://x.io/yar", kind: .contract)]
        var alfa = Org(id: "a", name: "Альфа")
        alfa.requisiteFiles = [Att(source: .img, name: "rek.png")]
        let sessions = [
            shoot("s1", day(3), org: "y", docs: [link("https://x.io/akt", kind: .act, title: "Акт Б")]),
            shoot("s2", day(20), org: "a", docs: [link("https://x.io/schet", kind: .invoice)]),
            shoot("s3", day(10, month: 8), org: nil, client: "Мария", docs: [link("https://x.io/dog", kind: .contract, title: "акт А")]),
            shoot("s4", day(5), org: nil, docs: [link("https://x.io/tz", kind: .brief)]),
        ]
        let orgs = [yar, alfa]
        return (OrgBook.shelf(orgs: orgs, sessions: sessions), words(orgs: orgs, sessions: sessions))
    }

    // MARK: название

    @Test func titleIsOwnOrBuiltFromKindOwnerAndDate() {
        let f = Self.fixture()
        let byUrl = Dictionary(uniqueKeysWithValues: f.shelf.map { ($0.doc.url ?? $0.doc.name ?? "", DocShelf.row($0, f.words)) })
        #expect(byUrl["https://x.io/akt"]?.title == "Акт Б", "своё название главнее")
        #expect(byUrl["https://x.io/schet"]?.title == "K-invoice · Альфа · 20.9", "вид · организация · дата")
        #expect(byUrl["https://x.io/dog"]?.title == "акт А")
        #expect(byUrl["https://x.io/tz"]?.title == "K-brief · 5.9", "ни организации, ни клиента — без середины")
        #expect(byUrl["https://x.io/yar"]?.title == "K-contract · Яр", "у бумаги организации даты нет")
        #expect(byUrl["rek.png"]?.title == "Реквизиты · Альфа")
        for r in f.shelf.map({ DocShelf.row($0, f.words) }) {
            #expect(!r.title.contains("x.io") && !r.title.contains("/"), "хвост ссылки именем не бывает")
        }
    }

    @Test func blankTitleCountsAsNoTitleAndSurvivesCodable() throws {
        #expect(Att.link("a.io/x", kind: nil, title: "   ")?.title == nil, "пробелы — не название")
        #expect(Att.link("a.io/x", kind: nil, title: " Договор ")?.title == "Договор")
        let a = Att.link("a.io/x", kind: .act, title: "Мой акт")!
        let back = try JSONDecoder().decode(Att.self, from: JSONEncoder().encode(a))
        #expect(back.title == "Мой акт")
        let old = try JSONDecoder().decode(Att.self, from: Data(#"{"k":"link","url":"https://a.io"}"#.utf8))
        #expect(old.title == nil, "старая запись без названия читается")
    }

    // MARK: группы

    @Test func groupsByOrganizationWithClientAndPrivateGroups() {
        let f = Self.fixture()
        let g = DocShelf.groups(f.shelf, prefs: DocsPrefs(), practice: .ru, words: f.words)
        #expect(g.map(\.label) == ["Альфа", "Мария", "Яр", "Частные клиенты"], "по алфавиту, частные последними")
        #expect(g.map { $0.rows.count } == [2, 1, 2, 1])
        #expect(g.last?.rows.first?.shelf.doc.url == "https://x.io/tz", "без организации и клиента — «Частные клиенты»")
    }

    @Test func groupsByMonthNewestFirstAndKeepsUndatedLast() {
        let f = Self.fixture()
        var p = DocsPrefs(); p.grouping = .month
        let g = DocShelf.groups(f.shelf, prefs: p, practice: .ru, words: f.words)
        #expect(g.map(\.label) == ["9/2026", "8/2026", "Без даты"])
        p.ascending = true
        #expect(DocShelf.groups(f.shelf, prefs: p, practice: .ru, words: f.words).map(\.label) == ["8/2026", "9/2026", "Без даты"])
    }

    @Test func groupsByKindInPracticeOrderThenRequisitesAndFile() {
        let f = Self.fixture()
        var p = DocsPrefs(); p.grouping = .kind
        let g = DocShelf.groups(f.shelf, prefs: p, practice: .ru, words: f.words)
        let order = LightPlanDomain.Practice.ru.docKinds.map { "K-" + $0.rawValue }
        let kinds = g.map(\.label).filter { order.contains($0) }
        #expect(kinds == order.filter(kinds.contains), "виды идут в порядке практики")
        #expect(g.suffix(1).map(\.label) == ["Реквизиты"])
    }

    // MARK: сортировки

    @Test func sortsByDateBothWaysWithUndatedAlwaysLast() {
        var f = Self.fixture()
        f.shelf = f.shelf.filter { $0.doc.url != "https://x.io/tz" }
        var p = DocsPrefs(); p.grouping = .kind
        func titles(_ p: DocsPrefs) -> [String] {
            DocShelf.groups(f.shelf, prefs: p, practice: .ru, words: f.words).flatMap(\.rows).filter { $0.shelf.kind == .contract }.map(\.title)
        }
        // договоры: «акт А» 10.8, «K-contract · Яр» без даты
        #expect(titles(p) == ["акт А", "K-contract · Яр"])
        p.ascending = true
        #expect(titles(p) == ["акт А", "K-contract · Яр"], "без даты — внизу и при сортировке вверх")
        let rows = DocShelf.groups(f.shelf, prefs: DocsPrefs(), practice: .ru, words: f.words)
        #expect(rows.first(where: { $0.label == "Альфа" })?.rows.first?.shelf.day == Self.day(20))
    }

    @Test func sortsByTitleIgnoringCaseAndTapFlipsDirection() {
        let f = Self.fixture()
        var p = DocsPrefs(); p.grouping = .kind
        let all = f.shelf.filter { $0.kind == .act || $0.kind == .contract }
        var q = p; q.tapColumn(.title)
        #expect(q.sortKey == .title && q.ascending, "название — сперва А→Я")
        let up = DocShelf.groups(all, prefs: q, practice: .ru, words: f.words).flatMap(\.rows).map(\.title)
        // группы: договор, акт — внутри каждой по названию
        #expect(Set(up) == ["K-contract · Яр", "акт А", "Акт Б"] && up.last == "Акт Б", "группа договоров, потом акт")
        var down = q; down.tapColumn(.title)
        let rev = DocShelf.groups(all, prefs: down, practice: .ru, words: f.words).flatMap(\.rows).map(\.title)
        #expect(Array(rev.prefix(2)) == Array(up.prefix(2).reversed()), "обратный порядок внутри группы — зеркало прямого")
        var one = DocsPrefs(); one.grouping = .month; one.tapColumn(.title)
        let a = DocShelf.groups(all, prefs: one, practice: .ru, words: f.words).first { $0.label == "9/2026" }!.rows.map(\.title)
        #expect(a == ["Акт Б"])
        one.tapColumn(.title)
        #expect(!one.ascending, "второй тап по той же колонке — обратный порядок")
        one.tapColumn(.date)
        #expect(one.sortKey == .date && !one.ascending, "дата — новые сверху")
        one.tapColumn(.date)
        #expect(one.ascending)
    }

    @Test func titleSortIsCaseInsensitiveAndNumeric() {
        let rows = ["б 10", "Б 2", "а 1"].map { t in
            DocShelf.Row(shelf: OrgBook.ShelfDoc(doc: Att(source: .link, url: "u"), kind: nil, isRequisite: false, orgId: nil, sessionId: nil, day: nil),
                         title: t, kindLabel: "", ownerLabel: nil, dateText: nil)
        }
        var p = DocsPrefs(); p.sortKey = .title; p.ascending = true
        #expect(DocShelf.sorted(rows, p).map(\.title) == ["а 1", "Б 2", "б 10"])
        p.ascending = false
        #expect(DocShelf.sorted(rows, p).map(\.title) == ["б 10", "Б 2", "а 1"])
    }

    // MARK: фильтр чипов и запоминание

    @Test func kindChipFilterNarrowsGroupsAndDropsEmptyOnes() {
        let f = Self.fixture()
        let only = OrgBook.filtered(f.shelf, kind: .invoice)
        let g = DocShelf.groups(only, prefs: DocsPrefs(), practice: .ru, words: f.words)
        #expect(g.map(\.label) == ["Альфа"] && g[0].rows.count == 1, "пустые группы не рисуются")
        #expect(OrgBook.shelfKinds(f.shelf, practice: .ru, selected: nil).first { $0.kind == .contract }?.count == 2)
    }

    @Test func prefsRoundTripKeepLayoutGroupingSortAndCollapsedGroups() {
        var p = DocsPrefs()
        p.layout = .months; p.grouping = .month; p.tapColumn(.title); p.toggleGroup("org:y"); p.toggleGroup("m:2026-09")
        let back = DocsPrefs.from(p.data())
        #expect(back == p && back.collapsed == ["org:y", "m:2026-09"])
        var q = back; q.toggleGroup("org:y")
        #expect(q.collapsed == ["m:2026-09"], "второй тап разворачивает")
        #expect(DocsPrefs.from(nil) == DocsPrefs(), "нет записи — вид «список», группы по организации")
        #expect(DocsPrefs.from(Data(#"{"layout":"cube","grouping":"x","collapsed":["a"]}"#.utf8)).layout == .list, "незнакомый вид не роняет")
        #expect(DocsPrefs.from(Data("мусор".utf8)) == DocsPrefs())
    }
}
