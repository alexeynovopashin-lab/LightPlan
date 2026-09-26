import Foundation

/// Страна телефонной нумерации (веб `TEL_CC`, L25306–25334): код, магистральный
/// префикс, длины национального номера, образец разрядов и образец мобильного.
public struct TelCountry: Sendable, Hashable {
    public let iso: String
    public let cc: String
    public let trunk: String
    /// Допустимые длины национального номера; пусто — не меряется (DE, IT).
    public let nsn: [Int]
    /// Образец разрядов: «#» — цифра, остальное печатается как есть.
    public let format: String
    /// Регулярное выражение мобильного национального номера (с якорями).
    public let mobile: String
    /// Образец местного мобильного — пример под списком стран.
    public let example: String

    public static let all: [TelCountry] = [
        .init(iso: "RU", cc: "7", trunk: "8", nsn: [10], format: "### ###-##-##", mobile: "^9\\d{9}$", example: "9261234567"),
        .init(iso: "KZ", cc: "7", trunk: "8", nsn: [10], format: "### ###-##-##", mobile: "^7\\d{9}$", example: "7011234567"),
        .init(iso: "BY", cc: "375", trunk: "80", nsn: [9], format: "## ###-##-##", mobile: "^(25|29|33|44)\\d{7}$", example: "291234567"),
        .init(iso: "UA", cc: "380", trunk: "0", nsn: [9], format: "## ###-##-##", mobile: "^(39|50|63|66|67|68|9[1-9])\\d{7}$", example: "671234567"),
        .init(iso: "UZ", cc: "998", trunk: "8", nsn: [9], format: "## ### ## ##", mobile: "^(9[0-9]|33|77|88)\\d{7}$", example: "901234567"),
        .init(iso: "GE", cc: "995", trunk: "0", nsn: [9], format: "### ## ## ##", mobile: "^5\\d{8}$", example: "555123456"),
        .init(iso: "AM", cc: "374", trunk: "0", nsn: [8], format: "## ## ## ##", mobile: "^(4[139]|55|77|9[1-9])\\d{6}$", example: "77123456"),
        .init(iso: "AZ", cc: "994", trunk: "0", nsn: [9], format: "## ###-##-##", mobile: "^(10|5[015]|7[07]|99)\\d{7}$", example: "501234567"),
        .init(iso: "US", cc: "1", trunk: "1", nsn: [10], format: "### ###-####", mobile: "^[2-9]\\d{9}$", example: "2125550123"),
        .init(iso: "CA", cc: "1", trunk: "1", nsn: [10], format: "### ###-####", mobile: "^[2-9]\\d{9}$", example: "4165550123"),
        .init(iso: "GB", cc: "44", trunk: "0", nsn: [10], format: "#### ######", mobile: "^7[1-9]\\d{8}$", example: "7911123456"),
        .init(iso: "ES", cc: "34", trunk: "", nsn: [9], format: "### ### ###", mobile: "^[67]\\d{8}$", example: "612345678"),
        .init(iso: "PT", cc: "351", trunk: "", nsn: [9], format: "### ### ###", mobile: "^9[1236]\\d{7}$", example: "912345678"),
        .init(iso: "FR", cc: "33", trunk: "0", nsn: [9], format: "# ## ## ## ##", mobile: "^[67]\\d{8}$", example: "612345678"),
        .init(iso: "DE", cc: "49", trunk: "0", nsn: [], format: "### #######", mobile: "^1[5-7]\\d{7,9}$", example: "1512345678"),
        .init(iso: "IT", cc: "39", trunk: "", nsn: [], format: "### ### ####", mobile: "^3\\d{8,9}$", example: "3121234567"),
        .init(iso: "PL", cc: "48", trunk: "", nsn: [9], format: "### ### ###", mobile: "^[45-8]\\d{8}$", example: "512345678"),
        .init(iso: "NL", cc: "31", trunk: "0", nsn: [9], format: "# ########", mobile: "^6\\d{8}$", example: "612345678"),
        .init(iso: "TR", cc: "90", trunk: "0", nsn: [10], format: "### ### ## ##", mobile: "^5\\d{9}$", example: "5321234567"),
        .init(iso: "AE", cc: "971", trunk: "0", nsn: [9], format: "## ### ####", mobile: "^5[0245689]\\d{7}$", example: "501234567"),
        .init(iso: "IL", cc: "972", trunk: "0", nsn: [9], format: "##-###-####", mobile: "^5\\d{8}$", example: "501234567"),
        .init(iso: "TH", cc: "66", trunk: "0", nsn: [9], format: "## ### ####", mobile: "^[689]\\d{8}$", example: "812345678"),
        .init(iso: "IN", cc: "91", trunk: "0", nsn: [10], format: "##### #####", mobile: "^[6-9]\\d{9}$", example: "9812345678"),
        .init(iso: "CN", cc: "86", trunk: "", nsn: [11], format: "### #### ####", mobile: "^1[3-9]\\d{9}$", example: "13812345678"),
        .init(iso: "JP", cc: "81", trunk: "0", nsn: [10], format: "##-####-####", mobile: "^[789]0\\d{8}$", example: "9012345678"),
        .init(iso: "BR", cc: "55", trunk: "0", nsn: [10, 11], format: "## #####-####", mobile: "^\\d{2}9\\d{8}$", example: "11912345678"),
        .init(iso: "MX", cc: "52", trunk: "0", nsn: [10], format: "## #### ####", mobile: "^[1-9]\\d{9}$", example: "5512345678"),
    ]

