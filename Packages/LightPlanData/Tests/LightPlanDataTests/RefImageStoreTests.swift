import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LightPlanData

/// Итерация 28, шаг 5г: файлы картинок мудборда — запись, чтение, удаление, размеры.
struct RefImageStoreTests {

    private func temp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lp-refimg-" + UUID().uuidString, isDirectory: true)
    }

    static func png(_ w: Int, _ h: Int, orientation: Int? = nil) -> Data {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!,
                                   orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary })
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    @Test func saveReadDelete() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let s = RefImageStore(directory: dir)
        #expect(s.save(Data([1, 2, 3]), as: "abc"))
        #expect(s.exists("abc") && s.read("abc") == Data([1, 2, 3]) && s.names() == ["abc"])
        #expect(s.save(Data([9]), as: "abc") && s.read("abc") == Data([9]))     // то же имя — замена
        #expect(s.delete("abc"))
        #expect(!s.exists("abc") && s.read("abc") == nil && s.names().isEmpty)
        #expect(!s.delete("abc"))                                                // файла нет — не ошибка
    }

    @Test func unsafeNamesNeverLeaveTheFolder() {
        let parent = temp(); defer { try? FileManager.default.removeItem(at: parent) }
        let dir = parent.appendingPathComponent("img", isDirectory: true)
        let s = RefImageStore(directory: dir)
        for bad in ["", ".", "..", "../x", "a/b"] {
            #expect(!s.save(Data([1]), as: bad), "\(bad)")
            #expect(s.url(bad) == nil)
        }
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        #expect(siblings == ["img"] && s.names().isEmpty)
    }

    @Test func imageIsShrunkToTheTileSideAndNeverGrown() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let s = RefImageStore(directory: dir)
        s.save(Self.png(400, 200), as: "big")
        s.save(Self.png(30, 20), as: "small")
        let tile = s.image("big", maxPixel: 100)
        #expect(tile?.width == 100 && tile?.height == 50)                         // длинная сторона — 100, пропорции целы
        let whole = s.image("big", maxPixel: nil)
        #expect(whole?.width == 400 && whole?.height == 200)                      // просмотрщик берёт оригинал
        let tiny = s.image("small", maxPixel: 640)
        #expect(tiny?.width == 30 && tiny?.height == 20)                          // меньше плитки — не растягиваем
    }

    @Test func imageAppliesTheExifTurnAndAnswersNilWithoutAFile() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let s = RefImageStore(directory: dir)
        s.save(Self.png(30, 20, orientation: 6), as: "side")
        let img = s.image("side", maxPixel: nil)
        #expect(img?.width == 20 && img?.height == 30)                            // лежал боком, показывается прямо
        #expect(s.image("nope", maxPixel: 100) == nil)
        #expect(s.image("../x", maxPixel: 100) == nil)
        s.save(Data([1, 2, 3]), as: "junk")
        #expect(s.image("junk", maxPixel: 100) == nil && s.image("junk", maxPixel: nil) == nil)
    }

    @Test func stampChangesWhenTheFileIsReplacedUnderTheSameName() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let s = RefImageStore(directory: dir)
        #expect(s.stamp("a") == nil)                                              // файла нет — отпечатка нет
        s.save(Self.png(30, 20), as: "a")
        let first = s.stamp("a")
        #expect(first != nil && first == s.stamp("a"))
        s.save(Self.png(60, 40), as: "a")
        #expect(s.stamp("a") != first)                                            // другая картинка — другой ключ кэша
        s.delete("a")
        #expect(s.stamp("a") == nil && s.stamp("../a") == nil)
    }

    @Test func stampChangesEvenForSameSizeAndSameModificationTime() throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let s = RefImageStore(directory: dir)
        s.save(Data([1, 2, 3]), as: "a")
        let path = dir.appendingPathComponent("a").path
        let when = try #require(FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
        let first = s.stamp("a")
        s.save(Data([4, 5, 6]), as: "a")                                          // тот же размер, запись атомарна
        try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: path)   // и то же время правки
        #expect(s.stamp("a") != first)
    }

    @Test func pixelSizeOfImage() {
        let size = RefImageStore.pixelSize(of: Self.png(30, 20))
        #expect(size?.w == 30 && size?.h == 20)
        #expect(RefImageStore.pixelSize(of: Data([1, 2, 3])) == nil)
    }

    @Test func pixelSizeFollowsExifRotation() {
        // снимок с телефона лежит боком (ориентация 6) и показывается прямо: 30×20 в файле = 20×30 на экране
        let sideways = RefImageStore.pixelSize(of: Self.png(30, 20, orientation: 6))
        #expect(sideways?.w == 20 && sideways?.h == 30)
        let upright = RefImageStore.pixelSize(of: Self.png(30, 20, orientation: 1))
        #expect(upright?.w == 30 && upright?.h == 20)
    }
}
