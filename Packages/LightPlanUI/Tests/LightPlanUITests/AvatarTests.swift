import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import LightPlanCore
import LightPlanDomain
@testable import LightPlanData
@testable import LightPlanUI

/// Своя аватарка и «Удалить мои данные» (31.13).
@MainActor
@Suite("Аватарка (31.13)")
struct AvatarTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    final class Core: CoreClient, @unchecked Sendable {
        let lock = NSLock()
        var calls: [String] = []
        func add(_ s: String) { lock.withLock { calls.append(s) } }
        func register(_ r: CoreRegistration) async throws -> CoreDevice {
            add("register \(r.appId)")
            return CoreDevice(deviceId: "d", pass: "p", idState: "unconfirmed", home: CoreHome.of(country: r.country), appId: r.appId)
        }
        func move(_ d: CoreDevice, to appId: String, at: Date) async throws { add("move") }
        func putAvatar(_ jpeg: Data, device: CoreDevice) async throws { add("put \(jpeg.count)") }
        func deleteAvatar(device: CoreDevice) async throws { add("delAvatar") }
        func deleteMe(device: CoreDevice) async throws { add("delMe") }
    }

    func app(phone: String? = "+7 916 123-45-67") -> AppModel {
        var snap = Snapshot()
        if let phone { snap.extra["me"] = .object(["phone": .string(phone)]) }
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
    }

    /// Картинка w×h с геометкой и моделью камеры в метаданных, как снимок с iPhone.
    static func photo(_ w: Int, _ h: Int) -> Data {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: w / 2, y: 0, width: w - w / 2, height: h))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        let meta: [CFString: Any] = [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 56.48, kCGImagePropertyGPSLatitudeRef: "N"],
                                     kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone 15 Pro Max"]]
        CGImageDestinationAddImage(dest, ctx.makeImage()!, meta as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    static func props(_ d: Data) -> [CFString: Any] {
        let src = CGImageSourceCreateWithData(d as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
    }

    // MARK: Картинка

    @Test func squareIs512JpegWithoutLocationOrCamera() throws {
        let raw = Self.photo(1200, 800)
        #expect(Self.props(raw)[kCGImagePropertyGPSDictionary] != nil, "проверка: в исходнике геометка есть")
        let img = try #require(AvatarImage.load(raw))
        let out = try #require(AvatarImage.square(img, crop: AvatarCrop.rect(image: CGSize(width: 1200, height: 800), d: 300, scale: 1, offset: .zero)))
        let p = Self.props(out)
        #expect(p[kCGImagePropertyPixelWidth] as? Int == 512)
        #expect(p[kCGImagePropertyPixelHeight] as? Int == 512)
        #expect(p[kCGImagePropertyGPSDictionary] == nil)
        #expect((p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
        // ImageIO сам пишет в EXIF только размеры и цветовое пространство — ни даты, ни объектива, ни места.
        let exif = Set(((p[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]).keys.map { $0 as String })
        #expect(exif.isSubset(of: [kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension,
                                   kCGImagePropertyExifColorSpace].map { $0 as String }), "EXIF: \(exif.sorted())")
        #expect(out.count <= AvatarImage.maxBytes)
    }

    @Test func cropFillsTheCircleAndNeverLeavesThePhoto() {
        let size = CGSize(width: 1200, height: 800), d: CGFloat = 300
        // Без сдвига и увеличения — средний квадрат по короткой стороне.
        #expect(AvatarCrop.rect(image: size, d: d, scale: 1, offset: .zero) == CGRect(x: 200, y: 0, width: 800, height: 800))
        // Сдвиг до упора вправо (картинка уехала вправо) — левый край фото, дальше не пускает.
        #expect(AvatarCrop.rect(image: size, d: d, scale: 1, offset: CGSize(width: 9999, height: 9999)) == CGRect(x: 0, y: 0, width: 800, height: 800))
        // Увеличение вдвое — квадрат вдвое меньше, по центру.
        #expect(AvatarCrop.rect(image: size, d: d, scale: 2, offset: .zero) == CGRect(x: 400, y: 200, width: 400, height: 400))
        // Сдвиг на 75 точек экрана при k = 0,75 — на 100 точек картинки.
        #expect(AvatarCrop.rect(image: size, d: d, scale: 2, offset: CGSize(width: 0, height: 75)) == CGRect(x: 400, y: 100, width: 400, height: 400))
    }

    @Test func croppedSideIsTheSideUnderTheCircle() throws {
        // Левая половина красная, правая синяя: сдвиг до упора вправо даёт красный квадрат.
        let img = try #require(AvatarImage.load(Self.photo(1200, 800)))
        let r = AvatarCrop.rect(image: CGSize(width: 1200, height: 800), d: 300, scale: 2, offset: CGSize(width: 9999, height: 0))
        let out = try #require(AvatarImage.square(img, crop: r))
        let back = try #require(AvatarImage.decoded(out))
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(back, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        #expect(px[0] > 200 && px[2] < 60, "красный: r=\(px[0]) b=\(px[2])")
    }

    // MARK: Заглушка

    @Test func stubIsChosenOnceAndKept() {
        let records = InMemoryAvatarRecordStore()
        let a = app(); a.avatarWiring.records = records
        let first = a.avatarStub
        #expect((0..<20).allSatisfy { _ in a.avatarStub == first })
        a.loadAvatar()
        #expect(a.avatar.stub == first, "после чтения памяти — та же")
        let b = app(); b.avatarWiring.records = records
        #expect(b.avatarStub == first, "другая модель той же установки — та же заглушка")
        #expect(Set(AvatarStub.allCases.map { AppModel.stubIcon($0).name }) == ["cat", "dog", "portrait"])
    }

    @Test func stubIconsExistInTheLibrary() {
        #expect(IconLibrary.common["cat"] != nil)
        #expect(IconLibrary.common["dog"] != nil)
        #expect(IconLibrary.genres["portrait"] != nil)
    }

    // MARK: Фото и очередь

    @Test func photoGoesToTheCoreWhenItAnswers() async {
        let a = app(), core = Core()
        a.avatarWiring.client = core
        a.setAvatar(Data(repeating: 1, count: 10))
        await a.waitCoreSync()
        #expect(core.calls == ["register id79161234567", "put 10"])
        #expect(a.avatar.queue.isEmpty)
        #expect(a.avatarWiring.records.load().queue.isEmpty)
    }

    @Test func withoutTheServerThePhotoWaitsQuietly() async {
        let a = app()   // ядра нет: AbsentCoreClient
        a.setAvatar(Data(repeating: 1, count: 10))
        await a.waitCoreSync()
        #expect(a.avatar.jpeg?.count == 10)
        #expect(a.avatar.queue == CoreQueue(avatar: true))
        #expect(a.avatarWiring.records.load().queue == CoreQueue(avatar: true), "очередь переживает перезапуск")
        #expect(a.avatar.unreadable == false)
    }

    @Test func removingThePhotoBringsTheStubBack() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("av-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = app()
        a.avatarWiring.store = AvatarStore(directory: dir)
        a.setAvatar(Data([1, 2, 3]))
        #expect(AvatarStore(directory: dir).read() == Data([1, 2, 3]))
        a.removeAvatar()
        #expect(a.avatar.jpeg == nil)
        #expect(AvatarStore(directory: dir).read() == nil, "старое фото стёрто сразу")
        #expect(a.avatar.queue.avatar, "ядру — стереть")
    }

    @Test func forgetMeErasesThePhotoHereAndAsksTheCore() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("av-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = app(), core = Core()
        a.avatarWiring.store = AvatarStore(directory: dir)
        a.avatarWiring.client = core
        a.setAvatar(Data([9]))
        await a.waitCoreSync()
        let stub = a.avatarStub
        a.avatar.confirmForget = true
        a.forgetMe()
        await a.waitCoreSync()
        #expect(core.calls.last == "delMe")
        #expect(a.avatar.jpeg == nil && AvatarStore(directory: dir).read() == nil)
        #expect(a.avatarWiring.passes.load() == nil)
        #expect(a.avatar.queue.isEmpty && !a.avatar.confirmForget)
        #expect(a.avatarStub == stub, "снова та же заглушка")
        #expect(a.myPhone == "+7 916 123-45-67", "номер в приложении остаётся")
    }

    @Test func forgetWithoutTheServerKeepsTheRequest() async {
        let a = app()
        a.avatarWiring.passes = InMemoryCorePassStore(CoreDevice(deviceId: "d", pass: "p", idState: "unconfirmed", home: .ru, appId: "id79161234567"))
        a.forgetMe()
        await a.waitCoreSync()
        #expect(a.avatar.queue == CoreQueue(forget: true))
        #expect(a.avatarWiring.passes.load() != nil, "без пропуска просьбу потом не отправить")
    }

    @Test func noMobileNumberNoRegistration() async {
        let a = app(phone: nil), core = Core()
        a.avatarWiring.client = core
        a.setAvatar(Data([1]))
        await a.waitCoreSync()
        #expect(core.calls.isEmpty)
        #expect(a.avatar.queue.avatar)
    }

    @Test func wordsExistInEveryLanguageAndNeverSayCore() {
        let keys = ["av.pick", "av.change", "av.pickOther", "av.remove", "av.note", "av.unreadable", "av.cropHint",
                    "my.data", "my.delete", "my.deleteSub", "my.deleteNote", "my.deleteQ", "my.deleteText"]
        for lang in ["ru", "en", "es", "ja", "zh"] {
            let t = Lexicon(lang)
            for k in keys {
                let w = t.t(k)
                #expect(w != k && !w.isEmpty, "\(lang) \(k)")
                #expect(!w.lowercased().contains("ядр") && !w.lowercased().contains("core") && !w.contains("Event OS"), "\(lang) \(k): \(w)")
            }
        }
    }
}
