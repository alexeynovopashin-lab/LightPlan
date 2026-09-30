import Foundation
import LightPlanCore

/// Ответ клиента по опроснику: 25 известных ключей, только строки (веб `QUEST_KEYS`, `questDecode`;
/// итерация 28, шаг 8; справка `docs/quest_reference.md` § 1).
public struct QuestAnswer: Sendable, Equatable {
    /// Ключи страницы `quest/wedding.html` (`FIELDS`), порядок веба.
    public static let keys = ["b", "bt", "bs", "bm", "g", "gt", "d", "z", "vn", "vy", "q", "n",
                              "pr", "sv", "vd", "au", "ko", "pl", "mu", "fi", "zh",
                              "re", "ms", "w", "pin"]
    /// Длиннее — обрезается (веб `slice(0, 600)` по единицам UTF-16, как `String.length` в JS).
    public static let maxLength = 600

    /// Непустые значения известных ключей, уже без пробелов по краям и не длиннее `maxLength`.
    public let values: [String: String]
    /// Ключи, чей ответ был длиннее `maxLength` и потерял хвост. Веб терял его молча (ошибка веба А5).
    public let truncated: Set<String>

    public init(values: [String: String], truncated: Set<String> = []) {
        self.values = values
        self.truncated = truncated
    }

    public subscript(key: String) -> String? { values[key] }
    public var isEmpty: Bool { values.isEmpty }
    public var wasTruncated: Bool { !truncated.isEmpty }
}

/// Что пришло от клиента: ничего похожего на ответ / ответ испорчен / ответ и знак записи.
public enum QuestIncoming: Sendable, Equatable {
    /// В тексте нет `ans=` (вставка: `quest.pasteBad`).
    case noAnswer
    /// Код есть, но не читается (баннер `quest.badTitle`) — не падение, а состояние.
    case bad(QuestFailure)
    /// `recordId` — знак записи `r`, если он был в ссылке и его вид знакомый.
    case answer(QuestAnswer, recordId: String?)
}

public enum QuestFailure: Error, Sendable, Equatable {
    /// Не base64url.
    case notCode
    /// Не JSON.
    case notJSON
    /// JSON, но не объект (массив, число, `null`).
    case notObject
    /// Объект, но ни одного знакомого непустого ключа.
    case empty
}

public enum QuestParse {

