import Testing
import SwiftUI
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

private func d(_ y: Int, _ m: Int, _ day: Int = 1) -> CivilDate { CivilDate(year: y, month: m, day: day) }

/// 30.1б (Алексей 29.10, по Календарю iOS: «закрепим название месяца, двигаем экран — месяц зависает, также линейка дней недели»,
/// «кнопки увеличили, но на других экранах месяца продублировать правку»). Лента года: шапка стоит — кнопки (те же 44 × 44, что у
/// «Съёмок»), название месяца, что сейчас наверху, линейка дней недели с волоском; лента едет под ней.
@MainActor
struct YearPinnedHeaderTests {

    // MARK: - Правило: какой месяц назван

    /// Верхи блоков как в ленте: месяц ≈ 344 pt, первый блок на 22.
    private var tops: [CivilDate: CGFloat] {
        var t: [CivilDate: CGFloat] = [:]
        for m in 1...12 { t[d(2026, m)] = 22 + CGFloat(m - 1) * 344 }
        for m in 1...12 { t[d(2027, m)] = 22 + 12 * 344 + 120 + CGFloat(m - 1) * 344 }
        return t
    }

    @Test func theTitleNamesTheMonthAtTheTopEdge() {
        let t = tops
        func at(_ s: CGFloat) -> CivilDate { YearPin.month(scrolled: s, tops: t, first: d(2026, 1)) }
        #expect(at(0) == d(2026, 1), "в покое — первый месяц, его блок ещё ниже линии")
        #expect(at(22) == d(2026, 1))
        #expect(at(22 + 343) == d(2026, 1), "октябрь ещё держит верх")
        #expect(at(22 + 344) == d(2026, 2), "имя февраля дошло до линии — название сменилось")
        let oct = t[d(2026, 10)]!, nov = t[d(2026, 11)]!
        #expect(at(oct + 100) == d(2026, 10))
        #expect(at(nov - 0.6) == d(2026, 10))
        #expect(at(nov) == d(2026, 11), "граница октября и ноября")
        #expect(at(nov + 200) == d(2026, 11))
        #expect(at(t[d(2027, 3)]! + 5) == d(2027, 3), "второй год ленты")
    }

    /// Встать на месяц: первый ряд под линейкой, а не имя месяца под шапкой — иначе шапка назвала бы прежний месяц.
    @Test func restingOnAMonthNamesThatMonth() {
        let t = tops
        let nameRow: CGFloat = 23
        for m in [d(2026, 10), d(2026, 11), d(2027, 1)] {
            let rest = YearPin.restOffset(gridTop: t[m]! + nameRow)
            #expect(YearPin.month(scrolled: rest, tops: t, first: d(2026, 1)) == m, "\(m)")
            // Имя этого месяца уже названо шапкой: оно выше линии, чужое имя ниже первого ряда не видно.
            #expect(rest >= t[m]!)
        }
        #expect(YearPin.restOffset(gridTop: 10) == 6)
        #expect(YearPin.restOffset(gridTop: 2) == 0, "выше начала не прокручиваем")
    }

    /// Высота сетки месяца считается от ширины, не берётся у ленивой сетки (её оценки рядов вне экрана сдвигали верхи месяцев,
    /// шапка называла февраль вместо октября): ряды — квадраты ширина / 7, между ними 3.
    @Test func theMonthGridHeightComesFromItsWidth() {
        let rows: (CGFloat) -> CGFloat = { $0 * 56 + ($0 - 1) * 3 }
        #expect(YearLentaView.gridHeight(lead: 2, days: 31, width: 392) == rows(5), "октябрь 2026 с понедельника — 5 рядов")
        #expect(YearLentaView.gridHeight(lead: 6, days: 31, width: 392) == rows(6), "месяц на 6 рядов")
        #expect(YearLentaView.gridHeight(lead: 0, days: 28, width: 392) == rows(4), "февраль ровно в 4 ряда")
        #expect(YearLentaView.gridHeight(lead: 3, days: 30, width: 0) == nil, "до первой раскладки высоту не задаём")
    }

    // MARK: - Экран

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