    public static func of(_ iso: String) -> TelCountry? { all.first { $0.iso == iso } }
    public static let fallback = all[0]

    /// Догадка по часовому поясу, потом по региону языка, иначе Россия
    /// (веб `guessTelCountry`, L25344–25370).
    public static func guess(zoneId: String, region: String? = nil) -> TelCountry {
        let byZone: [String: String] = [
            "Europe/London": "GB", "Europe/Madrid": "ES", "Atlantic/Canary": "ES",
            "Europe/Lisbon": "PT", "Europe/Paris": "FR", "Europe/Berlin": "DE",
            "Europe/Rome": "IT", "Europe/Warsaw": "PL", "Europe/Amsterdam": "NL",
            "Europe/Istanbul": "TR", "Europe/Minsk": "BY", "Europe/Kiev": "UA",
            "Europe/Kyiv": "UA", "Asia/Tbilisi": "GE", "Asia/Yerevan": "AM",
            "Asia/Baku": "AZ", "Asia/Tashkent": "UZ", "Asia/Samarkand": "UZ",
            "Asia/Almaty": "KZ", "Asia/Aqtobe": "KZ", "Asia/Atyrau": "KZ",
            "Asia/Dubai": "AE", "Asia/Jerusalem": "IL", "Asia/Bangkok": "TH",
            "Asia/Kolkata": "IN", "Asia/Calcutta": "IN", "Asia/Shanghai": "CN",
            "Asia/Tokyo": "JP", "America/Sao_Paulo": "BR", "America/Mexico_City": "MX",
            "America/Toronto": "CA", "America/Vancouver": "CA", "America/Edmonton": "CA",
            "America/Winnipeg": "CA", "America/Halifax": "CA",
        ]
        if let iso = byZone[zoneId], let c = of(iso) { return c }
        let ru = "^(Europe/(Moscow|Kaliningrad|Samara|Volgograd|Saratov|Astrakhan|Ulyanovsk|Kirov)|Asia/(Yekaterinburg|Omsk|Novosibirsk|Krasnoyarsk|Irkutsk|Yakutsk|Vladivostok|Magadan|Kamchatka|Sakhalin|Barnaul|Tomsk|Novokuznetsk|Chita|Khandyga|Ust-Nera|Srednekolymsk|Anadyr))$"
        if zoneId.range(of: ru, options: .regularExpression) != nil { return of("RU")! }
        if zoneId.hasPrefix("America/") { return of("US")! }
        if let region, let c = of(region) { return c }
        return fallback
    }

    /// Остаток похож на местный национальный номер: длина сошлась (у DE и IT — образец мобильного).
    func nsnOk(_ n: String) -> Bool {
        if !nsn.isEmpty { return nsn.contains(n.count) }
        return n.range(of: mobile, options: .regularExpression) != nil
    }
    /// «Ещё влезает» — для поля, где номер набирается по цифре.
    func nsnFits(_ n: String) -> Bool { n.count <= (nsn.max() ?? 11) }
}

/// Телефон: разряды при вводе, международный вид, ID приложения — то же, что
/// `formatTel`, `telFull`, `telMobile`, `appId` веба (L25442–25705). Хранится
/// строка, как её показали, — ключом служит `full`, не строка.
public enum TelFormat {

