import Foundation
import LightPlanCore

/// Группировка полки «Документы» (итерация 28, шаг 12а; DECISIONS 01.10: «Раздел «Документы»…»).
public enum DocGrouping: String, Sendable, CaseIterable {
    case org, month, kind
}

/// По чему сортируются бумаги внутри группы.
public enum DocSortKey: String, Sendable {
    case date, title
    /// Только таблица (12б): вид и организация.
    case kind, org
}

/// Вид раздела (слово Алексея 01.10: три вида и переключатель сверху, как в Finder).
/// Список — группы с заголовками; таблица — одна строка на бумагу, сортировка по любой колонке; месяцы — как «Фото».
public enum DocsLayout: String, Sendable, CaseIterable {
    case list, table, months
}

/// Что помнит раздел между запусками: вид, группировка, сортировка, свёрнутые группы.
public struct DocsPrefs: Equatable, Sendable, Codable {
    public var layout: DocsLayout = .list
    public var grouping: DocGrouping = .org
    public var sortKey: DocSortKey = .date
    /// Дата — от новых к старым, пока не нажато; название — от А к Я.
    public var ascending = false
    /// Номера свёрнутых групп (`DocShelf.Group.id`).
    public var collapsed: Set<String> = []

    public init() {}

    enum CodingKeys: String, CodingKey { case layout, grouping, sortKey, ascending, collapsed }

    /// Незнакомое слово (запись из будущей версии) не роняет разбор — берётся значение по умолчанию.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? c.decode(String.self, forKey: .layout)).flatMap(DocsLayout.init(rawValue:)) ?? .list
        grouping = (try? c.decode(String.self, forKey: .grouping)).flatMap(DocGrouping.init(rawValue:)) ?? .org
        sortKey = (try? c.decode(String.self, forKey: .sortKey)).flatMap(DocSortKey.init(rawValue:)) ?? .date
        ascending = (try? c.decode(Bool.self, forKey: .ascending)) ?? false
        collapsed = Set((try? c.decode([String].self, forKey: .collapsed)) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layout.rawValue, forKey: .layout)
        try c.encode(grouping.rawValue, forKey: .grouping)
        try c.encode(sortKey.rawValue, forKey: .sortKey)
        try c.encode(ascending, forKey: .ascending)
        try c.encode(collapsed.sorted(), forKey: .collapsed)
    }

    /// Тап по заголовку колонки: тот же ключ — меняет направление, другой — берёт его
    /// с обычным направлением (дата — новые сверху, остальные — А→Я).
    public mutating func tapColumn(_ key: DocSortKey) {
        if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = key != .date }
    }

    public mutating func toggleGroup(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    public func data() -> Data? { try? JSONEncoder().encode(self) }

    public static func from(_ data: Data?) -> DocsPrefs {
        data.flatMap { try? JSONDecoder().decode(DocsPrefs.self, from: $0) } ?? DocsPrefs()
    }
}

/// Слова и поиски, которых нет в домене: язык, организации, клиенты, даты.
public struct DocShelfWords {
    public struct Owner: Hashable, Sendable {
        public var key: String
        public var label: String
        public init(key: String, label: String) { self.key = key; self.label = label }
    }
    public var kindName: (DocKind) -> String
    /// «Реквизиты» — бумага без вида, файл реквизитов.
    public var requisite: String
    /// «Файл» — вид не задан, расширения нет.
    public var fileWord: String
    /// «Частные клиенты» — у бумаги нет ни организации, ни клиента.
    public var privateClients: String
    /// «Без даты».
    public var noDate: String
    /// Организация бумаги или клиент её съёмки; `nil` — ни того, ни другого.
    public var owner: (OrgBook.ShelfDoc) -> Owner?
    public var dateText: (CivilDate) -> String
    public var monthLabel: (_ year: Int, _ month: Int) -> String

    public init(kindName: @escaping (DocKind) -> String, requisite: String, fileWord: String,
                privateClients: String, noDate: String,
                owner: @escaping (OrgBook.ShelfDoc) -> Owner?,
                dateText: @escaping (CivilDate) -> String,
                monthLabel: @escaping (Int, Int) -> String) {
        self.kindName = kindName; self.requisite = requisite; self.fileWord = fileWord
        self.privateClients = privateClients; self.noDate = noDate
        self.owner = owner; self.dateText = dateText; self.monthLabel = monthLabel
    }
}

