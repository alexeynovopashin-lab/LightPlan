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
        return lastWins(list)
    }

    /// Порядок группы целиком, без дублей и без выноса «после» — то, что
    /// хранится и что правит перестановка.
    public static func full(genre: Genre?, saved: [GenreGroup: [CardBlock]]) -> [CardBlock] {
        lastWins(order(genre: genre, saved: saved))
    }

    /// Дубль стоит на последнем месте: веб переносит узел, а не копирует его.
    private static func lastWins(_ list: [CardBlock]) -> [CardBlock] {
        var out: [CardBlock] = []
        for b in list {
            out.removeAll { $0 == b }
            out.append(b)
        }
        return out
    }

    /// Места списка перестановки, куда блок можно опустить. У заказа после съёмки
    /// первые строки (`afterFirst`) вынесены вперёд поверх любого порядка: выше них
    /// ничего не встанет, а сами они стоят на месте (пятая плитка дня «не поднималась»,
    /// а на четвёртое место уезжала в конец — 29.09, слова Алексея с телефона).
    public static func slots(of b: CardBlock, listed: [CardBlock], genre: Genre?, phase: EventPhase) -> ClosedRange<Int> {
        guard let i = listed.firstIndex(of: b) else { return 0...max(0, listed.count - 1) }
        guard phase == .after, GenreProfile(genre).group == .client else { return 0...(listed.count - 1) }
        let pinned = listed.prefix { afterFirst.contains($0) }.count
        return afterFirst.contains(b) ? i...i : pinned...(listed.count - 1)
    }

    /// Перенос одного блока перетаскиванием (шаг 2 итерации 26). `listed` —
    /// строки перестановки до переноса, `j` — место, куда блок встал, `full` —
    /// порядок группы. Двигается только перенесённый блок: вниз он встаёт сразу
    /// за строкой, мимо которой прошёл последней, вверх — сразу перед ней.
    /// Блоки, которых в этой съёмке нет, остаются где были — у веба они
    /// уезжали в конец (справка, ошибка 2).
    public static func move(_ b: CardBlock, to j: Int, listed: [CardBlock], order full: [CardBlock]) -> [CardBlock] {
        guard let i = listed.firstIndex(of: b), i != j, listed.indices.contains(j) else { return full }
        let passed = listed[j]
        var out = full.filter { $0 != b }
        guard let k = out.firstIndex(of: passed) else { return full }
        out.insert(b, at: j > i ? k + 1 : k)
        return out
    }

    /// Выключен ли блок у группы жанра (веб `blockOff`): «показывать ли вообще» —
    /// отдельная ось от «где стоит».
    public static func isOff(_ block: CardBlock, genre: Genre?, off: [GenreGroup: [CardBlock]]) -> Bool {
        off[GenreProfile(genre).group]?.contains(block) ?? false
    }
}

/// Есть ли у записи что показать в блоке (веб: блок без данных не существует
/// ни в карточке, ни в списке перестановки; `docs/12`, инвариант 15).
public enum CardPresence {
    /// По самой записи. `nil` — решает прибор, а не запись: наложение, свет,
    /// погода, место (шаги 3–4 итерации 26).
    public static func byRecord(_ b: CardBlock, _ s: Session, phase: EventPhase,
                                practice: Practice, among sessions: [Session]) -> Bool? {
        switch b {
        case .clash, .light, .weather, .place: nil
        case .day: true
        case .deal: DealChain.isShown(genre: s.genre, practice: practice)
        case .route: phase != .after && s.kind.isWork && s.route.contains { $0.start != nil && !$0.name.isEmpty }
        // Подборок кадров в нативе нет — 27/28.
        case .refs: false
        case .brief: !s.brief.isEmpty
        case .models: s.models.split(separator: "\n").contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .docs: !s.docs.isEmpty
        case .notes: !s.notes.isEmpty
        case .delivery: s.kind.isWork && GenreProfile(s.genre).spec.delivery
        case .money: Money.income(of: s, among: sessions) > 0 || s.expense > 0
        }
    }
}
