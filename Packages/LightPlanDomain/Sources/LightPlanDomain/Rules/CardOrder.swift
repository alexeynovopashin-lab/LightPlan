import Foundation

/// Блок карточки съёмки (веб `CARD_BLOCKS`). Порядок случаев — порядок по
/// умолчанию: иерархия продумана и проверена (`docs/12`, «Порядок блоков»).
public enum CardBlock: String, CaseIterable, Sendable {
    case deal, day, clash, light, place, weather, route, refs, brief, models, docs, notes, delivery, money

    /// Имя знака в общей библиотеке.
    public var iconName: String {
        switch self {
        case .deal: "doc"
        case .day: "clock"
        case .clash: "warn"
        case .light: "sun"
        case .place: "pin"
        case .weather: "cloud"
        case .route: "route"
        case .refs: "camera"
        case .brief: "note_edit"
        case .models: "guests"
        case .docs: "doc"
        case .notes: "note"
        case .delivery: "clock"
        case .money: "purse"
        }
    }
}

/// Порядок блоков карточки: по умолчанию наш, переложенный фотографом —
/// запоминается по группе жанров, а не по отдельной съёмке.
public enum CardOrder {

    /// Порядок у заказа (веб `GROUP_ORDER.client`): сделка отвечает на главный
    /// вопрос, задание и документы важнее маршрута и референсов.
    public static let clientOrder: [CardBlock] = [
        .deal, .day, .clash, .light, .place, .weather, .brief, .docs,
        .models, .notes, .delivery, .money, .route, .refs,
    ]

    /// Что выходит вперёд у заказа после съёмки (веб `AFTER_FIRST`): съёмка
    /// прошла, а счёт и акт ещё нет.
    public static let afterFirst: [CardBlock] = [.deal, .docs, .money, .delivery]

    /// Порядок группы без правки фотографа.
    public static func base(for group: GenreGroup) -> [CardBlock] {
        group == .client ? clientOrder : CardBlock.allCases
    }

    /// Порядок с правкой фотографа (веб `orderFor`). Правку могли сохранить до
    /// появления нового блока — недостающие дописываются в конец.
    public static func order(genre: Genre?, saved: [GenreGroup: [CardBlock]]) -> [CardBlock] {
        let group = GenreProfile(genre).group
        let base = base(for: group)
        guard var out = saved[group] else { return base }
        for b in base where !out.contains(b) { out.append(b) }
        return out
    }

    /// Блоки в том порядке, в каком карточка их ставит (веб `applyOrder`). У
    /// заказа в фазе «после» бумаги и деньги выходят вперёд поверх любого
    /// порядка. Блок, записанный в правке дважды, стоит на последнем месте:
    /// веб переносит узел, а не копирует его.
    public static func shown(genre: Genre?, saved: [GenreGroup: [CardBlock]], phase: EventPhase) -> [CardBlock] {
        var list = order(genre: genre, saved: saved)
        if phase == .after && GenreProfile(genre).group == .client {
            let first = afterFirst.filter { list.contains($0) }
            list = first + list.filter { !first.contains($0) }
        }
        var out: [CardBlock] = []
        for b in list {
            out.removeAll { $0 == b }
            out.append(b)
        }
        return out
    }

    /// Выключен ли блок у группы жанра (веб `blockOff`): «показывать ли вообще» —
    /// отдельная ось от «где стоит».
    public static func isOff(_ block: CardBlock, genre: Genre?, off: [GenreGroup: [CardBlock]]) -> Bool {
        off[GenreProfile(genre).group]?.contains(block) ?? false
    }
}
