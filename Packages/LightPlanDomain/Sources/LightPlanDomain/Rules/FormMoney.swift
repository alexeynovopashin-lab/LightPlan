import Foundation
import LightPlanCore

/// Пакет жанра (веб `genrePacks[жанр][]`: `n`, `p`, `h`): готовая сумма со
/// своим именем и, если задано, своими часами.
public struct Pack: Sendable, Hashable {
    /// `n` — имя: «Загс и прогулка».
    public var name: String
    /// `p` — цена; пакет с нулём живёт только в редакторе.
    public var price: Decimal
    /// `h` — часы; есть — выбор пакета двигает конец съёмки.
    public var hours: Double?

    public init(name: String, price: Decimal, hours: Double? = nil) {
        self.name = name
        self.price = price
        self.hours = hours
    }

    /// Больше шести пакетов у жанра не заводится (веб `packAdd`).
    public static let limit = 6
}

/// Что форме нужно извне, чтобы посчитать деньги: жанровая ставка и доля
/// предоплаты (веб `rateOf`, `prepayShare`) и живые записи — доля месяца
/// помесячной карточки делится между соседями по группе.
public struct FormMoneyContext: Sendable {
    public var genreRate: Decimal
    /// Доля предоплаты жанра в процентах; 0 — доли нет.
    public var prepayShare: Double
    public var sessions: [Session]

    public init(genreRate: Decimal = 0, prepayShare: Double = 0, sessions: [Session] = []) {
        self.genreRate = genreRate
        self.prepayShare = prepayShare
        self.sessions = sessions
    }
}

/// Оплата и срок сдачи в форме (веб `renderPay`, `renderDelv`, L24097–24245,
/// L20380–20403). Здесь правила; вид блока — в `LightPlanUI`.
extension EventForm {

    /// Доли предоплаты в листе «Ставка и пакеты» (веб `PRE_SHARES`).
    public static let prepayShares = [0, 10, 20, 30, 50]
    /// Деления шкалы срока сдачи (веб `DELV_OPTS`): крайние — состояния, середина — дни.
    public static let deadlineStops: [DeadlineChoice] = [.auto, .days(3), .days(7), .days(14), .days(30), .days(90), .none]
    /// Предел количества у поштучной оплаты (веб `UNITS_MAX`).
    public static let unitsMax = 9999

    // MARK: - Способ

    /// Способы, которые предлагает форма (веб `keys` в `renderPay`): жанровые, и
    /// «В месяц» — пока повтор заводится и у карточки помесячной группы.
    public var payKinds: [PayKind] {
        var keys = GenreProfile(genre).spec.pay
        if repeatOn || base?.repeatInfo?.start != nil { keys.append(.monthly) }
        return keys
    }

    /// Способ не из этого жанра — берётся первый; помесячная сумма ставкой
    /// другого способа не становится (веб начало `renderPay`).
    public mutating func fitPay(genreRate: Decimal) {
        let keys = payKinds
        guard !keys.contains(pay), let first = keys.first else { return }
        if pay == .monthly { rate = first.mechanic == .hourly ? genreRate : 0 }
        pay = first
    }

    /// Выбор способа чипсом. Сменилась механика — прежнее число становится
    /// ложью (сорок тысяч за пакет оказывались ставкой в час), и его стирают;
    /// вход в пакеты и выход из них — тоже: совпавшая сумма подсветила бы
    /// пакет, которого никто не выбирал.
    public mutating func choosePay(_ k: PayKind, genreRate: Decimal) {
        guard k != pay, payKinds.contains(k) else { return }
        let was = pay
        pay = k
        if k.mechanic != was.mechanic || k == .pack || was == .pack {
            rate = k.mechanic == .hourly ? genreRate : k.mechanic == .monthly ? nil : 0
        }
    }

    /// Пакет подставляет цену, а если в нём заданы часы — и длительность.
    public mutating func choose(_ p: Pack) {
        rate = p.price
        if let h = p.hours, h > 0 { duration = Int((h * 60).rounded()) }
    }

