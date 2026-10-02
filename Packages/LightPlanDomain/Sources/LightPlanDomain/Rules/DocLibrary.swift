import Foundation
import LightPlanCore

/// Бумаги и их переходы (итерация 28д, справка `docs_reference.md` § 2.2): создать, перенести
/// между «Мои», съёмкой и организацией, удалить в корзину документов, вернуть. Чистые правки над
/// тем, что снимок знает о бумагах; сам снимок (`Snapshot`) лежит выше, в Data, и берёт отсюда
/// `docLibrary`. Знак бумаги — `Attachment.id`, а не номер в массиве.
public struct DocLibrary: Sendable, Hashable {
    public var sessions: [Session]
    public var orgs: [Org]
    /// «Мои» — бумага без привязки.
    public var myDocs: [Attachment]
    /// Корзина документов; корзина съёмок остаётся в снимке как есть.
    public var trashedDocs: [TrashedDoc]
    /// Съёмки в корзине съёмок: их бумага едет вместе с ними, а вернуть бумагу «к ним» нельзя.
    public var trashedSessionIds: Set<String>

    public init(sessions: [Session] = [], orgs: [Org] = [], myDocs: [Attachment] = [],
                trashedDocs: [TrashedDoc] = [], trashedSessionIds: Set<String> = []) {
        self.sessions = sessions
        self.orgs = orgs
        self.myDocs = myDocs
        self.trashedDocs = trashedDocs
        self.trashedSessionIds = trashedSessionIds
    }

    /// Чем кончился возврат.
    public enum Restored: Sendable, Hashable {
        /// Встала на своё место.
        case home
        /// Хозяина больше нет — бумага вернулась в «Мои» (плашка: «вернулась в «Мои»: <кому> больше нет»).
        case mine(lost: DocOwner)
    }

    // MARK: - Создать

    /// Новая бумага: время — «сейчас». Без привязки — в начало «Мои» (быстрое «+»); у съёмки и
    /// организации — в конец её бумаг (как `OrgBook.addLink`). Хозяина нет, а реквизиты-файл
    /// сюда не кладутся — `false`, ничего не меняется. У бумаги съёмки своей даты нет:
    /// днём служит день съёмки.
    @discardableResult
    public mutating func create(_ doc: Attachment, in owner: DocOwner = .mine, now ms: Int64) -> Bool {
        guard isLive(owner), owner.isDocShelf else { return false }
        var d = doc
        d.at = ms
        place(&d, in: owner, at: nil)
        return true
    }

    // MARK: - Перенести

    /// «Привязать…» / «Отвязать»: бумага уходит к другому хозяину, `id` тот же, `at` — «сейчас».
    /// Из съёмки уходит и день: у бумаги ставится `date` = день съёмки (иначе потеряется, к какой
    /// дате она относилась); в съёмку приходит без собственной даты. `false` — бумаги нет, она в
    /// корзине, назначение не живёт, оно то же самое, или бумага — реквизиты-файл (они остаются у
    /// организации).
    @discardableResult
    public mutating func move(_ id: String, to owner: DocOwner, now ms: Int64) -> Bool {
        guard isLive(owner), owner.isDocShelf,
              let (from, _) = locate(id), from != owner, from.isDocShelf,
              var d = take(id, from: from) else { return false }
        if case .session(let sid) = from, !owner.isSession, let day = sessions.first(where: { $0.id == sid })?.day {
            d.date = day
        }
        d.at = ms
        place(&d, in: owner, at: nil)
        return true
    }

    // MARK: - Корзина документов

    /// «Удалить»: бумага уходит в начало корзины с хозяином, местом и временем.
    @discardableResult
    public mutating func trash(_ id: String, now ms: Int64) -> Bool {
        guard let (owner, index) = locate(id), let d = take(id, from: owner) else { return false }
        trashedDocs.insert(TrashedDoc(doc: d, from: owner, index: index, deletedAt: ms), at: 0)
        return true
    }

