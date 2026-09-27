import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Оплата и срок сдачи в форме, лист «Ставка и пакеты» (итерация 24, шаг 3).
/// Правила счёта — в `EventForm` (`FormMoney.swift`); здесь — память жанра и
/// связи с остальными записями.
extension AppModel {

    // MARK: - Что жанр подставляет

    /// Ставка часа жанра (веб `rateOf`): своя, иначе общая запасная.
    public func genreRate(_ g: Genre) -> Decimal { snapshot.genrePrefs[g]?.rate ?? snapshot.defaultRate }

    /// Доля предоплаты жанра в процентах (веб `prepayShare`); 0 — доли нет.
    public func genrePrepayShare(_ g: Genre) -> Int { Int(snapshot.genrePrefs[g]?.prepayShare ?? 0) }

    /// Пакеты жанра в редакторе — со строками без цены.
    public func genrePacks(_ g: Genre) -> [Pack] { snapshot.packs[g] ?? [] }

    /// Пакеты, которые форма предлагает чипсами (веб `usablePacks`): с ценой.
    public func usablePacks(_ g: Genre) -> [Pack] { genrePacks(g).filter { $0.price > 0 } }

    /// Счёт формы: жанровая ставка и доля, живые записи для доли месяца.
    public func formMoney(_ f: EventForm) -> FormMoneyContext {
        FormMoneyContext(genreRate: genreRate(f.genre), prepayShare: Double(genrePrepayShare(f.genre)),
                         sessions: snapshot.sessions)
    }

    private func remember(_ g: Genre, _ change: (inout GenrePrefs) -> Void) {
        var p = snapshot.genrePrefs[g] ?? GenrePrefs()
        change(&p)
        snapshot.genrePrefs[g] = p
        persist()
    }

    // MARK: - Оплата в форме

    /// Способ чипсом; «В месяц» жанру не запоминается — у новой съёмки без повтора его нет.
    public func setFormPay(_ k: PayKind) {
        guard let g = form?.genre else { return }
        editForm { $0.choosePay(k, genreRate: genreRate(g)) }
        if k != .monthly { remember(g) { $0.pay = k } }
    }

    public func chooseFormPack(_ p: Pack) { editForm { $0.choose(p) } }
    public func toggleFormPay() { editForm { $0.payOpen.toggle() } }
    public func setFormCurrency(_ c: Currency) { editForm { $0.currency = c } }

    /// Поле ставки: у помесячной карточки пустое поле — доля месяца, а «0» — бесплатная съёмка.
    public func setFormRate(_ v: Decimal?) {
        editForm { f in f.rate = v == nil && f.pay == .monthly ? nil : (v ?? 0) }
    }
    public func setFormExpense(_ v: Decimal?) { editForm { $0.expense = v ?? 0 } }
    public func setFormPrepay(_ v: Decimal?) { editForm { $0.typePrepay(v ?? 0) } }
    public func setFormUnits(_ n: Int) { editForm { $0.units = max(1, min(EventForm.unitsMax, n)) } }
    public func stepFormUnits(_ d: Int) { editForm { $0.stepUnits(d) } }
    public func setFormMonth(total v: Decimal?) { editForm { $0.repeatMonthly = v ?? 0 } }
    public func setFormMonth(perShoot v: Decimal?) { editForm { $0.setMonth(perShoot: v ?? 0) } }
    public func setFormMonth(perHour v: Decimal?) { editForm { $0.setMonth(perHour: v ?? 0) } }
    /// «За месяц» у карточки группы; пустое поле — сумма не меняется.
    public func setFormMonthSum(_ v: Decimal?) { editForm { $0.monthSumTyped = v } }

    /// Смена суммы месяца — всей группе с месяца этой карточки, и карточкам в
    /// корзине тоже: возвращённая понесёт её сама (веб `#fSave`, L31830–31838).
    func addMonthSum(_ e: MonthSum, group g: String) {
        for i in snapshot.sessions.indices where snapshot.sessions[i].repeatInfo?.group == g {
            snapshot.sessions[i].repeatInfo!.sums.append(e)
        }
        for i in snapshot.trashed.indices where snapshot.trashed[i].record.repeatInfo?.group == g {
            snapshot.trashed[i].record.repeatInfo!.sums.append(e)
        }
    }

