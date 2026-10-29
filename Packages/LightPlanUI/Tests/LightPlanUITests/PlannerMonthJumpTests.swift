import Testing
import SwiftUI
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

private func d(_ y: Int, _ m: Int, _ day: Int) -> CivilDate { CivilDate(year: y, month: m, day: day) }

/// 29.10 (Алексей: «если переходить на вид по месяцам, с вида на день или неделю, нажимая на название месяца, то календарь
/// переходит на начало года»). Тап по названию месяца в шапке открывает ленту года, а лента встаёт на месяц выбранного дня
/// (веб `planTitle` → `scrollYearTo(calMonth)`). Её `scrollTo` не доходил до прокрутки: кнопка прыжка (`.scrollJump`, 28.10)
/// вешала на ту же прокрутку свой `.scrollPosition`, и он перекрывал экранный. Лента стояла на январе, лента дня — на 00:00.
/// Состояние видов (`PlannerState`) было в порядке — первые три теста держат его контракт для трёх начал недели; два
/// последних читают настоящую прокрутку на экране и на прежнем коде красные.
@MainActor
struct PlannerMonthJumpTests {

    // MARK: - Состояние: вид → месяц держит месяц выбранного дня

    private let starts: [WeekStart] = [.monday, .sunday, .saturday]

    @Test func dayToMonthShowsTheMonthOfTheSelectedDay() {
        for ws in starts {
            var s = PlannerState(today: d(2026, 10, 29))
            s.setScope(.day)
            s.setScope(.month)
            #expect(s.month == d(2026, 10, 1), "\(ws)")
            #expect(s.selected == d(2026, 10, 29))
            #expect(s.monthGrid(ws).contains(s.selected))
        }
    }

    /// Неделя через границу месяца: 26 окт – 1 ноя (пн), выбран день по обе стороны границы — месяц тот, что держит выбранный день.
    @Test func weekAcrossAMonthBoundaryShowsTheMonthOfTheSelectedDay() {
        for ws in starts {
            for (sel, month) in [(d(2026, 10, 29), d(2026, 10, 1)), (d(2026, 10, 31), d(2026, 10, 1)), (d(2026, 11, 1), d(2026, 11, 1))] {
                var s = PlannerState(today: d(2026, 10, 29))
                s.setScope(.week)
                s.pickInStrip(sel)
                #expect(s.week(ws).contains(sel))
                s.setScope(.month)
                #expect(s.month == month, "\(ws) \(sel)")
                #expect(s.selected == sel)
                #expect(s.monthGrid(ws).contains(sel))
            }
        }
    }

    /// Неделя через границу года: 28 дек – 3 янв.
    @Test func weekAcrossAYearBoundaryShowsTheMonthOfTheSelectedDay() {
        for ws in starts {
            for (sel, month) in [(d(2026, 12, 30), d(2026, 12, 1)), (d(2027, 1, 2), d(2027, 1, 1))] {
                var s = PlannerState(today: d(2026, 12, 30))
                s.setScope(.week)
                s.pickInStrip(sel)
                s.setScope(.month)
                #expect(s.month == month, "\(ws) \(sel)")
                #expect(s.selected == sel)
                var nav = (year: 0, target: d(2000, 1, 1))
                nav.year = s.month.year; nav.target = s.month      // `PlannerNav.openLenta(from: month)`
                #expect(nav.year == month.year && nav.target == month)
            }
        }
    }

    // MARK: - Экран: лента года и лента дня встают туда, куда их ведёт экран

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

    private func model() -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-10-29T13:00:00+07:00")!
        return AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                        locator: Doubles.NoLocator(), geocoder: Doubles.SilentGeocoder(), cityLookup: Doubles.NoCities(),
                        weatherSource: Doubles.NoWeather(), now: { now })
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let s = view as? UIScrollView, s.contentSize.height > 1000 { return s }
        for v in view.subviews { if let s = scrollView(in: v) { return s } }
        return nil
    }

    /// Лента года открывается на месяце цели, не на январе. Смещение — по её настоящей прокрутке (440 × 956): январь стоит наверху
    /// (поле шапки 14), до октября девять месяцев по ~360 pt (замер 3372), ноябрь ниже октября на месяц (+360). На январе — ноль.
    @Test func theYearTapeOpensOnTheTargetMonth() async throws {
        func offset(target: CivilDate) async throws -> CGFloat {
            let app = model()
            let nav = PlannerNav()
            nav.openLenta(from: target)
            let f = PlannerFacts(app: app, dark: true)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
            window.rootViewController = UIHostingController(rootView: YearLentaView(app: app, f: f, nav: nav, part: PartDay()))
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            var sv: UIScrollView?
            for _ in 0..<60 {                                    // раскладка, рамки месяцев, прыжок — по кадрам
                try await Task.sleep(for: .milliseconds(50))
                sv = scrollView(in: window)
                if let sv, sv.contentOffset.y > 0 { break }
            }
            return (sv?.contentOffset.y ?? -1) + (sv?.adjustedContentInset.top ?? 0)
        }
        let jan = try await offset(target: d(2026, 1, 1))
        let oct = try await offset(target: d(2026, 10, 1))
        let nov = try await offset(target: d(2026, 11, 1))
        #expect(jan < 100, "январь — наверху, смещение \(jan)")
        #expect(oct > 3000, "октябрь — глубоко в ленте, смещение \(oct)")
        #expect(nov > oct + 250 && nov < oct + 500, "ноябрь ниже октября на месяц: \(nov) против \(oct)")
    }

    /// Лента дня при первом показе наводится на 09:00 (веб `dayScrollDay`) — тот же `scrollTo`, то же перекрытие.
    @Test func theDayStripAimsAtNineInTheMorning() async throws {
        let app = model()
        app.tab = .planner
        app.planner.setScope(.day)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = UIHostingController(rootView: PlannerScreenView(app: app))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        var y: CGFloat = 0
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(50))
            if let sv = scrollView(in: window) { y = sv.contentOffset.y + sv.adjustedContentInset.top; if y > 0 { break } }
        }
        #expect(y > 300, "09:00 — час девять в списке, лента ушла вниз (замер 375): \(y)")
    }
    #endif
}
