import Foundation
import LightPlanCore

/// Мессенджер человека (шаг К4, справка `docs/clients_reference.md` § 7.1; список — слово Алексея 23.10, вопрос 5).
/// `rawValue` — ключ `k` в снимке (`ClientMessenger.kind`).
public enum MessengerKind: String, CaseIterable, Sendable {
    case telegram, vk, instagram, whatsapp, max

    /// Имя на кнопке и в меню. Названия сервисов не переводятся.
    public var title: String {
        switch self {
        case .telegram: "Telegram"
        case .vk: "VK"
        case .instagram: "Instagram"
        case .whatsapp: "WhatsApp"
        case .max: "MAX"
        }
    }

    /// Пустое поле значит «по номеру телефона человека»: WhatsApp работает только по номеру, Telegram — по номеру,
    /// если имени не знаем (§ 7.1).
    public var byPhone: Bool { self == .telegram || self == .whatsapp }
}

/// Как связаться с человеком: позвонить, SMS, мессенджер (§ 7.1). Кнопка в шапке карточки съёмки и в карточке клиента
/// берёт основной способ человека «Пишем»; долгое нажатие — все способы. Ссылки `https://` универсальные: открывают
/// приложение, если оно стоит, иначе браузер (из документации, не мерено); MAX — ссылка, которую вписал фотограф.
public enum ClientReach {

    /// Способ связи.
    public enum Way: Hashable, Sendable {
        case call, sms
        case messenger(MessengerKind)
    }

    /// Способ и адрес, который он открывает; `detail` — что показать рядом с названием (`@olga`, номер).
    public struct Option: Hashable, Sendable {
        public var way: Way
        public var url: URL
        public var detail: String
    }

    // MARK: - Разбор вставленного

