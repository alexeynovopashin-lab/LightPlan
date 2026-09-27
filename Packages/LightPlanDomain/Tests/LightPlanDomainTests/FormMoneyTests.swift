import Foundation
import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Деньги и срок сдачи в форме (итерация 24, шаг 3): правила `renderPay` веба,
/// доля месяца с набранной суммой против беты, круговой тест записи.
@Suite struct FormMoneyTests {
    let day = CivilDate(year: 2026, month: 10, day: 3)
    let f = DomainOracle.file
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func fresh(_ g: Genre, prefs: GenrePrefs? = nil, rate: Decimal = 0) -> EventForm {
        EventForm.new(id: "x1", day: day, start: 600, fromLight: false, genre: g, prefs: prefs, light: nil, genreRate: rate)
    }

    // MARK: против беты

    @Test func monthShareWithTypedSumMatchesWeb() {
        let list = f["money"]["monthlySessions"].array!.map(DomainOracle.session)
        let rows = f["money"]["monthEdit"].array!
        var bad: [String] = []
        for r in rows {
            let s = list.first { $0.id == r["id"].string! }!
            let e = MonthSum(month: r["k"].int!, sum: Decimal(r["sum"].double!), at: .max)
            let share = Money.monthShare(of: s, among: list, edit: e)
            let k = Money.monthIndex(start: s.repeatInfo!.start!, day: s.day)
            let at = Money.monthSum(s.repeatInfo!, month: k, among: list, edit: e)
            if !DomainOracle.sameMoney(share, r["share"].double!) || !DomainOracle.sameMoney(at, r["at"].double!) {
                bad.append("\(r["id"]) k=\(r["k"]) sum=\(r["sum"]): \(share) / \(at) вместо \(r["share"]) / \(r["at"])")
            }
        }
        #expect(rows.count == 72)
        #expect(bad.isEmpty, "\(bad.count) расхождений: \(bad.prefix(5))")
    }

    @Test func periodStartMatchesWeb() {
        let rows = f["money"]["periodStart"].array!
        var bad: [String] = []
        for r in rows {
            let p = r["start"].string!.split(separator: "-").map { Int($0)! }
            let got = Money.periodStart(start: CivilDate(year: p[0], month: p[1], day: p[2]), month: r["k"].int!)
            if got != CivilDate(year: r["y"].int!, month: r["m"].int!, day: r["d"].int!) {
                bad.append("\(r["start"]) k=\(r["k"]): \(got) вместо \(r["y"])-\(r["m"])-\(r["d"])")
            }
        }
        #expect(rows.count == 102)
        #expect(bad.isEmpty, "\(bad.prefix(5))")
    }

    // MARK: способ и ставка

    @Test func presetTakesGenreRateAndRememberedPay() {
        let a = fresh(.portrait, rate: 2500)
        #expect(a.pay == .hourly && a.rate == 2500 && a.units == 1)
        #expect(!a.payOpen, "ставка настроена — доход считается сам, блок свёрнут")
        let b = fresh(.portrait, prefs: GenrePrefs(pay: .flat), rate: 2500)
        #expect(b.pay == .flat && b.rate == 0 && b.payOpen)
        // Запомненный способ не из жанра — первый жанровый
        let c = fresh(.architecture, prefs: GenrePrefs(pay: .hourly), rate: 2500)
        #expect(c.pay == .object && c.rate == 0)
        #expect(fresh(.portrait).payOpen, "ставки нет — блок раскрыт")
    }

    @Test func switchingMechanicClearsTheNumber() {
        var x = fresh(.portrait, rate: 2000)
        x.choosePay(.flat, genreRate: 2000)
        #expect(x.rate == 0, "сумма часа не становится суммой сделки")
        x.rate = 40000
        x.choosePay(.pack, genreRate: 2000)
        #expect(x.rate == 0, "вход в пакеты чистит поле")
        x.choose(Pack(name: "Загс", price: 40000, hours: 3))
        #expect(x.rate == 40000 && x.duration == 180 && x.isChosen(Pack(name: "Загс", price: 40000)))
        x.choosePay(.hourly, genreRate: 2000)
        #expect(x.rate == 2000)
        x.choosePay(.item, genreRate: 2000)       // не из жанра
        #expect(x.pay == .hourly)
    }

