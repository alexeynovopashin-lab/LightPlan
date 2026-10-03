import Testing
import Foundation
@testable import LightPlanDomain

/// Итерация 28м, шаг 3: что в мудборде считается пином, доской, короткой ссылкой, и операции с пинами в папке.
struct PinterestLinkTests {

    // MARK: распознавание

    @Test func pinLinks() {
        #expect(PinterestLink.kind("https://www.pinterest.com/pin/115264071708018540/") == .pin(id: "115264071708018540"))
        #expect(PinterestLink.kind("pinterest.com/pin/42") == .pin(id: "42"))
        #expect(PinterestLink.kind("https://ru.pinterest.com/pin/42/?utm=x") == .pin(id: "42"))
        #expect(PinterestLink.kind("https://pinterest.ru/pin/slug--77/") == .pin(id: "77"))
        #expect(PinterestLink.kind("http://uk.pinterest.com/pin/9/") == .pin(id: "9"))
    }

    @Test func boardLinks() {
        #expect(PinterestLink.kind("https://www.pinterest.com/alex/kollektiv/") == .board(user: "alex", slug: "kollektiv"))
        #expect(PinterestLink.kind("https://ru.pinterest.com/alex/kollektiv/portraits/") == .board(user: "alex", slug: "kollektiv"))
        #expect(PinterestLink.kind("pinterest.co.uk/u/b") == .board(user: "u", slug: "b"))
        #expect(PinterestLink.kind("https://pinterest.ru/user/%D0%B4%D0%BE%D1%81%D0%BA%D0%B0/") == .board(user: "user", slug: "доска"))
    }

    @Test func shortLinks() {
        #expect(PinterestLink.kind("https://pin.it/3qVvzLDZl") == .short)
        #expect(PinterestLink.kind("pin.it/abc") == .short)
        #expect(PinterestLink.kind("https://pin.it/") == .other)
    }

    @Test func notPinterest() {
        for s in ["https://example.com/alex/board/", "https://notpinterest.com/a/b/", "https://pinterest.com.evil.io/a/b/",
                  "https://evil.io/pinterest.com/a/b/", "https://instagram.com/p/xyz/", "мусор", "", "https://www.pinterest.com/",
                  "https://www.pinterest.com/alex/", "https://www.pinterest.com/pin/", "https://www.pinterest.com/pin/abc/",
                  "https://api.pinterest.com/url_shortener/abc/redirect/"] {
            #expect(PinterestLink.kind(s) == .other, "\(s)")
        }
    }

    @Test func pinterestPagesThatAreNotBoards() {
        #expect(PinterestLink.kind("https://www.pinterest.com/search/pins/") == .other)
        #expect(PinterestLink.kind("https://www.pinterest.com/ideas/weddings/123/") == .other)
        #expect(PinterestLink.kind("https://www.pinterest.com/alex/_saved/") == .other)
    }

    @Test func secureUpgradesScheme() {
        #expect(PinterestLink.secure("http://pin.it/abc") == "https://pin.it/abc")
        #expect(PinterestLink.secure("pin.it/abc") == "https://pin.it/abc")
        #expect(PinterestLink.secure("мусор") == nil)
    }

    // MARK: операции над подборкой

    private func lib() -> RefLibrary {
        RefLibrary(shots: [RefFrame(id: "old", kind: .link, url: "https://ru.pinterest.com/pin/7/?invite=1")],
                   boards: [RefBoard(id: "x", kind: .tpl, genre: "wedding", items: ["old"]),
                            RefBoard(id: "y", kind: .tpl, genre: "wedding", items: [])])
    }

    @Test func addPinPutsLinkFrameWithPicture() {
        var l = lib()
        let r = l.addPin(permalink: PinterestLink.permalink(id: "1"), im: "f1", w: 736, h: 1104, to: "x", tag: "t", now: 5)
        #expect(r == .added("f1"))
        let f = l.shot("f1")
        #expect(f?.kind == .link && f?.im == "f1" && f?.w == 736 && f?.tags == ["t"])
        #expect(l.board("x")?.items == ["old", "f1"])
    }

    @Test func samePinTwiceIsDuplicateEvenWithOtherHostOrInvite() {
        var l = lib()
        let r1 = l.addPin(permalink: PinterestLink.permalink(id: "7"), im: "f7", w: 1, h: 1, to: "x")
        #expect(r1 == .duplicate)
        #expect(l.shot("f7") == nil)                      // кадра нет — файлу нечего держать
        let r2 = l.addPin(permalink: PinterestLink.permalink(id: "1"), im: "a", w: 1, h: 1, to: "x")
        #expect(r2 == .added("a"))
        let r3 = l.addPin(permalink: PinterestLink.permalink(id: "1"), im: "b", w: 1, h: 1, to: "x")
        #expect(r3 == .duplicate)
    }

    @Test func samePinInTwoFoldersIsTwoFramesWithTwoFiles() {
        var l = lib()
        let r4 = l.addPin(permalink: PinterestLink.permalink(id: "1"), im: "a", w: 1, h: 1, to: "x")
        #expect(r4 == .added("a"))
        let r5 = l.addPin(permalink: PinterestLink.permalink(id: "1"), im: "b", w: 1, h: 1, to: "y")
        #expect(r5 == .added("b"))
        #expect(l.imageNames == ["a", "b"])
    }

    @Test func addPinRefusesBadInput() {
        var l = lib()
        let r6 = l.addPin(permalink: "https://www.pinterest.com/pin/1/", im: "", w: 1, h: 1, to: "x")
        #expect(r6 == .invalid)
        let r7 = l.addPin(permalink: "https://www.pinterest.com/pin/1/", im: "a", w: 1, h: 1, to: "нет")
        #expect(r7 == .invalid)
        let r8 = l.addPin(permalink: "", im: "a", w: 1, h: 1, to: "x")
        #expect(r8 == .invalid)
        l.addPin(permalink: "https://www.pinterest.com/pin/1/", im: "a", w: 1, h: 1, to: "x")
        let r9 = l.addPin(permalink: "https://www.pinterest.com/pin/2/", im: "a", w: 1, h: 1, to: "x")
        #expect(r9 == .invalid)   // имя занято
    }

    @Test func attachImageOnlyToLiveBareLink() {
        var l = lib()
        let r10 = l.attachImage(im: "p", w: 10, h: 20, toFrame: "old", now: 9)
        #expect(r10)
        #expect(l.shot("old")?.im == "p" && l.shot("old")?.h == 20)
        let r11 = l.attachImage(im: "q", w: 1, h: 1, toFrame: "old")
        #expect(!r11)        // картинка уже есть
        let r12 = l.attachImage(im: "q", w: 1, h: 1, toFrame: "нет")
        #expect(!r12)        // кадр убрали
        l.shots.append(RefFrame(id: "photo", kind: .img, im: "z"))
        let r13 = l.attachImage(im: "q", w: 1, h: 1, toFrame: "photo")
        #expect(!r13)      // не ссылка
        l.shots.append(RefFrame(id: "bare", kind: .link, url: "https://pin.it/a"))
        let r14 = l.attachImage(im: "p", w: 1, h: 1, toFrame: "bare")
        #expect(!r14)       // имя занято другим кадром
    }
}
