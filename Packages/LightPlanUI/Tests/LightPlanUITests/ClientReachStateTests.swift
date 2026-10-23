import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг К4 «Клиенты: мессенджеры»: кнопка в шапке карточки съёмки и в карточке клиента, меню долгого нажатия, правка
/// мессенджеров и «Пишем» в карточке клиента (справка `docs/clients_reference.md` § 7.1).
@MainActor
struct ClientReachStateTests {

    private struct NoWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func model(clients: [Client] = [], sessions: [Session] = []) -> AppModel {
        var snap = Snapshot()
        snap.clients = clients
        snap.sessions = sessions
        snap.clientsAssembled = true
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func shoot(_ id: String, client: String? = nil, tel: String = "", contact: String = "Ольга") -> Session {
        var s = Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 10, day: 5), start: 840, end: 930, duration: 90,
                        genre: .portrait)
        s.contact = contact
        s.clientPhone = tel
        s.clientId = client
        return s
    }

    private func person(_ name: String, _ tel: String, _ msg: [(MessengerKind, String)] = [], pref: MessengerKind? = nil) -> ClientPerson {
        var p = ClientPerson(name: name, phone: tel)
        p.messengers = msg.map { ClientMessenger(kind: $0.0.rawValue, value: $0.1) }
        p.preferred = pref?.rawValue
        return p
    }

    private func client(_ id: String, _ kind: ClientKind = .person, _ people: [ClientPerson], main: Int = 0) -> Client {
        var c = Client(id: id, kind: kind)
        c.people = people
        c.main = main
        return c
    }

    // MARK: шапка карточки съёмки

    @Test func theShootHeaderButtonOpensTheClientsMainMessengerAndTheMenuHasEveryWay() throws {
        let c = client("c1", .person, [person("Ольга Смирнова", "8 913 787-97-07", [(.vk, "https://vk.com/id123"), (.telegram, "olga_s")],
                                              pref: .telegram)])
        let app = model(clients: [c], sessions: [shoot("s1", client: "c1", tel: "8 913 787-97-07")])
        let plan = try #require(app.shootReach(app.sessions[0]), "у съёмки с клиентом кнопка есть")
        #expect(plan.primary.title == "Telegram" && plan.primary.url.absoluteString == "https://t.me/olga_s")
        #expect(plan.sections.count == 1 && plan.sections[0].title == "", "у персоны меню без подписи человека")
        #expect(plan.sections[0].items.map(\.title) == ["Позвонить", "SMS", "VK", "Telegram"])
        #expect(plan.sections[0].items.map(\.url.absoluteString)
                == ["tel:+79137879707", "sms:+79137879707", "https://vk.me/id123", "https://t.me/olga_s"])
    }

    @Test func aClientWithoutMessengersGetsAnSMSButton() throws {
        let app = model(clients: [client("c1", .person, [person("Ольга", "8 913 787-97-07")])],
                        sessions: [shoot("s1", client: "c1", tel: "8 913 787-97-07")])
        let plan = try #require(app.shootReach(app.sessions[0]))
        #expect(plan.primary.id == "sms" && plan.primary.url.absoluteString == "sms:+79137879707")
        #expect(plan.sections[0].items.map(\.id) == ["call", "sms"])
    }

    @Test func aShootWithoutAClientWritesAnSMSToTheHeaderNumberAndWithoutANumberThereIsNoButton() throws {
        let app = model(sessions: [shoot("s1", tel: "+7 916 123-45-67"), shoot("s2", contact: "Иван")])
        let plan = try #require(app.shootReach(app.sessions[0]))
        #expect(plan.primary.url.absoluteString == "sms:+79161234567")
        #expect(app.shootReach(app.sessions[1]) == nil, "ни номера, ни клиента — кнопки нет")
    }

    @Test func aCoupleWritesToWhomTheCardSaysAndTheMenuShowsBothByName() throws {
        let c = client("c1", .couple, [person("Анна Петрова", "+7 916 111-22-33"),
                                       person("Иван Петров", "+7 903 444-55-66", [(.whatsapp, "")])], main: 1)
        let app = model(clients: [c], sessions: [shoot("s1", client: "c1", tel: "+7 916 111-22-33", contact: "Анна и Иван")])
        let plan = try #require(app.shootReach(app.sessions[0]))
        #expect(plan.primary.title == "WhatsApp" && plan.primary.url.absoluteString == "https://wa.me/79034445566",
                "пишем Ивану: его WhatsApp по номеру")
        #expect(plan.sections.map(\.title) == ["Иван Петров", "Анна Петрова"], "тот, кому пишем, — первым")
        #expect(plan.sections[1].items.map(\.id) == ["0.call", "0.sms"])
    }

    // MARK: карточка клиента

    @Test func pastingAProfileLinkInTheCardKeepsTheHandleAndTheButtonFollowsTheStar() throws {
        let app = model(clients: [client("c1", .person, [person("Ольга", "8 913 787-97-07")])])
        app.openClientCard(id: "c1")
        #expect(app.personReach(app.clients[0].people[0])?.primary.id == "sms", "без мессенджера — SMS")
        app.addClientMessenger("c1", at: 0, .instagram)
        app.setClientMessenger("c1", at: 0, .instagram, "https://www.instagram.com/olga.s/")
        app.addClientMessenger("c1", at: 0, .max)
        app.setClientMessenger("c1", at: 0, .max, "https://web.max.ru/u/olga")
        let p = app.clients[0].people[0]
        #expect(p.messengers.map(\.value) == ["olga.s", "https://web.max.ru/u/olga"], "ссылка Instagram — имя, MAX — как есть")
        #expect(app.personReach(p)?.primary.url.absoluteString == "https://ig.me/m/olga.s", "первый мессенджер сразу основной")
        app.setClientPreferred("c1", at: 0, .max)
        #expect(app.personReach(app.clients[0].people[0])?.primary.url.absoluteString == "https://web.max.ru/u/olga")
        app.removeClientMessenger("c1", at: 0, .max)
        #expect(app.clients[0].people[0].preferred == "instagram")
    }

    @Test func writeToOffersOnlyPeopleYouCanReachAndMovesTheButton() throws {
        let c = client("c1", .family, [person("Марина Кузнецова", "8 913 000-11-22"), person("Соня", ""),
                                       person("Олег Кузнецов", "", [(.telegram, "oleg")])])
        let app = model(clients: [c], sessions: [shoot("s1", client: "c1", tel: "8 913 000-11-22", contact: "Семья")])
        #expect(app.clientWriters(app.clients[0]).map(\.label) == ["Марина", "Олег"], "ребёнок без связи — не в «Пишем»")
        #expect(app.shootReach(app.sessions[0])?.primary.id == "sms")
        app.setClientMain("c1", 2)
        #expect(app.shootReach(app.sessions[0])?.primary.url.absoluteString == "https://t.me/oleg")
        #expect(app.clients[0].modifiedAt != nil, "правка пишется сразу")
    }

    @Test func aDraftClientBecomesRealWhenAMessengerIsAdded() {
        let app = model()
        app.newClient()
        let id = app.org.clientCardId!
        app.addClientMessenger(id, at: 0, .telegram)
        #expect(app.clients.count == 1 && app.clients[0].people[0].messengers.map(\.kind) == ["telegram"])
    }
}