    @Test func unitsStayInRange() {
        var x = fresh(.product)
        x.choosePay(.item, genreRate: 0)
        x.rate = 700
        x.stepUnits(-1)
        #expect(x.units == 1)
        x.units = 3
        #expect(x.income(FormMoneyContext()) == 2100)
        x.units = 9999; x.stepUnits(1)
        #expect(x.units == 9999)
    }

    // MARK: предоплата

    @Test func prepayFollowsGenreShareUntilTyped() {
        var x = fresh(.portrait, rate: 1500)
        x.duration = 90
        let ctx = FormMoneyContext(genreRate: 1500, prepayShare: 30)
        #expect(x.income(ctx) == 2250 && x.prepay(ctx) == 675 && x.rest(ctx) == 1575)
        x.rate = 1501                               // 2251,5 × 30 % = 675,45 → 675
        #expect(x.prepay(ctx) == 675)
        x.typePrepay(1000)
        #expect(x.prepay(ctx) == 1000, "набранное руками доля не пересчитывает")
        x.prepayShareChanged(to: 50)
        #expect(x.prepay(FormMoneyContext(genreRate: 1500, prepayShare: 50)) == 1126, "выбрали долю в листе — она снова держит поле")
        x.prepayShareChanged(to: 0)
        #expect(x.prepay(FormMoneyContext(genreRate: 1500)) == 0, "«Нет» убирает поставленное долей")
        // Сохранённая запись: предоплата уже названа числом, доля ей не указ
        var s = Session(id: "p", day: day, start: 600, duration: 90, genre: .portrait)
        s.pay = .hourly; s.rate = 1500; s.prepay = 500
        #expect(EventForm.editing(s).prepay(ctx) == 500)
    }

    @Test func netAndRestAreSeparateQuestions() {
        var x = fresh(.portrait)
        x.choosePay(.flat, genreRate: 0)
        x.rate = 10000; x.expense = 1200; x.typePrepay(12000)
        let ctx = FormMoneyContext()
        #expect(x.net(ctx) == 8800 && x.rest(ctx) == 0, "остаток не уходит в минус")
        #expect(x.summaryAmount(ctx) == 8800)
    }

    // MARK: помесячно

    @Test func composingAMonthSplitsTheSum() {
        var x = fresh(.portrait)
        x.repeatRule = .week
        x.repeatCount = 8
        #expect(x.payKinds.last == .monthly)
        x.choosePay(.monthly, genreRate: 0)
        #expect(x.rate == nil && x.composesMonth)
        #expect(x.firstMonthCount == 5, "3, 10, 17, 24, 31 октября")
        x.setMonth(perShoot: 8000)
        #expect(x.repeatMonthly == 40000 && x.income(FormMoneyContext()) == 8000)
        x.setMonth(perHour: 4000)                   // час × 4000 × 5 съёмок
        #expect(x.repeatMonthly == 20000 && x.summaryAmount(FormMoneyContext()) == 20000)
        // Повтор сняли — «В месяц» пропадает, ставка не становится суммой месяца
        x.repeatRule = nil
        x.fitPay(genreRate: 1800)
        #expect(x.pay == .hourly && x.rate == 1800)
        var s = x.session(orgName: nil, and: " и ")
        s.pay = .monthly
        let copies = Repeats.make(&s, rule: .week, count: 3, blocks: RepeatBlock.defaults, home: RepeatHome(town: "", latitude: 0, longitude: 0),
                                  group: "g", monthly: 40000) { "c" }
        #expect(s.repeatInfo?.monthly == 40000 && s.rate == nil && copies.count == 2)
    }

    @Test func typedMonthSumIsNewShareFromThisMonth() {
        let list = f["money"]["monthlySessions"].array!.map(DomainOracle.session)
        let m5 = list.first { $0.id == "m5" }!
        var x = EventForm.editing(m5)
        let ctx = FormMoneyContext(sessions: list)
        #expect(x.monthGroup != nil)
        let was = x.monthSumWas(ctx)
        #expect(x.summaryAmount(ctx) == was && x.monthSumEdit(ctx) == nil)
        x.monthSumTyped = was
        #expect(x.monthSumEdit(ctx) == nil, "то же число — не смена")
        x.monthSumTyped = 60000
        let e = x.monthSumEdit(ctx)!
        #expect(e.sum == 60000 && e.month == Money.monthIndex(start: m5.repeatInfo!.start!, day: m5.day))
        #expect(x.income(ctx) == Money.monthShare(of: m5, among: list, edit: e))
        #expect(x.summaryAmount(ctx) == 60000)
        #expect(x.ratePlaceholder(ctx) == EventForm.roundMoney(x.income(ctx)))
    }

