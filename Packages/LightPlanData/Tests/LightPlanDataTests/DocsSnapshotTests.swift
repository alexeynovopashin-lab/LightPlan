import Testing
import Foundation
import LightPlanDomain
@testable import LightPlanData

/// Шаг 28д: «Мои» и корзина документов в снимке; бумага со знаком и временем переживает чтение-запись.
struct DocsSnapshotTests {
    typealias Att = LightPlanDomain.Attachment

    @Test func missingKeysMeanEmpty() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data("{}".utf8))
        #expect(s.myDocs.isEmpty && s.trashedDocs.isEmpty)
    }

    @Test func myDocsAndTrashRoundTrip() throws {
        var s = Snapshot()
        s.myDocs = [Att(source: .link, url: "https://x.io/a", kind: .invoice, title: "Счёт", id: "m1", at: 10)]
        s.trashedDocs = [TrashedDoc(doc: Att(source: .link, url: "https://x.io/b", id: "t1", at: 5),
                                    from: .session("s1"), index: 2, deletedAt: 99)]
        let back = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(s))
        #expect(back.myDocs == s.myDocs && back.trashedDocs == s.trashedDocs)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]
        #expect(obj?["myDocs"] != nil && obj?["trashedDocs"] != nil, "ключи сохраняются под своими именами")
    }

    @Test func docLibraryWritesBackOnlyWhatTheRulesChange() {
        var s = Snapshot()
        s.sessions = [Session(id: "s1", kind: .shoot, day: .init(year: 2026, month: 10, day: 1), start: 600, genre: .product)]
        s.trashed = [TrashedItem(record: Session(id: "gone", kind: .shoot, day: .init(year: 2026, month: 9, day: 1), start: 600), index: 0, deletedAt: 1)]
        s.extra["graves"] = .array([])
        var lib = s.docLibrary
        #expect(lib.trashedSessionIds == ["gone"], "съёмка в корзине съёмок известна правилам")
        lib.create(Att(source: .link, url: "https://x.io/n", id: "n"), in: .session("s1"), now: 5)
        lib.create(Att(source: .link, url: "https://x.io/m", id: "m"), now: 6)
        lib.trash("n", now: 7)
        s.docLibrary = lib
        #expect(s.myDocs.map(\.id) == ["m"] && s.trashedDocs.map(\.doc.id) == ["n"] && s.sessions[0].docs.isEmpty)
        #expect(s.trashed.count == 1 && s.extra["graves"] != nil, "корзина съёмок и чужие ключи не тронуты")
    }
}
