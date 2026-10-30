import Testing
import SwiftUI
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// 30.2, хвост 1 (Алексей 30.10: «берем 2»). Линейка дней недели «Съёмок» в виде «месяц» стоит в шапке и не уезжает с прокруткой
/// списка дня (раньше лежала внутри плашки и уходила вверх вместе с сеткой; слово Алексея 29.10 по Календарю iOS).
@MainActor
struct MonthPinnedRulerTests {

    // MARK: - 1. Линейка месяца

    #if os(iOS)
    private struct Doubles {
        struct NoWeather: WeatherSource {
            struct Offline: Error {}
            func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
            func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
        }
        struct SilentGeocoder: ReverseGeocoding {
            func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
                GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
            }
        }
        struct NoCities: CityLookup { func cities(matching query: String) async throws -> [CityHit] { [] } }
        final class NoLocator: DeviceLocating {
            var isAlreadyAuthorized: Bool { false }
            func currentFix() async -> DeviceFix { .unavailable }
        }
    }

    private func model(_ start: WeekStartChoice = .mon) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-10-29T13:00:00+07:00")!
        var snap = Snapshot()
        snap.weekStart = start == .standard ? nil : start.rawValue
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                           locator: Doubles.NoLocator(), geocoder: Doubles.SilentGeocoder(), cityLookup: Doubles.NoCities(),
                           weatherSource: Doubles.NoWeather(), now: { now })
        app.planner.setScope(.month)
        return app
    }

    private struct Node: Decodable { var x, y, w, h: Double; var text: String? }

    /// Рамки узлов экрана в окне (`.shotNode`, Debug): сценарий снимков пишет их в файл — тем же путём, что пары «веб / натив». Включить
    /// запись нужно до того, как экран нарисован.
    private func probe() async throws -> [String: Node] {
        UserDefaults.standard.set(0.1, forKey: "LPShotReportDelay")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lp-probe-\(UUID().uuidString).json")
        ShotProbe.shared.start(report: url, screen: .planner)
        try await Task.sleep(for: .milliseconds(500))
        struct Report: Decodable { var nodes: [String: Node] }
        return try JSONDecoder().decode(Report.self, from: Data(contentsOf: url)).nodes
    }

    @MainActor private final class Rig {
        let window: UIWindow
        init(_ app: AppModel, width: CGFloat = 393, height: CGFloat = 640, dark: Bool = true) {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.rootViewController = UIHostingController(rootView: PlannerScreenView(app: app))
            window.makeKeyAndVisible()
        }
        deinit { window.isHidden = true }
        func settle(_ ms: Int = 60) async throws { try await Task.sleep(for: .milliseconds(ms)) }

        var scroll: UIScrollView? {
            func find(_ v: UIView) -> UIScrollView? {
                var best: UIScrollView?
                if let s = v as? UIScrollView, s.contentSize.height > window.bounds.height { best = s }
                for c in v.subviews { if let s = find(c), s.contentSize.height > (best?.contentSize.height ?? 0) { best = s } }
                return best
            }
            return find(window)
        }
    }

    /// Главное: пока список дня под сеткой едет вверх, слова линейки стоят там, где стояли, а сетка уезжает ровно на ход прокрутки.
    /// (На коде до 30.2 линейка лежала в плашке и уезжала вместе с сеткой.)
    @Test func theRulerStandsWhileTheListScrolls() async throws {
        try await ProbeLock.run {
            ShotProbe.shared.start(report: nil, screen: .planner)
            let app = model()
            let rig = Rig(app)
            try await rig.settle(700)
            let sv = try #require(rig.scroll, "прокрутка «Съёмок» не найдена")
            let top = sv.adjustedContentInset.top
            let range = sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom
            try #require(range > 140, "на окне 640 pt прокручивать нечего: \(range)")
            let n0 = try await probe()
            let r0 = try #require(n0["head.0"], "слова линейки не найдены"), g0 = try #require(n0["cal"], "сетка не найдена")
            for step in [40.0, 90, 140] {
                sv.setContentOffset(CGPoint(x: 0, y: -top + step), animated: false)
                try await rig.settle(150)
                let n = try await probe()
                let r = try #require(n["head.0"]), g = try #require(n["cal"])
                #expect(abs(r.y - r0.y) < 0.5, "линейка уехала при прокрутке на \(step): \(r0.y) → \(r.y)")
                #expect(abs((g0.y - g.y) - step) < 1, "сетка должна ехать с прокруткой на \(step): сдвиг \(g0.y - g.y)")
            }
        }
    }

    /// Порядок слов и выходные по началу недели (пн / вс / сб): слева направо идут слова от начала недели, субботу и воскресенье
    /// красит `Palette.weekend` (колонки выходных — по `WeekStart.isWeekend`).
    @Test(arguments: [WeekStartChoice.mon, .sun, .sat]) func theRulerWordsFollowTheWeekStart(_ choice: WeekStartChoice) async throws {
        try await ProbeLock.run {
            ShotProbe.shared.start(report: nil, screen: .planner)
            let app = model(choice)
            let f = PlannerFacts(app: app, dark: true)
            let week = app.weekStart.week(of: f.today)
            let words = week.map { f.dates.wdShort(f.date($0)) }
            let rig = Rig(app)
            try await rig.settle(700)
            _ = rig
            let n = try await probe()
            let nodes = (0..<7).compactMap { n["head.\($0)"] }
            try #require(nodes.count == 7, "\(choice): слов на экране \(nodes.count) из 7")
            #expect(nodes.map { $0.text ?? "" } == words, "\(choice): порядок слов")
            #expect(nodes.map(\.x) == nodes.map(\.x).sorted())
            #expect(Set(nodes.map(\.y)).count == 1, "\(choice): слова на разной высоте")
            let weekend = week.map { WeekStart.isWeekend($0) }
            switch choice {
            case .mon: #expect(weekend == [false, false, false, false, false, true, true])
            case .sun: #expect(weekend == [true, false, false, false, false, false, true])
            case .sat: #expect(weekend == [true, true, false, false, false, false, false])
            default: break
            }
        }
    }

    /// Слова линейки стоят над столбцами сетки: центры слов и первой строки дат расходятся меньше чем на 1 pt.
    @Test func theRulerSitsOverTheGridColumns() async throws {
        try await ProbeLock.run {
            ShotProbe.shared.start(report: nil, screen: .planner)
            let rig = Rig(model())
            try await rig.settle(700)
            _ = rig
            let n = try await probe()
            for i in 0..<7 {
                let h = try #require(n["head.\(i)"]), c = try #require(n["cal.\(i)"])
                #expect(abs((h.x + h.w / 2) - (c.x + c.w / 2)) < 1, "столбец \(i): слово \(h.x + h.w / 2), клетка \(c.x + c.w / 2)")
            }
        }
    }
    #endif
}
