import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Мессенджеры клиента (шаг К4, справка `clients_reference.md` § 7.1): разбор вставленной ссылки профиля, адрес каждого
/// мессенджера, SMS без мессенджера, основной способ и «кому пишем».
@Suite struct ClientReachTests {
    static let ru = TelCountry.fallback

    static func person(_ tel: String = "", _ msg: [(MessengerKind, String)] = [], pref: MessengerKind? = nil) -> ClientPerson {
        var p = ClientPerson(name: "Ольга", phone: tel)
        p.messengers = msg.map { ClientMessenger(kind: $0.0.rawValue, value: $0.1) }
        p.preferred = pref?.rawValue
        return p
    }

    static func url(_ k: MessengerKind, _ v: String, phone: String = "") -> String? {
        ClientReach.url(k, value: v, phone: phone, country: ru)?.absoluteString
    }

    // MARK: разбор ссылки профиля

    @Test func pastedProfileLinksGiveTheHandle() {
        let cases: [(MessengerKind, String, String)] = [
            (.vk, "https://vk.com/id123", "id123"),
            (.vk, "vk.com/olga_smirnova", "olga_smirnova"),
            (.vk, "https://m.vk.com/olga?from=profile", "olga"),
            (.vk, "vk.ru/id77", "id77"),
            (.vk, "https://vk.me/olga", "olga"),
            (.instagram, "https://www.instagram.com/olga.s/", "olga.s"),
            (.instagram, "instagram.com/olga?igsh=abc", "olga"),
            (.instagram, "https://ig.me/m/olga", "olga"),
            (.instagram, "@olga.s", "olga.s"),
            (.telegram, "https://t.me/olga", "olga"),
            (.telegram, "t.me/olga_s", "olga_s"),
            (.telegram, "telegram.me/olga", "olga"),
            (.telegram, "https://t.me/+79161234567", "+79161234567"),
            (.telegram, "tg://resolve?domain=olga", "olga"),
            (.telegram, "@olga", "olga"),
            (.whatsapp, "https://wa.me/79161234567", "+79161234567"),
            (.whatsapp, "wa.me/79161234567?text=hi", "+79161234567"),
            (.whatsapp, "https://api.whatsapp.com/send?phone=79161234567", "+79161234567"),
        ]
        for (k, raw, want) in cases {
            #expect(ClientReach.parse(raw, as: k) == want, Comment(rawValue: "\(k) \(raw)"))
        }
    }

    @Test func maxLinkAndForeignTextStayAsTyped() {
        #expect(ClientReach.parse("  https://web.max.ru/u/olga  ", as: .max) == "https://web.max.ru/u/olga", "MAX — как есть")
        #expect(ClientReach.parse("https://t.me/olga", as: .vk) == "https://t.me/olga", "чужая ссылка не разбирается")
        #expect(ClientReach.parse("+7 916 123-45-67", as: .whatsapp) == "+7 916 123-45-67", "номер — как набран")
        #expect(ClientReach.parse("t.me/", as: .telegram) == "t.me/", "ссылка без имени остаётся, пока её набирают")
        #expect(ClientReach.parse("olga.s", as: .instagram) == "olga.s", "имя с точкой — не ссылка")
    }

    // MARK: адреса по таблице § 7.1

    @Test func eachMessengerOpensItsUniversalLink() {
        #expect(Self.url(.telegram, "olga") == "https://t.me/olga")
        #expect(Self.url(.telegram, "https://t.me/olga") == "https://t.me/olga")
        #expect(Self.url(.vk, "https://vk.com/id123") == "https://vk.me/id123")
        #expect(Self.url(.instagram, "instagram.com/olga.s/") == "https://ig.me/m/olga.s")
        #expect(Self.url(.whatsapp, "8 916 123-45-67") == "https://wa.me/79161234567")
        #expect(Self.url(.max, "https://web.max.ru/u/olga") == "https://web.max.ru/u/olga")
        #expect(Self.url(.max, "web.max.ru/u/olga") == "https://web.max.ru/u/olga", "без схемы — https")
    }

    @Test func telegramAndWhatsAppGoByThePhoneWhenTheFieldIsEmpty() {
        #expect(Self.url(.whatsapp, "", phone: "8 916 123-45-67") == "https://wa.me/79161234567")
        #expect(Self.url(.telegram, "", phone: "+7 916 123-45-67") == "https://t.me/+79161234567")
        #expect(Self.url(.telegram, "8 903 111 22 33", phone: "+7 916 123-45-67") == "https://t.me/+79031112233", "свой номер Telegram")
        #expect(Self.url(.whatsapp, "") == nil && Self.url(.vk, "", phone: "8 916 123-45-67") == nil)
    }