    /// Разбить набранное по образцу страны. `pasted` — номер пришёл разом
    /// (автозаполнение, буфер) или вырос без «+»: тогда недостающая
    /// ведущая часть возвращается на место.
    public static func format(_ value: String, country sp: TelCountry, pasted: Bool = false) -> String {
        let plus = value.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("+")
        var d = digits(value)
        if d.isEmpty { return plus ? "+" : "" }
        let head = plus ? sp.cc : (sp.trunk.isEmpty ? sp.cc : sp.trunk)
        if pasted, sp.nsnOk(d), !d.hasPrefix(head) { d = head + d }
        var lead = "", rest = d
        if plus {
            if !d.hasPrefix(sp.cc) { return "+" + d }
            lead = "+" + sp.cc + " "
            rest = String(d.dropFirst(sp.cc.count))
        } else if !sp.trunk.isEmpty, d.hasPrefix(sp.trunk) {
            lead = sp.trunk + (sp.trunk == "0" ? "" : " ")
            rest = String(d.dropFirst(sp.trunk.count))
        } else if d.hasPrefix(sp.cc), sp.nsnFits(String(d.dropFirst(sp.cc.count))) {
            lead = sp.cc + " "
            rest = String(d.dropFirst(sp.cc.count))
        }
        var out = lead + groups(rest, sp.format)
        while out.last?.isWhitespace == true { out.removeLast() }
        return out
    }

    /// Ввод с клавиатуры (`input` веба): «вставка» — цифр прибавилось больше
    /// одной или прибавилась хоть одна без «+» (автозаполнение iOS отдаёт номер
    /// по цифре и снимает код страны).
    public static func typed(_ value: String, previousDigits: Int, country: TelCountry) -> String {
        let n = digits(value).count
        let hasPlus = value.drop(while: { $0 == " " }).hasPrefix("+")
        let pasted = n - previousDigits > 1 || (n > previousDigits && !hasPlus)
        return format(value, country: country, pasted: pasted)
    }

    /// Уход из поля: номер без «+» гонят ещё раз как вставленный.
    public static func settled(_ value: String, country: TelCountry) -> String {
        if value.drop(while: { $0 == " " }).hasPrefix("+") { return value }
        return format(value, country: country, pasted: true)
    }

    /// Международные цифры номера (`telFull`): «8 916 123-45-67», «+7 916 …»
    /// и «916 123-45-67» — один номер.
    public static func full(_ value: String, country sp: TelCountry) -> String {
        let d = digits(value)
        if d.isEmpty { return "" }
        if value.drop(while: { $0 == " " }).hasPrefix("+") { return d }
        if d.count > 2, d.hasPrefix("00") { return String(d.dropFirst(2)) }
        if !sp.trunk.isEmpty, d.count > sp.trunk.count, d.hasPrefix(sp.trunk) {
            let cut = String(d.dropFirst(sp.trunk.count))
            if sp.nsnOk(cut) { return sp.cc + cut }
        }
        if sp.nsnOk(d) { return sp.cc + d }
        return d
    }

    public static func e164(_ value: String, country: TelCountry) -> String {
        let d = full(value, country: country)
        return d.isEmpty ? "" : "+" + d
    }

    /// Мобильный ли номер: только такой даёт ID (`telMobile`).
    public static func isMobile(_ value: String, country sp: TelCountry) -> Bool {
        let d = full(value, country: sp)
        if d.isEmpty { return false }
        if d.hasPrefix(sp.cc) {
            return String(d.dropFirst(sp.cc.count)).range(of: sp.mobile, options: .regularExpression) != nil
        }
        return value.drop(while: { $0 == " " }).hasPrefix("+") || digits(value).hasPrefix("00")
    }

    /// ID приложения: «id» и международные цифры; пусто, если номер не мобильный (`appId`).
    public static func appId(_ value: String, country: TelCountry) -> String {
        let d = full(value, country: country)
        return (!d.isEmpty && isMobile(value, country: country)) ? "id" + d : ""
    }

    public static func digits(_ s: String) -> String { s.filter { $0.isASCII && $0.isNumber } }

    /// Разложить цифры по образцу; кончились цифры — обрываем без хвоста разделителей.
    static func groups(_ d: String, _ fmt: String) -> String {
        var out = "", pend = ""
        var it = d.makeIterator()
        var used = 0
        for ch in fmt {
            if used >= d.count { break }
            if ch == "#" { if let c = it.next() { out += pend + String(c); pend = ""; used += 1 } }
            else { pend.append(ch) }
        }
        return out + String(d.dropFirst(used))
    }
}

// MARK: - Национальная часть и цепочка прежних ID (профиль)

extension TelFormat {

    /// Короче пяти цифр — не номер, а обрывок (`telReal`).
    public static func isReal(_ value: String, country: TelCountry) -> Bool { full(value, country: country).count >= 5 }