    // MARK: срок сдачи

    @Test func deadlineDialAndDelivered() {
        var x = fresh(.portrait, prefs: GenrePrefs(deadline: .days(14)))
        #expect(x.deadline == .days(14) && x.deadlineStop == 3)
        x.deadline = .days(5)
        #expect(x.deadlineStop == 0, "своё число вне шкалы стоит на первом делении, как у веба")
        x.setDelivered(true, now: now)
        #expect(x.delivered && x.deliveredAt == now)
        x.setDelivered(false, now: now)
        #expect(x.deliveredAt == nil)
        #expect(fresh(.landscape).deadline == .none, "пейзажу сдавать некому")
        // Сохранённую запись перевели в пейзаж — срока и отметки нет
        x.setDelivered(true, now: now)
        var e = EventForm.editing(x.session(orgName: nil, and: " и "))
        e.pick(.landscape)
        #expect(e.deadline == .none && !e.delivered && e.pay == .flat)
    }

    // MARK: запись без потерь

    /// Запись → форма → сохранение → та же запись, поле в поле: деньги, срок,
    /// отметка «сдан» и поля, которых в форме нет, сохраняются сами.
    @Test func roundTripKeepsEveryField() {
        var s = Session(id: "rt", day: day, start: 660, duration: 120, genre: .wedding)
        s.end = 780                                  // веб пишет конец всегда
        s.pay = .pack; s.rate = 85000; s.units = 1; s.expense = 3500; s.prepay = 20000; s.currency = .eur
        s.deadline = .days(30); s.delivered = true; s.deliveredAt = now
        s.questSent = now; s.fromMeetId = "m1"; s.fromMeetOn = day; s.grewToId = "g2"
        s.persons = [Person(name: "Елена", phone: ""), Person(name: "Иван", phone: "")]
        s.contact = "Елена и Иван"; s.guests = 80
        s.modifiedAt = 1
        let back = EventForm.editing(s, home: .rub).session(orgName: nil, and: " и ", now: Date(timeIntervalSince1970: 0.001))
        #expect(back == s)
        // Своей валюты нет — у правки она из настроек, и в запись уходит явно, как у веба
        var r = s; r.currency = nil
        #expect(EventForm.editing(r, home: .usd).session(orgName: nil, and: " и ").currency == .usd)
    }

    @Test func draftKeepsMoney() throws {
        var x = fresh(.portrait, rate: 1200)
        x.choosePay(.flat, genreRate: 1200)
        x.rate = 9000; x.expense = 500; x.typePrepay(3000); x.currency = .usd
        x.deadline = .none; x.setDelivered(true, now: now); x.contact = "Ольга"
        let data = try #require(x.draftData())
        let back = try #require(EventForm.fromDraft(data))
        #expect(back.pay == .flat && back.rate == 9000 && back.expense == 500 && back.prepayTyped == 3000)
        #expect(!back.prepayAuto && back.currency == .usd && back.deadline == .none)
        #expect(back.delivered && back.deliveredAt == now)
    }

    @Test func typedRateMakesADraft() {
        #expect(fresh(.portrait).hasTypedContent == false)
        #expect(fresh(.portrait, rate: 1500).hasTypedContent, "жанровая ставка часа — черновик, как у веба (`+o.rate > 0`)")
    }

    // MARK: пакеты в снимке

    @Test func packsReadLikeWeb() throws {
        let old = try JSONDecoder().decode(JSONValue.self, from: Data("[14000, 0, 25000]".utf8))
        let a = Pack.genrePacks(from: old)
        #expect(a[.wedding]?.map(\.price) == [14000, 25000])
        let json = """
        {"portrait":[{"n":"Фотосет","p":6000,"h":1.5},{"n":"","p":0,"h":null}],"nope":[{"n":"x","p":1}]}
        """
        let b = Pack.genrePacks(from: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
        #expect(b.count == 1 && b[.portrait] == [Pack(name: "Фотосет", price: 6000, hours: 1.5)])
    }
}
