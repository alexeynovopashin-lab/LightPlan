import Foundation
import LightPlanCore

/// Организации: список, карточка, общая полка бумаг (веб `orgs[]`, `orgShoots`,
/// `allDocuments`, итерация 28, шаг 6; справка `docs/org_reference.md` § 1).
/// Связь с записью одна — `Session.orgId`; съёмки организации ищутся фильтром.
public enum OrgBook {

    // MARK: - Съёмки организации

    /// Записи организации, от новых к старым (веб `orgShoots`: по дате, потом по началу).
    public static func shoots(of orgId: String, in sessions: [Session]) -> [Session] {
        sessions.filter { $0.orgId == orgId }.sorted { a, b in
            a.day != b.day ? a.day > b.day : a.start > b.start
        }
    }

    /// Итог строки списка: сколько съёмок и сколько по валютам (веб `renderOrgList`).
    /// Суммы — доход записи (`Money.income`), валюта первой — домашняя.
    public struct Line: Equatable, Sendable {
        public var shootCount: Int
        public var sums: [(currency: Currency, sum: Decimal)]
        public init(shootCount: Int, sums: [(currency: Currency, sum: Decimal)]) {
            self.shootCount = shootCount
            self.sums = sums
        }
        public static func == (a: Line, b: Line) -> Bool {
            a.shootCount == b.shootCount && a.sums.count == b.sums.count
                && zip(a.sums, b.sums).allSatisfy { $0.currency == $1.currency && $0.sum == $1.sum }
        }
    }

    public static func line(of orgId: String, in sessions: [Session], home: Currency) -> Line {
        let list = sessions.filter { $0.orgId == orgId }
        return Line(shootCount: list.count,
                    sums: Money.sumByCurrency(list, home: home) { Money.income(of: $0, among: sessions) })
    }

    // MARK: - Пустая организация не остаётся (ошибка веба 24)

    /// В организации нет ничего, что человек вписал: ни названия, ни лица, ни телефона,
    /// ни реквизитов, ни бумаг.
    public static func isBlank(_ o: Org) -> Bool {
        func empty(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return empty(o.name) && empty(o.person) && empty(o.phone) && empty(o.requisites)
            && o.docs.isEmpty && o.requisiteFiles.isEmpty
    }

    /// Организацию держат, если в ней что-то есть или за ней числятся съёмки: записи
    /// без заказчика терять нельзя, даже если имя стёрли.
    public static func keeps(_ o: Org, in sessions: [Session]) -> Bool {
        !isBlank(o) || sessions.contains { $0.orgId == o.id }
    }

    // MARK: - Удаление

    /// Записи, что числились за организацией: `orgId` снят, отметка правки свежая
    /// (веб L23665). Имя и телефон в записях остаются — теряется только связь.
    public static func detach(_ orgId: String, from sessions: [Session], at ms: Int64) -> [Session] {
        sessions.map { s in
            guard s.orgId == orgId else { return s }
            var c = s
            c.orgId = nil
            c.modifiedAt = ms
            return c
        }
    }

    // MARK: - Бумаги

    /// Вид документа: сохранённый главнее угаданного по имени (веб `docKind`).
    public static func kind(of d: Attachment) -> DocKind? {
        d.kind ?? DocKind.guess(fileName: d.name ?? d.url ?? "")
    }

    /// Строка бумаг организации: свои — с местом в `docs` (можно убрать), бумаги её
    /// съёмок — без него (живут в съёмке; веб L23785).
    public struct OrgDoc: Sendable, Hashable {
        public var doc: Attachment
        /// Место в `Org.docs`; `nil` — бумага съёмки.
        public var index: Int?
        /// Съёмка, откуда бумага.
        public var sessionId: String?
        public var day: CivilDate?
    }

    /// Бумаги карточки организации под фильтром вида (`nil` — все): свои, потом съёмок от новых к старым.
    public static func docs(of o: Org, in sessions: [Session], kind: DocKind?) -> [OrgDoc] {
        var out = o.docs.enumerated().map { OrgDoc(doc: $0.element, index: $0.offset, sessionId: nil, day: nil) }
        for s in shoots(of: o.id, in: sessions) {
            out += s.docs.map { OrgDoc(doc: $0, index: nil, sessionId: s.id, day: s.day) }
        }
        return kind == nil ? out : out.filter { self.kind(of: $0.doc) == kind }
    }

    /// Число бумаг вида в карточке (счётчик на чипе).
    public static func docCount(of o: Org, in sessions: [Session], kind: DocKind) -> Int {
        docs(of: o, in: sessions, kind: kind).count
    }

    /// Новая ссылка в документы организации (лист «Ссылка»). Пустая — ничего.
    @discardableResult
    public static func addLink(_ raw: String, kind: DocKind?, to o: inout Org) -> Bool {
        guard let d = Attachment.link(raw, kind: kind) else { return false }
        o.docs.append(d)
        return true
    }

    public static func removeDoc(at i: Int, from o: inout Org) {
        guard o.docs.indices.contains(i) else { return }
        o.docs.remove(at: i)
    }

    // MARK: - Общая полка «Документы»

    /// Бумага на общей полке (веб `allDocuments`): чья она, кому и когда.
    public struct ShelfDoc: Sendable, Hashable {
        public var doc: Attachment
        /// Вид; реквизиты-файлы вида не имеют — их метка `isRequisite`.
        public var kind: DocKind?
        public var isRequisite: Bool
        public var orgId: String?
        public var sessionId: String?
        public var day: CivilDate?
    }

    /// Все бумаги: съёмок, организаций, реквизиты-файлы. Свежие сверху по дате съёмки;
    /// бумаги организации без даты — внизу (веб L21075).
    public static func shelf(orgs: [Org], sessions: [Session]) -> [ShelfDoc] {
        var out: [ShelfDoc] = []
        for s in sessions {
            for d in s.docs {
                out.append(ShelfDoc(doc: d, kind: kind(of: d), isRequisite: false, orgId: s.orgId, sessionId: s.id, day: s.day))
            }
        }
        for o in orgs {
            for d in o.docs {
                out.append(ShelfDoc(doc: d, kind: kind(of: d), isRequisite: false, orgId: o.id, sessionId: nil, day: nil))
            }
            for d in o.requisiteFiles {
                out.append(ShelfDoc(doc: d, kind: nil, isRequisite: true, orgId: o.id, sessionId: nil, day: nil))
            }
        }
        // Устойчиво: равные по дате остаются в порядке появления.
        return out.enumerated().sorted { a, b in
            switch (a.element.day, b.element.day) {
            case let (x?, y?) where x != y: return x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Чипы видов полки: вид виден, если у него есть бумага или он сейчас выбран
    /// (веб `renderAllDocs`); порядок — по практике. Число — сколько бумаг.
    public static func shelfKinds(_ shelf: [ShelfDoc], practice: Practice, selected: DocKind?) -> [(kind: DocKind, count: Int)] {
        practice.docKinds.compactMap { k in
            let n = shelf.filter { $0.kind == k }.count
            return n > 0 || selected == k ? (k, n) : nil
        }
    }

    /// Полка под фильтром вида; `nil` — всё.
    public static func filtered(_ shelf: [ShelfDoc], kind: DocKind?) -> [ShelfDoc] {
        kind == nil ? shelf : shelf.filter { $0.kind == kind }
    }
}
