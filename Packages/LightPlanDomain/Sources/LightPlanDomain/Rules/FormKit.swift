import Foundation
import LightPlanCore

// MARK: - Оборудование

/// Оборудование в форме (веб `#fKitRow`, `#kSheet`, L30797–30804, L31207–31252).
/// Список техники общий и ведёт его сам фотограф (`equipment` настроек), а
/// запись помнит имена взятого — не номера: список могут поправить, пока
/// запись лежит нетронутой.
extension EventForm {
    /// Сколько отмечено из того, что ещё есть в списке (веб `kitCheckedCount`):
    /// позиция, убранная из списка, в счёт не идёт, хоть имя и лежит в записи.
    public func kitChecked(in equipment: [String]) -> Int {
        gear.filter { equipment.contains($0) }.count
    }

    /// Тумблер позиции на листе.
    public mutating func toggleGear(_ name: String) {
        if let i = gear.firstIndex(of: name) { gear.remove(at: i) } else { gear.append(name) }
    }
}

/// Правка общего списка с листа «Оборудование»: новая позиция сразу берётся
/// на эту съёмку (веб `#kitAdd`), убранная — снимается и с неё (`[data-kit-x]`).
public enum Kit {
    /// Новая позиция; пустая строка — ничего. Повтор имени в список не идёт, но отмечается.
    public static func add(_ raw: String, to equipment: inout [String], form: inout EventForm) {
        let v = raw.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        if !equipment.contains(v) { equipment.append(v) }
        if !form.gear.contains(v) { form.gear.append(v) }
    }

    public static func remove(at i: Int, from equipment: inout [String], form: inout EventForm) {
        guard equipment.indices.contains(i) else { return }
        let name = equipment.remove(at: i)
        form.gear.removeAll { $0 == name }
    }
}

// MARK: - Документы заказа

/// Документы заказа в форме (веб «Документы заказа», L20903–21039). Вид
/// документа выбирается до добавления: он же фильтр списка, он же метка новым.
extension EventForm {
    /// Документы под фильтром вида с их местом в записи; `nil` — все.
    public func docsShown(kind: DocKind?) -> [(index: Int, doc: Attachment)] {
        docs.enumerated().filter { kind == nil || $0.element.kind == kind }.map { ($0.offset, $0.element) }
    }

    /// Счётчик на чипсе вида.
    public func docCount(_ kind: DocKind) -> Int { docs.filter { $0.kind == kind }.count }

    /// Ссылка на документ (веб `#docLink` + `askUrl`): без схемы — `https://`;
    /// вид — выбранный чипсом, иначе угаданный по адресу. Пустая — ничего.
    public mutating func addDocLink(_ raw: String, kind: DocKind?) {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        if url.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) == nil { url = "https://" + url }
        docs.append(Attachment(source: .link, url: url, kind: kind ?? DocKind.guess(fileName: url)))
    }

    /// Крестик у документа. Файл на Диске не стирается: «Отмена» должна вернуть
    /// документ, а копии группы везут тот же путь (веб `docsGone` при сохранении — итерация 31).
    public mutating func removeDoc(at i: Int) {
        guard docs.indices.contains(i) else { return }
        docs.remove(at: i)
    }
}

/// Подписи карточки документа (веб `renderDocs`, `refHost`, `refTail`, `docExt`, `docSize`).
public enum DocLabel {
    /// Верхняя строка: вид, а без вида — сайт у ссылки и расширение у файла.
    /// `kindName` — имя вида словарём; `fileWord` — «файл», когда расширения нет.
    public static func top(_ d: Attachment, kindName: (DocKind) -> String, fileWord: String, linkWord: String) -> String {
        if let k = d.kind { return kindName(k) }
        if d.source == .link { return host(d.url ?? "", linkWord: linkWord) }
        return ext(d.name ?? "") ?? fileWord
    }

    /// Нижняя строка: у ссылки — последний кусок пути, у файла — имя.
    public static func sub(_ d: Attachment, anyWord: String) -> String {
        if d.source == .link { return tail(d.url ?? "").split(separator: "/").last.map(String.init) ?? "" }
        return (d.name?.isEmpty == false ? d.name : nil) ?? anyWord
    }

    /// Сайт без `www.` (веб `refHost`); адрес не разобрался — `linkWord` («Ссылка»).
    public static func host(_ url: String, linkWord: String = "") -> String {
        guard let h = URLComponents(string: url)?.host, !h.isEmpty else { return linkWord }
        return h.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    /// Путь без крайних косых, не длиннее 42 знаков; пустой — сайт (веб `refTail`).
    public static func tail(_ url: String) -> String {
        guard let u = URLComponents(string: url), u.host?.isEmpty == false else { return String(url.prefix(42)) }
        var p = u.path
        if p.hasPrefix("/") { p.removeFirst() }
        if p.hasSuffix("/") { p.removeLast() }
        let t = String(p.prefix(42))
        return t.isEmpty ? (u.host ?? "") : t
    }

    /// Расширение прописными (веб `docExt`); без него — `nil`.
    public static func ext(_ name: String) -> String? {
        guard let r = name.range(of: "\\.([A-Za-z0-9]+)$", options: .regularExpression) else { return nil }
        return String(name[r].dropFirst()).uppercased()
    }
}
