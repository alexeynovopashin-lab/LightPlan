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
    /// Строка поиска; пусто — поиска нет, экран показывает разделы как есть. Один на корень и разделы.
    var query = ""
    /// Открытая бумага (экран бумаги поверх корня и раздела).
    var paper: OrgBook.ShelfDoc?
    /// Сообщение экрана бумаги: «Файл не открылся» (облака нет до итерации 30).
    var paperNote: String?
    /// Лист быстрого «+» или правки бумаги (шаг 4).
    var sheet: DocSheet?
    /// Вопрос корзины документов: стереть одну бумагу навсегда или очистить всю корзину.
    var binAsk: DocBinAsk?
}

enum DocBinAsk: Equatable {
    case purge(id: String)
    case clear
}

/// Лист бумаги: новая («+») или правка существующей — по знаку бумаги.
enum DocSheet: Equatable, Identifiable {
    case add
    case edit(id: String)
    var id: String { if case .edit(let i) = self { "edit:" + i } else { "add" } }
}

/// Поля листа «+» и правки: правятся в листе и пишутся только по «Добавить» / «Сохранить».
struct DocDraft: Equatable {
    var kind: DocKind?
    /// Вид выбран рукой (в том числе «Без вида»): ссылка его больше не угадывает.
    var kindTouched = false
    var title = ""
    var url = ""
    var date: CivilDate?
    var owner: LightPlanDomain.DocOwner = .mine
    /// Бумага-ссылка: у файла поля ссылки нет, править её нельзя.
    var linkEditable = true

    /// Нужно хоть что-то: ссылка, название или вид — пустую бумагу не заводим.
    var canSave: Bool {
        !url.trimmingCharacters(in: .whitespaces).isEmpty || !title.trimmingCharacters(in: .whitespaces).isEmpty || kind != nil
    }

    mutating func pickKind(_ k: DocKind?) { kind = k; kindTouched = true }

    /// Ссылка вставлена или набрана: пока вид не выбран рукой — угадывается по ней (`DocKind.guess`).
    mutating func setURL(_ raw: String) {
        url = raw
        if !kindTouched { kind = DocKind.guess(fileName: raw) }
    }
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

    func openDocPaper(_ d: OrgBook.ShelfDoc) {
        docsNav.paperNote = nil
        docsNav.paper = d
    }

    func closeDocPaper() {
        docsNav.paper = nil
        docsNav.paperNote = nil
    }

    // MARK: - Поиск (справка § 5)

    var docSearching: Bool { !DocSearch.tokens(docsNav.query).isEmpty }

    /// Результат поиска по всей живой полке (корзина и «Требуют внимания» не ищутся) — один плоский
    /// список: сначала совпавшие в названии, потом по дате от новых.
    func docSearchResults() -> [OrgBook.ShelfDoc] {
        let lib = docLibrary
        return DocSearch.search(docsNav.query, in: DocSections.shelf(lib), orgs: lib.orgs, sessions: lib.sessions,
                                words: docShelfWords())
    }

    /// Вид «список»: строки в порядке релевантности (сортировка колонок на результате не действует).
    func docSearchRows() -> [DocShelf.Row] {
        let words = docShelfWords()
        return docSearchResults().map { DocShelf.row($0, words) }
    }

    func docSearchTableRows() -> [DocShelf.Row] {
        let words = docShelfWords()
        return docSearchResults().map { DocShelf.row($0, words, table: true) }
    }

    func docSearchMonths() -> [DocShelf.Group] {
        DocShelf.months(docSearchResults(), practice: dealPractice, words: docShelfWords())
    }

    // MARK: - Экран бумаги (справка § 2.3, шаг 3б)

    /// К чему привязана бумага.
    enum DocOwner: Hashable { case session, org, requisites, mine }

    struct DocPaper: Hashable {
        let row: DocShelf.Row
        /// Крупный заголовок: своё название, а без него — вид (остальное в строках ниже).
        let headline: String
        let owner: DocOwner
        /// Съёмка словами «дата · жанр · клиент», название организации или «Мои».
        let ownerText: String
        let sessionId: String?
        /// Цепочка сделки съёмки бумаги; `nil` — бумага не съёмки или у такой съёмки сделки нет.
        let deal: CardDeal?
        /// Звено цепочки, которое закрывает бумага этого вида.
        let step: DealStep?
        let url: URL?
    }

    /// Звено сделки, которое закрывает бумага вида; у чека звена нет.
    static func dealStep(of k: DocKind?) -> DealStep? {
        switch k {
        case .contract: .contract
        case .invoice: .invoice
        case .act: .act
        case .release: .release
        case .acceptance: .acceptance
        case .brief: .brief
        case .receipt, nil: nil
        }
    }

    func docPaper(_ d: OrgBook.ShelfDoc) -> DocPaper {
        let row = DocShelf.row(d, docShelfWords())
        let own = d.doc.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let owner: DocOwner = d.sessionId != nil ? .session : d.isRequisite ? .requisites : d.orgId != nil ? .org : .mine
        let session = d.sessionId.flatMap { id in docLibrary.sessions.first { $0.id == id } }
        let orgName = d.orgId.flatMap(orgRecord).map(orgTitle) ?? ""
        let ownerText: String
        switch owner {
        case .session: ownerText = session.map(docSessionTitle) ?? ""
        case .org, .requisites: ownerText = orgName
        case .mine: ownerText = lexicon.t("doc.secMine")
        }
        let step = Self.dealStep(of: d.kind).flatMap { dealPractice.chain.contains($0) ? $0 : nil }
        let url = d.doc.source == .link ? d.doc.url.flatMap(URL.init(string:)).flatMap { $0.scheme == nil ? nil : $0 } : nil
        return DocPaper(row: row, headline: own.isEmpty ? row.kindLabel : own, owner: owner, ownerText: ownerText,
                        sessionId: session?.id, deal: session.flatMap(cardDeal), step: step, url: url)
    }

    /// Без ссылки (файл — облака нет до 30) бумагу открыть нечем: сообщение на экране бумаги.
    func noteDocNotOpened() { docsNav.paperNote = lexicon.t("doc.openFail") }

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
            var row = DocShelf.row(.init(doc: t.doc, kind: OrgBook.kind(of: t.doc), isRequisite: false, orgId: nil, sessionId: nil, day: nil), words)
            // Без своего названия у строки остаётся один вид: слева он уже стоит, второй раз его не пишем.
            if row.title == row.kindLabel { row.title = "" }
            return (t, row)
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
