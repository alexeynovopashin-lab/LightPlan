import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Экран «Документы» (итерация 28д, шаг 3а): вход с полосы на «Съёмках», восемь разделов, внутри —
/// бумаги тремя видами. Правил здесь нет: выборки — `DocSections`, `DocAttention`, группы — `DocShelf`.
struct DocsNav: Equatable {
    var isOpen = false
    /// Открытый раздел; `nil` — список разделов.
    var section: DocSection?
}

extension AppModel {

    // MARK: - Слои

    func openDocs() {
        org.docs = DocsPrefs.from(docsPrefsStore.load())
        org.shelfKind = nil
        docsNav = DocsNav(isOpen: true, section: nil)
    }

    func closeDocs() {
        docsNav = DocsNav()
        org.shelfKind = nil
    }

    func openDocSection(_ s: DocSection) {
        org.shelfKind = nil
        docsNav.section = s
    }

    func closeDocSection() {
        org.shelfKind = nil
        docsNav.section = nil
    }

    // MARK: - Числа

    var docLibrary: DocLibrary { snapshot.docLibrary }

    /// Числа справа у разделов и в полосе «Съёмок».
    func docCounts() -> DocCounts { DocSections.counts(docLibrary, practice: dealPractice, today: today) }

    func docAttention() -> [DocAttention.Item] {
        DocAttention.items(sessions: docLibrary.sessions, orgs: docLibrary.orgs, practice: dealPractice, today: today)
    }

    // MARK: - Выборки раздела

    /// Бумаги раздела (без «Требуют внимания» и «Корзины» — там не бумаги полки). «По съёмкам» —
    /// бумаги съёмок в порядке групп.
    func docArea(_ s: DocSection) -> [OrgBook.ShelfDoc] {
        s == .bySession ? docBySession().flatMap(\.docs) : DocSections.area(for: s, docLibrary)
    }

    func docBySession() -> [DocSections.SessionGroup] {
        DocSections.bySession(docLibrary, practice: dealPractice, today: today)
    }

    /// Область раздела под выбранными чипами видов.
    func docFilteredArea(_ s: DocSection) -> [OrgBook.ShelfDoc] {
        OrgBook.filtered(docArea(s), kind: org.shelfKind)
    }

    /// Группировка, которую задаёт раздел; у остальных разделов групп нет.
    func docGrouping(of s: DocSection) -> DocGrouping? {
        switch s {
        case .byOrg: .org
        case .byKind: .kind
        case .byMonth: .month
        default: nil
        }
    }

    /// Вид «список» разделов с группами: группы полки под чипами и сортировкой колонки.
    func docGroups(for s: DocSection) -> [DocShelf.Group] {
        guard let g = docGrouping(of: s) else { return [] }
        var prefs = org.docs
        prefs.grouping = g
        return DocShelf.groups(docFilteredArea(s), prefs: prefs, practice: dealPractice, words: docShelfWords())
    }

    /// Вид «список» без групп: «Недавние» держат порядок по времени, «Мои» — дата сверху (`DocsPrefs`).
    func docFlatRows(for s: DocSection) -> [DocShelf.Row] {
        let words = docShelfWords()
        let area = docFilteredArea(s)
        if s == .recent { return area.map { DocShelf.row($0, words) } }
        return DocShelf.sorted(area.map { DocShelf.row($0, words) }, org.docs)
    }

    /// Вид «таблица»: «Недавние» остаются по времени, остальные — по колонке из `DocsPrefs`.
    func docTableRows(for s: DocSection) -> [DocShelf.Row] {
        let words = docShelfWords()
        let area = docFilteredArea(s)
        if s == .recent { return area.map { DocShelf.row($0, words, table: true) } }
        return DocShelf.table(area, prefs: org.docs, words: words)
    }

    func docMonths(for s: DocSection) -> [DocShelf.Group] {
        DocShelf.months(docFilteredArea(s), practice: dealPractice, words: docShelfWords())
    }

