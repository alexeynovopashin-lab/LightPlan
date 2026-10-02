import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Быстрое «+», правка, перенос, удаление в корзину документов и возврат (итерация 28д, шаг 4).
/// Правил здесь нет: всё делает `DocLibrary` (шаг 2); здесь — листы, плашки «Вернуть» / «Отменить»
/// и то, что экран бумаги держит копию бумаги и должен её обновить.
extension AppModel {

    // MARK: - Листы

    func openDocAdd() { docsNav.sheet = .add }

    func openDocEdit(_ id: String) {
        guard docDraft(for: id) != nil else { return }
        docsNav.sheet = .edit(id: id)
    }

    func closeDocSheet() { docsNav.sheet = nil }

    /// Заготовка листа: пустая у «+» (привязка «Мои»), у правки — как бумага лежит сейчас.
    func docDraft(for sheet: DocSheet) -> DocDraft? {
        switch sheet {
        case .add: DocDraft()
        case .edit(let id): docDraft(for: id)
        }
    }

    func docDraft(for id: String) -> DocDraft? {
        let lib = docLibrary
        guard let (owner, _) = lib.locate(id), owner.isEditable,
              let d = DocSections.shelf(lib).first(where: { $0.doc.id == id })?.doc else { return nil }
        var draft = DocDraft(kind: d.kind, kindTouched: true, title: d.title ?? "", url: d.url ?? "", date: d.date, owner: owner)
        draft.linkEditable = d.source == .link
        return draft
    }

    // MARK: - Привязка в листе

    func docRecentSessions() -> [Session] { DocBinding.recentSessions(docLibrary, today: today) }

    func docRecentOrgs() -> [Org] { DocBinding.recentOrgs(docLibrary) }

    /// Все живые съёмки для «Другая съёмка…»: новые сверху, поиск по строке «дата · жанр · клиент».
    func docSessionChoices(matching q: String) -> [Session] {
        let all = DocBinding.live(docLibrary).sorted { ($0.day.year, $0.day.month, $0.day.day) > ($1.day.year, $1.day.month, $1.day.day) }
        let tokens = DocSearch.tokens(q)
        guard !tokens.isEmpty else { return all }
        return all.filter { s in
            let hay = docSessionTitle(s).lowercased()
            return tokens.allSatisfy { hay.contains($0) }
        }
    }

    func docOrgChoices(matching q: String) -> [Org] {
        let all = docLibrary.orgs.sorted { orgTitle($0).localizedCaseInsensitiveCompare(orgTitle($1)) == .orderedAscending }
        let tokens = DocSearch.tokens(q)
        guard !tokens.isEmpty else { return all }
        return all.filter { o in tokens.allSatisfy { orgTitle(o).lowercased().contains($0) } }
    }

    /// Привязка словами: «Без привязки (Мои)», строка съёмки, название организации.
    func docOwnerText(_ owner: LightPlanDomain.DocOwner) -> String {
        switch owner {
        case .mine: lexicon.t("doc.addMine")
        case .session(let id): docLibrary.sessions.first { $0.id == id }.map(docSessionTitle) ?? ""
        case .org(let id), .orgRequisite(let id): orgRecord(id).map(orgTitle) ?? ""
        }
    }

    // MARK: - Добавить и править

    /// «Добавить»: бумага без привязки встаёт в начало «Мои» и видна там сразу; плашка «Добавлено» с
    /// «Отменить». `nil` — ничего не добавлено (пустая бумага или хозяина уже нет).
    @discardableResult
    func addDoc(_ draft: DocDraft) -> String? {
        guard draft.canSave else { return nil }
        let doc = Attachment.paper(url: draft.url, kind: draft.kind, title: draft.title, date: draft.date)
        guard snapshot.docLibrary.create(doc, in: draft.owner, now: nowMs) else { return nil }
        docsNav.sheet = nil
        undo = UndoOffer(what: .docAdded(id: doc.id), text: lexicon.t("doc.added", ["name": docDisplayName(doc)]),
                         actionKey: "doc.undo")
        persist()
        return doc.id
    }

