import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Итерация 26, шаг 2: перенос блока в порядке группы и «есть ли у записи
/// что показать». Справка — `Light_Plan/docs/card_reference.md`, «Блоки».
struct CardBlocksTests {

    private let base = CardBlock.allCases

    // MARK: - Перенос

    /// Вниз блок встаёт сразу за строкой, мимо которой прошёл последней.
    @Test func moveDownLandsRightAfterPassedRow() {
        let listed: [CardBlock] = [.deal, .day, .brief, .money]
        let out = CardOrder.move(.deal, to: 1, listed: listed, order: base)
        #expect(Array(out.prefix(3)) == [.day, .deal, .clash])
    }

    /// Вверх — сразу перед строкой, мимо которой прошёл последней.
    @Test func moveUpLandsRightBeforePassedRow() {
        let listed: [CardBlock] = [.deal, .day, .brief, .notes, .money]
        let out = CardOrder.move(.notes, to: 2, listed: listed, order: base)
        let i = out.firstIndex(of: .notes)!
        #expect(out[i + 1] == .brief)
        #expect(out[i - 1] == .refs)
    }

    /// Ошибка 2 веба: портрет без маршрута переставили — у следующего
    /// портрета с маршрутом «Маршрут дня» не уезжает ниже гонорара.
    @Test func moveKeepsAbsentBlocksInPlace() {
        let listed: [CardBlock] = [.deal, .day, .brief, .notes, .delivery, .money]
        let out = CardOrder.move(.money, to: 0, listed: listed, order: base)
        #expect(out == [.money] + base.filter { $0 != .money })
        #expect(out.firstIndex(of: .route)! < out.firstIndex(of: .delivery)!)
    }

    @Test func moveToSamePlaceChangesNothing() {
        #expect(CardOrder.move(.day, to: 1, listed: [.deal, .day], order: base) == base)
    }

    /// Правка с дублем — полный порядок без дублей (дубль на последнем месте).
    @Test func fullOrderDropsDuplicates() {
        let full = CardOrder.full(genre: .portrait, saved: [.people: [.money, .deal, .money]])
        #expect(full.count == 14)
        #expect(full.first == .deal)
    }

    // MARK: - Есть ли что показать

    private func shoot(_ g: Genre = .portrait) -> Session {
        Session(id: "s", kind: .shoot, day: CivilDate(year: 2026, month: 9, day: 21),
                start: 600, end: 720, duration: 120, genre: g)
    }

    private func has(_ b: CardBlock, _ s: Session, _ p: EventPhase = .before, _ pr: Practice = .ru) -> Bool? {
        CardPresence.byRecord(b, s, phase: p, practice: pr, among: [s])
    }

    @Test func routeNeedsTimedNamedPointBeforeEnd() {
        var s = shoot()
        #expect(has(.route, s) == false)
        s.route = [RoutePoint(start: nil, name: "Парк")]
        #expect(has(.route, s) == false)
        s.route = [RoutePoint(start: 660, name: "Парк")]
        #expect(has(.route, s) == true)
        #expect(has(.route, s, .after) == false)
        s.kind = .meet
        #expect(has(.route, s) == false)
    }

    @Test func recordFieldsDecide() {
        var s = shoot()
        #expect(has(.day, s) == true)
        #expect(has(.brief, s) == false)
        #expect(has(.models, s) == false)
        s.models = "\n  \n"
        #expect(has(.models, s) == false)
        s.models = "\nАня"
        #expect(has(.models, s) == true)
        s.brief = "каталог"; s.notes = "зонт"
        #expect(has(.brief, s) == true)
        #expect(has(.notes, s) == true)
        #expect(has(.docs, s) == false)
        #expect(has(.refs, s) == nil)   // кадры лежат в снимке, решает `AppModel.cardRefs` (27)
        #expect(has(.money, s) == false)
        s.expense = 300
        #expect(has(.money, s) == true)
    }

    @Test func deliveryOnlyForWorkWithDelivery() {
        #expect(has(.delivery, shoot()) == true)
        #expect(has(.delivery, shoot(.landscape)) == false)
        var m = shoot(); m.kind = .meet
        #expect(has(.delivery, m) == false)
    }

    @Test func dealForClientOrForeignPractice() {
        #expect(has(.deal, shoot(.product)) == true)
        #expect(has(.deal, shoot()) == false)
        #expect(has(.deal, shoot(), .before, .us) == true)
    }

    /// Наложение, свет, погоду и место решает прибор, а не запись.
    @Test func instrumentBlocksAskCaller() {
        for b in [CardBlock.clash, .light, .weather, .place] { #expect(has(b, shoot()) == nil) }
    }

    // MARK: - Заказ после съёмки: без закрепления (Алексей, 29.09)

    private var clientGenre: Genre { Genre.allCases.first { GenreProfile($0).group == .client }! }

    /// Веб выносит сделку, документы, гонорар и сдачу вперёд поверх порядка — Алексей назвал
    /// это ошибкой: плитка дня стоит там, куда её поставили, в любой фазе.
    @Test func afterPhaseKeepsPhotographersOrder() {
        let g = clientGenre
        let full = CardOrder.full(genre: g, saved: [:])
        for phase in [EventPhase.before, .during, .after] {
            #expect(CardOrder.shown(genre: g, saved: [:], phase: phase) == full)
        }
        let listed = full.filter { [.deal, .docs, .money, .delivery, .day, .place, .brief].contains($0) }
        // Плитку дня — на первое место, и на карточке она первая, в том числе после съёмки.
        let up = CardOrder.move(.day, to: 0, listed: listed, order: full)
        #expect(CardOrder.shown(genre: g, saved: [.client: up], phase: .after).first == .day)
        // На четвёртое — и стоит четвёртой среди видимых, а не в конце.
        let mid = CardOrder.move(.day, to: 3, listed: listed, order: full)
        let seen = CardOrder.shown(genre: g, saved: [.client: mid], phase: .after).filter { listed.contains($0) }
        #expect(seen.firstIndex(of: .day) == 3)
    }
}