    /// `ans=` где угодно во вставленном тексте: годится и адрес, и сообщение целиком (веб `#qPasteBtn`, L31539).
    public static func code(in text: String) -> String? {
        firstMatch(#"[?&]ans=([A-Za-z0-9_-]+)"#, in: text)
    }

    /// Знак записи `r`: тот же вид, что пропускает страница (`^[a-z0-9]{1,32}$`), чужое — отбрасывается.
    /// Ищется только в той же ссылке, что и `ans`: ссылка — участок вокруг него без пробелов и без `; , ( ) < > " '`,
    /// обрезанный по началу соседнего `http://` или `https://` в любом регистре (две ссылки вплотную) и по `#`. Промежуточные параметры,
    /// что дописал мессенджер (`source=photo.story`, `%20`), ссылку не рвут (ревью GPT к faaca1a, ee940f1, 6e55097).
    public static func recordId(in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"[?&]ans=[A-Za-z0-9_-]+"#),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text) else { return nil }
        func stops(_ c: Character) -> Bool { c.isWhitespace || ";,()<>\"'".contains(c) }
        var lo = r.lowerBound, hi = r.upperBound
        while lo > text.startIndex, !stops(text[text.index(before: lo)]) { lo = text.index(before: lo) }
        while hi < text.endIndex, !stops(text[hi]) { hi = text.index(after: hi) }
        // Соседняя ссылка вплотную: начало своей — последнее «http(s)://» до `ans`, конец — первое после его начала.
        for scheme in ["https://", "http://"] {
            var from = lo
            while let s = text.range(of: scheme, options: .caseInsensitive, range: from..<hi) {
                if s.lowerBound <= r.lowerBound { lo = max(lo, s.lowerBound) } else { hi = min(hi, s.lowerBound); break }
                from = s.upperBound
            }
        }
        // `#` — уже не строка запроса: знак во фрагменте не в счёт.
        if let hash = text[r.upperBound..<hi].firstIndex(of: "#") { hi = hash }
        return firstMatch(#"[?&]r=([a-z0-9]{1,32})(?![A-Za-z0-9_-])"#, in: String(text[lo..<hi]))
    }

    /// Ссылка или вставленный текст → ответ. Один путь и для ссылки, и для вставки.
    public static func receive(_ text: String) -> QuestIncoming {
        guard let code = code(in: text) else { return .noAnswer }
        switch decode(code) {
        case .success(let a): return .answer(a, recordId: recordId(in: text))
        case .failure(let f): return .bad(f)
        }
    }

    /// base64url → байты UTF-8 → JSON-объект → известные ключи (веб `questDecode`).
    public static func decode(_ code: String) -> Result<QuestAnswer, QuestFailure> {
        var b = code.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let data = Data(base64Encoded: b) else { return .failure(.notCode) }
        // Как `TextDecoder` веба: испорченные байты — знак замены, а не отказ.
        let text = String(decoding: data, as: UTF8.self)
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        else { return .failure(.notJSON) }
        guard let object = json as? [String: Any] else { return .failure(.notObject) }
        var values: [String: String] = [:]
        var cut: Set<String> = []
        for k in QuestAnswer.keys {
            // Только строки: `NSNumber` и `true` строкой не считаются.
            guard let s = object[k] as? String else { continue }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if t.utf16.count > QuestAnswer.maxLength {
                values[k] = String(decoding: Array(t.utf16.prefix(QuestAnswer.maxLength)), as: UTF16.self)
                cut.insert(k)
            } else {
                values[k] = t
            }
        }
        return values.isEmpty ? .failure(.empty) : .success(QuestAnswer(values: values, truncated: cut))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

/// Поля формы записи, которых касается сверка: имена и телефоны пары и заметки.
public struct QuestForm: Sendable, Equatable {
    public var p1Name: String
    public var p2Name: String
    public var p1Phone: String
    public var p2Phone: String
    public var notes: String
    /// Пара есть не у всякого жанра. Нет пары — имена и телефоны уходят строками в заметки.
    public var hasPair: Bool

    public init(p1Name: String = "", p2Name: String = "", p1Phone: String = "", p2Phone: String = "",
                notes: String = "", hasPair: Bool = true) {
        self.p1Name = p1Name; self.p2Name = p2Name
        self.p1Phone = p1Phone; self.p2Phone = p2Phone
        self.notes = notes; self.hasPair = hasPair
    }
}

/// Слова для заметки: домен не знает языков, приложение передаёт свой каталог (веб `LANG.t`).
public struct QuestLabels: Sendable {
    /// Слово по ключу каталога: `quest.head`, `person.bride`, `form.phone`, `pane.guests`…
    public var text: @Sendable (String) -> String
    /// Дата словами языка приложения (веб `dMonYear`).
    public var date: @Sendable (CivilDate) -> String

    public init(text: @escaping @Sendable (String) -> String, date: @escaping @Sendable (CivilDate) -> String) {
        self.text = text
        self.date = date
    }
}

/// Итог сверки: новая форма, расхождения, признак повтора.
public struct QuestReport: Sendable, Equatable {
    public var form: QuestForm
    /// Строки «<Роль>: было / ответ»; в заметку они уже вписаны (последним абзацем), если ответ не повтор.
    public var clash: [String]
    /// Этот же ответ уже лежит в заметках — второй блок «Из опроса» не дописан (ошибка веба А4).
    public var alreadyApplied: Bool
    /// Ключи, у которых ответ обрезан до 600 знаков (ошибка веба А5).
    public var truncated: Set<String>
}

public enum QuestMerge {

    /// Веб `nameKey`: регистр, «ё» → «е», пробелы. «Лена» и «Елена» разойдутся — терпимый шум веба, повторён один в один.
    public static func nameKey(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "ё", with: "е")
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Веб `questApply` без экрана. Пустое поле заполняется молча, занятое не трогается, расхождение уходит
    /// абзацем в заметки; заметки фотографа остаются сверху. Тот же ответ второй раз заметки не меняет.
    public static func apply(_ a: QuestAnswer, to form: QuestForm, country: TelCountry, labels: QuestLabels) -> QuestReport {
        var f = form
        var clash: [String] = []
        let t = labels.text

        func put(_ cur: inout String, _ val: String?, _ role: String, same: (String, String) -> Bool) {
            guard let val, !val.isEmpty else { return }
            let now = cur.trimmingCharacters(in: .whitespacesAndNewlines)
            if now.isEmpty { cur = val; return }
            if !same(now, val) { clash.append(t(role) + ": " + now + " / " + val) }
        }
        let sameName: (String, String) -> Bool = { nameKey($0) == nameKey($1) }
        let sameTel: (String, String) -> Bool = { TelFormat.full($0, country: country) == TelFormat.full($1, country: country) }
        func phone(_ v: String?) -> String? {
            v.map { TelFormat.format($0, country: country, pasted: true) }
        }

        if f.hasPair {
            put(&f.p1Name, a["b"], "person.bride", same: sameName)
            put(&f.p2Name, a["g"], "person.groom", same: sameName)
            put(&f.p1Phone, phone(a["bt"]), "person.bride", same: sameTel)
            put(&f.p2Phone, phone(a["gt"]), "person.groom", same: sameTel)
        }

        var lines: [String] = []
        func line(_ key: String, _ v: String?) { if let v, !v.isEmpty { lines.append(t(key) + ": " + v) } }
        if !f.hasPair {
            line("person.bride", a["b"]); line("form.phone", a["bt"])
            line("person.groom", a["g"]); line("form.phone", a["gt"])
        }
        line("quest.social", a["bs"])
        line("quest.msgr", a["bm"])
        line("quest.date", a["d"].map { date($0, labels) })
        line("quest.reg", a["z"])
        line("quest.church", a["vn"])
        line("quest.offsite", a["vy"])
        line("quest.party", a["q"])
        line("pane.guests", a["n"])
        line("quest.parents", a["pr"])
        line("quest.witnesses", a["sv"])
        line("quest.host", a["vd"])
        line("quest.car", a["au"])
        line("quest.suit", a["ko"])
        line("quest.dress", a["pl"])
        line("quest.music", a["mu"])
        line("quest.finale", a["fi"])
        line("quest.pets", a["zh"])

        var parts: [String] = []
        if !lines.isEmpty { parts.append(t("quest.head") + "\n" + lines.joined(separator: "\n")) }
        for (key, v) in [("quest.rites", a["re"]), ("quest.places", a["ms"]), ("quest.wishes", a["w"]), ("quest.pin", a["pin"])] {
            if let v, !v.isEmpty { parts.append(t(key) + ": " + v) }
        }
        let block = parts.joined(separator: "\n\n")

        // Тот же ответ уже в заметках: второй блок не дописываем, расхождения тоже (они стоят под первым).
        // Ответ, где нет ничего кроме имён пары, блока не даёт — тогда повтор узнаётся по абзацу расхождений.
        let clashPart = clash.isEmpty ? "" : t("quest.clash") + "\n" + clash.joined(separator: "\n")
        let was = f.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let seen = block.isEmpty ? clashPart : block
        let repeated = !seen.isEmpty && containsWhole(was, seen)
        if !repeated {
            if !clashPart.isEmpty { parts.append(clashPart) }
            if !parts.isEmpty { f.notes = (was.isEmpty ? "" : was + "\n\n") + parts.joined(separator: "\n\n") }
        }
        return QuestReport(form: f, clash: clash, alreadyApplied: repeated, truncated: a.truncated)
    }

    /// `piece` стоит в `text` целыми абзацами: до него начало текста или пустая строка, после — конец или пустая строка.
    /// Простой `contains` принял бы новый ответ «Х» за уже применённый «ХХ» (ревью GPT к faaca1a).
    static func containsWhole(_ text: String, _ piece: String) -> Bool {
        var from = text.startIndex
        while let r = text.range(of: piece, range: from..<text.endIndex) {
            let before = text[..<r.lowerBound], after = text[r.upperBound...]
            if (before.isEmpty || before.hasSuffix("\n\n")) && (after.isEmpty || after.hasPrefix("\n\n")) { return true }
            from = text.index(after: r.lowerBound)
        }
        return false
    }

    /// Веб `questDate`: `2027-06-15` → словами; не дата — как пришло. Несуществующее число (30 февраля) — тоже как
    /// пришло: `new Date` веба перекатил бы его на март (отход обратим).
    static func date(_ iso: String, _ labels: QuestLabels) -> String {
        let p = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
              (1...12).contains(m), d >= 1, d <= daysIn(month: m, year: y) else { return iso }
        return labels.date(CivilDate(year: y, month: m, day: d))
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}
