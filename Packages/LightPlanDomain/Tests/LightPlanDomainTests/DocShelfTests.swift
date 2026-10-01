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

    @Test func twoDatedPapersInOneGroupSwapOrderWithDirectionAndUndatedStaysLast() {
        var o = Org(id: "y", name: "Яр"); o.docs = [Self.link("https://x.io/nodate", kind: .contract, title: "Без даты")]
        let sessions = [Self.shoot("a", Self.day(3), org: "y", docs: [Self.link("https://x.io/a", kind: .act, title: "Раннее")]),
                        Self.shoot("b", Self.day(9), org: "y", docs: [Self.link("https://x.io/b", kind: .act, title: "Позднее")])]
        let shelf = OrgBook.shelf(orgs: [o], sessions: sessions)
        let w = Self.words(orgs: [o], sessions: sessions)
        var p = DocsPrefs()
        func order() -> [String] { DocShelf.groups(shelf, prefs: p, practice: .ru, words: w)[0].rows.map(\.title) }
        #expect(order() == ["Позднее", "Раннее", "Без даты"], "по умолчанию новые сверху, без даты внизу")
        p.tapColumn(.date)
        #expect(p.ascending && order() == ["Раннее", "Позднее", "Без даты"], "тап по «Дата» разворачивает порядок; без даты всё равно внизу")
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

    // MARK: шаг 12б — таблица, месяцы, имя в группе и вне, поле «Дата»

    static func titles(_ rows: [DocShelf.Row]) -> [String] { rows.map(\.title) }

    @Test func tableSortsByEveryColumnBothWaysWithEmptyCellsLast() {
        // Названия и организации — латиницей: порядок кириллицы и латиницы зависит от языка устройства.
        let alpha = { () -> Org in var o = Org(id: "a", name: "Alpha"); o.docs = [Self.link("u/f", kind: .act, title: "a 2")]; return o }()
        var bravo = Org(id: "b", name: "Bravo"); bravo.docs = [Self.link("u/d", kind: .contract, title: "d")]
        let sessions = [Self.shoot("s1", Self.day(3), org: "b", docs: [Self.link("u/c", kind: .act, title: "c")]),
                        Self.shoot("s2", Self.day(20), org: "a", docs: [Self.link("u/B", kind: .invoice, title: "B")]),
                        Self.shoot("s3", Self.day(10, month: 8), org: nil, client: "Zed", docs: [Self.link("u/n", kind: .contract, title: "a 10")]),
                        Self.shoot("s5", Self.day(5), org: nil, docs: [Self.link("u/e", kind: .brief, title: "e")])]
        let w = Self.words(orgs: [alpha, bravo], sessions: sessions)
        let shelf = OrgBook.shelf(orgs: [alpha, bravo], sessions: sessions)
        var p = DocsPrefs()
        func t() -> [String] { Self.titles(DocShelf.table(shelf, prefs: p, words: w)) }
        #expect(t() == ["B", "e", "c", "a 10", "a 2", "d"], "дата: новые сверху, без даты внизу")
        p.tapColumn(.date)
        #expect(t() == ["a 10", "c", "e", "B", "a 2", "d"], "повтор — обратный порядок, без даты всё равно внизу")
        p.tapColumn(.title)
        #expect(t() == ["a 2", "a 10", "B", "c", "d", "e"], "название А→Я без учёта регистра, числа по значению")
        p.tapColumn(.title)
        #expect(t() == ["e", "d", "c", "B", "a 10", "a 2"])
        p.tapColumn(.org)
        #expect(t() == ["B", "a 2", "c", "d", "a 10", "e"], "организация А→Я; без организации — внизу; внутри — новые сверху")
        p.tapColumn(.org)
        #expect(t() == ["a 10", "c", "d", "B", "a 2", "e"], "обратный порядок; без организации всё равно внизу")
        p.tapColumn(.kind)
        #expect(t() == ["c", "a 2", "e", "a 10", "d", "B"], "вид А→Я; внутри вида — новые сверху")
        p.tapColumn(.kind)
        #expect(t() == ["B", "a 10", "d", "e", "c", "a 2"])
    }

    @Test func tableNamesAreFullAndColumnTapKeepsDirectionRules() {
        let f = Self.fixture()
        let rows = DocShelf.table(f.shelf, prefs: DocsPrefs(), words: f.words)
        #expect(rows.contains { $0.title == "K-invoice · Альфа · 20.9" }, "вне группы имя полное: вид · организация · дата")
        var p = DocsPrefs()
        p.tapColumn(.org); #expect(p.sortKey == .org && p.ascending, "организация — сперва А→Я")
        p.tapColumn(.kind); #expect(p.sortKey == .kind && p.ascending)
        p.tapColumn(.date); #expect(p.sortKey == .date && !p.ascending, "дата — сперва новые сверху")
    }

    @Test func nameInsideGroupDropsWhatTheHeaderAlreadySays() {
        let f = Self.fixture()
        func group(_ g: DocGrouping, _ label: String) -> [String] {
            var p = DocsPrefs(); p.grouping = g
            return Self.titles(DocShelf.groups(f.shelf, prefs: p, practice: .ru, words: f.words).first { $0.label == label }!.rows)
        }
        #expect(group(.org, "Альфа") == ["K-invoice · 20.9", "Реквизиты"], "в группе организации — «Вид · дата», без организации")
        #expect(group(.org, "Яр").contains("K-contract"), "у бумаги без даты и без повтора организации — только вид")
        #expect(group(.month, "9/2026") == ["K-invoice · Альфа", "K-brief", "Акт Б"], "в месяце — без даты, организация остаётся")
        #expect(group(.kind, "K-invoice") == ["K-invoice · Альфа · 20.9"], "в группе вида имя полное")
        #expect(DocShelf.row(f.shelf.first { $0.doc.url == "https://x.io/schet" }!, f.words).title == "K-invoice · Альфа · 20.9", "вне группы — полное")
    }

    @Test func monthsViewIsNewestMonthFirstNewestPaperFirstAndUndatedLast() {
        let f = Self.fixture()
        let g = DocShelf.months(f.shelf, practice: .ru, words: f.words)
        #expect(g.map(\.label) == ["9/2026", "8/2026", "Без даты"])
        #expect(g[0].rows.map { $0.shelf.day?.day } == [20, 5, 3], "в месяце — от новых")
        #expect(g[2].rows.count == 2 && g[2].rows.allSatisfy { $0.shelf.day == nil }, "бумаги без даты — последней группой")
    }

    @Test func listIgnoresTableOnlySortKeysLeftFromTheTable() {
        // ревью GPT к 92b1a9b: сортировка таблицы по виду или организации не должна менять порядок списка
        let f = Self.fixture()
        func order(_ p: DocsPrefs) -> [[String]] {
            DocShelf.groups(f.shelf, prefs: p, practice: .ru, words: f.words).map { Self.titles($0.rows) }
        }
        let plain = order(DocsPrefs())
        var p = DocsPrefs(); p.tapColumn(.org)
        #expect(order(p) == plain, "после таблицы с сортировкой по организации список — как по умолчанию")
        p.tapColumn(.kind); p.tapColumn(.kind)
        #expect(order(p) == plain, "и по виду, в любую сторону")
        p.layout = .list; p.tapColumn(.title)
        #expect(order(p) != plain || p.sortKey == .title, "тап по «Название» в списке работает как прежде")
    }

    @Test func monthsViewIgnoresRememberedTableSort() {
        // запомненная сортировка таблицы не должна переставлять месяцы
        let f = Self.fixture()
        var p = DocsPrefs(); p.layout = .months; p.tapColumn(.title); p.tapColumn(.org)
        #expect(DocsPrefs.from(p.data()).sortKey == .org, "ключ таблицы запоминается")
        #expect(DocShelf.months(f.shelf, practice: .ru, words: f.words).first?.rows.map { $0.shelf.day?.day } == [20, 5, 3])
    }

    @Test func orgPaperDateRoundTripsPlacesPaperInItsMonthAndSortsByIt() throws {
        var y = Org(id: "y", name: "Яр")
        let d1 = Att.link("a.io/new", kind: .act, title: "Ноябрьский", date: CivilDate(year: 2026, month: 11, day: 4))!
        let d2 = Att.link("a.io/late", kind: .act, title: "Конец сентября", date: Self.day(30))!
        let d3 = Att.link("a.io/none", kind: .act, title: "Без числа")!
        #expect(OrgBook.addLink("a.io/via", kind: .act, title: "Через addLink", date: Self.day(1), to: &y))
        y.docs += [d1, d2, d3]
        #expect(y.docs[0].date == Self.day(1))
        let sessions = [Self.shoot("s", Self.day(20), org: "y", docs: [Self.link("https://x.io/s", kind: .act, title: "Съёмка")])]
        let w = Self.words(orgs: [y], sessions: sessions)
        let shelf = OrgBook.shelf(orgs: [y], sessions: sessions)
        let g = DocShelf.months(shelf, practice: .ru, words: w)
        #expect(g.map(\.label) == ["11/2026", "9/2026", "Без даты"], "бумага с датой встаёт в свой месяц")
        #expect(Self.titles(g[1].rows) == ["Конец сентября", "Съёмка", "Через addLink"], "и сортируется по ней вместе со съёмками")
        #expect(g[2].rows.map(\.title) == ["Без числа"])
        let back = try JSONDecoder().decode(Att.self, from: JSONEncoder().encode(d1))
        #expect(back.date == CivilDate(year: 2026, month: 11, day: 4))
        let enc = String(decoding: try JSONEncoder().encode(d3), as: UTF8.self)
        #expect(!enc.contains("date"), "пустая дата в данные не пишется")
        #expect(try JSONDecoder().decode(Att.self, from: Data(#"{"k":"link","url":"https://a.io","date":"мусор"}"#.utf8)).date == nil, "негодная дата читается как «нет даты»")
        #expect(try JSONDecoder().decode(Att.self, from: Data(#"{"k":"link","url":"https://a.io"}"#.utf8)).date == nil, "старая запись без даты читается")
    }
}
