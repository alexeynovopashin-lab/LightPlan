import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Итерация 28, шаг 5в: листы мудборда — меню подборки, «Добавить в…», «Новая подборка», обложка, теги.
struct MoodboardSheetsTests {
    private func lib() -> RefLibrary {
        let shots = [RefFrame(id: "a", kind: .img, im: "a.jpg", tags: ["Пара"]), RefFrame(id: "b", kind: .link, url: "https://x.io/p"),
                     RefFrame(id: "c", im: "c.jpg"), RefFrame(id: "d")]
        let w = RefBoard(id: "w", kind: .tpl, genre: "wedding", items: ["a", "b", "c"])
        let sea = RefBoard(id: "sea", kind: .tpl, genre: "wedding", items: ["c"], name: "На море")
        let por = RefBoard(id: "por", kind: .tpl, genre: "portrait", items: ["d"])
        let shoot = RefBoard(id: "s1", kind: .shoot, sid: "S1", genre: "wedding", items: ["a"])
        return RefLibrary(shots: shots, boards: [w, sea, por, shoot])
    }

    // MARK: меню

    @Test func menuOfGenreFolderHasAllSevenItems() {
        let l = lib()
        let m = MbSheets.menu(l.board("w")!, frames: 3, mergeTargets: MbSheets.mergeTargets(of: l.board("w")!, in: l).count)
        #expect(m == [.sort, .cover, .pick, .rename, .newFolder, .merge, .delete])
    }

    @Test func menuOfShootHasNoNewFolderAndNoMerge() {
        let l = lib()
        #expect(MbSheets.menu(l.board("s1")!, frames: 1, mergeTargets: 5) == [.sort, .cover, .pick, .rename, .delete])
    }

    @Test func emptyFolderHasNoCoverAndNoPick() {
        let b = RefBoard(id: "e", kind: .tpl, genre: "wedding")
        #expect(MbSheets.menu(b, frames: 0, mergeTargets: 0) == [.sort, .rename, .newFolder, .delete])
    }

    @Test func mergeTargetsOwnGenreFirstThenOthersNeverShoots() {
        let l = lib()
        #expect(MbSheets.mergeTargets(of: l.board("w")!, in: l).map(\.id) == ["sea", "por"])
        #expect(MbSheets.mergeTargets(of: l.board("por")!, in: l).map(\.id) == ["w", "sea"])
        #expect(MbSheets.mergeTargets(of: l.board("s1")!, in: l).isEmpty)
        #expect(MbSheets.mergeMoving(l.board("w")!, into: l.board("sea")!) == 2)   // «c» уже там
    }

    // MARK: порядок, имя, обложка

    @Test func sortAcceptsOnlyThreeValues() {
        var l = lib()
        let r1 = l.setSort(2, of: "w", now: 5)
        #expect(r1)
        #expect(l.board("w")?.sort == 2 && l.board("w")?.mt == 5)
        let r2 = l.setSort(3, of: "w")
        let r3 = l.setSort(-1, of: "w")
        let r4 = l.setSort(1, of: "нет")
        #expect(r2 == false && r3 == false && r4 == false)
        #expect(l.board("w")?.sort == 2)
    }

    @Test func renameTrimsAndEmptyClearsName() {
        var l = lib()
        let r5 = l.rename("sea", to: "  Закат  ")
        #expect(r5)
        #expect(l.board("sea")?.name == "Закат")
        let r6 = l.rename("sea", to: "   ")
        #expect(r6)
        #expect(l.board("sea")?.name == nil)
        let r7 = l.rename("нет", to: "x")
        #expect(r7 == false)
    }

    @Test func coverOnlyFromOwnFramesAndNilIsAuto() {
        var l = lib()
        let r8 = l.setCover("a", of: "w")
        #expect(r8)
        #expect(l.board("w")?.cover == "a")
        let r9 = l.setCover("d", of: "w")
        #expect(r9 == false)             // «d» в этой подборке не лежит
        #expect(l.board("w")?.cover == "a")
        let r10 = l.setCover(nil, of: "w")
        #expect(r10)
        #expect(l.board("w")?.cover == nil)
        #expect(l.coverCandidates("w").map(\.id) == ["a", "c"])   // «b» — ссылка без картинки
    }

    // MARK: «Добавить в…»

    private func rows(_ l: RefLibrary, shot: String?, excluding: String?, on: [String] = ["wedding", "portrait", "street"]) -> [MbSheets.AddRow] {
        MbSheets.addRows(l, genresOn: on, shot: shot, excluding: excluding,
                         shootTitle: { $0.sid == "S1" ? "Иванова" : nil }, genreName: { $0 })
    }

    @Test func addRowsListShootsThenFoldersThenFreeGenres() {
        let r = rows(lib(), shot: nil, excluding: nil)
        #expect(r.map(\.title) == ["Иванова", "wedding", "wedding · На море", "portrait", "street"])
        #expect(r.last?.target == .newGenre("street"))
    }

