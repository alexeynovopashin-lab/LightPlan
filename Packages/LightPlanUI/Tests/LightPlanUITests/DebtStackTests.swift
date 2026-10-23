import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг К5: стопка долгов (`clients_reference.md` § 7.2). Нажатие в календаре на несданную съёмку — над её карточкой
/// все долги, старый ближе к листу; на сданную, будущую, встречу — стопка дня. «Сдана» держит карточку открытой,
/// из стопки она уходит, когда открыли следующий долг. Посев сезона (`seed_planner.json`), 23.10 12:00, Барнаул.
@MainActor
struct DebtStackTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        struct Silent: Error {}
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer { throw Silent() }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func app(_ iso: String = "2026-10-23T12:00:00+07:00") -> AppModel {
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: CardPhaseTests.seed, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func others(_ a: AppModel) -> [String] { a.stack(of: a.card!).map(\.id) }

    /// Все долги посева на 23.10, старый первым: пейзаж (без сдачи), сданные августовские, встречи и будущие — не долг.
    static let debts = ["sd_sep_love", "sd_sep_party", "sd_sep_now", "sd_sep_wed", "sd_sep_clash_a", "sd_sep_clash_b",
                        "sd_sep_inter", "sd_sep_pet", "sd_sep_team", "sd_oct_ad"]

    @Test func seasonDebtsOldestFirst() {
        #expect(app().debts().map(\.id) == Self.debts)
    }

    // MARK: - Два режима

    /// Нажали несданную свадьбу 24.09 — над ней все остальные долги, старый ближе к листу, а не соседи по дню.
    @Test func calendarTapOnADebtStacksAllDebts() {
        let a = app()
        a.openCardFromCalendar(id: "sd_sep_wed")
        #expect(a.card?.id == "sd_sep_wed")
        #expect(a.cardStackMode == .debts)
        #expect(others(a) == Self.debts.filter { $0 != "sd_sep_wed" })
    }

    /// Сданная, будущая и встреча открываются со стопкой своего дня.
    @Test func calendarTapOnDeliveredFutureOrMeetingStacksTheDay() {
        let a = app()
        for id in ["sd_aug_wed", "sd_oct_wed_kem", "sd_sep_meet", "sd_aug_land"] {
            a.openCardFromCalendar(id: id)
            #expect(a.cardStackMode == .day, Comment(rawValue: id))
            #expect(others(a) == a.dayStack(of: a.card!).map(\.id), Comment(rawValue: id))
        }
        // Встреча 23.09 — сосед по дню портрет, а не долги.
        a.openCardFromCalendar(id: "sd_sep_meet")
        #expect(others(a) == ["sd_sep_now"])
    }

    /// Остальные входы (поиск, карточка клиента, уведомление) открывают стопку дня даже у долга; закрыли — режим сброшен.
    @Test func otherEntriesKeepTheDayStack() {
        let a = app()
        a.openCardFromCalendar(id: "sd_sep_now")
        #expect(a.cardStackMode == .debts)
        a.closeCard()
        #expect(a.cardStackMode == .day)
        a.openCard(id: "sd_sep_now")
        #expect(a.cardStackMode == .day)
        #expect(others(a) == ["sd_sep_meet"])
    }

    // MARK: - «Сдана»

    /// Отметили «сдана» — карточка открыта, стопка над ней та же; открыли следующий долг с края — отмеченной в стопке нет.
    @Test func deliveredCardStaysOpenAndLeavesOnNext() {
        let a = app()
        a.openCardFromCalendar(id: "sd_sep_love")
        let before = others(a)
        a.toggleDelivered(id: "sd_sep_love")
        #expect(a.card?.id == "sd_sep_love")
        #expect(a.card?.delivered == true)
        #expect(a.cardStackMode == .debts)
        #expect(others(a) == before)
        // Тап по ближнему краю — как у `CardStack.edge` в стопке долгов.
        a.openCard(id: before[0], stack: .debts)
        #expect(a.card?.id == "sd_sep_party")
        #expect(a.cardStackMode == .debts)
        #expect(!others(a).contains("sd_sep_love"))
        #expect(others(a) == Self.debts.filter { $0 != "sd_sep_love" && $0 != "sd_sep_party" })
    }

    // MARK: - Края

    /// Видны шесть старых краёв, остальные считает строка над стопкой; стопка дня не режется.
    @Test func debtsStackShowsSixOldestAndCountsTheRest() {
        let a = app()
        a.openCardFromCalendar(id: "sd_oct_ad")
        let all = a.stack(of: a.card!)
        let (edges, more) = CardStack<EmptyView>.shown(all, mode: .debts)
        #expect(edges.map(\.id) == Array(Self.debts.prefix(6)))
        #expect(more == 3)
        let few = Array(all.prefix(4))
        #expect(CardStack<EmptyView>.shown(few, mode: .debts).more == 0)
        #expect(CardStack<EmptyView>.shown(all, mode: .day).edges.count == all.count)
    }

    /// Край долга пишет день съёмки и просрочку («17 сент · −N дн», терракотой), а не часы.
    @Test func debtEdgeSaysDayAndOverdue() {
        let a = app()
        a.openCardFromCalendar(id: "sd_oct_ad")
        let card = a.card!
        for p in a.stack(of: card) {
            let x = PeekText(p, card: card, app: a, debts: true)
            let day = DateText(language: "ru").dMonShort(PlannerFacts(app: a, dark: true).date(p.day))
            #expect(x.time.hasPrefix(day), Comment(rawValue: "\(p.id): \(x.time)"))
            #expect(!x.time.contains(":"), Comment(rawValue: "\(p.id): часов нет — \(x.time)"))
            if case .overdue(let d) = a.deliveryStatus(p) {
                #expect(x.over && x.time == day + " · −" + a.lexicon.count("unit.dayShort", d), Comment(rawValue: "\(p.id): \(x.time)"))
            } else {
                #expect(!x.over && x.time == day, Comment(rawValue: "\(p.id): \(x.time)"))
            }
        }
        #expect(a.stack(of: card).contains { if case .overdue = a.deliveryStatus($0) { true } else { false } }, "есть просроченный")
        #expect(PeekText.debtDay(CivilDate(year: 2026, month: 9, day: 17), app: a) == "17 сен")
        #expect(PeekText.debtDay(CivilDate(year: 2025, month: 12, day: 30), app: a).hasSuffix("2025"))
        // Стопка дня — по-прежнему часы.
        let day = PeekText(a.sessions.first { $0.id == "sd_sep_meet" }!, card: a.sessions.first { $0.id == "sd_sep_now" }!, app: a)
        #expect(day.time == "19:00 – 20:00")
    }
}
