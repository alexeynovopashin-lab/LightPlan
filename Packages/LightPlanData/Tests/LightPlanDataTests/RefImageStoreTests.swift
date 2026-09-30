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
