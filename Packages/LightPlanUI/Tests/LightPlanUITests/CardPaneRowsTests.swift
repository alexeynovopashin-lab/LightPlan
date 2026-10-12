import Testing
import SwiftUI
import UIKit
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг 29.2з: плитки одной строки «Места и дальше» равны по высоте — как ячейки
/// `.ev-grid` беты (`display: grid`, строка тянет всех к самой высокой). Считаем
/// не рамки, а пиксели: колонка на 12 pt от края плитки (внутри поля 14, ни знака,
/// ни текста) красится только фоном плитки; длина её последнего участка — высота без
/// 1 pt на скругление углов (радиус 16).
@MainActor
struct CardPaneRowsTests {

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

    private static let width: CGFloat = 392
    private static let scale: CGFloat = 3

    /// Съёмка 21.09 11:00–22:00, часы — 09:00 того же дня: фаза «до».
    private func render(_ edit: (inout Session) -> Void) throws -> (image: CGImage, panes: Int) {
        var s = Session(id: "w", kind: .shoot, day: CivilDate(year: 2026, month: 9, day: 21),
                        start: 660, end: 1320, duration: 660, genre: .wedding)
        edit(&s)
        var snap = Snapshot()
        snap.sessions = [s]
        snap.practice = "ru"
        let now = ISO8601DateFormatter().date(from: "2026-09-21T09:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), now: { now })
        let rec = app.sessions[0]
        let phase = app.phase(of: rec)
        let pal = Palette(.dark)
        let view = CardPanesBlock(app: app, s: rec, phase: phase, pal: pal)
            .frame(width: Self.width, alignment: .top)
            .padding(.bottom, 20)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: view)
        r.scale = Self.scale
        return (try #require(r.cgImage), app.cardPanes(rec, phase: phase).count)
    }

    /// Высоты участков цвета плитки в колонке `x` (pt), сверху вниз.
    private func runs(_ img: CGImage, x: CGFloat) -> [CGFloat] {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let col = Int((x * Self.scale).rounded())
        // sheet3 тёмной темы — 0x1A1710
        func isPane(_ y: Int) -> Bool {
            let i = (y * w + col) * 4
            return abs(Int(buf[i]) - 0x1A) <= 3 && abs(Int(buf[i + 1]) - 0x17) <= 3 && abs(Int(buf[i + 2]) - 0x10) <= 3
        }
        var out: [CGFloat] = [], len = 0
        for y in 0..<h {
            if isPane(y) { len += 1 } else if len > 0 { out.append(CGFloat(len) / Self.scale); len = 0 }
        }
        if len > 0 { out.append(CGFloat(len) / Self.scale) }
        return out
    }

    private var leftX: CGFloat { 12 }
    private var rightX: CGFloat { (Self.width - 9) / 2 + 9 + 12 }

    /// «Дальше» (знак, подпись, мелкая строка «через … · час») и «Гостей» (знак,
    /// подпись, число): первая выше второй, обе стоят в одной строке.
    @Test func nextAndGuestsShareOneHeight() throws {
        let (img, panes) = try render {
            $0.route = [RoutePoint(start: 660, name: "Банкет")]
            $0.guests = 45
        }
        #expect(panes == 3)                       // место + дальше + гости
        let l = runs(img, x: leftX), r = runs(img, x: rightX)
        let left = try #require(l.last), right = try #require(r.last)
        #expect(l.count == 2 && r.count == 2)     // место сверху, плитка строки под ним
        #expect(abs(left - right) < 0.4, "дальше \(left) pt, гостей \(right) pt")
        #expect(left > 80, "строка ниже натурального «Дальше»: \(left) pt")
    }

    /// Две низкие плитки не раздуваются: «Гостей» и «Выезд» остаются своей высоты
    /// (знак 38 + поля 13 + 13 = 64 pt, в колонке замера 63), строка тянет только к самой высокой.
    @Test func equalTilesKeepTheirNaturalHeight() throws {
        let (img, _) = try render {
            $0.guests = 80
            $0.trip = true
            $0.tripPlace = "Кемерово"
        }
        let l = runs(img, x: leftX), r = runs(img, x: rightX)
        let left = try #require(l.last), right = try #require(r.last)
        #expect(abs(left - right) < 0.4)
        #expect(abs(left - 63) < 0.7, "плитка строки: \(left) pt")
    }

    /// Одинокая плитка строки, растянутая на ряд, остаётся как была: 64 pt.
    @Test func lonelyTileIsUntouched() throws {
        let (img, panes) = try render { $0.guests = 45 }
        #expect(panes == 1)
        let l = runs(img, x: leftX)
        #expect(l.count == 1)
        let left = try #require(l.last)
        #expect(abs(left - 63) < 0.7, "одинокая плитка: \(left) pt")
    }
}