    /// «Сохранить» правки: вид, название, ссылка, день, затем перенос, если привязку сменили. `false` —
    /// бумаги нет или её не правят (реквизиты-файл).
    @discardableResult
    func saveDoc(_ id: String, _ draft: DocDraft) -> Bool {
        var lib = docLibrary
        guard let (from, _) = lib.locate(id) else { return false }
        let e = DocLibrary.Edit(kind: draft.kind, title: draft.title, url: draft.url, date: draft.date)
        guard lib.edit(id, e, now: nowMs) else { return false }
        if from != draft.owner { _ = lib.move(id, to: draft.owner, now: nowMs) }
        snapshot.docLibrary = lib
        docsNav.sheet = nil
        refreshPaper(id)
        persist()
        return true
    }

    // MARK: - Корзина документов

    /// «Удалить»: бумага уходит в корзину документов, полоса «Вернуть» 6 секунд. Экран этой бумаги закрывается.
    func trashDoc(_ id: String) {
        guard let d = DocSections.shelf(docLibrary).first(where: { $0.doc.id == id })?.doc else { return }
        guard snapshot.docLibrary.trash(id, now: nowMs) else { return }
        if docsNav.paper?.doc.id == id { closeDocPaper() }
        undo = UndoOffer(what: .docTrashed(id: id), text: lexicon.t("doc.inBin", ["name": docDisplayName(d)]))
        persist()
    }

    /// «Вернуть»: на своё место; хозяина нет — в «Мои» с плашкой, кого больше нет. Плашка «Вернуть» этой
    /// бумаги (`keepOffer` — её нажали самой) гаснет.
    func restoreDoc(_ id: String, keepOffer: Bool = false) {
        var lib = docLibrary
        guard let r = lib.restore(id, now: nowMs) else { return }
        snapshot.docLibrary = lib
        if !keepOffer, undo?.what == .docTrashed(id: id) { undo = nil }
        if case .mine(let lost) = r {
            let who = lexicon.t(lost.isSession ? "doc.lostSession" : "doc.lostOrg")
            undo = UndoOffer(what: .notice, text: lexicon.t("doc.restoredMine", ["who": who]))
        }
        persist()
    }

    /// «Удалить навсегда» (после вопроса).
    func purgeDoc(_ id: String) {
        guard snapshot.docLibrary.purge(id) else { return }
        if undo?.what == .docTrashed(id: id) { undo = nil }
        persist()
    }

    /// «Очистить корзину» (после вопроса).
    func clearDocBin() {
        guard !snapshot.trashedDocs.isEmpty else { return }
        snapshot.docLibrary.clearTrash()
        if case .docTrashed? = undo?.what { undo = nil }
        persist()
    }

    /// «Отменить» на «Добавлено».
    func discardDoc(_ id: String) {
        guard snapshot.docLibrary.discard(id) else { return }
        if docsNav.paper?.doc.id == id { closeDocPaper() }
        persist()
    }

    // MARK: - Внутри

    /// Экран бумаги держит копию строки полки: после правки и переноса берём свежую по знаку.
    private func refreshPaper(_ id: String) {
        guard docsNav.paper?.doc.id == id else { return }
        if let fresh = DocSections.shelf(docLibrary).first(where: { $0.doc.id == id }) { docsNav.paper = fresh }
    }

    /// Имя бумаги на плашках: своё название, а без него — как в строке полки.
    func docDisplayName(_ a: Attachment) -> String {
        let row = DocShelf.row(.init(doc: a, kind: OrgBook.kind(of: a), isRequisite: false, orgId: nil, sessionId: nil, day: nil), docShelfWords())
        return row.title.isEmpty ? row.kindLabel : row.title
    }
}

extension LightPlanDomain.DocOwner {
    /// Реквизиты-файл правке и переносу не подлежат (только удалить).
    var isEditable: Bool { if case .orgRequisite = self { false } else { true } }
    var isSession: Bool { if case .session = self { true } else { false } }
}
