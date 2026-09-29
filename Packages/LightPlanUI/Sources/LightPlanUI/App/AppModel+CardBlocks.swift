import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

// MARK: - Блоки карточки и их порядок (итерация 26, шаг 2)

extension AppModel {

    /// Практика сделки из настроек (веб `practice`).
    var dealPractice: LightPlanDomain.Practice { LightPlanDomain.Practice(rawValue: settings.practice.rawValue) ?? .ru }

    private func cardGroup(_ s: Session) -> GenreGroup { GenreProfile(s.genre).group }

    /// Есть ли у блока что показать. Свет, погода и место — шаги 3–4: до них
    /// блоков нет.
    func cardBlockHasData(_ b: CardBlock, _ s: Session, phase: EventPhase) -> Bool {
        if let v = CardPresence.byRecord(b, s, phase: phase, practice: dealPractice, among: snapshot.sessions) { return v }
        switch b {
        case .clash: return cardClash(s, phase: phase) != nil
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
    /// вернуть), в порядке группы — без выноса «после»: правится порядок
    /// группы, он общий для всех фаз.
    public func cardOrderRows(_ s: Session, phase: EventPhase) -> [CardBlock] {
        CardOrder.full(genre: s.genre, saved: snapshot.cardOrder).filter { cardBlockHasData($0, s, phase: phase) }
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

    public func isCardFoldOpen(_ b: CardBlock) -> Bool { cardFolds.contains(b) }

    public func toggleCardFold(_ b: CardBlock) {
        if cardFolds.contains(b) { cardFolds.remove(b) } else { cardFolds.insert(b) }
    }
}
