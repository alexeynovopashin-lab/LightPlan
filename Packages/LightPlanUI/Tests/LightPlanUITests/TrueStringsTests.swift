import Foundation
import Testing

@testable import LightPlanUI

/// Строки о данных человека говорят только то, что делает код (шаг 30в.10): ни одна старая неправда
/// не вернётся ни на одном языке, а новый текст называет то, что раньше отрицал. Файлы читаются как есть:
/// каталоги компилирует только Xcode, а эти обещания должны проверяться и под `swift test`.
@Suite("Правдивые строки о данных")
struct TrueStringsTests {

    /// Значения ключа по языкам из файла каталога.
    static func values(_ file: String, _ key: String) throws -> [String: String] {
        let url = TextFixtures.root.appendingPathComponent(file)
        let top = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(top["strings"] as? [String: Any])
        let entry = try #require(strings[key] as? [String: Any], "\(key): нет в \(file)")
        let locs = try #require(entry["localizations"] as? [String: [String: [String: String]]])
        return locs.compactMapValues { $0["stringUnit"]?["value"] }
    }

    static let catalog = "Packages/LightPlanUI/Sources/LightPlanUI/Resources/Localizable.xcstrings"
    static let plist = "App-iOS/InfoPlist.xcstrings"
    static let calendarKey = "NSCalendarsFullAccessUsageDescription"

    /// Старые слова о том, что сервера нет и ничего не уходит.
    static let noServerClaims: [String: [String]] = [
        "ru": ["не уходит ничего", "его нет"],
        "en": ["Nothing goes", "there is none"],
        "es": ["no va nada", "no existe"],
        "ja": ["何も送られません", "サーバーがありません"],
        "zh": ["没有任何数据", "因为不存在"],
    ]
    /// Что новый текст обязан назвать: наши серверы, телефоны, ссылки, координаты.
    static let privacyMust: [String: [String]] = [
        "ru": ["наши серверы", "телефоны", "ссылки", "координаты"],
        "en": ["our servers", "phone numbers", "links", "coordinates"],
        "es": ["nuestros servidores", "teléfonos", "enlaces", "coordenadas"],
        "ja": ["当方のサーバー", "電話番号", "リンク", "座標"],
        "zh": ["我们的服务器", "电话号码", "链接", "坐标"],
    ]
    /// Старые слова «только свой календарь, других не трогает» и «чужие события не трогает».
    static let onlyOwnClaims: [String: [String]] = [
        "ru": ["только свой календарь", "чужие события не трогает"],
        "en": ["only its own calendar", "never touches other events"],
        "es": ["solo ese calendario", "nunca toca otros eventos"],
        "ja": ["専用カレンダーだけ", "ほかの予定には触れず"],
        "zh-Hans": ["只读取和修改自己的日历", "不会触碰其他事件"],
    ]
    /// Что новый текст обязан назвать: другие календари, которые читаются по выбору человека.
    static let calendarMust: [String: String] = [
        "ru": "другие календари", "en": "other calendars", "es": "otros calendarios",
        "ja": "ほかのカレンダー", "zh-Hans": "其他日历",
    ]

    /// Геопозиция: старое «больше никуда» и обязательное слово о серверах маршрутов.
    static let locationKey = "NSLocationWhenInUseUsageDescription"
    static let macPlist = "App-macOS/InfoPlist.xcstrings"
    static let macLocationKey = "NSLocationUsageDescription"
    static let nowhereElseClaims: [String: String] = [
        "ru": "больше никуда не отправляются", "en": "not sent anywhere else", "es": "no se envían a ningún otro sitio",
        "ja": "それ以外には送信されません", "zh-Hans": "不会发送到其他任何地方",
    ]
    static let locationMust: [String: String] = [
        "ru": "серверы маршрутов", "en": "routing servers", "es": "servidores de rutas",
        "ja": "ルート検索サーバー", "zh-Hans": "路线服务器",
    ]
    /// Контакты: старое общее «ничего никуда» и обязательное слово о брони.
    static let contactsKey = "NSContactsUsageDescription"
    static let sendsNothingClaims: [String: String] = [
        "ru": "ничего никуда не отправляет", "en": "sends nothing anywhere", "es": "no envía nada a ningún sitio",
        "ja": "どこにも何も送信しません", "zh-Hans": "也不会向任何地方发送内容",
    ]
    static let contactsMust: [String: String] = [
        "ru": "брони", "en": "booking", "es": "reserva", "ja": "予約", "zh-Hans": "预订",
    ]