    /// Выбранный пакет — тот, чья цена стоит в поле (веб `p.p === fRate`).
    public func isChosen(_ p: Pack) -> Bool { pay == .pack && rate == p.price }

    /// Количество кнопкой: от 1 до 9999.
    public mutating func stepUnits(_ d: Int) {
        units = max(1, min(Self.unitsMax, units + d))
    }

    // MARK: - Помесячная оплата

    /// Заводимая помесячная группа: одна сумма тремя полями (веб `compose`).
    public var composesMonth: Bool { pay.mechanic == .monthly && repeatOn }

    /// Сведения помесячной группы у правимой карточки (веб `sumRow`): строка «За месяц».
    public var monthGroup: Repeat? {
        guard pay.mechanic == .monthly, !composesMonth, let r = base?.repeatInfo, r.start != nil else { return nil }
        return r
    }

    /// Сколько карточек заводимой группы ложится в первый месяц (веб `repFirstCount`).
    public var firstMonthCount: Int {
        guard let rule = repeatRule else { return 1 }
        return Repeats.dates(from: day, rule: rule, count: repeatCount)
            .filter { Money.monthIndex(start: day, day: $0) == 0 }.count
    }

    /// Сумма за съёмку у заводимой группы.
    public var perShoot: Decimal {
        let n = firstMonthCount
        return n > 0 ? repeatMonthly / Decimal(n) : 0
    }

    /// Поле «за съёмку» или «за час» переписывает сумму месяца (веб `fMonShoot`, `fMonHour`).
    public mutating func setMonth(perShoot v: Decimal) { repeatMonthly = v * Decimal(firstMonthCount) }
    public mutating func setMonth(perHour v: Decimal) {
        repeatMonthly = v * Decimal(duration) / 60 * Decimal(firstMonthCount)
    }

    /// Номер месяца группы у правимой карточки.
    public var monthIndex: Int? {
        guard let r = monthGroup, let start = r.start else { return nil }
        return Money.monthIndex(start: start, day: day)
    }

    /// Сумма месяца, какой она записана (веб `sumWas`).
    public func monthSumWas(_ ctx: FormMoneyContext) -> Decimal {
        guard let r = monthGroup, let k = monthIndex else { return 0 }
        return Money.monthSum(r, month: k, among: ctx.sessions)
    }

    /// Набранная смена суммы месяца, если она отличается от записанной (веб `sumEdit`).
    public func monthSumEdit(_ ctx: FormMoneyContext) -> MonthSum? {
        guard let typed = monthSumTyped, let k = monthIndex, typed != monthSumWas(ctx) else { return nil }
        return MonthSum(month: k, sum: typed, at: .max)
    }

    // MARK: - Итог

    /// Запись-заготовка для счёта (веб `payProbe`): те же поля, что уйдут в запись.
    public var probe: Session {
        var s = base ?? Session(id: id, kind: mode == .meet ? .meet : .shoot, day: day, start: start)
        s.kind = mode == .meet ? .meet : (base?.kind ?? .shoot)
        s.day = day
        s.duration = duration
        s.pay = pay
        s.rate = rate
        s.units = Decimal(units)
        s.expense = expense
        return s
    }

    /// Доход (веб `inc`): у заводимой группы — сумма за съёмку, у карточки с
    /// набранной суммой месяца — её новая доля, иначе обычный счёт записи.
    public func income(_ ctx: FormMoneyContext) -> Decimal {
        if composesMonth { return perShoot }
        if rate == nil, let e = monthSumEdit(ctx) { return Money.monthShare(of: probe, among: ctx.sessions, edit: e) }
        return Money.income(of: probe, among: ctx.sessions)
    }

    public func net(_ ctx: FormMoneyContext) -> Decimal { income(ctx) - expense }

