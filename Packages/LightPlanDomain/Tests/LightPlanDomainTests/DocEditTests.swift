import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Правка бумаги и «последние» в привязке быстрого «+» (шаг 28д.4).
@Suite struct DocEditTests {
    typealias Att = LightPlanDomain.Attachment
    static let d1 = DocLibraryTests.d1

    // MARK: бумага из «+»

    @Test func paperKeepsChosenNoKindAndLinkIsOptional() {
        let a = Att.paper(url: "x.io/dogovor", kind: nil, title: "  ")
        #expect(a.kind == nil, "«Без вида», выбранный человеком, не угадывается по ссылке заново")
        #expect(a.url == "https://x.io/dogovor" && a.title == nil && a.date == nil)
        let b = Att.paper(url: "", kind: .invoice, title: " Счёт ")
        #expect(b.url == nil && b.title == "Счёт" && b.kind == .invoice, "без ссылки бумага — запись; даты не подставляем")
    }

    // MARK: правка

    @Test func editChangesKindTitleUrlAndStampsNow() {
        var l = DocDocs.lib()
        let ok = l.edit("m-a", .init(kind: .act, title: " Акт ", url: "y.io/z", date: Self.d1), now: 900)
        #expect(ok)
        let d = l.myDocs[0]
        #expect(d.kind == .act && d.title == "Акт" && d.url == "https://y.io/z" && d.date == Self.d1 && d.at == 900 && d.id == "m-a")
    }

    @Test func editWithEmptyTitleAndKindClearsThem() {
        var l = DocDocs.lib()
        l.edit("o-a", .init(kind: .contract, title: "x", url: "a.io"), now: 1)
        l.edit("o-a", .init(kind: nil, title: "", url: "a.io"), now: 2)
        #expect(l.orgs[0].docs[0].kind == nil && l.orgs[0].docs[0].title == nil && l.orgs[0].docs[0].date == nil, "дата не возвращается сама")
    }

    @Test func shootPaperNeverKeepsItsOwnDate() {
        var l = DocDocs.lib()
        l.edit("s-a", .init(kind: nil, title: "", url: "x.io", date: Self.d1), now: 1)
        #expect(l.sessions[0].docs[0].date == nil, "у бумаги съёмки днём служит день съёмки")
    }

    @Test func fileKeepsItsUrlAndRequisitesCannotBeEdited() {
        var l = DocDocs.lib()
        l.myDocs.append(Att(source: .doc, path: "p", name: "f.pdf", id: "file"))
        l.edit("file", .init(kind: .brief, title: "ТЗ", url: "evil.io"), now: 5)
        #expect(l.myDocs.last?.url == nil && l.myDocs.last?.kind == .brief)
        let before = l
        let req = l.edit("o-req", .init(title: "x"), now: 6), none = l.edit("нет", .init(title: "x"), now: 6)
        #expect(!req && !none && l == before)
    }

    @Test func editThenMoveKeepsIdAndEdits() {
        var l = DocDocs.lib()
        l.edit("m-a", .init(kind: .invoice, title: "Счёт", url: "x.io/a"), now: 10)
        let moved = l.move("m-a", to: .org("o1"), now: 11)
        #expect(moved)
        let d = l.orgs[0].docs.last!
        #expect(d.id == "m-a" && d.kind == .invoice && d.title == "Счёт" && l.myDocs.isEmpty)
    }

    // MARK: последние

    private func lib(days: [Int], today: CivilDate) -> DocLibrary {
        DocLibrary(sessions: days.enumerated().map { i, n in
            var s = Session(id: "s\(i)", kind: .shoot, day: today.adding(days: n), start: 600, genre: .product)
            s.orgId = i % 2 == 0 ? "o1" : nil
            return s
        }, orgs: [Org(id: "o1", name: "Яр"), Org(id: "o2", name: "Аква"), Org(id: "o3", name: "Бриз")])
    }

    @Test func recentSessionsAreTwoNearestFutureThenThreeLatestPast() {
        let today = Self.d1
        let l = lib(days: [-9, -1, -5, 4, 1, 30, -2, 0, -20], today: today)
        let r = DocBinding.recentSessions(l, today: today)
        #expect(r.map { $0.day } == [0, 1, -1, -2, -5].map { today.adding(days: $0) },
                "сегодня — будущая; две ближайшие будущие по возрастанию, три последние прошедшие от новых")
        #expect(DocBinding.recentSessions(lib(days: [3], today: today), today: today).count == 1)
    }

    @Test func recentSessionsSkipSessionsInTheShootBin() {
        let today = Self.d1
        var l = lib(days: [1, 2, 3], today: today)
        l.trashedSessionIds = ["s0"]
        #expect(DocBinding.recentSessions(l, today: today).map(\.id) == ["s1", "s2"])
    }

    @Test func recentOrgsGoByLastShootThenAlphabeticalWithoutShoots() {
        let today = Self.d1
        // o1 — съёмки на 0, 2 (i=0,2…); o2/o3 без съёмок
        let l = lib(days: [0, 5, 2], today: today)
        #expect(DocBinding.recentOrgs(l).map(\.id) == ["o1", "o2", "o3"], "с днём — первыми, остальные по алфавиту: Аква, Бриз")
        #expect(DocBinding.recentOrgs(l, limit: 2).map(\.id) == ["o1", "o2"])
    }
}

enum DocDocs { static func lib() -> DocLibrary { DocLibraryTests.lib() } }
