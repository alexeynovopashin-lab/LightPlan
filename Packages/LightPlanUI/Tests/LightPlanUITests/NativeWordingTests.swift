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

    /// «您» — вежливое «вы». Приложение говорит «你» (шаг 30а.5). Проверка идёт по `lang_native.json`:
    /// у слов веба (`beta/lang.js`, заморожен) «您» стоит в 13 ключах, их приложение не переопределяет.
    static let formalZh = "您"

    @Test func chineseSpeaksToTheReaderAsNi() throws {
        var bad: [String] = []
        for (key, text) in try Self.strings("zh").sorted(by: { $0.key < $1.key }) where text.contains(Self.formalZh) {
            bad.append("zh \(key): \(text)")
        }
        #expect(bad.isEmpty, Comment(rawValue: bad.joined(separator: "\n")))
    }

    @Test func theFormalListCatchesTheOldWording() {
        // Порча: три строки до шага 30а.5 должны краснить проверку.
        let old = ["在您清空回收站前一直保留", "移除的图片会进入此情绪板的回收站，直到您清空前一直保留。", "在时段结束前10分钟和5分钟提醒您吗？"]
        for text in old { #expect(text.contains(Self.formalZh), "не поймана порча: \(text)") }
        for text in ["在你清空回收站前一直保留", "在时段结束前10分钟和5分钟提醒你吗？"] {
            #expect(!text.contains(Self.formalZh), "ложная тревога: \(text)")
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