    /// Подсказка в пустом поле ставки у помесячной карточки: её доля месяца.
    public func ratePlaceholder(_ ctx: FormMoneyContext) -> Decimal {
        guard pay.mechanic == .monthly, !composesMonth else { return 0 }
        return Self.roundMoney(Money.monthShare(of: probe, among: ctx.sessions, edit: monthSumEdit(ctx)))
    }

    /// Предоплата, которая уйдёт в запись. Доля жанра держит поле, пока в него
    /// не вписали своё; жанр без строки предоплаты — ноль (веб `applyGenreShape`).
    public func prepay(_ ctx: FormMoneyContext) -> Decimal {
        guard shows(.prepay) else { return 0 }
        if prepayAuto && ctx.prepayShare > 0 {
            return Self.roundMoney(income(ctx) * Decimal(ctx.prepayShare) / 100)
        }
        return prepayTyped
    }

    /// Остаток к дню съёмки: доход минус предоплата, не ниже нуля.
    public func rest(_ ctx: FormMoneyContext) -> Decimal { max(0, income(ctx) - prepay(ctx)) }

    /// Число сводки свёрнутой оплаты (веб `summ`): у помесячной — сумма месяца,
    /// а не доля, иначе «В месяц · 12 500» читалось бы как месяц за 12 500.
    public func summaryAmount(_ ctx: FormMoneyContext) -> Decimal {
        guard pay.mechanic == .monthly else { return net(ctx) }
        if composesMonth { return repeatMonthly }
        if monthGroup != nil { return monthSumEdit(ctx)?.sum ?? monthSumWas(ctx) }
        return base?.repeatInfo?.monthly ?? 0
    }

    /// Предоплату вписали руками: доля жанра её больше не пересчитывает.
    public mutating func typePrepay(_ v: Decimal) {
        prepayTyped = v
        prepayAuto = false
    }

    /// Доля жанра сменилась в листе: «Нет» убирает и то, что доля успела
    /// поставить; своя доля снова держит поле (веб `renderPrepayChips`).
    public mutating func prepayShareChanged(to pct: Int) {
        if pct == 0 && prepayAuto { prepayTyped = 0 }
        if pct > 0 { prepayAuto = true }
    }

    /// `Math.round` веба: половина — вверх.
    public static func roundMoney(_ v: Decimal) -> Decimal {
        var x = v + Decimal(string: "0.5")!, r = Decimal()
        NSDecimalRound(&r, &x, 0, .down)
        return r
    }

    // MARK: - Срок сдачи

    /// Деление шкалы срока: своё число дней вне шкалы стоит на первом, как у веба.
    public var deadlineStop: Int {
        Self.deadlineStops.firstIndex(of: deadline) ?? 0
    }

    /// «Материал сдан»: момент ставится один раз, в минуту отметки; сняли и
    /// поставили заново — время новое.
    public mutating func setDelivered(_ on: Bool, now: Date) {
        delivered = on
        deliveredAt = on ? now : nil
    }

    // MARK: - Открытие и запись

    /// Пресет оплаты и срока у новой записи (веб `applyGenrePreset`, L26716–26735).
    mutating func presetMoney(prefs: GenrePrefs?, genreRate: Decimal) {
        let sp = GenreProfile(genre).spec
        deadline = sp.delivery ? (prefs?.deadline ?? .auto) : .none
        if !sp.delivery { delivered = false; deliveredAt = nil }
        if let p = prefs?.pay, sp.pay.contains(p) { pay = p } else { pay = sp.pay.first ?? .flat }
        rate = pay.mechanic == .hourly ? genreRate : 0
        units = 1
        expense = 0
        prepayAuto = true
        if !shows(.prepay) { prepayTyped = 0 }
        // Ставка настроена и доход считается сам — блок свёрнут; иначе его раскрывают.
        payOpen = !(Money.income(of: probe, among: []) > 0)
    }

