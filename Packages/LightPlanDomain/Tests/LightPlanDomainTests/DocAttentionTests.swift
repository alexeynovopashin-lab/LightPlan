import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// «Требуют внимания»: правила и границы таблицы § 4.2 справки 28д, «сегодня» по поясу.
@Suite struct DocAttentionTests {
    typealias Att = LightPlanDomain.Attachment
    static let today = CivilDate(year: 2026, month: 10, day: 1)

    /// Съёмка заказчика (сделка в `ru` показывается) через `ahead` дней от `today` (отрицательное — было).
    static func shoot(_ id: String = "s", ahead: Int, genre: Genre = .product, rate: Decimal? = 40_000,
                      prepay: Decimal = 0, org: String? = nil, docs: [DocKind] = [], delivered: Bool = false) -> Session {
        var s = Session(id: id, kind: .shoot, day: today.adding(days: ahead), start: 600, end: 720, duration: 120, genre: genre)
        s.pay = rate == nil ? nil : .flat
        s.rate = rate
        s.prepay = prepay
        s.orgId = org
        s.delivered = delivered
        s.docs = docs.map { Att(source: .link, url: "https://x.io/\($0.rawValue)", kind: $0) }
        return s
    }

    static func reasons(_ s: Session, _ practice: Practice = .ru, orgs: [Org] = [], today t: CivilDate = today) -> [DocAttention.Reason] {
        DocAttention.reasons(for: s, orgs: orgs, among: [s], practice: practice, today: t)
    }

    // MARK: правило 1 — нет договора

    @Test(arguments: [(0, true), (7, true), (8, false), (1, true)])
    func contractWindowIsZeroToSevenDays(ahead: Int, listed: Bool) {
        let r = Self.reasons(Self.shoot(ahead: ahead, rate: nil))
        #expect(r.contains(.noContract) == listed, "до съёмки \(ahead) дн.")
    }

    @Test func yesterdayWithoutContractIsNotRuleOne() {
        let r = Self.reasons(Self.shoot(ahead: -1, rate: nil))
        #expect(!r.contains(.noContract), "съёмка прошла — это уже не правило 1")
        #expect(r.isEmpty, "и до трёх дней после акт ещё не ждут")
    }

    @Test func contractOnTheShootClosesRuleOne() {
        #expect(Self.reasons(Self.shoot(ahead: 5, rate: nil, docs: [.contract])).isEmpty)
    }

    @Test func yearContractOfOrgClosesRuleOneHereOnly() {
        var yar = Org(id: "y", name: "Яр")
        yar.docs = [Att(source: .link, url: "https://x.io/dog", kind: .contract)]
        let s = Self.shoot(ahead: 5, rate: nil, org: "y")
        #expect(Self.reasons(s, orgs: [yar]).isEmpty, "годовой договор организации закрывает «Договор» в списке")
        #expect(Self.reasons(s, orgs: []) == [.noContract], "организации нет под рукой — договора нет")
        let card = DealChain.links(for: s, practice: .ru, among: [s]).first { $0.step == .contract }
        #expect(card?.done == false, "карточка съёмки не меняется: там «Договор» по-прежнему открыт")
        var other = yar; other.id = "z"
        #expect(Self.reasons(s, orgs: [other]) == [.noContract], "договор чужой организации не считается")
        var noKind = yar; noKind.docs = [Att(source: .link, url: "https://x.io/other", kind: .invoice)]
        #expect(Self.reasons(s, orgs: [noKind]) == [.noContract], "в организации лежит не договор")
    }

    // MARK: правило 2 — нет закрывающей бумаги

    @Test(arguments: [(-3, true), (-2, false), (0, false), (-40, true), (-4, true)])
    func closingPaperWaitsThreeDays(ahead: Int, listed: Bool) {
        let r = Self.reasons(Self.shoot(ahead: ahead, rate: nil, docs: [.contract]))
        #expect(r.contains(.noClosing) == listed, "после съёмки \(-ahead) дн.")
    }

