import Testing
import Foundation
import LightPlanCore
@testable import LightPlanDomain

/// Итерация 28, шаг 5г: фото и ссылки в папке, файл уходит вместе с кадром.
struct RefImagesTests {

    private func lib() -> RefLibrary {
        RefLibrary(shots: [RefFrame(id: "a", im: "a"), RefFrame(id: "b", im: "b"),
                           RefFrame(id: "l", kind: .link, url: "https://pinterest.com/pin/1")],
                   boards: [RefBoard(id: "x", kind: .tpl, genre: "wedding", items: ["a", "b", "l"]),
                            RefBoard(id: "y", kind: .tpl, genre: "wedding", items: ["b"])])
    }

    // MARK: файл уходит вместе с кадром

    @Test func lastBoardDropReleasesFile() {
        let before = lib(); var after = before
        after.dropWithShots("x")                       // a лежал только тут; b — ещё и в «y»
        #expect(RefLibrary.orphanImages(before: before, after: after) == ["a"])
    }

    @Test func frameStillInAnotherBoardKeepsFile() {
        let before = lib(); var after = before
        #expect(after.remove(["b"], from: "x").isEmpty)    // b остался в «y»
        #expect(RefLibrary.orphanImages(before: before, after: after).isEmpty)
    }

    @Test func removingLastPlaceReleasesFile() {
        let before = lib(); var after = before
        #expect(after.remove(["a"], from: "x") == ["a"])
        #expect(RefLibrary.orphanImages(before: before, after: after) == ["a"])
    }

    @Test func linkWithoutImageReleasesNothing() {
        let before = lib(); var after = before
        after.remove(["l"], from: "x")
        #expect(RefLibrary.orphanImages(before: before, after: after).isEmpty)
    }

    @Test func emptyImNameIsNotAFile() {
        let l = RefLibrary(shots: [RefFrame(id: "e", im: "")], boards: [])
        #expect(l.imageNames.isEmpty)
    }

    // MARK: фото

    @Test func photoBecomesFrameInBoard() {
        var l = lib()
        let id = l.addPhoto(im: "p1", w: 30, h: 20, to: "y", tag: "couple", now: 5)
        #expect(id == "p1")
        let f = l.shot("p1")
        #expect(f?.kind == .img && f?.im == "p1" && f?.w == 30 && f?.h == 20 && f?.mt == 5 && f?.tags == ["couple"])
        #expect(l.board("y")?.items == ["b", "p1"] && l.board("y")?.mt == 5)
        #expect(l.imageNames.contains("p1"))
    }

    @Test func photoNeedsBoardAndFreeName() {
        var l = lib()
        #expect(l.addPhoto(im: "p1", w: 1, h: 1, to: "nope") == nil)
        #expect(l.addPhoto(im: "", w: 1, h: 1, to: "y") == nil)
        #expect(l.addPhoto(im: "a", w: 1, h: 1, to: "y") == nil)      // имя уже держит кадр
        #expect(l == lib())
    }

    @Test func photoKeepsUnknownFieldsOfOthers() {
        var extra: [String: JSONValue] = ["shots": .array([.object(["id": .string("z"), "k": .string("img"), "im": .string("z"),
                                                                     "pending": .bool(true)])]),
                                          "boards": .array([.object(["id": .string("x"), "kind": .string("tpl"),
                                                                     "genre": .string("wedding"), "items": .array([.string("z")])])])]
        var l = RefLibrary(extra: extra)
        l.addPhoto(im: "p1", w: 1, h: 1, to: "x")
        l.write(into: &extra)
        guard case .array(let shots)? = extra["shots"], case .object(let z)? = shots.first else { Issue.record("нет кадров"); return }
        #expect(z["pending"] == .bool(true) && shots.count == 2)
    }

    // MARK: ссылка

    @Test func normalizeFollowsWebThenRejectsJunk() {
        #expect(RefLink.normalize("  pinterest.com/pin/1 ") == "https://pinterest.com/pin/1")
        #expect(RefLink.normalize("HTTP://Example.com/a") == "HTTP://Example.com/a")
        #expect(RefLink.normalize("https://ex.com") == "https://ex.com")
        #expect(RefLink.normalize("") == nil)
        #expect(RefLink.normalize("   ") == nil)
        #expect(RefLink.normalize("abc") == nil)                         // хоста без точки нет
        #expect(RefLink.normalize("two words.com") == nil)
        #expect(RefLink.normalize("ftp://ex.com/a") == nil)
        #expect(RefLink.normalize("https://.com") == nil)
    }

    @Test func linkBecomesFrameInBoard() {
        var l = lib()
        let r = l.addLink("site.com/a/b", to: "y", id: "n1", tag: "couple", now: 7)
        #expect(r == .added("n1"))
        let f = l.shot("n1")
        #expect(f?.kind == .link && f?.url == "https://site.com/a/b" && f?.im == nil && f?.mt == 7 && f?.tags == ["couple"])
        #expect(l.board("y")?.items == ["b", "n1"])
    }

    @Test func junkLinkWritesNothing() {
        var l = lib()
        #expect(l.addLink("abc", to: "y", id: "n1") == .invalid)
        #expect(l.addLink("site.com", to: "nope", id: "n1") == .invalid)
        #expect(l == lib())
    }

    @Test func sameLinkInSameBoardIsDuplicate() {
        var l = lib()
        #expect(l.addLink("https://Pinterest.com/pin/1", to: "x", id: "n1") == .duplicate)
        #expect(l.shot("n1") == nil && l.board("x")?.items == ["a", "b", "l"])
        // в другой подборке — можно: у кадров общий фонд, но это новая запись человека
        #expect(l.addLink("https://pinterest.com/pin/1", to: "y", id: "n2") == .added("n2"))
    }
}