    private func model(start: WeekChoiceBox = .monday) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-10-29T13:00:00+07:00")!
        var snap = Snapshot()
        snap.weekStart = start.choice == .standard ? nil : start.choice.rawValue
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                        locator: Doubles.NoLocator(), geocoder: Doubles.SilentGeocoder(), cityLookup: Doubles.NoCities(),
                        weatherSource: Doubles.NoWeather(), now: { now })
    }

    struct WeekChoiceBox { let choice: WeekStartChoice
        static let monday = WeekChoiceBox(choice: .mon), sunday = WeekChoiceBox(choice: .sun), saturday = WeekChoiceBox(choice: .sat) }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let s = view as? UIScrollView, s.contentSize.height > 1000 { return s }
        for v in view.subviews { if let s = scrollView(in: v) { return s } }
        return nil
    }

    @MainActor private final class Rig {
        let window: UIWindow
        let app: AppModel
        let nav = PlannerNav()
        init(_ app: AppModel, target: CivilDate, width: CGFloat = 440, height: CGFloat = 956, dark: Bool = true) {
            self.app = app
            nav.openLenta(from: target)
            let f = PlannerFacts(app: app, dark: dark)
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.rootViewController = UIHostingController(rootView: YearLentaView(app: app, f: f, nav: nav, part: PartDay()))
            window.makeKeyAndVisible()
        }
        deinit { window.isHidden = true }
        var scroll: UIScrollView? { PlannerPinScroll.find(window) }
        func settle(_ ms: Int = 50) async throws { try await Task.sleep(for: .milliseconds(ms)) }
        struct Trail { var last: CivilDate?; var foreign: [CivilDate] }
        /// Шапка после прокрутки: каждые 10 мс записывает её название, пока оно не устоится на `want` (150 мс без смены), не дольше
        /// `ms`. `last` — на чём устоялась, `foreign` — месяцы, кроме `want` и `allowed`, названные хоть раз по дороге. Один взгляд
        /// через фиксированные 120–150 мс пропускал или ловил случайно кратковременный скачок: ленивая сетка месяца оценивала высоту
        /// рядов вне экрана, верхи месяцев на 50–400 мс были неверны (октябрь 3236 → 3944…12546), и шапка называла сентябрь или
        /// февраль, потом сама возвращалась (замер 31.10). Ожидание даёт итог, след ловит сам скачок.
        func pinned(_ want: CivilDate, allowing allowed: [CivilDate] = [], within ms: Int = 1500) async throws -> Trail {
            var trail = Trail(last: nav.lentaPinned, foreign: [])
            var still = 0
            func note(_ m: CivilDate?) { if let m, m != want, !allowed.contains(m), !trail.foreign.contains(m) { trail.foreign.append(m) } }
            note(trail.last)
            for _ in 0..<(ms / 10) {
                try await settle(10)
                let now = nav.lentaPinned
                note(now)
                still = now == trail.last ? still + 10 : 0
                trail.last = now
                if now == want, still >= 150 { break }
            }
            return trail
        }
    }

    enum PlannerPinScroll {
        static func find(_ view: UIView) -> UIScrollView? {
            if let s = view as? UIScrollView, s.contentSize.height > 1000 { return s }
            for v in view.subviews { if let s = find(v) { return s } }
            return nil
        }
    }

    private func opened(_ app: AppModel, on target: CivilDate) async throws -> Rig {
        let rig = Rig(app, target: target)
        for _ in 0..<80 {
            try await rig.settle()
            if let sv = rig.scroll, sv.contentOffset.y + sv.adjustedContentInset.top > 100 || target.month == 1, rig.nav.lentaPinned != nil { break }
        }
        try await rig.settle(150)
        return rig
    }

    /// Лента открывается на месяце цели, и шапка называет его; пролистали в ноябрь — шапка называет ноябрь; вернулись — октябрь.
    @Test func theHeaderFollowsTheScroll() async throws {
        let rig = try await opened(model(), on: d(2026, 10))
        let opened = try await rig.pinned(d(2026, 10)).last
        #expect(opened == d(2026, 10), "открыли на октябре: \(String(describing: opened))")
        let sv = try #require(rig.scroll)
        let top = sv.adjustedContentInset.top
        let oct = sv.contentOffset.y + top
        sv.setContentOffset(CGPoint(x: 0, y: -top + oct + 330), animated: false)    // пол-ряда за октябрь, граница ноября дальше
        let mid = try await rig.pinned(d(2026, 10), allowing: [d(2026, 11)])
        #expect(mid.foreign.isEmpty, "по дороге к концу октября шапка называла чужие месяцы: \(mid.foreign)")
        sv.setContentOffset(CGPoint(x: 0, y: -top + oct + 360 + 40), animated: false)
        let nov = try await rig.pinned(d(2026, 11), allowing: [d(2026, 10)])
        #expect(nov.last == d(2026, 11), "ноябрь у верхнего края: \(String(describing: nov.last)), до того \(String(describing: mid.last))")
        #expect(nov.foreign.isEmpty, "по дороге в ноябрь шапка называла чужие месяцы: \(nov.foreign)")
        sv.setContentOffset(CGPoint(x: 0, y: -top + oct), animated: false)
        let back = try await rig.pinned(d(2026, 10), allowing: [d(2026, 11)])
        #expect(back.last == d(2026, 10), "вернулись на октябрь: \(String(describing: back.last))")
        #expect(back.foreign.isEmpty, "по дороге назад шапка называла чужие месяцы: \(back.foreign)")
    }

    /// Шапка стоит: пока лента едет внутри одного месяца, рамки шапки, названия и линейки (в окне, не в ленте) не меняются ни на
    /// пункт, а лента под ней действительно едет. Рамки пишет стенд (`pinGeo`, Debug).
    @Test func theHeaderStandsWhileTheTapeMoves() async throws {
        let rig = try await opened(model(), on: d(2026, 10))
        let sv = try #require(rig.scroll)
        let top = sv.adjustedContentInset.top
        let a = (PinBench.geo["head"], PinBench.geo["month"], PinBench.geo["ruler"])
        #expect(a.0 != nil && a.1 != nil && a.2 != nil, "стенд не записал рамки шапки")
        let y0 = sv.contentOffset.y
        for step in [20.0, 60, 120] {
            sv.setContentOffset(CGPoint(x: 0, y: y0 + step), animated: false)     // внутри октября
            let pinned = try await rig.pinned(d(2026, 10))
            #expect(pinned.last == d(2026, 10), "прокрутка на \(step): \(String(describing: pinned.last))")
            #expect(pinned.foreign.isEmpty, "прокрутка на \(step): шапка называла чужие месяцы \(pinned.foreign)")
            #expect(PinBench.geo["head"] == a.0 && PinBench.geo["month"] == a.1 && PinBench.geo["ruler"] == a.2,
                    "шапка сдвинулась при прокрутке на \(step)")
        }
        #expect(sv.contentOffset.y - y0 == 120, "лента едет под шапкой")
        let head = try #require(a.0)
        #expect(top >= head.height, "лента начинается под шапкой: отступ прокрутки \(top), шапка \(head.height)")
        #expect(head.height > 100 && head.height < 130, "высота шапки под безопасной зоной: \(head.height)")
    }

    /// Слова линейки идут от начала недели, суббота и воскресенье янтарные; линейка одна (в блоках месяцев её больше нет).
    @Test(arguments: [WeekChoiceBox.monday, .sunday, .saturday]) func theRulerFollowsTheWeekStart(_ box: WeekChoiceBox) {
        let app = model(start: box)
        let ws = app.weekStart
        let f = PlannerFacts(app: app, dark: true)
        let week = ws.week(of: f.today)
        let words = week.map { f.dates.wdShort(f.date($0)) }
        let first = ws.start(of: f.today)
        #expect(week.first == first)
        #expect(week.count == 7)
        let flags = week.map { WeekStart.isWeekend($0) }
        #expect(flags.filter { $0 }.count == 2, "\(box.choice): \(words) \(flags)")
        switch box.choice {
        case .mon: #expect(flags == [false, false, false, false, false, true, true])
        case .sun: #expect(flags == [true, false, false, false, false, false, true])
        case .sat: #expect(flags == [true, true, false, false, false, false, false])
        default: break
        }
        #expect(Set(words).count == 7)
    }

    /// Кнопки ленты — те же, что у «Съёмок»: общий значок, зона 44 × 44 впритык.
    @Test func theTapeButtonsAreTheSameAsThePlannerOnes() {
        #expect(PlanTitleLayout.buttonSide == 44)
        #expect(PlanTitleLayout.actionGlyph == 28)
        let h = UIHostingController(rootView: OverlayIconButton(kind: .add, color: .orange, label: "x") {})
        let size = h.sizeThatFits(in: CGSize(width: 200, height: 200))
        #expect(size.width == 44 && size.height == 44, "зона нажатия \(size)")
    }
    #endif
}