    @Test func locationTextNamesRoutesAndDropsNowhereElse() throws {
        for (file, key) in [(Self.plist, Self.locationKey), (Self.macPlist, Self.macLocationKey)] {
            let v = try Self.values(file, key)
            #expect(Set(v.keys) == Set(Self.locationMust.keys), "\(file)")
            for (lang, value) in v {
                #expect(!value.contains(Self.nowhereElseClaims[lang] ?? "—"), "\(file) \(lang): старое «больше никуда»")
                #expect(value.contains(Self.locationMust[lang] ?? "—"), "\(file) \(lang): не сказано о маршрутах")
            }
        }
    }

    @Test func contactsTextDropsSendsNothing() throws {
        let v = try Self.values(Self.plist, Self.contactsKey)
        #expect(Set(v.keys) == Set(Self.contactsMust.keys))
        for (lang, value) in v {
            #expect(!value.contains(Self.sendsNothingClaims[lang] ?? "—"), "\(lang): старое «ничего никуда»")
            #expect(value.contains(Self.contactsMust[lang] ?? "—"), "\(lang): не сказано о брони")
        }
    }

    @Test func privacyLineNoLongerDeniesServers() throws {
        let v = try Self.values(Self.catalog, "set.privacy")
        #expect(Set(v.keys).isSuperset(of: Self.noServerClaims.keys))
        for (lang, value) in v {
            for claim in Self.noServerClaims[lang] ?? [] { #expect(!value.contains(claim), "\(lang): \(claim)") }
            for word in Self.privacyMust[lang] ?? [] { #expect(value.contains(word), "\(lang): нет «\(word)»") }
        }
    }

    @Test func calendarTextAdmitsOtherCalendars() throws {
        let v = try Self.values(Self.plist, Self.calendarKey)
        #expect(Set(v.keys) == Set(Self.calendarMust.keys))
        for (lang, value) in v {
            for claim in Self.onlyOwnClaims[lang] ?? [] { #expect(!value.contains(claim), "\(lang): \(claim)") }
            #expect(value.contains(Self.calendarMust[lang] ?? "—"), "\(lang): не сказано о других календарях")
        }
    }

    /// Базовое значение сборки (`Config/*.xcconfig`) не должно остаться старым при новых переводах.
    @Test(arguments: [
        ("Config/iOS.xcconfig", plist, calendarKey), ("Config/iOS.xcconfig", plist, locationKey),
        ("Config/iOS.xcconfig", plist, contactsKey), ("Config/macOS.xcconfig", macPlist, macLocationKey),
    ])
    func baseValueIsTheEnglishTranslation(config: String, file: String, key: String) throws {
        let url = TextFixtures.root.appendingPathComponent(config)
        let prefix = "INFOPLIST_KEY_\(key) = "
        let line = try #require(try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
            .first { $0.hasPrefix(prefix) })
        let en = try #require(try Self.values(file, key)["en"])
        #expect(line.dropFirst(prefix.count) == en)
    }

    /// Каждый язык — настоящий перевод, а не русская копия.
    @Test func everyLanguageIsItsOwnTranslation() throws {
        for (file, key) in [(Self.catalog, "set.privacy"), (Self.plist, Self.calendarKey), (Self.plist, Self.locationKey),
                            (Self.plist, Self.contactsKey), (Self.macPlist, Self.macLocationKey)] {
            let v = try Self.values(file, key)
            #expect(Set(v.values).count == v.count, "\(key): одинаковые значения в разных языках")
            for (lang, value) in v where lang != "ru" {
                #expect(value.rangeOfCharacter(from: CharacterSet(charactersIn: "а"..."я")) == nil, "\(key) (\(lang)): кириллица")
            }
        }
    }

    /// Что записано в источнике слова (`Tools/lang_fixes.json`): этого ждут и каталог, и экран.
    static func privacySource() throws -> [String: String] {
        let url = TextFixtures.root.appendingPathComponent("Tools/lang_fixes.json")
        let obj = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: [String: String]]])
        return obj.compactMapValues { $0["set.privacy"]?["app"] }
    }

    @Test func catalogHoldsTheSourceWording() throws {
        let want = try Self.privacySource()
        #expect(Set(want.keys) == Set(Self.noServerClaims.keys))
        let have = try Self.values(Self.catalog, "set.privacy")
        for (lang, text) in want {
            #expect(!text.isEmpty, "\(lang): пусто в источнике")
            #expect(have[lang] == text, "\(lang): каталог разошёлся с источником")
        }
    }

    /// То, что доходит до экрана: собранный каталог отдаёт ровно этот текст, не пустой и не посторонний
    /// (замечание ревью f199ab8; под `swift test` каталога нет).
    @Test(.enabled(if: catalogCompiled, "каталог не скомпилирован"))
    func compiledLineIsTheSourceWording() throws {
        let want = try Self.privacySource()
        for lang in ["ru", "en", "en-GB", "en-US", "es", "ja", "zh"] {
            let expected = try #require(want[String(lang.prefix(2))])
            #expect(Lexicon(lang).t("set.privacy") == expected, "\(lang)")
        }
    }
}