/// Полка «Документы» как список с группами: название бумаги, группы, сортировки.
public enum DocShelf {
    public struct Row: Hashable, Sendable {
        public var shelf: OrgBook.ShelfDoc
        /// Своё «Название», а без него — «Вид · Организация (или клиент) · дата».
        public var title: String
        /// Вид словом: слева в строке.
        public var kindLabel: String
        public var ownerLabel: String?
        /// Дата съёмки; у бумаги организации её нет — `nil`.
        public var dateText: String?

        public init(shelf: OrgBook.ShelfDoc, title: String, kindLabel: String, ownerLabel: String?, dateText: String?) {
            self.shelf = shelf; self.title = title; self.kindLabel = kindLabel
            self.ownerLabel = ownerLabel; self.dateText = dateText
        }
    }

    public struct Group: Hashable, Sendable {
        /// Устойчивый номер: по нему помнится «свёрнута».
        public var id: String
        public var label: String
        public var rows: [Row]
    }

    /// Вид словом: имя вида, у реквизитов — «Реквизиты», иначе расширение файла или «Файл».
    public static func kindLabel(_ d: OrgBook.ShelfDoc, _ w: DocShelfWords) -> String {
        if d.isRequisite { return w.requisite }
        if let k = d.kind { return w.kindName(k) }
        return DocLabel.ext(d.doc.name ?? "") ?? w.fileWord
    }

    /// `within` — в какой группе строка стоит: что заголовок группы уже говорит, имя не повторяет
    /// (по организации — без организации, по месяцу — без даты; решение 01.10: «Вид · дата» внутри
    /// группы). Вне группы (таблица, карточка, поиск) — полное «Вид · Организация · дата».
    public static func row(_ d: OrgBook.ShelfDoc, _ w: DocShelfWords, within: DocGrouping? = nil) -> Row {
        let kind = kindLabel(d, w)
        let owner = w.owner(d)?.label
        let date = d.day.map(w.dateText)
        let own = d.doc.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = [kind, within == .org ? "" : owner ?? "", within == .month ? "" : date ?? ""]
        let title = own.isEmpty ? parts.filter { !$0.isEmpty }.joined(separator: " · ") : own
        return Row(shelf: d, title: title, kindLabel: kind, ownerLabel: owner, dateText: date)
    }

    /// Строки полки группами. Фильтр чипами делается до вызова (`OrgBook.filtered`).
    /// Порядок групп: организации по алфавиту, «Частные клиенты» последними; месяцы — новые
    /// сверху (при сортировке даты «вверх» — старые); виды — как в практике, потом реквизиты и «Файл».
    public static func groups(_ shelf: [OrgBook.ShelfDoc], prefs: DocsPrefs, practice: Practice,
                              words w: DocShelfWords) -> [Group] {
        // В списке заголовков «Вид» и «Организация» нет: сортировка таблицы по ним в список не
        // протекает — там читается как обычная «Дата, новые сверху» (ревью GPT к 92b1a9b).
        var prefs = prefs
        if prefs.sortKey == .kind || prefs.sortKey == .org { prefs.sortKey = .date; prefs.ascending = false }
        var order: [String] = []
        var labels: [String: String] = [:]
        var buckets: [String: [Row]] = [:]
        for d in shelf {
            let r = row(d, w, within: prefs.grouping)
            let (id, label) = key(for: d, grouping: prefs.grouping, words: w)
            if buckets[id] == nil { order.append(id); labels[id] = label }
            buckets[id, default: []].append(r)
        }
        let rank = Dictionary(uniqueKeysWithValues: practice.docKinds.enumerated().map { ("k:" + $1.rawValue, $0) })
        let ids = order.sorted { a, b in
            switch prefs.grouping {
            case .org:
                if (a == privateId) != (b == privateId) { return b == privateId }
                return labels[a]!.localizedCaseInsensitiveCompare(labels[b]!) == .orderedAscending
            case .month:
                if (a == noDateId) != (b == noDateId) { return b == noDateId }
                let up = prefs.sortKey == .date && prefs.ascending
                return up ? a < b : a > b
            case .kind:
                return kindRank(a, rank) < kindRank(b, rank)
            }
        }
        return ids.map { Group(id: $0, label: labels[$0]!, rows: sorted(buckets[$0]!, prefs)) }
    }