    /// Страны, при которых введённое выходит мобильным (`telCcFit`). Городской номер сюда не попадает.
    public static func countriesFitting(_ raw: String) -> [TelCountry] {
        var d = digits(raw)
        if d.isEmpty { return [] }
        let plus = raw.drop(while: { $0 == " " }).hasPrefix("+") || d.hasPrefix("00")
        if d.hasPrefix("00") { d = String(d.dropFirst(2)) }
        return TelCountry.all.filter { sp in
            let n: String
            if plus {
                guard d.hasPrefix(sp.cc) else { return false }
                n = String(d.dropFirst(sp.cc.count))
            } else if !sp.trunk.isEmpty, d.count > sp.trunk.count, d.hasPrefix(sp.trunk) {
                n = String(d.dropFirst(sp.trunk.count))
            } else if d.hasPrefix(sp.cc), sp.nsnOk(String(d.dropFirst(sp.cc.count))) {
                n = String(d.dropFirst(sp.cc.count))
            } else {
                n = d
            }
            return sp.nsnOk(n) && n.range(of: sp.mobile, options: .regularExpression) != nil
        }
    }

    /// Разбор входящего в поле без кода страны (`telNatIn`): лишнюю голову снимаем;
    /// если она называет другую страну — переставляем и блок кода.
    public static func natIn(_ str: String, international: Bool = false, country sp: TelCountry) -> (country: TelCountry?, national: String) {
        var d = digits(str)
        let plus = international || str.drop(while: { $0 == " " }).hasPrefix("+") || d.hasPrefix("00")
        if d.hasPrefix("00") { d = String(d.dropFirst(2)) }
        if plus {
            if d.hasPrefix(sp.cc), sp.nsnFits(String(d.dropFirst(sp.cc.count))) { return (nil, String(d.dropFirst(sp.cc.count))) }
            if let fit = countriesFitting("+" + d).first { return (fit, String(d.dropFirst(fit.cc.count))) }
            return (nil, d)
        }
        if !sp.trunk.isEmpty, d.count > sp.trunk.count, d.hasPrefix(sp.trunk), sp.nsnFits(String(d.dropFirst(sp.trunk.count))) {
            return (nil, String(d.dropFirst(sp.trunk.count)))
        }
        if d.hasPrefix(sp.cc), sp.nsnOk(String(d.dropFirst(sp.cc.count))) { return (nil, String(d.dropFirst(sp.cc.count))) }
        return (nil, d)
    }

    /// Национальная часть, разложенная по образцу страны (`telNatFmt`).
    public static func nationalFormatted(_ d: String, country sp: TelCountry) -> String { groups(digits(d), sp.format) }

    /// Из хранимой международной записи — то, что стоит в поле (`telNatOf`).
    public static func national(of value: String, country sp: TelCountry) -> String {
        let f = full(value, country: sp)
        if f.isEmpty { return "" }
        return nationalFormatted(f.hasPrefix(sp.cc) ? String(f.dropFirst(sp.cc.count)) : f, country: sp)
    }

    /// Хранимый номер из блока кода и поля (`telJoin`).
    public static func join(national: String, country sp: TelCountry) -> String {
        let d = digits(national)
        return d.isEmpty ? "" : format("+" + sp.cc + d, country: sp)
    }
}

/// Прежний ID владельца: ID, а не номер — наружу уходил ID, его и держат чужие системы.
public struct MyIdEntry: Sendable, Hashable {
    public var was: String
    /// ISO 8601, как пишет веб.
    public var at: String
    public init(was: String, at: String) { self.was = was; self.at = at }
}

/// Цепочка прежних ID владельца, старые первыми (веб `myIdRetire`).
public enum MyIdChain {
    public static let maxLength = 12

    /// Смена номера: пустое поле и тот же номер, записанный иначе, сменой не считаются.
    public static func swapped(from before: String, to after: String, country: TelCountry) -> Bool {
        TelFormat.isReal(before, country: country) && TelFormat.isReal(after, country: country)
            && TelFormat.full(before, country: country) != TelFormat.full(after, country: country)
    }

    /// Новая цепочка и признак настоящей смены. Вернулись к номеру, которым уже были, —
    /// цепочка срезается до этой точки, колец A→Б→A нет. Прежний номер не мобильный —
    /// хранить нечего, но смена настоящая.
    public static func retire(_ list: [MyIdEntry], from before: String, to after: String,
                              country: TelCountry, at now: String) -> (list: [MyIdEntry], real: Bool) {
        guard swapped(from: before, to: after, country: country) else { return (list, false) }
        let nk = TelFormat.full(after, country: country)
        if let i = list.firstIndex(where: { TelFormat.full($0.was, country: country) == nk }) {
            return (Array(list[..<i]), true)
        }
        let wasId = TelFormat.appId(before, country: country)
        guard !wasId.isEmpty else { return (list, true) }
        var out = list + [MyIdEntry(was: wasId, at: now)]
        if out.count > maxLength { out = Array(out.suffix(maxLength)) }
        return (out, true)
    }
}
