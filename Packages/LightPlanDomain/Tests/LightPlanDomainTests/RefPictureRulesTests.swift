import Testing
@testable import LightPlanDomain

/// Итерация 28, шаг 5д: чем рисуется кадр, что открывается в просмотрщике, «Вернуть» после
/// «Объединить», строка тегов просмотрщика.
struct RefPictureRulesTests {

    // MARK: чем рисуется кадр

    @Test func faceIsPhotoOnlyWhenTheFileIsThere() {
        let img = RefFrame(id: "a", kind: .img, im: "a")
        #expect(img.face(hasFile: { $0 == "a" }) == .photo("a"))
        #expect(img.face(hasFile: { _ in false }) == .placeholder)                // файла нет — штриховка, как было
    }

    @Test func bareLinkIsAnInscriptionAndLinkWithPictureIsAPhoto() {
        let bare = RefFrame(id: "l", kind: .link, url: "https://example.org/x")
        #expect(bare.face(hasFile: { _ in true }) == .link("https://example.org/x"))
        let pic = RefFrame(id: "p", kind: .link, im: "p", url: "https://example.org/x")
        #expect(pic.face(hasFile: { $0 == "p" }) == .photo("p"))                  // og:image — как картинка
        #expect(pic.face(hasFile: { _ in false }) == .placeholder)                // картинка обещана, файла нет
    }

    @Test func emptyNameAndEmptyLinkAreNotFiles() {
        #expect(RefFrame(id: "e", kind: .img, im: "").face(hasFile: { _ in true }) == .placeholder)
        #expect(RefFrame(id: "n", kind: .img).face(hasFile: { _ in true }) == .placeholder)
        #expect(RefFrame(id: "u", kind: .link, url: "").face(hasFile: { _ in true }) == .placeholder)
        #expect(RefFrame(id: "v", kind: .link).face(hasFile: { _ in true }) == .placeholder)
    }

    // MARK: что открывается (веб `openRefAt`)

    @Test func emptyImageNameIsNotViewable() {
        #expect(!RefFrame(id: "a", kind: .img, im: "").isViewable)                // веб: `!r.im`
        #expect(RefFrame(id: "b", kind: .img, im: "b").isViewable)
        #expect(RefFrame(id: "c", kind: .img, path: "/cloud/c.jpg").isViewable)
        #expect(!RefFrame(id: "d", kind: .img, im: "", path: "").isViewable)
        #expect(!RefFrame(id: "e", kind: .img).isViewable)
    }

    @Test func linkOpensAsFrameOnlyWithItsOwnPicture() {
        #expect(!RefFrame(id: "a", kind: .link, url: "https://x.org").isViewable)
        #expect(!RefFrame(id: "b", kind: .link, im: "", url: "https://x.org").isViewable)
        #expect(!RefFrame(id: "c", kind: .link, path: "/cloud/c", url: "https://x.org").isViewable)   // без `im` — в браузер
        #expect(RefFrame(id: "d", kind: .link, im: "d", url: "https://x.org").isViewable)
    }

    // MARK: «Вернуть» после «Объединить»

    private func library() -> RefLibrary {
        RefLibrary(shots: ["a", "b", "c"].map { RefFrame(id: $0, im: $0) },
                   boards: [RefBoard(id: "t1", kind: .tpl, genre: "wedding", items: ["a", "b"], name: "Одна", mt: 1),
                            RefBoard(id: "t2", kind: .tpl, genre: "wedding", items: ["b", "c"], name: "Другая", mt: 2),
                            RefBoard(id: "t3", kind: .tpl, genre: "wedding", items: [], name: "Третья", mt: 3)])
    }

    @Test func undoMergeBringsBackTheBoardAtItsPlaceAndTheOldTargetFrames() {
        let before = library()
        var lib = before
        let memory = lib.mergeUndo("t2", into: "t1")!
        lib.merge("t2", into: "t1", now: 9)
        #expect(lib.board("t2") == nil && lib.board("t1")?.items == ["a", "b", "c"])
        let back = lib.undoMerge(memory)
        #expect(back)
        #expect(lib.boards == before.boards)                                      // в том числе порядок и отметка правки
        #expect(lib.shots == before.shots)
    }

    @Test func undoMergeKeepsTheOriginalBoardId() {
        var lib = library()
        let memory = lib.mergeUndo("t1", into: "t3")!
        lib.merge("t1", into: "t3")
        lib.undoMerge(memory)
        #expect(lib.board("t1")?.items == ["a", "b"] && lib.board("t3")?.items == [])
    }

    @Test func undoMergeWhenTheTargetWasDeletedMeanwhileReturnsOnlyTheVanished() {
        var lib = library()
        let memory = lib.mergeUndo("t2", into: "t1")!
        lib.merge("t2", into: "t1")
        lib.boards.removeAll { $0.id == "t1" }
        let back = lib.undoMerge(memory)
        #expect(back)
        #expect(lib.boards.map(\.id) == ["t3", "t2"])                             // на месте, что можно (индекс 1 → не дальше конца)
    }

    @Test func undoMergeTwiceDoesNotDuplicateTheBoard() {
        var lib = library()
        let memory = lib.mergeUndo("t2", into: "t1")!
        lib.merge("t2", into: "t1")
        let first = lib.undoMerge(memory)
        let second = lib.undoMerge(memory)
        #expect(first && !second)
        #expect(lib.boards.filter { $0.id == "t2" }.count == 1)
    }

    @Test func mergeMemoryNeedsTwoDifferentBoards() {
        let lib = library()
        #expect(lib.mergeUndo("t1", into: "t1") == nil)
        #expect(lib.mergeUndo("t1", into: "nope") == nil)
        #expect(lib.mergeUndo("nope", into: "t1") == nil)
    }

    // MARK: строка тегов просмотрщика

    @Test func tagRowIsCaptionWhereNotEditableAndDoorWhereEditable() {
        #expect(RefViewerTags.chips(["couple", "walk"], editable: false) == [.tag("couple"), .tag("walk")])
        #expect(RefViewerTags.chips(["couple"], editable: true) == [.tag("couple")])
        #expect(RefViewerTags.chips([], editable: true) == [.add])                // без тегов — «+ тег», иначе не на что нажимать
        #expect(RefViewerTags.chips([], editable: false).isEmpty)                 // подписи нет — строки нет
    }
}