    /// Смена жанра у сохранённой записи (веб `applyGenreShape` + начало `renderPay`):
    /// нечего сдавать — срока нет; способ не из жанра — первый жанровый.
    mutating func fitShape(genreRate: Decimal) {
        if !GenreProfile(genre).spec.delivery { deadline = .none; delivered = false; deliveredAt = nil }
        if !shows(.prepay) { prepayTyped = 0 }
        fitPay(genreRate: genreRate)
    }

    /// Деньги и сдача сохранённой записи (веб `fillFormFrom`): предоплата уже
    /// названа числом — доля жанра ей не указ; блок оплаты свёрнут.
    mutating func loadMoney(_ s: Session, home: Currency) {
        let kinds = GenreProfile(s.genre).spec.pay
        if let p = s.pay, kinds.contains(p) || p == .monthly { pay = p } else { pay = kinds.first ?? .flat }
        rate = s.pay == .monthly && s.rate == nil ? nil : (s.rate ?? 0)
        units = s.units > 0 ? NSDecimalNumber(decimal: s.units).intValue : 1
        expense = s.expense
        currency = s.currency ?? home
        prepayTyped = s.prepay
        prepayAuto = false
        deadline = s.deadline
        delivered = s.delivered
        deliveredAt = s.deliveredAt
        payOpen = false
    }

    /// Деньги и сдача в запись (веб `#fSave`: `pay`, `rate`, `units`, `expense`,
    /// `prepay`, `currency`, `deadlineChoice`, `delivered`, `deliveredAt`).
    /// Предоплату, зависящую от соседей по группе, пишет `session(…, money:)`.
    func writeMoney(_ s: inout Session, _ ctx: FormMoneyContext?) {
        s.pay = pay
        s.rate = rate
        s.units = Decimal(units)
        s.expense = expense
        s.prepay = ctx.map { prepay($0) } ?? (shows(.prepay) ? prepayTyped : 0)
        s.currency = currency
        s.deadline = deadline
        s.delivered = delivered
        s.deliveredAt = delivered ? deliveredAt : nil
    }
}

extension Pack: Codable {
    enum CodingKeys: String, CodingKey { case n, p, h }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: (try? c.decodeIfPresent(String.self, forKey: .n)) ?? "",
                  price: (try? c.decodeIfPresent(Decimal.self, forKey: .p)) ?? 0,
                  hours: try? c.decodeIfPresent(Double.self, forKey: .h))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .n)
        try c.encode(price, forKey: .p)
        if let hours { try c.encode(hours, forKey: .h) } else { try c.encodeNil(forKey: .h) }
    }

    /// Пакеты из снимка (веб `normPacks`): старый список числами — «Пакет N»
    /// без имени (имя подставит экран), пустые и нулевые отбрасываются, не
    /// больше шести. Старый общий список (массив вместо словаря) — свадебный.
    public static func genrePacks(from raw: JSONValue?) -> [Genre: [Pack]] {
        func norm(_ v: JSONValue) -> [Pack] {
            guard case .array(let list) = v else { return [] }
            let packs: [Pack] = list.compactMap { item in
                switch item {
                case .number(let n): return Pack(name: "", price: Decimal(n))
                case .object(let o):
                    var price: Decimal = 0, name = "", hours: Double?
                    if case .number(let p)? = o["p"] { price = Decimal(string: String(p)) ?? Decimal(p) }
                    if case .string(let s)? = o["n"] { name = s }
                    if case .number(let h)? = o["h"] { hours = h }
                    return Pack(name: name, price: price, hours: hours)
                default: return nil
                }
            }
            return Array(packs.filter { $0.price > 0 }.prefix(limit))
        }
        switch raw {
        case .array?: return [.wedding: norm(raw!)]
        case .object(let o)?:
            var out: [Genre: [Pack]] = [:]
            for (k, v) in o { if let g = Genre(rawValue: k) { out[g] = norm(v) } }
            return out
        default: return [:]
        }
    }
}
