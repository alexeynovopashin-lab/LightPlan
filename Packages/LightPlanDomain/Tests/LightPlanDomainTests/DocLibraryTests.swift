import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Бумаги: создать, перенести, удалить в корзину, вернуть (шаг 28д, § 2.2).
@Suite struct DocLibraryTests {
    typealias Att = LightPlanDomain.Attachment
    static func doc(_ n: String, kind: DocKind? = nil, date: CivilDate? = nil) -> Att {
        Att(source: .link, url: "https://x.io/\(n)", kind: kind, title: n, date: date, id: n)
    }
    static let d1 = CivilDate(year: 2026, month: 9, day: 12)

    static func lib() -> DocLibrary {
        var s = Session(id: "s1", kind: .shoot, day: d1, start: 600, genre: .product)
        s.docs = [doc("s-a"), doc("s-b")]
        var o = Org(id: "o1", name: "Яр")
        o.docs = [doc("o-a", date: CivilDate(year: 2026, month: 1, day: 5))]
        o.requisiteFiles = [Att(source: .doc, name: "rek.pdf", id: "o-req")]
        var s2 = Session(id: "s2", kind: .shoot, day: d1.adding(days: 3), start: 600, genre: .product)
        s2.docs = []
        return DocLibrary(sessions: [s, s2], orgs: [o], myDocs: [doc("m-a")])
    }

    // MARK: знак и время

    @Test func eachNewPaperGetsItsOwnId() {
        let a = Att(source: .link, url: "https://x.io/1"), b = Att(source: .link, url: "https://x.io/1")
        #expect(a.id != b.id && !a.id.isEmpty)
        #expect(a.at == nil, "время ставит операция, а не конструктор")
    }