    /// «По съёмкам», вид «список»: съёмка с бумагами под чипами; пустые после фильтра не показываются.
    func docSessionGroups() -> [(title: String, id: String, rows: [DocShelf.Row])] {
        let words = docShelfWords()
        return docBySession().compactMap { g in
            let docs = OrgBook.filtered(g.docs, kind: org.shelfKind)
            guard !docs.isEmpty else { return nil }
            return (docSessionTitle(g.session), g.session.id, docs.map { DocShelf.row($0, words, within: .org) })
        }
    }

    /// «Дата · жанр · клиент или организация» — заголовок съёмки в «По съёмкам» и в «Требуют внимания».
    func docSessionTitle(_ s: Session) -> String {
        let words = PlannerWords(lexicon: lexicon, orgs: orgs)
        let facts = PlannerFacts(app: self, dark: true)
        let who = s.orgId.flatMap(orgRecord).map(orgTitle).flatMap { $0.isEmpty ? nil : $0 } ?? words.clientName(s)
        return [facts.dates.dMon(facts.date(s.day)), words.typeName(s), who].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - «Требуют внимания»

    /// Причина словами; у «нет закрывающей бумаги» слово зависит от практики.
    func docReasonWord(_ r: DocAttention.Reason) -> String {
        switch r {
        case .noContract: lexicon.t("doc.attnNoContract")
        case .noClosing: lexicon.t(dealPractice == .eu ? "doc.attnNoActEu" : "doc.attnNoAct")
        case .noPay: lexicon.t("doc.attnNoPay")
        }
    }

    /// Справа в строке: «через 5 дн.», «3 дн. назад», «сегодня».
    func docAttentionTiming(_ i: DocAttention.Item) -> String {
        if i.daysUntil == 0 { return lexicon.t("doc.attnToday") }
        return lexicon.t(i.daysUntil > 0 ? "doc.attnIn" : "doc.attnAgo", ["n": String(abs(i.daysUntil))])
    }

    // MARK: - «Корзина»

    /// «удалена 28 сен».
    func docDeletedText(_ d: TrashedDoc) -> String {
        let facts = PlannerFacts(app: self, dark: true)
        let date = Date(timeIntervalSince1970: Double(d.deletedAt) / 1000)
        return lexicon.t("doc.binDeleted", ["date": facts.dates.dMon(date)])
    }

    func docBinRows() -> [(trashed: TrashedDoc, row: DocShelf.Row)] {
        let words = docShelfWords()
        return DocSections.bin(docLibrary).map { t in
            (t, DocShelf.row(.init(doc: t.doc, kind: OrgBook.kind(of: t.doc), isRequisite: false, orgId: nil, sessionId: nil, day: nil), words))
        }
    }

    // MARK: - Слова

    func docSectionTitle(_ s: DocSection) -> String {
        lexicon.t("doc." + Self.docSectionKey[s]!)
    }

    static let docSectionKey: [DocSection: String] = [
        .attention: "secAttn", .recent: "secRecent", .bySession: "secSession", .byOrg: "secOrg",
        .byKind: "secKind", .byMonth: "secMonth", .mine: "secMine", .bin: "secBin",
    ]

    static func docSectionIcon(_ s: DocSection) -> String {
        switch s {
        case .attention: "warn"
        case .recent: "clock"
        case .bySession: "camera"
        case .byOrg: "city"
        case .byKind: "stamp"
        case .byMonth: "view_month"
        case .mine: "bookmark"
        case .bin: "trash"
        }
    }

    func docEmptyKey(_ s: DocSection) -> String {
        switch s {
        case .attention: "doc.emptyAttn"
        case .recent: "doc.emptyRecent"
        case .bySession: "doc.emptySession"
        case .byOrg, .byKind, .byMonth: "doc.emptyShelf"
        case .mine: "doc.emptyMine"
        case .bin: "doc.emptyBin"
        }
    }
}
