import Testing
import Foundation

/// Шаг 30а.4: сверка слов en/es/ja/zh в `Tools/lang_native.json` (то, что приложение
/// говорит только на телефоне). Тест читает сам файл, а не каталог, поэтому идёт и на хосте.
///
/// Решения (DECISIONS 17.10): «студийный час» — русское понятие, в других языках просто «час».
/// «Зал студии» и «студия» — разные слова, и в одной строке их не мешаем:
///   зал     en room · es sala · ja ルーム · zh 拍摄厅
///   студия  en studio · es estudio · ja スタジオ · zh 影棚
/// Испанский везде на «ты». Носитель слова не проверял.
struct NativeWordingTests {

    private static let langs = ["en", "es", "ja", "zh"]

    private static func load() throws -> [String: [String: Any]] {
        let url = TextFixtures.root.appendingPathComponent("Tools/lang_native.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require(obj as? [String: [String: Any]])
    }

    private static func strings(_ lang: String) throws -> [String: String] {
        try load()[lang, default: [:]].compactMapValues { $0 as? String }
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        let re = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    // MARK: зал и студия

    /// Ключи, где речь о зале студии (ru: «выхода из зала», «Выбрать зал», «Добавить зал»).
    static let hallKeys = ["set.studioAlertNote", "form.hallPick", "form.hallAdd"]
    static let hallWord = ["en": "room", "es": "sala", "ja": "ルーム", "zh": "拍摄厅"]
    static let studioWord = ["en": "studio", "es": "estudio", "ja": "スタジオ", "zh": "影棚"]

    @Test func hallKeysUseTheRoomWordAndNeverTheStudioWord() throws {
        var bad: [String] = []
        for lang in Self.langs {
            let s = try Self.strings(lang)
            for key in Self.hallKeys {
                let text = try #require(s[key], "нет \(lang) \(key)")
                if !text.lowercased().contains(Self.hallWord[lang]!) { bad.append("\(lang) \(key): нет «\(Self.hallWord[lang]!)» — \(text)") }
                if text.lowercased().contains(Self.studioWord[lang]!) { bad.append("\(lang) \(key): слово студии в строке про зал — \(text)") }
            }
        }
        #expect(bad.isEmpty, Comment(rawValue: bad.joined(separator: "\n")))
    }

    @Test func noConcertHallAnywhere() throws {
        var bad: [String] = []
        for lang in Self.langs {
            for (key, text) in try Self.strings(lang) {
                if lang == "en", !Self.matches("(?i)\\bhalls?\\b", in: text).isEmpty { bad.append("en \(key): hall — \(text)") }
                if lang == "ja", text.contains("ホール") { bad.append("ja \(key): ホール — \(text)") }
                // «厅» без «拍摄» перед ним — не наш зал студии.
                if lang == "zh", !Self.matches("(?<!拍摄)厅", in: text).isEmpty { bad.append("zh \(key): голое 厅 — \(text)") }
            }
        }
        #expect(bad.isEmpty, Comment(rawValue: bad.joined(separator: "\n")))
    }

    @Test func studioHourPlateStaysWithoutStudioWord() throws {
        for lang in Self.langs {
            let text = try #require(try Self.strings(lang)["studio.askT"])
            #expect(!text.lowercased().contains(Self.studioWord[lang]!), "«студийный час» в \(lang) — просто «час»: \(text)")
        }
    }

    // MARK: испанский на «ты»

    /// Известные формы «usted». Список конечный: тест ловит их, а не всякое «вы» на свете.
    /// Формы глагола в начале предложения (после начала строки или . : ; ¿ ? ! —), потому что
    /// «puede» и «está» внутри фразы — обычное третье лицо («no se puede guardar», «no está en…»).
    static let ustedStarts = ["Puede", "Pueden", "Está", "Están", "Busque", "Elija", "Quite", "Vacíe", "Muévalo", "Muévala",
                              "Mueva", "Pulse", "Toque", "Seleccione", "Escriba", "Introduzca", "Añada", "Active", "Desactive",
                              "Permita", "Espere", "Intente", "Vuelva", "Compruebe", "Revise", "Verifique", "Reinicie", "Abra",
                              "Cierre", "Pruebe", "Mantenga", "Gire", "Deje", "Utilice", "Guarde", "Borre", "Elimine",
                              "Confirme", "Continúe", "Siga", "Acepte", "Deslice", "Arrastre", "Use", "Elíjalo", "Dígame"]
    /// Формы, которые «usted» в любом месте строки.
    static let ustedAnywhere = ["usted", "ustedes", "su", "sus", "suyo", "suya", "suyos", "suyas", "elija", "quite", "vacíe",
                                "vacíela", "muévalo", "muévala", "busque", "permita", "escriba", "pulse", "toque", "seleccione",
                                "introduzca", "intente", "vuelva", "espere", "compruebe", "verifique", "añada"]
    /// «dónde está», «donde está» — спрашивают про того, к кому обращаются.
    static let ustedPhrases = ["(?i)\\bd[oó]nde est[aá]\\b", "(?i)\\bque est[aá] (?:usted|ahí)\\b"]

    static func ustedPatterns() -> [String] {
        let starts = ustedStarts.joined(separator: "|")
        return ["(?:^|[.:;¿?!—]\\s*)(?:\(starts))\\b",
                "(?i)(?<![\\p{L}])(?:\(ustedAnywhere.joined(separator: "|")))(?![\\p{L}])"] + ustedPhrases
    }

    @Test func spanishSpeaksToTheReaderAsTu() throws {
        var bad: [String] = []
        for (key, text) in try Self.strings("es").sorted(by: { $0.key < $1.key }) {
            for p in Self.ustedPatterns() {
                for hit in Self.matches(p, in: text) { bad.append("es \(key): «\(hit.trimmingCharacters(in: .whitespaces))» — \(text)") }
            }
        }
        #expect(bad.isEmpty, Comment(rawValue: bad.joined(separator: "\n")))
    }

    @Test func theUstedListCatchesTheOldWording() {
        // Порча: строки до шага 30а.4 должны краснить проверку, иначе она ничего не ловит.
        let old = ["Muévalo si las estrellas importan.", "elija otra hora.", "quite la fecha de la repetición",
                   "Se queda hasta que vacíe la papelera", "Puede permitirlo en los ajustes", "No se pudo determinar dónde está.",
                   "Está lejos del lugar elegido", "Buscando su ubicación…", "AR muestra el cielo donde está."]
        for text in old {
            let hits = Self.ustedPatterns().flatMap { Self.matches($0, in: text) }
            #expect(!hits.isEmpty, "не поймана порча: \(text)")
        }
        let fine = ["No se puede guardar una sesión en un horario ocupado: elige otra hora.", "Lo que no está en ningún otro sitio",
                    "Estás lejos del lugar elegido", "Puedes permitirlo en los ajustes", "Buscando tu ubicación…"]
        for text in fine {
            let hits = Self.ustedPatterns().flatMap { Self.matches($0, in: text) }
            #expect(hits.isEmpty, "ложная тревога: \(text) → \(hits)")
        }
    }

    // MARK: китайский на «你»

    /// «您» — вежливое «вы». Приложение говорит «你» (шаги 30а.5 и 30а.6). Проверка идёт и по
    /// `lang_native.json` (слова только телефона), и по словам веба (`Fixtures/lang.json` из `beta/lang.js`):
    /// веб правили 17.10 только в словаре, «您» там сменили на «你» в 13 ключах.
    static let formalZh = "您"

    /// Словарь веба на одном языке: `Fixtures/lang.json`, строки идут в порядке `keys`.
    private static func webStrings(_ lang: String) throws -> [String: String] {
        let f = try TextFixtures.load("lang.json", as: TextFixtures.LangFile.self)
        let t = try #require(f.langs[lang]).t
        try #require(t.count == f.keys.count, "lang.json: \(lang) \(t.count) строк при \(f.keys.count) ключах")
        return Dictionary(uniqueKeysWithValues: zip(f.keys, t))
    }

    @Test func chineseSpeaksToTheReaderAsNi() throws {
        var bad: [String] = []
        for (key, text) in try Self.strings("zh").sorted(by: { $0.key < $1.key }) where text.contains(Self.formalZh) {
            bad.append("zh native \(key): \(text)")
        }
        for (key, text) in try Self.webStrings("zh").sorted(by: { $0.key < $1.key }) where text.contains(Self.formalZh) {
            bad.append("zh web \(key): \(text)")
        }
        #expect(bad.isEmpty, Comment(rawValue: bad.joined(separator: "\n")))
    }

    // MARK: слова веба: зал студии и студия (шаг 30а.6)

    /// `loc.wayStudioSub` — подпись кнопки «студия» в форме места: «зал, адрес и телефон» (ru не меняли).
    static let wayStudioSubHall = ["en": "room", "es": "sala", "ja": "ルーム", "zh": "拍摄厅"]
    /// Слова, которыми зал студии звали до 17.10 (концертный зал, «площадка»).
    static let wayStudioSubOld = ["en": "hall", "es": "salón", "ja": "ホール", "zh": "场地"]

    @Test func webWayStudioSubSaysRoomOfTheStudio() throws {
        var bad: [String] = []
        for lang in Self.langs {
            let text = try #require(try Self.webStrings(lang)["loc.wayStudioSub"], "нет \(lang) loc.wayStudioSub")
            if !text.lowercased().contains(Self.wayStudioSubHall[lang]!) { bad.append("\(lang): нет «\(Self.wayStudioSubHall[lang]!)» — \(text)") }
            if text.lowercased().contains(Self.wayStudioSubOld[lang]!) { bad.append("\(lang): старое «\(Self.wayStudioSubOld[lang]!)» — \(text)") }
        }
        #expect(bad.isEmpty, Comment(rawValue: bad.joined(separator: "\n")))
    }

    @Test func webWayStudioButtonIsStudioInJapanese() throws {
        #expect(try Self.webStrings("ja")["loc.wayStudio"] == "スタジオ", "кнопка «студия» в ja — «スタジオ», не «フォトスタジオ» (шире на SE на 0,8 pt)")
    }

    @Test func theFormalAndHallListsCatchTheOldWebWording() {
        // Порча: строки веба до 30а.6 должны краснить обе проверки.
        for text in ["您的号码就是对外的地址", "{err}。您的数据未受影响。"] { #expect(text.contains(Self.formalZh), "не поймана порча: \(text)") }
        let old = ["en": "hall, address and phone", "ja": "ホール、住所、電話番号", "zh": "场地、地址与电话"]
        for (lang, text) in old { #expect(text.lowercased().contains(Self.wayStudioSubOld[lang]!), "не поймана порча: \(text)") }
    }

    @Test func theFormalListCatchesTheOldWording() {
        // Порча: три строки до шага 30а.5 должны краснить проверку.
        let old = ["在您清空回收站前一直保留", "移除的图片会进入此情绪板的回收站，直到您清空前一直保留。", "在时段结束前10分钟和5分钟提醒您吗？"]
        for text in old { #expect(text.contains(Self.formalZh), "не поймана порча: \(text)") }
        for text in ["在你清空回收站前一直保留", "在时段结束前10分钟和5分钟提醒你吗？"] {
            #expect(!text.contains(Self.formalZh), "ложная тревога: \(text)")
        }
    }

    // MARK: слова веба: зал студии в пяти оставшихся ключах (шаг 30а.7)

    /// Ключи веба, где ru говорит «зал»: выход из зала, «без зала», выбор зала, поиск по залу.
    static let webHallKeys = ["studio.leaveIn", "studio.leaveNow", "form.hallNone", "form.pickHallAria", "loc.studioFindPh"]
    /// Слова, которыми зал звали до 30а.7: концертный «hall», «ホール», «厅» без «拍摄», «场地», «影棚厅»;
    /// а в zh ещё «影棚» вместо зала в трёх ключах (выход, «без зала», поиск).
    static let webHallOld: [String: [String]] = ["en": ["hall"], "ja": ["ホール"], "zh": ["场地", "影棚厅"]]

    private static func oldHallHits(_ lang: String, _ key: String, _ text: String) -> [String] {
        var hits = (webHallOld[lang] ?? []).filter { text.lowercased().contains($0) }
        if lang == "zh", !matches("(?<!拍摄)厅", in: text).isEmpty { hits.append("厅") }
        // «影棚» вместо зала: в «Выбрать зал студии» студия по смыслу есть, в остальных четырёх — нет.
        if lang == "zh", key != "form.pickHallAria", text.contains("影棚") { hits.append("影棚") }
        return hits
    }

    @Test func webHallKeysSayRoomNotHall() throws {
        var bad: [String] = []
        for lang in Self.langs {
            let s = try Self.webStrings(lang)
            for key in Self.webHallKeys {
                let text = try #require(s[key], "нет \(lang) \(key)")
                if !text.lowercased().contains(Self.hallWord[lang]!) { bad.append("\(lang) \(key): нет «\(Self.hallWord[lang]!)» — \(text)") }
                let hits = Self.oldHallHits(lang, key, text)
                if !hits.isEmpty { bad.append("\(lang) \(key): старое \(hits) — \(text)") }
            }
        }
        #expect(bad.isEmpty, Comment(rawValue: bad.joined(separator: "\n")))
    }

    @Test func theWebHallListCatchesTheOldWording() {
        // Порча: строки веба до 30а.7 должны краснить проверку.
        let old: [(String, String, String)] = [
            ("en", "studio.leaveNow", "Time to leave the hall. {where}."), ("en", "form.hallNone", "no hall"),
            ("en", "loc.studioFindPh", "Name, address or hall"),
            ("ja", "form.hallNone", "ホールなし"), ("ja", "form.pickHallAria", "スタジオのホールを選ぶ"),
            ("zh", "studio.leaveIn", "{left}后离开影棚。{where}。"), ("zh", "form.hallNone", "无影棚厅"),
            ("zh", "form.pickHallAria", "选择影棚厅"), ("zh", "loc.studioFindPh", "名称、地址或场地")]
        for (lang, key, text) in old { #expect(!Self.oldHallHits(lang, key, text).isEmpty, "не поймана порча: \(lang) \(key) \(text)") }
        for (lang, key, text) in [("zh", "form.hallNone", "无拍摄厅"), ("en", "form.pickHallAria", "Pick a studio room")] {
            #expect(Self.oldHallHits(lang, key, text).isEmpty, "ложная тревога: \(text)")
        }
    }

    // MARK: набор не разъехался

    @Test func fourLanguagesKeepTheSameKeysAsRussian() throws {
        let all = try Self.load()
        let ru = Set(try #require(all["ru"]).keys)
        for lang in Self.langs {
            #expect(Set(try #require(all[lang]).keys) == ru, "ключи \(lang) разошлись с ru")
        }
    }
}