    @Test func actClosesRuleTwo() {
        #expect(Self.reasons(Self.shoot(ahead: -40, rate: nil, docs: [.contract, .act])).isEmpty)
    }

    @Test func euClosingPaperIsAcceptanceProtocolNotAct() {
        let withAct = Self.shoot(ahead: -5, rate: nil, docs: [.contract, .act])
        #expect(Self.reasons(withAct, .eu) == [.noClosing], "в eu акта мало — нужен протокол приёмки")
        let withProtocol = Self.shoot(ahead: -5, rate: nil, docs: [.contract, .acceptance])
        #expect(Self.reasons(withProtocol, .eu).isEmpty)
    }

    @Test(arguments: [Practice.us, Practice.uk])
    func outsideRuAndEuThereIsNoClosingRule(practice: Practice) {
        // Решение Алексея 02.10: закрывающая бумага вне России — только акт (ru) и протокол приёмки (eu).
        // Строка таблицы справки «2, uk, 3 дня, не передано → в списке» этим решением заменена.
        let s = Self.shoot(ahead: -3, rate: nil, docs: [.contract], delivered: false)
        #expect(Self.reasons(s, practice).isEmpty, "релиз и передача материала не тревожат")
    }

    // MARK: правило 3 — счёт есть, оплаты нет

    @Test func invoiceWithoutPaymentIsListedAtAnyDistance() {
        for ahead in [-30, -3, 0, 14, 60] {
            let s = Self.shoot(ahead: ahead, rate: 40_000, prepay: 0, docs: [.contract, .invoice, .act])
            #expect(Self.reasons(s) == [.noPay], "счёт есть, оплаты нет, \(ahead) дн.: порога по дням нет")
        }
    }

    @Test func fullyPaidIsNotListed() {
        #expect(Self.reasons(Self.shoot(ahead: 2, rate: 40_000, prepay: 40_000, docs: [.contract, .invoice])).isEmpty)
    }

    @Test func partlyPaidStillWaits() {
        #expect(Self.reasons(Self.shoot(ahead: 2, rate: 40_000, prepay: 10_000, docs: [.contract, .invoice])) == [.noPay])
    }

    @Test func noIncomeMeansNoPaymentRule() {
        #expect(Self.reasons(Self.shoot(ahead: 2, rate: nil, docs: [.contract, .invoice])).isEmpty)
        #expect(Self.reasons(Self.shoot(ahead: 2, rate: 0, docs: [.contract, .invoice])).isEmpty, "гонорар ноль — не тревога")
    }

    @Test func noInvoiceMeansNoPaymentRule() {
        #expect(!Self.reasons(Self.shoot(ahead: 2, rate: 40_000, docs: [.contract])).contains(.noPay), "счёта нет — правило 1/2 по своему сроку")
    }

    @Test(arguments: [Practice.us, Practice.uk])
    func balanceIsThePayStepOutsideRu(practice: Practice) {
        let unpaid = Self.shoot(ahead: 2, rate: 40_000, prepay: 10_000, docs: [.contract, .invoice])
        #expect(Self.reasons(unpaid, practice) == [.noPay])
        let paid = Self.shoot(ahead: 2, rate: 40_000, prepay: 40_000, docs: [.contract, .invoice])
        #expect(Self.reasons(paid, practice).isEmpty)
    }

    // MARK: что вообще проверяется

    @Test func meetingsEventsAndPrivateRuShootsAreNever() {
        var meet = Self.shoot(ahead: 3, rate: nil); meet.kind = .meet
        var event = Self.shoot(ahead: 3, rate: nil); event.kind = .event
        #expect(Self.reasons(meet).isEmpty && Self.reasons(event).isEmpty)
        let own = Self.shoot(ahead: 3, genre: .landscape, rate: nil)
        #expect(Self.reasons(own, .ru).isEmpty, "частная съёмка в ru — сделки нет")
        #expect(Self.reasons(own, .us) == [.noContract], "а в us сделка и частной нужна")
    }