    /// Что лечь в поле мессенджера: из вставленной ссылки профиля вынимается имя (`vk.com/id123` → `id123`,
    /// `instagram.com/olga/` → `olga`, `t.me/olga` → `olga`, `wa.me/7916…` → `+7916…`), у имени снимается `@`. Ссылка
    /// MAX и всё, что не похоже на ссылку этого мессенджера, остаётся как вписано (без краевых пробелов).
    public static func parse(_ raw: String, as kind: MessengerKind) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .max || s.isEmpty { return s }
        if let link = Link(s) {
            if let v = handle(from: link, kind: kind) { return v }
            return s
        }
        if kind != .whatsapp, s.hasPrefix("@") { return String(s.dropFirst()) }
        return s
    }

    /// Ссылка, разобранная по частям: хост без `www.`/`m.`, куски пути, параметры.
    private struct Link {
        var host: String
        var path: [String]
        var query: [String: String]

        init?(_ s: String) {
            var text = s
            let lower = s.lowercased()
            if lower.hasPrefix("tg://") {
                // `tg://resolve?domain=olga` / `tg://resolve?phone=7916…`
                text = "https://tg/" + s.dropFirst(5)
            } else if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
                // `t.me/olga` без схемы — тоже ссылка, если до первой «/» стоит хост с точкой.
                guard let slash = s.firstIndex(of: "/"), s[..<slash].contains("."), !s[..<slash].contains(" ") else { return nil }
                text = "https://" + s
            }
            guard let c = URLComponents(string: text), var host = c.host?.lowercased(), !host.isEmpty else { return nil }
            for p in ["www.", "m.", "mobile."] where host.hasPrefix(p) { host = String(host.dropFirst(p.count)) }
            self.host = host
            path = c.path.split(separator: "/").map(String.init)   // `path` уже без %-кодов
            var q: [String: String] = [:]
            for item in c.queryItems ?? [] where q[item.name.lowercased()] == nil {
                if let v = item.value { q[item.name.lowercased()] = v }
            }
            query = q
        }
    }

    /// Имя или номер из ссылки мессенджера; ссылка чужого сайта или без имени — `nil`.
    private static func handle(from l: Link, kind: MessengerKind) -> String? {
        func first(_ skip: Set<String> = []) -> String? {
            l.path.first { !$0.isEmpty && !skip.contains($0.lowercased()) }.map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
        }
        func plusDigits(_ v: String) -> String? {
            let d = TelFormat.digits(v)
            return d.count >= 7 ? "+" + d : nil
        }
        switch kind {
        case .telegram:
            if l.host == "tg" { return l.query["domain"] ?? l.query["phone"].flatMap(plusDigits) }
            guard ["t.me", "telegram.me", "telegram.dog"].contains(l.host), let v = first(["s"]) else { return nil }
            return v.hasPrefix("+") ? plusDigits(v) : v
        case .vk:
            guard ["vk.com", "vk.ru", "vk.me", "vkontakte.ru"].contains(l.host) else { return nil }
            return first()
        case .instagram:
            guard ["instagram.com", "instagr.am", "ig.me"].contains(l.host) else { return nil }
            return first(l.host == "ig.me" ? ["m"] : [])
        case .whatsapp:
            if l.host == "wa.me" { return first().flatMap(plusDigits) }
            // Только сам `whatsapp.com` и его поддомены: `notwhatsapp.com` — чужой сайт (ревью GPT к 4555a60).
            guard l.host == "whatsapp.com" || l.host.hasSuffix(".whatsapp.com") else { return nil }
            return l.query["phone"].flatMap(plusDigits)
        case .max:
            return nil
        }
    }

    // MARK: - Адреса

    /// Похоже на номер: только цифры, пробелы, `+ - ( )`, цифр не меньше семи. Имя Telegram с цифры не начинается.
    static func looksLikePhone(_ v: String) -> Bool {
        v.allSatisfy { $0.isNumber || " +-()".contains($0) } && TelFormat.digits(v).count >= 7
    }

    /// Международные цифры номера, без `+`; ненастоящий номер — пусто.
    private static func intl(_ phone: String, country: TelCountry) -> String {
        guard TelFormat.isReal(phone, country: country) else { return "" }
        return TelFormat.full(phone, country: country)
    }

    /// Адрес мессенджера по таблице § 7.1. `value` — что вписано в поле, `phone` — телефон человека: у Telegram и
    /// WhatsApp пустое поле значит «по номеру». Нечего открыть — `nil`.
    public static func url(_ kind: MessengerKind, value: String, phone: String, country: TelCountry) -> URL? {
        let v = parse(value, as: kind)
        func web(_ s: String) -> URL? {
            guard let u = URL(string: s), u.host != nil else { return nil }
            return u
        }
        func path(_ s: String) -> String? {
            // Имя кладётся в путь как есть, если в нём нет ничего, кроме букв, цифр, «.», «_», «-».
            guard !s.isEmpty, s.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else { return nil }
            return s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        }
        switch kind {
        case .telegram:
            let number = v.isEmpty ? phone : (looksLikePhone(v) ? v : "")
            if !number.isEmpty {
                let d = intl(number, country: country)
                return d.isEmpty ? nil : web("https://t.me/+" + d)
            }
            return path(v).flatMap { web("https://t.me/" + $0) }
        case .vk:
            return path(v).flatMap { web("https://vk.me/" + $0) }
        case .instagram:
            return path(v).flatMap { web("https://ig.me/m/" + $0) }
        case .whatsapp:
            let d = intl(v.isEmpty ? phone : v, country: country)
            return d.isEmpty ? nil : web("https://wa.me/" + d)
        case .max:
            // Слова Алексея 23.10: «можно туда поместить Web ссылку» — открывается в браузере. Вид ссылки профиля MAX
            // не мерен: берётся любая ссылка с хостом; без схемы — `https://`.
            guard !v.isEmpty, !v.contains(" ") else { return nil }
            let lower = v.lowercased()
            if lower.hasPrefix("https://") || lower.hasPrefix("http://") { return web(v) }
            guard v.contains(".") else { return nil }
            return web("https://" + v)
        }
    }

    /// `sms:<номер>` — Сообщения (SMS или iMessage); ненастоящий номер — `nil` (§ 7.1: «как обычное смс»).
    public static func smsURL(_ phone: String, country: TelCountry) -> URL? {
        let d = intl(phone, country: country)
        return d.isEmpty ? nil : URL(string: "sms:+" + d)
    }

    /// `tel:<номер>` — звонок; ненастоящий номер — `nil`.
    public static func callURL(_ phone: String, country: TelCountry) -> URL? {
        let d = intl(phone, country: country)
        return d.isEmpty ? nil : URL(string: "tel:+" + d)
    }

    // MARK: - Способы человека

    /// Мессенджеры человека, которые есть чем открыть, в порядке, как вписаны (одного вида — первый).
    public static func messengers(of p: ClientPerson, country: TelCountry) -> [Option] {
        var seen = Set<MessengerKind>(), out: [Option] = []
        for m in p.messengers {
            guard let k = MessengerKind(rawValue: m.kind), !seen.contains(k),
                  let u = url(k, value: m.value, phone: p.phone, country: country) else { continue }
            seen.insert(k)
            let v = parse(m.value, as: k)
            let detail = v.isEmpty ? "" : (k == .max || looksLikePhone(v) || k == .whatsapp ? v : "@" + v)
            out.append(Option(way: .messenger(k), url: u, detail: detail))
        }
        return out
    }

    /// Все способы человека для меню долгого нажатия: позвонить, SMS, каждый мессенджер (§ 7.1).
    public static func options(of p: ClientPerson, country: TelCountry) -> [Option] {
        var out: [Option] = []
        let shown = TelFormat.isReal(p.phone, country: country)
            ? TelFormat.format(TelFormat.e164(p.phone, country: country), country: country) : ""
        if let u = callURL(p.phone, country: country) { out.append(Option(way: .call, url: u, detail: shown)) }
        if let u = smsURL(p.phone, country: country) { out.append(Option(way: .sms, url: u, detail: shown)) }
        return out + messengers(of: p, country: country)
    }

    /// Основной способ: мессенджер со звёздочкой (`pref`), иначе первый вписанный, иначе SMS; ничего — `nil`.
    public static func primary(of p: ClientPerson, country: TelCountry) -> Option? {
        let ms = messengers(of: p, country: country)
        if let pref = p.preferred.flatMap(MessengerKind.init(rawValue:)),
           let m = ms.first(where: { $0.way == .messenger(pref) }) { return m }
        if let m = ms.first { return m }
        return options(of: p, country: country).first { $0.way == .sms }
    }

    /// Кому пишем: человек `main`, если с ним есть как связаться, иначе первый, с кем есть; ни с кем — `nil`.
    public static func writer(of c: Client, country: TelCountry) -> Int? {
        if c.people.indices.contains(c.main), primary(of: c.people[c.main], country: country) != nil { return c.main }
        return c.people.indices.first { primary(of: c.people[$0], country: country) != nil }
    }

    // MARK: - Правка

    /// Мессенджер вписан или поправлен: значение разбирается (вставленная ссылка → имя), вида ещё нет — добавляется.
    public static func setMessenger(_ kind: MessengerKind, _ raw: String, in p: inout ClientPerson) {
        let v = parse(raw, as: kind)
        // Пока ссылку набирают руками («t.me/» без имени), поле держит набранное.
        let keep = v.isEmpty && !raw.trimmingCharacters(in: .whitespaces).isEmpty ? raw : v
        if let i = p.messengers.firstIndex(where: { $0.kind == kind.rawValue }) {
            p.messengers[i].value = keep
        } else {
            p.messengers.append(ClientMessenger(kind: kind.rawValue, value: keep))
        }
    }

    /// «+ мессенджер»: пустая строка вида, если его ещё нет. Первый мессенджер человека сразу основной.
    public static func addMessenger(_ kind: MessengerKind, to p: inout ClientPerson) {
        guard !p.messengers.contains(where: { $0.kind == kind.rawValue }) else { return }
        p.messengers.append(ClientMessenger(kind: kind.rawValue, value: ""))
        if p.preferred == nil { p.preferred = kind.rawValue }
    }

    /// Убрать мессенджер; основной уходит — основным становится следующий вписанный.
    public static func removeMessenger(_ kind: MessengerKind, from p: inout ClientPerson) {
        p.messengers.removeAll { $0.kind == kind.rawValue }
        if p.preferred == kind.rawValue {
            p.preferred = p.messengers.first(where: { MessengerKind(rawValue: $0.kind) != nil })?.kind
        }
    }

    /// Каких мессенджеров у человека ещё нет — для меню «+ мессенджер».
    public static func missing(in p: ClientPerson) -> [MessengerKind] {
        MessengerKind.allCases.filter { k in !p.messengers.contains { $0.kind == k.rawValue } }
    }
}