    @Test func idAndTimeSurviveCodingAndOldPaperGetsAnId() throws {
        let a = Att(source: .link, url: "https://x.io/1", id: "fixed", at: 1_700_000_000_000)
        let back = try JSONDecoder().decode(Att.self, from: JSONEncoder().encode(a))
        #expect(back.id == "fixed" && back.at == 1_700_000_000_000 && back == a)
        let old = try JSONDecoder().decode(Att.self, from: Data(#"{"k":"link","url":"https://x.io/old"}"#.utf8))
        #expect(!old.id.isEmpty && old.at == nil, "бумага без знака получает новый, без времени — «давно»")
        let again = try JSONEncoder().encode(old)
        #expect(try JSONDecoder().decode(Att.self, from: again).id == old.id, "знак записан и больше не меняется")
    }

    // MARK: создать

    @Test func newPaperWithoutOwnerGoesToTheFrontOfMineWithNow() {
        var l = Self.lib()
        let r1 = l.create(Self.doc("new"), now: 500)
        #expect(r1)
        #expect(l.myDocs.map(\.id) == ["new", "m-a"])
        #expect(l.myDocs[0].at == 500)
    }

    @Test func newPaperForShootOrOrgGoesToTheirEndAndShootPaperHasNoOwnDate() {
        var l = Self.lib()
        let r2 = l.create(Self.doc("n1", date: Self.d1), in: .session("s1"), now: 7)
        #expect(r2)
        #expect(l.sessions[0].docs.map(\.id) == ["s-a", "s-b", "n1"] && l.sessions[0].docs[2].date == nil, "днём служит день съёмки")
        let r3 = l.create(Self.doc("n2", date: Self.d1), in: .org("o1"), now: 8)
        #expect(r3)
        #expect(l.orgs[0].docs.map(\.id) == ["o-a", "n2"] && l.orgs[0].docs[1].date == Self.d1 && l.orgs[0].docs[1].at == 8)
    }

    @Test func nothingIsCreatedForAMissingOwnerOrRequisites() {
        var l = Self.lib()
        let before = l
        let r4 = l.create(Self.doc("x"), in: .session("none"), now: 1)
        #expect(!r4)
        let r5 = l.create(Self.doc("x"), in: .org("none"), now: 1)
        #expect(!r5)
        let r6 = l.create(Self.doc("x"), in: .orgRequisite("o1"), now: 1)
        #expect(!r6)
        #expect(l == before)
    }

    @Test func shootInTheShootBinIsNotAnOwner() {
        var l = Self.lib()
        l.trashedSessionIds = ["s2"]
        let r7 = l.create(Self.doc("x"), in: .session("s2"), now: 1)
        #expect(!r7)
    }

    // MARK: перенести

    @Test func moveBetweenMineShootAndOrgKeepsIdAndStampsNow() {
        var l = Self.lib()
        let r8 = l.move("m-a", to: .session("s1"), now: 100)
        #expect(r8)
        #expect(l.myDocs.isEmpty && l.sessions[0].docs.last?.id == "m-a" && l.sessions[0].docs.last?.at == 100)
        let r9 = l.move("m-a", to: .org("o1"), now: 200)
        #expect(r9)
        #expect(l.sessions[0].docs.map(\.id) == ["s-a", "s-b"] && l.orgs[0].docs.map(\.id) == ["o-a", "m-a"])
        let r10 = l.move("m-a", to: .mine, now: 300)
        #expect(r10)
        #expect(l.myDocs.map(\.id) == ["m-a"] && l.myDocs[0].at == 300)
    }

    @Test func leavingAShootKeepsItsDayAsTheOwnDate() {
        var l = Self.lib()
        let r11 = l.move("s-a", to: .mine, now: 1)
        #expect(r11)
        #expect(l.myDocs.first { $0.id == "s-a" }?.date == Self.d1, "иначе потеряется, к какой дате относилась")
        let r12 = l.move("s-b", to: .org("o1"), now: 2)
        #expect(r12)
        #expect(l.orgs[0].docs.last?.date == Self.d1)
    }

    @Test func joiningAShootErasesTheOwnDate() {
        var l = Self.lib()
        let r13 = l.move("o-a", to: .session("s2"), now: 1)
        #expect(r13)
        #expect(l.sessions[1].docs.first?.date == nil)
    }

    @Test func shootToShootDoesNotWriteADate() {
        var l = Self.lib()
        let r14 = l.move("s-a", to: .session("s2"), now: 1)
        #expect(r14)
        #expect(l.sessions[1].docs.first?.date == nil)
    }

    @Test func moveRefusesWhatCannotBeDone() {
        var l = Self.lib()
        let before = l
        let r15 = l.move("m-a", to: .mine, now: 1)
        #expect(!r15, "то же место")
        let r16 = l.move("nope", to: .org("o1"), now: 1)
        #expect(!r16, "бумаги нет")
        let r17 = l.move("m-a", to: .org("none"), now: 1)
        #expect(!r17, "организации нет")
        let r18 = l.move("o-req", to: .mine, now: 1)
        #expect(!r18, "реквизиты остаются у организации")
        let r19 = l.move("m-a", to: .orgRequisite("o1"), now: 1)
        #expect(!r19)
        #expect(l == before, "отказ ничего не меняет")
    }

    // MARK: корзина

    @Test func trashRemembersOwnerPlaceAndTime() {
        var l = Self.lib()
        let r20 = l.trash("s-b", now: 900)
        #expect(r20)
        #expect(l.sessions[0].docs.map(\.id) == ["s-a"])
        #expect(l.trashedDocs.map(\.doc.id) == ["s-b"])
        #expect(l.trashedDocs[0].from == .session("s1") && l.trashedDocs[0].index == 1 && l.trashedDocs[0].deletedAt == 900)
        let r21 = l.trash("m-a", now: 950)
        let r22 = l.trash("o-req", now: 960)
        let r23 = l.trash("o-a", now: 970)
        #expect(r21 && r22 && r23)
        #expect(l.trashedDocs.map(\.doc.id) == ["o-a", "o-req", "m-a", "s-b"], "новая — первой")
        #expect(l.orgs[0].docs.isEmpty && l.orgs[0].requisiteFiles.isEmpty && l.myDocs.isEmpty)
        let r24 = l.trash("nope", now: 1)
        let r25 = l.trash("s-b", now: 1)
        #expect(!r24 && !r25, "уже в корзине — второй раз нельзя")
    }

    @Test func restoreGoesBackToTheSamePlaceAndStampsNow() {
        var l = Self.lib()
        l.trash("s-a", now: 10)
        let r26 = l.restore("s-a", now: 777)
        #expect(r26 == .home)
        #expect(l.sessions[0].docs.map(\.id) == ["s-a", "s-b"], "на своё место, а не в конец")
        #expect(l.sessions[0].docs[0].at == 777 && l.trashedDocs.isEmpty)
    }

    @Test func restoreClampsPlaceToTheEndOfTheArray() {
        var l = Self.lib()
        l.trash("s-b", now: 10)
        l.trash("s-a", now: 11)
        l.sessions[0].docs = []
        let r27 = l.restore("s-b", now: 20)
        #expect(r27 == .home, "было место 1, а в массиве пусто")
        #expect(l.sessions[0].docs.map(\.id) == ["s-b"])
    }

    @Test func requisiteFileReturnsToRequisites() {
        var l = Self.lib()
        l.trash("o-req", now: 1)
        let r28 = l.restore("o-req", now: 2)
        #expect(r28 == .home)
        #expect(l.orgs[0].requisiteFiles.map(\.id) == ["o-req"])
    }

    @Test func restoreWithoutTheOwnerGoesToMineAndSaysWho() {
        var l = Self.lib()
        l.trash("o-a", now: 1)
        l.trash("s-a", now: 2)
        l.orgs = []
        l.trashedSessionIds = ["s1"]
        let r29 = l.restore("o-a", now: 5)
        #expect(r29 == .mine(lost: .org("o1")))
        let r30 = l.restore("s-a", now: 6)
        #expect(r30 == .mine(lost: .session("s1")), "съёмка в корзине съёмок — хозяина нет")
        #expect(l.myDocs.map(\.id) == ["s-a", "o-a", "m-a"] && l.myDocs[0].at == 6)
        let r31 = l.restore("o-a", now: 7)
        #expect(r31 == nil, "из корзины уже ушла")
    }

    @Test func purgeAndClearDestroyForever() {
        var l = Self.lib()
        l.trash("s-a", now: 1); l.trash("s-b", now: 2); l.trash("m-a", now: 3)
        let r32 = l.purge("s-b")
        #expect(r32 && l.trashedDocs.map(\.doc.id) == ["m-a", "s-a"])
        let r33 = l.purge("s-b")
        #expect(!r33)
        l.clearTrash()
        #expect(l.trashedDocs.isEmpty && l.locate("s-a") == nil && l.locate("m-a") == nil)
    }

    @Test func ownerStringRoundTripsAndIdMayContainColon() {
        for o in [DocOwner.mine, .session("a:b"), .org("o1"), .orgRequisite("o2")] {
            #expect(DocOwner(snapshotString: o.snapshotString) == o)
        }
        #expect(DocOwner(snapshotString: "weird") == nil)
        let t = TrashedDoc(doc: Self.doc("x"), from: .orgRequisite("o2"), index: 3, deletedAt: 9)
        let back = try? JSONDecoder().decode(TrashedDoc.self, from: JSONEncoder().encode(t))
        #expect(back == t)
        let junk = try? JSONDecoder().decode(TrashedDoc.self, from: Data(#"{"doc":{"k":"link"},"from":"???","index":1,"del":5}"#.utf8))
        #expect(junk?.from == .mine, "неразборчивый хозяин не теряет бумагу")
    }

    @Test func orgBookRemovesByIdNotByNumber() {
        var o = Self.lib().orgs[0]
        #expect(OrgBook.removeDoc(id: "o-a", from: &o) && o.docs.isEmpty)
        #expect(!OrgBook.removeDoc(id: "o-a", from: &o))
    }
}