    /// Вид Б — таблица: одна строка на бумагу, имя полное, сортировка по колонке из `prefs`.
    public static func table(_ shelf: [OrgBook.ShelfDoc], prefs: DocsPrefs, words w: DocShelfWords) -> [Row] {
        sorted(shelf.map { row($0, w) }, prefs)
    }

    /// Вид В — по месяцам, как «Фото»: новые месяцы сверху, в месяце бумаги от новых, «Без даты» последней.
    /// Порядок задан видом, а не запомненной сортировкой таблицы.
    public static func months(_ shelf: [OrgBook.ShelfDoc], practice: Practice, words w: DocShelfWords) -> [Group] {
        var p = DocsPrefs(); p.grouping = .month; p.sortKey = .date; p.ascending = false
        return groups(shelf, prefs: p, practice: practice, words: w)
    }

    static let privateId = "org:private"
    static let noDateId = "m:none"

    private static func kindRank(_ id: String, _ rank: [String: Int]) -> Int {
        if let r = rank[id] { return r }
        return id == "k:req" ? 1000 : 1001
    }

    private static func key(for d: OrgBook.ShelfDoc, grouping: DocGrouping, words w: DocShelfWords) -> (String, String) {
        switch grouping {
        case .org:
            guard let o = w.owner(d) else { return (privateId, w.privateClients) }
            return ("org:" + o.key, o.label)
        case .month:
            guard let day = d.day else { return (noDateId, w.noDate) }
            return (String(format: "m:%04d-%02d", day.year, day.month), w.monthLabel(day.year, day.month))
        case .kind:
            if d.isRequisite { return ("k:req", w.requisite) }
            guard let k = d.kind else { return ("k:file", w.fileWord) }
            return ("k:" + k.rawValue, w.kindName(k))
        }
    }

    /// Дата: бумаги без даты — внизу при любом направлении; равные — по названию.
    /// Название: без учёта регистра и с натуральным порядком цифр.
    public static func sorted(_ rows: [Row], _ prefs: DocsPrefs) -> [Row] {
        func byTitle(_ a: Row, _ b: Row) -> ComparisonResult {
            a.title.compare(b.title, options: [.caseInsensitive, .numeric], range: nil, locale: .current)
        }
        return rows.enumerated().sorted { x, y in
            let a = x.element, b = y.element
            switch prefs.sortKey {
            case .title:
                let c = byTitle(a, b)
                if c != .orderedSame { return prefs.ascending ? c == .orderedAscending : c == .orderedDescending }
            case .kind, .org:
                let (p, q) = prefs.sortKey == .kind ? (a.kindLabel, b.kindLabel as String?) : (a.ownerLabel, b.ownerLabel)
                switch (p, q) {
                case (nil, _?): return false
                case (_?, nil): return true
                case let (m?, n?):
                    let c = m.compare(n, options: [.caseInsensitive, .numeric], range: nil, locale: .current)
                    if c != .orderedSame { return prefs.ascending ? c == .orderedAscending : c == .orderedDescending }
                case (nil, nil): break
                }
                if a.shelf.day != b.shelf.day {
                    switch (a.shelf.day, b.shelf.day) {
                    case (nil, _?): return false
                    case (_?, nil): return true
                    case let (d?, e?): return d > e
                    default: break
                    }
                }
                let c = byTitle(a, b)
                if c != .orderedSame { return c == .orderedAscending }
            case .date:
                switch (a.shelf.day, b.shelf.day) {
                case (nil, _?): return false
                case (_?, nil): return true
                case let (p?, q?) where p != q: return prefs.ascending ? p < q : p > q
                default: break
                }
                let c = byTitle(a, b)
                if c != .orderedSame { return c == .orderedAscending }
            }
            return x.offset < y.offset
        }.map(\.element)
    }
}
