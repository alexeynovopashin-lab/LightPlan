import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг «Поле-1» (слова Алексея 25.10), сторона приложения: слова новых подвидов на всех языках, форма с гостями,
/// звёздочки мессенджеров в досье и кнопка «написать», которая идёт за ними.
@MainActor
struct FieldOneStateTests {

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

    private func model(clients: [Client] = []) -> AppModel {
        var snap = Snapshot()
        snap.clients = clients
        snap.clientsAssembled = true
        let now = ISO8601DateFormatter().date(from: "2026-10-25T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func person(_ msg: [(MessengerKind, String)], pref: MessengerKind? = nil) -> ClientPerson {
        var p = ClientPerson(name: "Алёна", phone: "")
        p.messengers = msg.map { ClientMessenger(kind: $0.0.rawValue, value: $0.1) }
        p.preferred = pref?.rawValue
        return p
    }

    private func client(_ people: [ClientPerson]) -> Client {
        var c = Client(id: "c1", kind: .person)
        c.people = people
        return c
    }

    // MARK: слова подвидов

    @Test func newSubGenresHaveAWordInEveryLanguage() {
        let ru = ["sub.bachelorette": "Девичник", "sub.bachelor": "Мальчишник"]
        for (k, v) in ru { #expect(Lexicon("ru").t(k) == v, Comment(rawValue: k)) }
        for lang in ["ru", "en", "es", "ja", "zh"] {
            for k in ["sub.bachelorette", "sub.bachelor"] {
                let w = Lexicon(lang).t(k)
                #expect(w != k && !w.isEmpty, Comment(rawValue: lang + " " + k))
            }
            #expect(Lexicon(lang).t("sub.bachelorette") != Lexicon(lang).t("sub.bachelor"), "девичник и мальчишник — разные слова: \(lang)")
        }
    }

    @Test func everySubGenreHasAWordAndAnIconInTheLibrary() {
        for sub in SubGenre.allCases {
            for lang in ["ru", "en", "es", "ja", "zh"] {
                let w = Lexicon(lang).t("sub." + sub.rawValue)
                #expect(w != "sub." + sub.rawValue && !w.isEmpty, Comment(rawValue: lang + " " + sub.rawValue))
            }
            #expect(IconLibrary.common[sub.iconName] != nil, Comment(rawValue: sub.iconName))
        }
    }

    @Test func birthdayInFamilyShowsTheSameWordAsInParty() {
        // Одно слово на два жанра: ключ `sub.birthday` общий, как у «Беременности» в портрете и в семье.
        #expect(Genre.family.subGenres.contains(.birthday) && Genre.party.subGenres.contains(.birthday))
        #expect(Lexicon("ru").t("sub.birthday") == "День рождения")
    }

    // MARK: звёздочки досье

    @Test func tappingAStarMovesTheWriteButtonAndRepeatedTapsKeepIt() throws {
        let app = model(clients: [client([person([(.vk, "id123"), (.instagram, "olga")])])])
        #expect(app.personReach(app.clients[0].people[0])?.primary.url.absoluteString == "https://vk.me/id123")
        app.setClientPreferred("c1", at: 0, .instagram)
        #expect(app.personReach(app.clients[0].people[0])?.primary.url.absoluteString == "https://ig.me/m/olga")
        app.setClientPreferred("c1", at: 0, .instagram)
        #expect(app.personReach(app.clients[0].people[0])?.primary.url.absoluteString == "https://ig.me/m/olga", "второй тап по той же — без перемен")
        app.setClientPreferred("c1", at: 0, .vk)
        #expect(app.personReach(app.clients[0].people[0])?.primary.url.absoluteString == "https://vk.me/id123")
        let stars = ClientReach.starred(in: app.clients[0].people[0], country: app.telCountry)
        #expect(stars == [.vk, .instagram])
    }

    @Test func starPlusRemovalInARowLeavesTheOtherLitAndNoStarAtAll() throws {
        let app = model(clients: [client([person([(.vk, "id123"), (.instagram, "olga")])])])
        app.setClientPreferred("c1", at: 0, .instagram)
        app.removeClientMessenger("c1", at: 0, .instagram)
        let p = app.clients[0].people[0]
        #expect(app.personReach(p)?.primary.url.absoluteString == "https://vk.me/id123")
        #expect(ClientReach.starred(in: p, country: app.telCountry).isEmpty, "остался один — выбирать не из чего")
    }

    @Test func aMessengerFilledAfterTheStarJoinsTheChoice() throws {
        let app = model(clients: [client([person([(.vk, "id123")])])])
        #expect(ClientReach.starred(in: app.clients[0].people[0], country: app.telCountry).isEmpty)
        app.addClientMessenger("c1", at: 0, .instagram)
        #expect(ClientReach.starred(in: app.clients[0].people[0], country: app.telCountry).isEmpty, "пустая строка — не выбор")
        app.setClientMessenger("c1", at: 0, .instagram, "https://www.instagram.com/olga.s/")
        let p = app.clients[0].people[0]
        #expect(ClientReach.starred(in: p, country: app.telCountry) == [.vk, .instagram])
        app.setClientPreferred("c1", at: 0, .instagram)
        #expect(app.personReach(app.clients[0].people[0])?.primary.url.absoluteString == "https://ig.me/m/olga.s")
    }

    @Test func aStarOnAnEmptyRowOfOldDataDoesNotHideTheLitOne() throws {
        let app = model(clients: [client([person([(.telegram, ""), (.vk, "id123"), (.instagram, "olga")], pref: .telegram)])])
        let p = app.clients[0].people[0]
        #expect(ClientReach.starred(in: p, country: app.telCountry) == [.vk, .instagram])
        #expect(app.personReach(p)?.primary.url.absoluteString == "https://vk.me/id123")
    }
}