    @Test func shootInTheBinIsNotInTheList() {
        // Съёмка в корзине съёмок в `sessions` не лежит: её здесь просто нет.
        let live = Self.shoot("live", ahead: 2, rate: nil)
        let items = DocAttention.items(sessions: [live], orgs: [], practice: .ru, today: Self.today)
        #expect(items.map(\.session.id) == ["live"])
        #expect(DocAttention.items(sessions: [], orgs: [], practice: .ru, today: Self.today).isEmpty)
    }

    // MARK: порядок и группы

    @Test func oneShootWithTwoReasonsIsOneRowInTheMoreUrgentGroup() {
        let both = Self.shoot("both", ahead: -5, rate: 40_000, docs: [.invoice])
        let items = DocAttention.items(sessions: [both], orgs: [], practice: .ru, today: Self.today)
        #expect(items.count == 1, "счётчик — съёмки, а не причины")
        #expect(items[0].reasons == [.noClosing, .noPay] && items[0].daysUntil == -5)
        let groups = DocAttention.groups(items)
        #expect(groups.map(\.reason) == [.noClosing], "стоит в срочной, вторая причина — словом в строке")
    }

    @Test func groupsAndRowsAreOrderedByUrgencyThenByNearestDay() {
        let c3 = Self.shoot("c3", ahead: 3, rate: nil), c1 = Self.shoot("c1", ahead: 1, rate: nil)
        let a10 = Self.shoot("a10", ahead: -10, rate: nil, docs: [.contract]), a4 = Self.shoot("a4", ahead: -4, rate: nil, docs: [.contract])
        let p = Self.shoot("p", ahead: 20, rate: 5_000, docs: [.contract, .invoice])
        let items = DocAttention.items(sessions: [p, a4, c3, a10, c1], orgs: [], practice: .ru, today: Self.today)
        #expect(items.map(\.session.id) == ["c1", "c3", "a10", "a4", "p"], "договор: ближе к съёмке выше; акт: давнее выше")
        #expect(DocAttention.groups(items).map(\.reason) == [.noContract, .noClosing, .noPay])
        #expect(DocAttention.groups(items).map { $0.items.count } == [2, 2, 1])
    }

    // MARK: «сегодня» по часовому поясу

    static func moment(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Moment {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return Moment(c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!)
    }

    @Test(arguments: [("Asia/Barnaul", 2, 7, true), ("UTC", 1, 8, false), ("America/Los_Angeles", 1, 8, false)])
    func todayFollowsThePhoneZone(zone: String, day: Int, ahead: Int, listed: Bool) {
        let t = DocAttention.today(at: Self.moment(2026, 10, 1, 20), zone: TimeZone(identifier: zone)!)
        #expect(t == CivilDate(year: 2026, month: 10, day: day), Comment(rawValue: zone))
        var s = Session(id: "s", kind: .shoot, day: CivilDate(year: 2026, month: 10, day: 9), start: 600, genre: .product)
        s.pay = nil
        #expect(s.day.days(since: t) == ahead)
        #expect(DocAttention.reasons(for: s, orgs: [], among: [s], practice: .ru, today: t).contains(.noContract) == listed)
    }

    @Test func todayFlipsExactlyAtLocalMidnight() {
        let barnaul = TimeZone(identifier: "Asia/Barnaul")!
        #expect(DocAttention.today(at: Self.moment(2026, 10, 1, 16, 59), zone: barnaul) == CivilDate(year: 2026, month: 10, day: 1))
        #expect(DocAttention.today(at: Self.moment(2026, 10, 1, 17, 0), zone: barnaul) == CivilDate(year: 2026, month: 10, day: 2))
    }
}