    /// «Вернуть»: на своё место (не дальше конца массива), `at` — «сейчас». Хозяина нет (съёмка в
    /// корзине съёмок или стёрта, организации нет) — в начало «Мои». `nil` — такой бумаги в корзине нет.
    @discardableResult
    public mutating func restore(_ id: String, now ms: Int64) -> Restored? {
        guard let k = trashedDocs.firstIndex(where: { $0.doc.id == id }) else { return nil }
        let t = trashedDocs.remove(at: k)
        var d = t.doc
        d.at = ms
        if isLive(t.from) {
            place(&d, in: t.from, at: t.index)
            return .home
        }
        place(&d, in: .mine, at: 0)
        return .mine(lost: t.from)
    }

    /// «Удалить навсегда» из листа корзины: тени у бумаги нет.
    @discardableResult
    public mutating func purge(_ id: String) -> Bool {
        guard let k = trashedDocs.firstIndex(where: { $0.doc.id == id }) else { return false }
        trashedDocs.remove(at: k)
        return true
    }

    /// «Очистить корзину документов» (после вопроса): автоочистки по сроку нет.
    public mutating func clearTrash() { trashedDocs = [] }

    // MARK: - Внутри

    /// Где бумага живёт: хозяин и место в его массиве.
    public func locate(_ id: String) -> (owner: DocOwner, index: Int)? {
        for s in sessions { if let i = s.docs.firstIndex(where: { $0.id == id }) { return (.session(s.id), i) } }
        for o in orgs {
            if let i = o.docs.firstIndex(where: { $0.id == id }) { return (.org(o.id), i) }
            if let i = o.requisiteFiles.firstIndex(where: { $0.id == id }) { return (.orgRequisite(o.id), i) }
        }
        if let i = myDocs.firstIndex(where: { $0.id == id }) { return (.mine, i) }
        return nil
    }

    /// Живёт ли хозяин: съёмка в списке (в корзине съёмок её здесь нет), организация в списке.
    public func isLive(_ owner: DocOwner) -> Bool {
        switch owner {
        case .mine: true
        case .session(let id): sessions.contains { $0.id == id } && !trashedSessionIds.contains(id)
        case .org(let id), .orgRequisite(let id): orgs.contains { $0.id == id }
        }
    }

    private mutating func take(_ id: String, from owner: DocOwner) -> Attachment? {
        func pull(_ a: inout [Attachment]) -> Attachment? {
            a.firstIndex { $0.id == id }.map { a.remove(at: $0) }
        }
        switch owner {
        case .mine: return pull(&myDocs)
        case .session(let sid):
            guard let i = sessions.firstIndex(where: { $0.id == sid }) else { return nil }
            return pull(&sessions[i].docs)
        case .org(let oid):
            guard let i = orgs.firstIndex(where: { $0.id == oid }) else { return nil }
            return pull(&orgs[i].docs)
        case .orgRequisite(let oid):
            guard let i = orgs.firstIndex(where: { $0.id == oid }) else { return nil }
            return pull(&orgs[i].requisiteFiles)
        }
    }

    /// `at: nil` — «Мои» в начало, остальные в конец; иначе на место `index`, не дальше конца.
    private mutating func place(_ d: inout Attachment, in owner: DocOwner, at index: Int?) {
        func put(_ a: inout [Attachment], front: Bool) {
            let i = index.map { min(max(0, $0), a.count) } ?? (front ? 0 : a.count)
            a.insert(d, at: i)
        }
        switch owner {
        case .mine: put(&myDocs, front: true)
        case .session(let sid):
            guard let i = sessions.firstIndex(where: { $0.id == sid }) else { return }
            d.date = nil
            put(&sessions[i].docs, front: false)
        case .org(let oid):
            guard let i = orgs.firstIndex(where: { $0.id == oid }) else { return }
            put(&orgs[i].docs, front: false)
        case .orgRequisite(let oid):
            guard let i = orgs.firstIndex(where: { $0.id == oid }) else { return }
            put(&orgs[i].requisiteFiles, front: false)
        }
    }
}

extension DocOwner {
    /// Куда бумагу можно класть и откуда переносить: реквизиты-файл — только удалить и вернуть.
    var isDocShelf: Bool { if case .orgRequisite = self { false } else { true } }
    var isSession: Bool { if case .session = self { true } else { false } }
}
