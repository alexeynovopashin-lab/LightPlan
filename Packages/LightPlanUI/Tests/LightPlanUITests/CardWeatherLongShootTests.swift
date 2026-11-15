import Testing
import SwiftUI
import UIKit
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// 30и.10: часовая полоса погоды в карточке при длинной съёмке (24,5 ч — 13 колонок)
/// не выходит за карточку, подписи в одну строку, высота блока — по содержимому.
@MainActor
struct CardWeatherLongShootTests {
    private struct Sky: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            var time: [String] = []
            let d0 = CivilDate(year: 2026, month: 9, day: 15)
            for k in 0..<21 { let d = d0.adding(days: k)
                for h in 0..<24 { time.append(String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, h)) } }
            let n = time.count
            return HourlyWeather(time: time, cloud: Array(repeating: 98, count: n), temperature: Array(repeating: -12, count: n),
                                 windSpeed: Array(repeating: 2, count: n), precipitation: Array(repeating: 0, count: n),
                                 weatherCode: Array(repeating: 3, count: n))
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    private struct G: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer { GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil) }
    }
    private struct C: CityLookup { func cities(matching query: String) async throws -> [CityHit] { [] } }
    private final class L: DeviceLocating { var isAlreadyAuthorized: Bool { false }; func currentFix() async -> DeviceFix { .unavailable } }

    /// Ширина блока в карточке на 393 pt: экран − 2·16 поля.
    static let cardWidth: CGFloat = 361

    private func measure(minutes: Int) async -> (cols: Int, size: CGSize, content: CGSize) {
        var s = Session(id: "a", kind: .shoot, day: CivilDate(year: 2026, month: 9, day: 21),
                        start: 1080, end: 1080 + minutes, duration: minutes, genre: .portrait)
        s.latitude = 55.75; s.longitude = 37.62
        var snap = Snapshot(); snap.sessions = [s]
        let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: L(), geocoder: G(), cityLookup: C(), weatherSource: Sky(), now: { now })
        app.openCard(id: "a"); await app.pointWeather.settled()
        let sess = app.sessions.first { $0.id == "a" }!
        guard case .columns(let cols)? = app.cardWeather(sess, phase: .before) else { return (0, .zero, .zero) }
        let pal = Palette(.dark)
        let v = CardWeatherBlock(app: app, s: sess, phase: .before, pal: pal)
        let size = UIHostingController(rootView: v.frame(width: Self.cardWidth)).sizeThatFits(in: CGSize(width: Self.cardWidth, height: 3000))
        let wide = UIHostingController(rootView: v).sizeThatFits(in: CGSize(width: 3000, height: 3000))
        if let dir = ProcessInfo.processInfo.environment["WX_OUT"] {
            let r = ImageRenderer(content: v.frame(width: Self.cardWidth).padding(8).background(pal.bg).environment(\.colorScheme, .dark))
            r.scale = 3
            if let img = r.uiImage, let d = img.pngData() { try? d.write(to: URL(fileURLWithPath: "\(dir)/wx_\(minutes).png")) }
        }
        print("WXMEASURE minutes=\(minutes) cols=\(cols.count) block=\(size) ideal=\(wide)")
        return (cols.count, size, wide)
    }

    @Test func longShootStaysInsideTheCard() async {
        let short = await measure(minutes: 30)
        for m in [30, 360, 1470] {
            let r = await measure(minutes: m)
            #expect(r.cols >= 2)
            #expect(r.size.width <= Self.cardWidth + 0.5, "\(m) мин: блок \(r.size.width) шире карточки")
            // Высота — как у короткой съёмки: колонка в четыре строки, без пустых полос.
            #expect(abs(r.size.height - short.size.height) < 1, "\(m) мин: блок высотой \(r.size.height), короткий \(short.size.height)")
        }
    }
}
