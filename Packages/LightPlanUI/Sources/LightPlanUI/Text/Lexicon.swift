import Foundation
import Synchronization

/// Словарь экрана: то же, что `LANG` в `beta/lang.js`.
///
/// Строки лежат в `Resources/Localizable.xcstrings`, который собирает
/// `Tools/lang2xcstrings.js`. Язык выбирается здесь явно, цепочкой, как в вебе,
/// а не системными настройками: в вебе язык — настройка приложения (`LANG.set`),
/// и Swift-версия обязана вести себя так же, пока Алексей не решил иначе.
///
/// **Цепочка.** Сам говор, его основа, английский: у `en-US` это
/// `["en-US", "en"]`, у `ru` — `["ru", "en"]`. Ключа нет ни в одном звене —
/// возвращается сам ключ: пропажа должна быть видна на экране.
///
/// **Склонение.** Слово по формам числа платформа берёт из каталога сама
/// (правила CLDR), но каталог требует, чтобы форма ссылалась на число, а веб
/// отдаёт слово без числа. Форма поэтому хранится как `число` + метка + слово;
/// `word` берёт то, что после метки, `count` собирает число, разделитель
/// языка и слово. Правило числа и разделитель принадлежат языку слова, а не
/// языку экрана: запасное английское слово на японском экране остаётся
/// английским («3 shoots»).
public struct Lexicon: Sendable {

    public let code: String
    private let bundle: Bundle

    public init(_ code: String = "ru") {
        self.init(code, bundle: .module)
    }

    /// Тесты подсовывают свой каталог: настоящий полон, и пропажу ключа в нём
    /// не показать.
    init(_ code: String, bundle: Bundle) {
        self.code = code
        self.bundle = bundle
    }

    // MARK: - Языки

    /// Метка между числом и словом в форме множественного числа. Совпадает с
    /// `MARK` в `Tools/lang2xcstrings.js`.
    static let mark: Character = "\u{2063}"

