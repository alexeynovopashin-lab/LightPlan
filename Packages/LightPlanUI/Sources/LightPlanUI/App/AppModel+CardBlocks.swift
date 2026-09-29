import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

// MARK: - Блоки карточки и их порядок (итерация 26, шаг 2)

extension AppModel {

    /// Практика сделки из настроек (веб `practice`).
    var dealPractice: LightPlanDomain.Practice { LightPlanDomain.Practice(rawValue: settings.practice.rawValue) ?? .ru }

    private func cardGroup(_ s: Session) -> GenreGroup { GenreProfile(s.genre).group }

    /// Есть ли у блока что показать.
    func cardBlockHasData(_ b: CardBlock, _ s: Session, phase: EventPhase) -> Bool {
        if let v = CardPresence.byRecord(b, s, phase: phase, practice: dealPractice, among: snapshot.sessions) { return v }
        switch b {
        case .clash: return cardClash(s, phase: phase) != nil
        case .light: return !cardSays(s, phase: phase).isEmpty
        case .weather: return cardWeather(s, phase: phase) != nil
        case .place: return !cardPanes(s, phase: phase).isEmpty
        case .refs: return phase != .after && !cardRefs(s).isEmpty
        default: return false
        }
    }

    /// Блоки карточки сверху вниз (веб `applyOrder` + `applyOff`): порядок
    /// группы жанров, у заказа после съёмки бумаги и деньги впереди; блоков
    /// без данных и выключенных нет.
    public func cardBlocks(_ s: Session, phase: EventPhase) -> [CardBlock] {
        CardOrder.shown(genre: s.genre, saved: snapshot.cardOrder, phase: phase).filter {
            cardBlockHasData($0, s, phase: phase) && !CardOrder.isOff($0, genre: s.genre, off: snapshot.cardOff)
        }
    }

    /// Строки перестановки: блоки с данными, выключенные тоже (чтобы было чем
    /// вернуть), в том порядке, в каком их ставит карточка — у заказа после
    /// съёмки сделка, документы, гонорар и сдача впереди (Алексей 29.09: как в
    /// бете). Перетащенный блок в порядок группы встаёт сам, вынос не пишется.
    public func cardOrderRows(_ s: Session, phase: EventPhase) -> [CardBlock] {
        CardOrder.shown(genre: s.genre, saved: snapshot.cardOrder, phase: phase).filter { cardBlockHasData($0, s, phase: phase) }
    }

    /// Блок перетащили на место `j` в списке перестановки. Хранится у группы.
    public func moveCardBlock(_ b: CardBlock, to j: Int, for s: Session) {
        let rows = cardOrderRows(s, phase: phase(of: s))
        let full = CardOrder.full(genre: s.genre, saved: snapshot.cardOrder)
        let out = CardOrder.move(b, to: j, listed: rows, order: full)
        guard out != full else { return }
        snapshot.cardOrder[cardGroup(s)] = out
        persist()
    }

    public func isCardBlockOff(_ b: CardBlock, for s: Session) -> Bool {
        CardOrder.isOff(b, genre: s.genre, off: snapshot.cardOff)
    }

    /// Тумблер строки перестановки (веб `cardOff`): сохраняется сразу.
    public func setCardBlock(_ b: CardBlock, shown: Bool, for s: Session) {
        let g = cardGroup(s)
        var off = snapshot.cardOff[g] ?? []
        off.removeAll { $0 == b }
        if !shown { off.append(b) }
        snapshot.cardOff[g] = off.isEmpty ? nil : off
        persist()
    }

    /// «По умолчанию»: у группы стираются порядок и выключенные, у записи —
    /// выключенный опросник (веб так же).
    public func resetCardOrder(for s: Session) {
        let g = cardGroup(s)
        snapshot.cardOrder[g] = nil
        snapshot.cardOff[g] = nil
        if let i = snapshot.sessions.firstIndex(where: { $0.id == s.id }), snapshot.sessions[i].questOff {
            snapshot.sessions[i].questOff = false
            snapshot.sessions[i].modifiedAt = nowMs
        }
        persist()
    }

    /// «Ползунки» и «Готово»: вход и выход из режима перестановки.
    public func toggleCardTuning() { cardTuning.toggle() }

    public func isCardFoldOpen(_ b: CardBlock) -> Bool { cardFolds.contains(b) }

    public func toggleCardFold(_ b: CardBlock) {
        if cardFolds.contains(b) { cardFolds.remove(b) } else { cardFolds.insert(b) }
    }
}