    @Test func addRowsHideTheFolderTheyTakeFrom() {
        let r = rows(lib(), shot: nil, excluding: "w")
        #expect(!r.contains { $0.target == .board("w") })
        #expect(r.contains { $0.target == .board("sea") })
    }

    @Test func addRowsHideTheShootFolderTheyTakeFrom() {
        let r = rows(lib(), shot: nil, excluding: "s1")
        #expect(!r.contains { $0.target == .board("s1") } && r.contains { $0.target == .board("w") })
    }

    @Test func addRowsCheckWhereTheShotLies() {
        let r = rows(lib(), shot: "c", excluding: nil)
        #expect(r.filter(\.checked).map(\.target) == [.board("w"), .board("sea")])
    }

    @Test func disabledGenreFolderIsNotOffered() {
        let r = rows(lib(), shot: nil, excluding: nil, on: ["wedding"])
        #expect(!r.contains { $0.target == .board("por") })
    }

    @Test func freeGenreGetsBoardOnTapAndKeepsExistingOne() {
        var l = lib()
        let id = l.ensureGenreBoard("street", id: "new1")
        #expect(id == "new1" && l.board("new1")?.kind == .tpl && l.board("new1")?.genre == "street")
        let r11 = l.ensureGenreBoard("wedding", id: "zzz")
        #expect(r11 == "w")     // основная уже есть
        #expect(l.board("zzz") == nil)
        let r12 = l.move(["d"], from: "por", to: "new1", remove: true)
        #expect(r12 == ["d"])
        #expect(l.board("new1")?.items == ["d"] && l.board("por")?.items == [])
    }

    // MARK: «Новая подборка»

    @Test func newBoardAsksNameWhenGenreHasFoldersAndOpensEmptyOtherwise() {
        let l = lib()
        #expect(MbSheets.newAction(genre: "wedding", in: l) == .askFolderName)
        #expect(MbSheets.newAction(genre: "street", in: l) == .openEmpty)
    }

    // MARK: карточка подборки

    @Test func loneCountIsFramesThatLeaveWithTheBoard() {
        let l = lib()
        #expect(l.loneCount("w") == 1)                 // «b»; «a» ещё в съёмке, «c» ещё в «На море»
        #expect(l.loneCount("sea") == 0)
        #expect(l.loneCount("нет") == 0)
    }

    @Test func loneCountSeesForeignBoards() {
        var extra: [String: JSONValue] = [:]
        lib().write(into: &extra)
        guard case .array(var arr)? = extra["boards"] else { Issue.record("нет boards"); return }
        arr.append(.object(["id": .string("f"), "k": .string("alien"), "items": .array([.string("b")])]))
        extra["boards"] = .array(arr)
        #expect(RefLibrary(extra: extra).loneCount("w") == 0)   // «b» держит сырая подборка неизвестного рода
    }

    // MARK: теги

    @Test func itemTagsListGenreWordsFirstThenOwn() {
        let f = RefFrame(id: "x", tags: ["Пара", "закат", "couple"])
        let w = MbSheets.itemTags(f, genre: "wedding")
        #expect(Array(w.prefix(7)) == ["gathering", "couple", "bride", "groom", "walk", "evening", "details"])
        #expect(w.last == "закат" && w.count == 8)
        #expect(MbSheets.itemTags(f, genre: nil).prefix(4) == ["wide", "closeUp", "light", "details"])
        #expect(MbSheets.hasTag(f, "couple"))
    }

    @Test func toggleTagTreatsOldRussianWordAndCodeAsOne() {
        var l = lib()
        let r13 = l.toggleTag("couple", on: "a")
        #expect(r13 == false)          // на кадре «Пара» — снялось
        #expect(l.shot("a")?.tags == [])
        let r14 = l.toggleTag("bride", on: "a")
        #expect(r14)
        #expect(l.shot("a")?.tags == ["bride"])
        let r15 = l.toggleTag("bride", on: "нет")
        #expect(r15 == false && l.shot("a")?.tags == ["bride"])
    }

    @Test func typedTagBecomesKnownCodeOrStaysLowercased() {
        var l = lib()
        let r16 = l.addTag(" Невеста, ", to: "b", tagName: { $0 })
        #expect(r16)
        #expect(l.shot("b")?.tags == ["bride"])
        let r17 = l.addTag("BRIDE", to: "b", tagName: { $0 })
        #expect(r17 == false)     // уже стоит
        let r18 = l.addTag("Закат", to: "b", tagName: { $0 })
        #expect(r18)
        #expect(l.shot("b")?.tags == ["bride", "закат"])
        let r19 = l.addTag("  ", to: "b", tagName: { $0 })
        #expect(r19 == false)
        let r20 = l.addTag("Faces", to: "b", tagName: { $0 == "face" ? "Faces" : $0 })
        #expect(r20)
        #expect(l.shot("b")?.tags.last == "face")                           // совпало с названием на языке
    }
}