    public static func base(_ code: String) -> String {
        String(code.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    /// Сам говор, его основа и английский последним рубежом.
    public static func chain(_ code: String) -> [String] {
        var out = [code]
        let b = base(code)
        if b != code { out.append(b) }
        if b != "en" { out.append("en") }
        return out
    }

    /// Языки, у которых заведено правило числа. Словарь может быть пуст:
    /// экран тогда уедет в английский по ключам.
    public static func known(_ code: String) -> Bool {
        rules[code] != nil || rules[base(code)] != nil
    }

    /// Есть ли у языка слова — считая по всей цепочке, как `LANG.has`.
    public static func has(_ code: String) -> Bool {
        has(code, bundle: .module)
    }

    static func has(_ code: String, bundle: Bundle) -> Bool {
        for c in chain(code) where c != "en" {
            if Self.languageBundle(c, in: bundle) != nil { return true }
        }
        return code == "en" || base(code) == "en"
    }

    /// Есть ли ключ в словаре самого языка, без цепочки. Нужно сверке состава.
    func defines(_ key: String, language: String) -> Bool {
        guard let b = Self.languageBundle(language, in: bundle) else { return false }
        let sentinel = "\u{1}missing\u{1}"
        return b.localizedString(forKey: key, value: sentinel, table: nil) != sentinel
    }

    // MARK: - Правило числа

    /// Номер формы слова для числа. Не слово: слово знает словарь.
    private static let rules: [String: @Sendable (Int) -> Int] = [
        "ru": { n in
            let t = n % 100, o = n % 10
            if t >= 11 && t <= 14 { return 2 }
            if o == 1 { return 0 }
            if o >= 2 && o <= 4 { return 1 }
            return 2
        },
        "en": { n in n == 1 ? 0 : 1 },
        "es": { n in n == 1 ? 0 : 1 },
        "ja": { _ in 0 },
        "zh": { _ in 0 },
    ]

    /// Разделитель между числом и словом. У ru, en, es они — разные слова, у
    /// ja и zh счётное слово прилипает к числу.
    private static let countSep: [String: String] = ["ru": " ", "en": " ", "es": " ", "ja": "", "zh": ""]

    private static func rule(_ code: String) -> @Sendable (Int) -> Int {
        rules[code] ?? rules[base(code)] ?? rules["en"]!
    }

    private static func sep(ofLanguage code: String) -> String {
        countSep[code] ?? countSep[base(code)] ?? " "
    }

    /// Номер формы по правилу языка экрана.
    public func index(_ n: Int) -> Int { Self.rule(code)(n) }

    /// То же по названному языку.
    public func index(in language: String, _ n: Int) -> Int { Self.rule(language)(n) }

    // MARK: - Поиск ключа

    private struct Found {
        let raw: String
        let language: String
        let isPlural: Bool
    }

    /// Пустой словарь не должен показывать список ключей: ищем по цепочке.
    /// `sentinel` — значение, которого в каталоге быть не может: по нему
    /// «ключа нет» отличается от ключа с любым настоящим значением.
    private func find(_ key: String) -> Found? {
        let sentinel = "\u{1}missing\u{1}"
        for c in Self.chain(code) {
            guard let b = Self.languageBundle(c, in: bundle) else { continue }
            let raw = b.localizedString(forKey: key, value: sentinel, table: nil)
            if raw != sentinel { return Found(raw: raw, language: c, isPlural: raw.contains("%#@")) }
        }
        return nil
    }

    /// Кэш подпапок языков. Папка `xx.lproj` в собранном ресурсе — то, что из
    /// каталога сделал Xcode; нет папки — у языка нет ни одного слова.
    private static let cache = Mutex<[String: Bundle?]>([:])

    private static func languageBundle(_ language: String, in bundle: Bundle) -> Bundle? {
        let id = bundle.bundlePath + "|" + language
        return cache.withLock { store in
            if let hit = store[id] { return hit }
            let made = bundle.path(forResource: language, ofType: "lproj").flatMap { Bundle(path: $0) }
            store[id] = .some(made)
            return made
        }
    }

    /// Слово, развёрнутое по числу: число как его написала платформа, слово.
    private func expand(_ found: Found, _ n: Int) -> (number: String, word: String) {
        let text = String(format: found.raw, locale: Locale(identifier: found.language), n)
        guard let i = text.firstIndex(of: Self.mark) else { return (String(n), text) }
        return (String(text[..<i]), String(text[text.index(after: i)...]))
    }

    // MARK: - Строки

    /// Строка по ключу. Подстановка по имени, а не по порядку: в другом языке
    /// порядок слов другой. Ключ-слово без числа отдаёт первую форму, как
    /// `LANG.t`: у всех правил единица — форма 0.
    public func t(_ key: String, _ vars: [String: String]? = nil) -> String {
        guard let found = find(key) else { return key }
        let s = found.isPlural ? expand(found, 1).word : found.raw
        guard let vars else { return s }
        return Self.substitute(s, vars)
    }

    /// `{name}` → значение. `\w` веба — только ASCII-буквы, цифры и `_`;
    /// разбор руками, а не регуляркой, чтобы `\w` не поумнел до юникода.
    /// Имени нет в словаре подстановок — остаётся как было, `{name}`.
    static func substitute(_ s: String, _ vars: [String: String]) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "{", let close = s[i...].firstIndex(of: "}") {
                let name = s[s.index(after: i)..<close]
                if !name.isEmpty, name.unicodeScalars.allSatisfy({ isWordScalar($0) }) {
                    out += vars[String(name)] ?? String(s[i...close])
                    i = s.index(after: close)
                    continue
                }
            }
            out.append(ch)
            i = s.index(after: i)
        }
        return out
    }

    private static func isWordScalar(_ u: Unicode.Scalar) -> Bool {
        (u.value >= 48 && u.value <= 57) || (u.value >= 65 && u.value <= 90)
            || (u.value >= 97 && u.value <= 122) || u.value == 95
    }

    /// Слово, согласованное с числом. Самого числа не подставляет.
    public func word(_ key: String, _ n: Int) -> String {
        guard let found = find(key), found.isPlural else { return t(key) }
        return expand(found, n).word
    }

    /// Число со словом: «3 съёмки», «12 часов», «12件».
    public func count(_ key: String, _ n: Int) -> String {
        String(n) + sep(key) + word(key, n)
    }

    /// Разделитель между числом и словом этого ключа — там, где число набрано
    /// отдельно другим начертанием и `count` собрать строку не может.
    public func sep(_ key: String) -> String {
        Self.sep(ofLanguage: find(key)?.language ?? code)
    }
}
