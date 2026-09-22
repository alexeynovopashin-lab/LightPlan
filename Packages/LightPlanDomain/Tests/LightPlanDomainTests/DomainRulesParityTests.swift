import Foundation
import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Правила съёмки против беты: каждый случай эталона прогоняется через Swift, и
/// расхождения копятся списком — тест падает с первыми пятью и их числом.
struct DomainRulesParityTests {
    let f = DomainOracle.file
    let utc = TimeZone(identifier: "UTC")!

    func report(_ name: String, _ bad: [String], total: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(total > 0, "\(name): эталон пуст", sourceLocation: sourceLocation)
        #expect(bad.isEmpty, "\(name): \(bad.count) расхождений из \(total)\n  \(bad.prefix(5).joined(separator: "\n  "))",
                sourceLocation: sourceLocation)
    }

    @Test func formShape() {
        var bad: [String] = []
        let rows = f["form"].array!
        for r in rows {
            let code = r["genre"].string!, mode = FormMode(rawValue: r["mode"].string!)!
            let want = r["on"].array!.map { $0.bool! }
            let got = FormField.allCases.map { FormShape.shows($0, genre: Genre(rawValue: code), mode: mode) }
            if got != want { bad.append("\(code)/\(mode): \(got) вместо \(want)") }
        }
        report("состав формы", bad, total: rows.count)
        #expect(rows.count == (Genre.allCases.count + 1) * 2)
    }

    @Test func deadlines() {
        var bad: [String] = []
        let rows = f["deadlines"].array!
        for r in rows {
            let s = DomainOracle.session(r["s"])
            let d = r["delivery"]
            let setting = DeliverySetting(mode: DeliveryMode(rawValue: d["mode"].string!) ?? .genre, days: d["days"].int!)
            var prefs: [Genre: GenrePrefs] = [:]
            if let own = r["pref"].int, let g = s.genre { prefs[g] = GenrePrefs(deliveryDays: own) }
            let days = Delivery.days(for: s, setting: setting, prefs: prefs)
            let date = Delivery.deadline(for: s, setting: setting, prefs: prefs)
            let dateText = date.map { String(format: "%04d-%02d-%02d", $0.year, $0.month, $0.day) }
            if days != r["days"].int || dateText != r["date"].string {
                bad.append("\(r["s"]) \(d): \(String(describing: days)) \(String(describing: dateText)) вместо \(r["days"]) \(r["date"])")
            }
        }
        report("сроки сдачи", bad, total: rows.count)
    }

    @Test func deliveryDays() {
        var bad: [String] = []
        let rows = f["deliveryDays"].array!
        for r in rows {
            let got = Delivery.daysTaken(DomainOracle.session(r["s"]), zone: utc)
            if got != r["days"].int { bad.append("\(r["s"]): \(String(describing: got)) вместо \(r["days"])") }
        }
        report("за сколько сдан материал", bad, total: rows.count)
    }

    @Test func deliveryStatus() {
        var bad: [String] = []
        let rows = f["deliveryStates"].array!
        for r in rows {
            let s = DomainOracle.session(r["s"])
            let st = Delivery.status(s, now: Moment(milliseconds: Int64(r["now"].double!)), zone: utc,
                                     setting: .standard, prefs: [:])
            let label: String?, count: Int?, p: J
            switch st {
            case .notWork: (label, count, p) = (nil, nil, .null)
            case .done: (label, count, p) = ("delv.done", nil, .null)
            case .ahead: (label, count, p) = ("delv.ahead", nil, .null)
            case .noTerm: (label, count, p) = ("delv.noTerm", nil, .null)
            case .due(let progress, let left): (label, count, p) = ("delv.dueIn", left, progress.isNaN ? .string("NaN") : .number(progress))
            case .overdue(let days): (label, count, p) = ("delv.overdue", days, .null)
            }
            var ok = st.rank == r["rank"].int! && label == r["label"].string && count == r["count"].int
            switch (p, r["p"]) {
            case (.number(let a), .number(let b)): ok = ok && abs(a - b) <= 1e-12
            case (.string(let a), .string(let b)): ok = ok && a == b
            case (.null, .null): break
            default: ok = false
            }
            if !ok { bad.append("\(r["s"]) now=\(r["now"]): \(st) вместо \(r["rank"]) \(r["label"]) \(r["count"]) \(r["p"])") }
        }
        report("ступень сдачи", bad, total: rows.count)
    }

    @Test func incomeAndNet() {
        var bad: [String] = []
        let rows = f["money"]["income"].array!
        for r in rows {
            let s = DomainOracle.session(r["s"])
            let inc = Money.income(of: s, among: []), net = Money.net(of: s, among: [])
            if !DomainOracle.sameMoney(inc, r["income"].double!) || !DomainOracle.sameMoney(net, r["net"].double!) {
                bad.append("\(r["s"]): \(inc) / \(net) вместо \(r["income"]) / \(r["net"])")
            }
        }
        report("доход по механикам оплаты", bad, total: rows.count)
    }

    @Test func monthlyShare() {
        var bad: [String] = []
        let list = f["money"]["monthlySessions"].array!.map(DomainOracle.session)
        let rows = f["money"]["monthly"].array!
        #expect(list.count == rows.count)
        for (s, r) in zip(list, rows) {
            let inc = Money.income(of: s, among: list), net = Money.net(of: s, among: list)
            let period = s.repeatInfo?.start.map { Money.monthIndex(start: $0, day: s.day) }
            if !DomainOracle.sameMoney(inc, r["income"].double!) || !DomainOracle.sameMoney(net, r["net"].double!)
                || period != r["period"].int {
                bad.append("\(s.id): \(inc) / \(net) / \(String(describing: period)) вместо \(r)")
            }
        }
        report("доля месяца у повтора", bad, total: rows.count)
    }

    @Test func sumsByCurrency() {
        var bad: [String] = []
        let lists = f["money"]["currencyLists"].array!.map { $0.array!.map(DomainOracle.session) }
        let rows = f["money"]["byCurrency"].array!
        for r in rows {
            let list = lists[r["list"].int!], home = Currency(rawValue: r["home"].string!)!
            let amount: (Session) -> Decimal
            switch r["amount"].string! {
            case "income": amount = { Money.income(of: $0, among: list) }
            case "net": amount = { Money.net(of: $0, among: list) }
            default: amount = { $0.prepay }
            }
            let got = Money.sumByCurrency(list, home: home, amount: amount)
            let want = r["sums"].array!.map { ($0[0].string!, $0[1].double!) }
            let same = got.count == want.count && zip(got, want).allSatisfy { $0.currency.rawValue == $1.0 && DomainOracle.sameMoney($0.sum, $1.1) }
            if !same { bad.append("список \(r["list"]) \(home) \(r["amount"]): \(got) вместо \(want)") }
        }
        report("суммы по валютам", bad, total: rows.count)
    }

    @Test func dealChains() {
        var bad: [String] = []
        let rows = f["deal"]["chains"].array!
        for r in rows {
            let s = DomainOracle.session(r["s"]), p = Practice(rawValue: r["practice"].string!)!
            let got = DealChain.links(for: s, practice: p, among: [s])
            let want = r["chain"].array!
            let same = got.count == want.count && zip(got, want).allSatisfy { l, w in
                l.step.rawValue == w[0].string! && l.done == w[1].bool! && l.partlyPaid == w[2].bool
            }
            if !same { bad.append("\(p) \(r["s"]): \(got.map { "\($0.step):\($0.done):\(String(describing: $0.partlyPaid))" })") }
        }
        report("цепочка сделки", bad, total: rows.count)

        var hidden: [String] = []
        let shown = f["deal"]["shown"].array!
        for r in shown {
            let got = DealChain.isShown(genre: Genre(rawValue: r["genre"].string!), practice: Practice(rawValue: r["practice"].string!)!)
            if got != r["shown"].bool! { hidden.append("\(r["practice"]) \(r["genre"])") }
        }
        report("блок сделки показан", hidden, total: shown.count)
    }

    @Test func cardOrder() {
        func blocks(_ j: J) -> [CardBlock] { (j.strings ?? []).compactMap(CardBlock.init(rawValue:)) }
        var bad: [String] = []
        let rows = f["order"]["orders"].array!
        for r in rows {
            let g = Genre(rawValue: r["genre"].string!)
            var saved: [GenreGroup: [CardBlock]] = [:]
            if !r["saved"].isNull { saved[GenreProfile(g).group] = blocks(r["saved"]) }
            let phase = EventPhase(rawValue: r["phase"].string!)!
            let order = CardOrder.order(genre: g, saved: saved), shown = CardOrder.shown(genre: g, saved: saved, phase: phase)
            if order.map(\.rawValue) != r["orderFor"].strings! || shown.map(\.rawValue) != r["shown"].strings! {
                bad.append("\(r["genre"]) \(r["saved"]) \(phase): \(order) / \(shown)")
            }
        }
        report("порядок блоков", bad, total: rows.count)

        var offBad: [String] = []
        let offs = f["order"]["off"].array!
        for r in offs {
            let g = Genre(rawValue: r["genre"].string!)
            let off: [GenreGroup: [CardBlock]] = [GenreProfile(g).group: blocks(r["off"])]
            let got = CardBlock.allCases.filter { CardOrder.isOff($0, genre: g, off: off) }.map(\.rawValue)
            if got != r["blocks"].strings! { offBad.append("\(r["genre"]) \(r["off"]): \(got)") }
        }
        report("выключенные блоки", offBad, total: offs.count)
    }

    @Test func eventPhases() {
        var bad: [String] = []
        let rows = f["phases"].array!
        for r in rows {
            let s = DomainOracle.session(r["s"])
            let now = WallTime(day: DomainOracle.civil(r["now"][0].string!), minutes: r["now"][1].int!)
            let phase = EventPhase.of(s, now: now, manualEnd: r["manual"].bool!)
            let m = s.minute(at: now)
            if phase.rawValue != r["phase"].string! || m != r["shootMin"].int {
                bad.append("\(r["s"]) now=\(r["now"]) manual=\(r["manual"]): \(phase) \(String(describing: m)) вместо \(r["phase"]) \(r["shootMin"])")
            }
        }
        report("фаза события", bad, total: rows.count)
    }

    @Test func dayParts() {
        var bad: [String] = []
        let rows = f["daySpans"].array!
        for r in rows {
            let s = DomainOracle.session(r["s"])
            let got = s.part(on: DomainOracle.civil(r["day"].string!))
            let want = r["part"]
            let same = got == nil ? want.isNull
                : (got!.start == want[0].int && got!.end == want[1].int && got!.fromYesterday == want[2].bool && got!.intoTomorrow == want[3].bool)
            if !same { bad.append("\(r["s"]) \(r["day"]): \(String(describing: got)) вместо \(want)") }
        }
        report("съёмка в своих сутках", bad, total: rows.count)
    }

    @Test func nestSpans() {
        var bad: [String] = []
        let rows = f["nests"].array!
        for r in rows {
            let got = Nest.span(of: DomainOracle.session(r["s"]))
            let want = r["span"]
            let same = got == nil ? want.isNull : (got!.start == want[0].int && got!.end == want[1].int)
            if !same { bad.append("\(r["s"]): \(String(describing: got)) вместо \(want)") }
        }
        report("матрёшка", bad, total: rows.count)
    }

    @Test func stops() {
        var bad: [String] = []
        let rows = f["stops"].array!
        for r in rows {
            let s = DomainOracle.session(r["s"])
            let timed = s.timedRoute.map { p in s.route.firstIndex(of: p)! }
            if timed != r["routeOf"].array!.map({ $0.int! }) { bad.append("\(s.id) routeOf: \(timed)") }
            let st = Stops.all(of: s, spots: DomainOracle.spots, studios: DomainOracle.studios)
            let want = r["stops"].array!
            let same = st.count == want.count && zip(st, want).allSatisfy { p, w in
                p.name == w[0].string && p.address == w[1].string && p.point.latitude == w[2].double
                    && p.point.longitude == w[3].double && p.sub == w[4].string && p.isStudio == w[5].bool
            }
            if !same { bad.append("\(s.id) stops: \(st)") }
            let at = Stops.skyPoint(of: s, spots: DomainOracle.spots, studios: DomainOracle.studios)
            if at?.latitude != r["shootAt"][0].double || at?.longitude != r["shootAt"][1].double { bad.append("\(s.id) shootAt: \(String(describing: at))") }
            if s.placeKey != r["placeKey"].string! || s.placeText != r["placeText"].string! { bad.append("\(s.id) place: «\(s.placeKey)» «\(s.placeText)»") }
        }
        report("место съёмки", bad, total: rows.count)
    }

    @Test func docKindGuess() {
        var bad: [String] = []
        let rows = f["docGuess"].array!
        for r in rows {
            let got = DocKind.guess(fileName: r["name"].string!)
            if got?.rawValue != r["kind"].string { bad.append("«\(r["name"])»: \(String(describing: got)) вместо \(r["kind"])") }
        }
        report("вид документа по имени", bad, total: rows.count)
        #expect(rows.filter { !$0["kind"].isNull }.count > 25)
    }
}
