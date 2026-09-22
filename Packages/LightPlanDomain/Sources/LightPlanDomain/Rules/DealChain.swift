import Foundation

/// Практика ведения дел (веб `PRACTICE`) — третья ось рядом с языком и
/// валютой: договор, предоплата и набор бумаг оформляются по территории права,
/// а не по языку.
public enum Practice: String, CaseIterable, Sendable {
    /// Россия и СНГ: пять звеньев кончаются актом; у частной съёмки сделки нет.
    case ru
    /// США: акта нет, есть релиз модели, платят в два приёма; договор нужен и паре.
    case us
    /// Британия: предоплата возвратная (депозит), кончается передачей материала.
    case uk
    /// Континентальная Европа: счёт с НДС и протокол приёмки.
    case eu

    /// Звенья сделки в порядке работы.
    public var chain: [DealStep] {
        switch self {
        case .ru: [.brief, .contract, .invoice, .pay, .act]
        case .us: [.brief, .contract, .retainer, .balance, .release]
        case .uk: [.brief, .contract, .deposit, .balance, .delivery]
        case .eu: [.brief, .contract, .invoice, .pay, .acceptance]
        }
    }

    /// Виды документов, которые предлагаются человеку.
    public var docKinds: [DocKind] {
        switch self {
        case .ru: [.contract, .invoice, .receipt, .act, .brief]
        case .us, .uk: [.contract, .invoice, .receipt, .release, .brief]
        case .eu: [.contract, .invoice, .receipt, .acceptance, .brief]
        }
    }

    /// Нужна ли цепочка и частной съёмке, а не только заказчику.
    public var dealForAll: Bool { self != .ru }
}

/// Звено сделки (веб `dealChain`, ключи `DONE`).
public enum DealStep: String, CaseIterable, Sendable {
    case brief, contract, invoice, pay, act, retainer, deposit, balance, release, delivery, acceptance
}

/// Звено у конкретной записи: закрыто или его ждут.
public struct DealLink: Hashable, Sendable {
    public let step: DealStep
    public let done: Bool
    /// «Внесена часть» — только у одноходовой оплаты (`pay`); у остальных `nil`.
    public let partlyPaid: Bool?
}

/// Состояние сделки: звено считается из того, что в записи уже есть, новых
/// полей под это не заводили (`docs/11_EVENT_CARD.md`).
public enum DealChain {

    /// Звенья записи по практике (веб `dealChain`).
    public static func links(for s: Session, practice: Practice, among sessions: [Session]) -> [DealLink] {
        func has(_ kind: DocKind) -> Bool { s.docs.contains { $0.kind == kind } }
        let income = Money.income(of: s, among: sessions)
        let pre = s.prepay
        /// Оплата закрыта, когда получено всё; нет суммы — звено ни закрыто, ни просрочено.
        let paid = income > 0 && pre >= income
        return practice.chain.map { step in
            let done: Bool
            switch step {
            case .brief: done = !s.brief.isEmpty || has(.brief)
            case .contract: done = has(.contract)
            case .invoice: done = has(.invoice)
            case .pay, .balance: done = paid
            case .act: done = has(.act)
            case .retainer, .deposit: done = pre > 0
            case .release: done = has(.release)
            case .delivery: done = s.delivered
            case .acceptance: done = has(.acceptance)
            }
            return DealLink(step: step, done: done, partlyPaid: step == .pay ? (!done && pre > 0) : nil)
        }
    }

    /// Показывается ли блок сделки (веб `renderDeal`): у заказчика всегда, у
    /// частной съёмки — если так велит практика.
    public static func isShown(genre: Genre?, practice: Practice) -> Bool {
        GenreProfile(genre).groupSpec.order || practice.dealForAll
    }
}