    /// Подсказка под новой суммой месяца (веб `repSumHint`): с какого дня,
    /// вместо какой, и чего она касается помимо доли — прошедших месяцев и
    /// предоплат, внесённых по прежней доле. «Сегодня» — по часам телефона
    /// (у веба — по месту карточки; разница в сутки на краю месяца).
    public func formMonthSumHint(_ f: EventForm) -> String? {
        let ctx = formMoney(f)
        guard let e = f.monthSumEdit(ctx), let rep = f.monthGroup, let start = rep.start else { return nil }
        let dt = DateText(language: language)
        let year = today.year
        func dm(_ d: CivilDate) -> String {
            let at = carrier(d)
            return d.year == year ? dt.dMon(at) : dt.dMonYear(at)
        }
        let cur = f.currency.rawValue
        let nt = NumberText(language: language)
        func money(_ v: Decimal) -> String { nt.money(NSDecimalNumber(decimal: v).doubleValue, cur) }
        var text = lexicon.t("rep.sumFrom", ["d": dm(Money.periodStart(start: start, month: e.month)),
                                             "sum": money(e.sum), "was": money(f.monthSumWas(ctx))])
        if Money.periodStart(start: start, month: e.month + 1) <= today { text += " " + lexicon.t("rep.sumPast") }
        var paid: [(d: CivilDate, pre: Decimal, sum: Decimal)] = []
        for x in snapshot.sessions {
            let me = x.id == f.id
            let p = me ? f.probe : x
            let pre = me ? f.prepay(ctx) : x.prepay
            guard pre != 0, p.repeatInfo?.group == rep.group, p.pay == .monthly, p.rate == nil,
                  Money.monthIndex(start: start, day: p.day) >= e.month else { continue }
            let now = Money.monthShare(of: p, among: snapshot.sessions, edit: e)
            if EventForm.roundMoney(now) != EventForm.roundMoney(Money.monthShare(of: p, among: snapshot.sessions)) {
                paid.append((p.day, pre, now))
            }
        }
        if !paid.isEmpty {
            paid.sort { $0.d < $1.d }
            var list = paid.prefix(3).map {
                lexicon.t("rep.sumPaidOf", ["d": dm($0.d), "pre": money($0.pre), "sum": money($0.sum)])
            }.joined(separator: "; ")
            if paid.count > 3 { list += " " + lexicon.t("rep.more", ["n": String(paid.count - 3)]) }
            text += " " + lexicon.t("rep.sumPaid", ["list": list])
        }
        return text
    }

    private func carrier(_ d: CivilDate) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (d.year, d.month, d.day, 12)
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }

    // MARK: - Срок сдачи

    /// Деление шкалы срока; выбранное запоминается жанру (веб `rememberGenre("delv")`).
    public func setFormDeadline(stop i: Int) {
        guard let f = form, EventForm.deadlineStops.indices.contains(i) else { return }
        let choice = EventForm.deadlineStops[i]
        guard choice != f.deadline else { return }
        editForm { $0.deadline = choice }
        remember(f.genre) { $0.deadline = choice }
    }

    public func setFormDelivered(_ on: Bool) { editForm { $0.setDelivered(on, now: now()) } }

    /// День, к которому сдать, у формы (веб `deadlineDate(probe)`); `nil` — срок не отслеживается.
    public func formDeadline(_ f: EventForm) -> CivilDate? {
        var s = f.probe
        s.genre = f.genre
        s.deadline = f.deadline
        return Delivery.deadline(for: s, setting: snapshot.delivery, prefs: snapshot.genrePrefs)
    }

    // MARK: - Лист «Ставка и пакеты»

    /// Ставка часа жанра; пустое поле — «как общая» (веб `gRate`).
    public func setGenreRate(_ g: Genre, _ v: Decimal?) { remember(g) { $0.rate = v } }

    /// Доля предоплаты жанра; «Нет» — `nil` (веб `rememberGenre("pre", pct || null)`).
    public func setGenrePrepayShare(_ g: Genre, _ pct: Int) {
        remember(g) { $0.prepayShare = pct > 0 ? Double(pct) : nil }
        editForm { $0.prepayShareChanged(to: pct) }
    }

    public func setGenrePacks(_ g: Genre, _ list: [Pack]) {
        snapshot.packs[g] = Array(list.prefix(Pack.limit))
        persist()
    }
}