    @Test func nothingToOpenGivesNoLink() {
        #expect(Self.url(.max, "olga") == nil, "MAX без ссылки — нечего открыть")
        #expect(Self.url(.vk, "Ольга Смирнова") == nil, "пробел — не имя")
        #expect(Self.url(.instagram, "@") == nil)
    }

    // MARK: SMS и основной способ

    @Test func withoutMessengersTheButtonWritesAnSMS() {
        let p = Self.person("8 913 787-97-07")
        let main = ClientReach.primary(of: p, country: Self.ru)
        #expect(main?.way == .sms && main?.url.absoluteString == "sms:+79137879707")
        #expect(ClientReach.options(of: p, country: Self.ru).map(\.way) == [.call, .sms])
        #expect(ClientReach.primary(of: Self.person(), country: Self.ru) == nil, "ни номера, ни мессенджера — кнопки нет")
    }

    @Test func theStarredMessengerIsTheMainOneOtherwiseTheFirst() {
        let p = Self.person("8 913 787-97-07", [(.vk, "olga"), (.telegram, "olga_s")], pref: .telegram)
        #expect(ClientReach.primary(of: p, country: Self.ru)?.url.absoluteString == "https://t.me/olga_s")
        let q = Self.person("8 913 787-97-07", [(.vk, "olga"), (.telegram, "olga_s")])
        #expect(ClientReach.primary(of: q, country: Self.ru)?.way == .messenger(.vk))
        // Звёздочка у мессенджера без адреса (MAX без ссылки) — основной первый, у кого адрес есть.
        let r = Self.person("8 913 787-97-07", [(.max, "olga"), (.instagram, "olga")], pref: .max)
        #expect(ClientReach.primary(of: r, country: Self.ru)?.way == .messenger(.instagram))
    }

    @Test func theMenuListsCallSMSAndEveryMessenger() {
        let p = Self.person("8 913 787-97-07", [(.telegram, "olga"), (.whatsapp, ""), (.max, "https://web.max.ru/u/olga")])
        let all = ClientReach.options(of: p, country: Self.ru)
        #expect(all.map(\.way) == [.call, .sms, .messenger(.telegram), .messenger(.whatsapp), .messenger(.max)])
        #expect(all[0].url.absoluteString == "tel:+79137879707" && all[0].detail == "+7 913 787-97-07")
        #expect(all[2].detail == "@olga" && all[3].url.absoluteString == "https://wa.me/79137879707")
    }

    @Test func theWriterIsMainIfReachableElseTheFirstReachable() {
        var c = Client(id: "c1", kind: .family)
        c.people = [Self.person("8 913 787-97-07"), Self.person(), Self.person("", [(.telegram, "ivan")])]
        c.main = 1
        #expect(ClientReach.writer(of: c, country: Self.ru) == 0, "ребёнок без телефона — пишем первому, с кем есть связь")
        c.main = 2
        #expect(ClientReach.writer(of: c, country: Self.ru) == 2)
        c.people = [Self.person()]
        #expect(ClientReach.writer(of: c, country: Self.ru) == nil)
    }

    // MARK: правка

    @Test func editingParsesTheLinkAndTheFirstMessengerIsMain() {
        var p = Self.person("8 913 787-97-07")
        ClientReach.addMessenger(.vk, to: &p)
        #expect(p.preferred == "vk" && p.messengers.map(\.kind) == ["vk"])
        ClientReach.setMessenger(.vk, "https://vk.com/id123", in: &p)
        #expect(p.messengers[0].value == "id123")
        ClientReach.addMessenger(.telegram, to: &p)
        ClientReach.addMessenger(.telegram, to: &p)
        #expect(p.messengers.count == 2 && p.preferred == "vk", "вид один раз; основной не меняется")
        #expect(ClientReach.missing(in: p) == [.instagram, .whatsapp, .max])
        ClientReach.removeMessenger(.vk, from: &p)
        #expect(p.preferred == "telegram" && p.messengers.map(\.kind) == ["telegram"])
    }

    @Test func messengersSurviveTheSnapshot() throws {
        var c = Client(id: "c1")
        c.people = [Self.person("8 913 787-97-07", [(.telegram, "olga"), (.max, "https://web.max.ru/u/olga")], pref: .max)]
        let back = try JSONDecoder().decode(Client.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }
}
