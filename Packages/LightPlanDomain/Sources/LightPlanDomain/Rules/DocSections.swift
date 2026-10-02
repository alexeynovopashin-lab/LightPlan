import Foundation
import LightPlanCore

/// Восемь разделов экрана «Документы» (итерация 28д, справка `docs_reference.md` § 3): что в каждом
/// лежит и сколько. Показ тремя видами и группы — `DocShelf`; здесь — выборки.
public enum DocSection: String, CaseIterable, Sendable {
    case attention, recent, bySession, byOrg, byKind, byMonth, mine, bin
}

/// Число справа у раздела; нулевое не рисуется (строка остаётся).
public struct DocCounts: Sendable, Hashable {
    public var attention = 0, recent = 0, bySession = 0, byOrg = 0, byKind = 0, byMonth = 0, mine = 0, bin = 0
    /// «Всего» в полосе на «Съёмках»: бумаги полки (раздел 4) + «Мои»; корзина не считается.
    public var total: Int { byOrg + mine }

    public func count(of s: DocSection) -> Int {
        switch s {
        case .attention: attention
        case .recent: recent
        case .bySession: bySession
        case .byOrg: byOrg
        case .byKind: byKind
        case .byMonth: byMonth
        case .mine: mine
        case .bin: bin
        }
    }
}

public enum DocSections {
    /// Сколько бумаг в «Недавних».
    public static let recentLimit = 20

    /// Вся живая полка: съёмки, организации, реквизиты, «Мои» — то, что ищет поиск и что считает «Недавние».
    public static func shelf(_ lib: DocLibrary) -> [OrgBook.ShelfDoc] {
        OrgBook.shelf(orgs: lib.orgs, sessions: lib.sessions, mine: lib.myDocs)
    }

    /// Область разделов «По организациям», «По видам», «По месяцам»: полка без «Мои». Группы —
    /// `DocShelf.groups` с `prefs.grouping` = `.org` / `.kind` / `.month`.
    public static func areaWithoutMine(_ lib: DocLibrary) -> [OrgBook.ShelfDoc] {
        OrgBook.shelf(orgs: lib.orgs, sessions: lib.sessions)
    }

    public static func area(for s: DocSection, _ lib: DocLibrary) -> [OrgBook.ShelfDoc] {
        switch s {
        case .recent: recent(lib)
        case .mine: mine(lib)
        case .byOrg, .byKind, .byMonth: areaWithoutMine(lib)
        default: []
        }
    }

    /// «Недавние»: 20 первых — по `at`, новые сверху (равные — как на полке); у бумаги без `at` —
    /// после, в порядке полки.
    public static func recent(_ lib: DocLibrary) -> [OrgBook.ShelfDoc] {
        let all = shelf(lib).enumerated()
        let stamped = all.filter { $0.element.doc.at != nil }.sorted { a, b in
            let (x, y) = (a.element.doc.at!, b.element.doc.at!)
            return x != y ? x > y : a.offset < b.offset
        }
        let rest = all.filter { $0.element.doc.at == nil }
        return Array((stamped + rest).prefix(recentLimit).map(\.element))
    }

    /// «Мои»: дата сверху, без даты внизу (у равных — порядок в «Мои», то есть новые первыми).
    public static func mine(_ lib: DocLibrary) -> [OrgBook.ShelfDoc] {
        OrgBook.shelf(orgs: [], sessions: [], mine: lib.myDocs)
    }

    /// «Корзина»: по `deletedAt`, новые сверху.
    public static func bin(_ lib: DocLibrary) -> [TrashedDoc] {
        lib.trashedDocs.enumerated().sorted { a, b in
            a.element.deletedAt != b.element.deletedAt ? a.element.deletedAt > b.element.deletedAt : a.offset < b.offset
        }.map(\.element)
    }

    /// Съёмка с бумагами.
    public struct SessionGroup: Sendable, Hashable {
        public var session: Session
        public var docs: [OrgBook.ShelfDoc]
    }

    /// «По съёмкам»: съёмки без бумаг не показываются; ближайшая первой (сегодня и впереди — по
    /// возрастанию дня), прошедшие — в хвост по убыванию дня (как порядок «Съёмок»). Внутри съёмки
    /// бумаги — по виду (порядок практики; без вида — в конце), потом по названию.
    public static func bySession(_ lib: DocLibrary, practice: Practice, today: CivilDate) -> [SessionGroup] {
        let rank = Dictionary(uniqueKeysWithValues: practice.docKinds.enumerated().map { ($1, $0) })
        func title(_ d: Attachment) -> String { d.title ?? d.name ?? d.url ?? "" }
        let groups = lib.sessions.filter { !$0.docs.isEmpty }.map { s in
            SessionGroup(session: s, docs: s.docs.enumerated().sorted { x, y in
                let (a, b) = (x.element, y.element)
                let ra = OrgBook.kind(of: a).flatMap { rank[$0] } ?? 1000
                let rb = OrgBook.kind(of: b).flatMap { rank[$0] } ?? 1000
                if ra != rb { return ra < rb }
                let c = title(a).compare(title(b), options: [.caseInsensitive, .numeric])
                return c != .orderedSame ? c == .orderedAscending : x.offset < y.offset
            }.map { x in
                OrgBook.ShelfDoc(doc: x.element, kind: OrgBook.kind(of: x.element), isRequisite: false,
                                 orgId: s.orgId, sessionId: s.id, day: s.day)
            })
        }
        let (ahead, past) = (groups.filter { $0.session.day.days(since: today) >= 0 },
                             groups.filter { $0.session.day.days(since: today) < 0 })
        return ahead.sorted { $0.session.day < $1.session.day } + past.sorted { $0.session.day > $1.session.day }
    }

    public static func counts(_ lib: DocLibrary, practice: Practice, today: CivilDate) -> DocCounts {
        var c = DocCounts()
        c.attention = DocAttention.items(sessions: lib.sessions, orgs: lib.orgs, practice: practice, today: today).count
        c.recent = recent(lib).count
        c.bySession = lib.sessions.filter { !$0.docs.isEmpty }.count
        let area = areaWithoutMine(lib).count
        (c.byOrg, c.byKind, c.byMonth) = (area, area, area)
        c.mine = lib.myDocs.count
        c.bin = lib.trashedDocs.count
        return c
    }
}
