import Foundation

/// Поиск по полке «Документы» (итерация 28д, справка `docs_reference.md` § 5). Чистая функция:
/// экран позже. Ищет по живой бумаге — съёмки, организации, реквизиты, «Мои»; корзина и «Требуют
/// внимания» не ищутся (их сюда просто не передают).
public enum DocSearch {

    /// Без учёта регистра, `ё` = `е`, лишние пробелы не в счёт.
    static func fold(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    /// Слова запроса; пусто — поиска нет (экран показывает раздел как есть).
    public static func tokens(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Бумаги, где **каждое** слово запроса нашлось (частью слова, в любом порядке) в одном из трёх
    /// полей: название (своё, а без своего — собранное «Вид · Организация · дата», поэтому слово вида
    /// тоже находит), организация (`Org.name`), клиент (`Session.contact` съёмки бумаги). Имя файла и
    /// хвост ссылки не ищутся. Сначала те, где совпало в названии, потом по дате от новых; бумага без
    /// даты — внизу; равные — в порядке полки.
    public static func search(_ query: String, in shelf: [OrgBook.ShelfDoc], orgs: [Org], sessions: [Session],
                              words: DocShelfWords) -> [OrgBook.ShelfDoc] {
        let needles = tokens(query)
        guard !needles.isEmpty else { return [] }
        let orgName = Dictionary(orgs.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let client = Dictionary(sessions.map { ($0.id, $0.contact) }, uniquingKeysWith: { a, _ in a })

        struct Hit { var offset: Int; var doc: OrgBook.ShelfDoc; var inTitle: Bool }
        var hits: [Hit] = []
        for (i, d) in shelf.enumerated() {
            let title = fold(DocShelf.row(d, words).title)
            let org = fold(d.orgId.flatMap { orgName[$0] } ?? "")
            let cli = fold(d.sessionId.flatMap { client[$0] } ?? "")
            guard needles.allSatisfy({ title.contains($0) || org.contains($0) || cli.contains($0) }) else { continue }
            hits.append(Hit(offset: i, doc: d, inTitle: needles.contains { title.contains($0) }))
        }
        return hits.sorted { a, b in
            if a.inTitle != b.inTitle { return a.inTitle }
            switch (a.doc.day, b.doc.day) {
            case (nil, _?): return false
            case (_?, nil): return true
            case let (x?, y?) where x != y: return x > y
            default: return a.offset < b.offset
            }
        }.map(\.doc)
    }
}
