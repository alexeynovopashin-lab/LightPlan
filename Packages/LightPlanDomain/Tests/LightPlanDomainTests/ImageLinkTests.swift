import Testing
@testable import LightPlanDomain

/// 28н.1: что по адресу видно картинкой — расширение, без расширения, не картинка.
struct ImageLinkTests {

    @Test func extensionMeansImage() {
        for u in ["https://ex.com/a/photo.jpg", "https://ex.com/photo.JPEG", "https://ex.com/p.png", "https://ex.com/p.webp",
                  "https://ex.com/p.heic", "https://ex.com/p.HEIF", "ex.com/p.jpg", "http://ex.com/p.jpg",
                  "https://ex.com/p.jpg?w=800&fm=jpg#x", "https://i.pinimg.com/736x/ab/cd/ef.jpg", "https://ex.com/my.photo.final.png"] {
            #expect(ImageLink.kind(u) == .image, "\(u)")
        }
    }

    @Test func noExtensionIsMaybe() {
        for u in ["https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800", "https://ex.com/blog/post-title", "https://ex.com/p?id=1"] {
            #expect(ImageLink.kind(u) == .maybe, "\(u)")
        }
    }

    @Test func notAnImage() {
        for u in ["https://ex.com/", "https://ex.com", "https://ex.com/blog/", "https://ex.com/page.html", "https://ex.com/doc.pdf",
                  "https://ex.com/a.php?img=photo.jpg", "https://ex.com/photo.jpg.html", "https://ex.com/a.gif", "https://ex.com/a.svg",
                  "not a link", "", "abc", "https://www.pinterest.com/pin/123/", "https://pin.it/abc", "https://ru.pinterest.com/user/board/"] {
            #expect(ImageLink.kind(u) == .page, "\(u)")
        }
    }

    @Test func queryAndFragmentDoNotMakeAnImage() {
        #expect(ImageLink.kind("https://ex.com/view?file=a.jpg") == .maybe)
        #expect(ImageLink.kind("https://ex.com/view#a.jpg") == .maybe)
    }
}
