import Testing
import Foundation
import CoreText
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Поле-1, пункты 5–8 (слова Алексея 25.10): знак главного мессенджера на кнопке «написать», галочка досье клиента,
/// двоеточие студийного часа по середине цифр, кнопка «Позвонить админу» вместо номера. Смотрим на данные, не на строки экрана.
@MainActor
struct FieldOneTailStateTests {

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

    private func model(clients: [Client] = [], sessions: [Session] = [], lang: String = "ru") -> AppModel {
        var snap = Snapshot()
        snap.clients = clients
        snap.sessions = sessions
        snap.clientsAssembled = true
        let now = ISO8601DateFormatter().date(from: "2026-10-25T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: lang, zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func person(_ name: String, _ phone: String, _ msg: [(MessengerKind, String)] = [],
                        pref: MessengerKind? = nil) -> ClientPerson {
        var p = ClientPerson(name: name, phone: phone)
        p.messengers = msg.map { ClientMessenger(kind: $0.0.rawValue, value: $0.1) }
        p.preferred = pref?.rawValue
        return p
    }

    private func client(_ id: String, _ people: [ClientPerson]) -> Client {
        var c = Client(id: id, kind: .person)
        c.people = people
        return c
    }

    private func client(_ people: [ClientPerson]) -> Client { client("c1", people) }

    private func shoot(client: String?, tel: String = "") -> Session {
        var s = Session(id: "s1", kind: .shoot, day: CivilDate(year: 2026, month: 10, day: 25), start: 840, end: 930,
                        duration: 90, genre: .portrait)
        s.contact = "Алёна"
        s.clientPhone = tel
        s.clientId = client
        return s
    }

    // MARK: 5. знак мессенджера на кнопке «написать»

    @Test func theButtonCarriesTheGlyphOfTheMainWayAndFollowsAStarWhileTheCardIsOpen() throws {
        let c = client([person("Алёна", "8 913 787-97-07", [(.vk, "id123"), (.telegram, "olga_s")], pref: .telegram)])
        let app = model(clients: [c], sessions: [shoot(client: "c1", tel: "8 913 787-97-07")])
        app.openClientCard(id: "c1")
        #expect(app.shootReach(app.sessions[0])?.primary.messenger == .telegram)
        #expect(app.personReach(app.clients[0].people[0])?.primary.messenger == .telegram)
        app.setClientPreferred("c1", at: 0, .vk)
        #expect(app.shootReach(app.sessions[0])?.primary.messenger == .vk, "смена звёздочки при открытой карточке — новый знак")
        #expect(app.personReach(app.clients[0].people[0])?.primary.messenger == .vk)
        app.removeClientMessenger("c1", at: 0, .vk)
        #expect(app.shootReach(app.sessions[0])?.primary.messenger == .telegram, "убрали основной — знак следующего")
        app.removeClientMessenger("c1", at: 0, .telegram)
        let sms = try #require(app.shootReach(app.sessions[0])?.primary)
        #expect(sms.id == "sms" && sms.messenger == nil, "мессенджеров нет — SMS и прежний знак")
    }

    @Test func anEmptyTelegramOrWhatsAppFieldWithANumberIsAWayAndShowsItsGlyph() throws {
        let c = client([person("Алёна", "8 913 787-97-07", [(.whatsapp, "")])])
        let app = model(clients: [c])
        let plan = try #require(app.personReach(c.people[0]))
        #expect(plan.primary.messenger == .whatsapp && plan.primary.url.absoluteString == "https://wa.me/79137879707")
        let bare = client("c2", [person("Алёна", "", [(.telegram, "")])])
        #expect(app.personReach(bare.people[0]) == nil, "пустое поле без номера — способа нет, кнопки нет")
    }

    @Test func everyMessengerHasItsOwnGlyphInsideTheCanvasAndNotTheChatBubble() {
        let chat = Icon.common("chat").parts.map(\.path)
        var seen: [[Path]] = []
        for k in MessengerKind.allCases {
            let art = MessengerGlyph.art(k)
            #expect(!art.parts.isEmpty, Comment(rawValue: k.rawValue))
            for part in art.parts {
                let box = part.path.boundingRect
                #expect(box.minX >= 0 && box.minY >= 0 && box.maxX <= 24 && box.maxY <= 24, Comment(rawValue: "\(k) вне холста 24×24"))
                #expect(box.width > 0 || box.height > 0)
            }
            let paths = art.parts.map(\.path)
            #expect(paths != chat, Comment(rawValue: "\(k) не должен быть облачком"))
            #expect(!seen.contains(paths), Comment(rawValue: "\(k) повторяет другой знак"))
            seen.append(paths)
        }
        #expect(seen.count == MessengerKind.allCases.count)
    }

    @Test func glyphsLiveOutsideTheGeneratedLibrary() {
        // `make icons` перезаписывает IconLibrary.generated.swift; знаки мессенджеров там были бы стёрты.
        for k in MessengerKind.allCases { #expect(IconLibrary.common[k.rawValue] == nil, Comment(rawValue: k.rawValue)) }
    }

    // MARK: 6. галочка досье

    @Test func nothingEditedNoCheckAndAnEditThatChangesNothingDoesNotTurnItOn() {
        let app = model(clients: [client([person("Ольга", "8 913 787-97-07")])])
        app.openClientCard(id: "c1")
        #expect(app.org.clientEdited == false)
        app.setClientPersonName("c1", at: 0, "Ольга")
        app.setClientKind("c1", .person)
        #expect(app.org.clientEdited == false, "то же значение — не правка")
    }

    @Test func anEditThenTheCheckClosesLikeBackKeepsEverythingAndShowsTheSign() {
        let app = model(clients: [client([person("Ольга", "8 913 787-97-07")])])
        app.openClientCard(id: "c1")
        app.setClientPersonName("c1", at: 0, "Ольга Смирнова")
        #expect(app.org.clientEdited)
        app.setClientKind("c1", .couple)
        app.doneClientCard()
        #expect(app.org.clientCardId == nil && app.org.savedSign)
        #expect(app.clients[0].people[0].name == "Ольга Смирнова" && app.clients[0].kind == .couple, "обе правки на месте")
    }

    @Test func anEditThenBackKeepsEverythingAndShowsNoSign() {
        let app = model(clients: [client([person("Ольга", "8 913 787-97-07")])])
        app.openClientCard(id: "c1")
        app.setClientPersonName("c1", at: 0, "Ольга Смирнова")
        app.setClientMessenger("c1", at: 0, .telegram, "olga_s")
        app.closeClientCard()
        #expect(app.org.clientCardId == nil && app.org.savedSign == false)
        #expect(app.clients[0].people[0].name == "Ольга Смирнова" && app.clients[0].people[0].messengers.first?.value == "olga_s")
    }

    @Test func theCheckResetsWhenTheCardIsOpenedAgain() {
        let app = model(clients: [client([person("Ольга", "8 913 787-97-07")])])
        app.openClientCard(id: "c1")
        app.setClientPersonName("c1", at: 0, "Ольга С.")
        app.closeClientCard()
        app.openClientCard(id: "c1")
        #expect(app.org.clientEdited == false, "новая карточка — галочки нет, пока не правили")
    }

    @Test func aNewClientGetsTheCheckOnlyOnceSomethingIsWritten() {
        let app = model()
        app.newClient()
        let id = app.org.clientCardId!
        app.setClientPersonName(id, at: 0, "")
        app.setClientPersonPhone(id, at: 0, "")
        #expect(app.org.clientEdited == false, "пустые поля данных не меняют — клиента нет, галочки нет")
        #expect(app.clients.isEmpty)
        app.setClientPersonName(id, at: 0, "Ольга")
        #expect(app.org.clientEdited && app.clients.count == 1)
        app.doneClientCard()
        #expect(app.clients.count == 1 && app.org.savedSign)
    }

    @Test func changingTheMainMessengerWithTheCardOpenIsAnEditAndTheCheckKeepsIt() {
        let c = client([person("Ольга", "8 913 787-97-07", [(.vk, "id123"), (.instagram, "olga")])])
        let app = model(clients: [c])
        app.openClientCard(id: "c1")
        app.setClientPreferred("c1", at: 0, .instagram)
        #expect(app.org.clientEdited)
        app.setClientPersonName("c1", at: 0, "Ольга Н.")
        app.doneClientCard()
        let p = app.clients[0].people[0]
        #expect(p.preferred == "instagram" && p.name == "Ольга Н.", "звёздочка и имя подряд — обе записаны")
    }

    @Test func aSecondCheckWhileTheSignStandsRestartsItsTimer() {
        let app = model(clients: [client("c1", [person("Ольга", "8 913 787-97-07")]), client("c2", [person("Иван", "8 913 111-22-33")])])
        app.openClientCard(id: "c1")
        app.setClientPersonName("c1", at: 0, "Ольга С.")
        app.doneClientCard()
        let first = app.org.savedSignTick
        app.openClientCard(id: "c2")
        app.setClientPersonName("c2", at: 0, "Иван П.")
        app.doneClientCard()
        #expect(app.org.savedSign && app.org.savedSignTick == first + 1, "знак уже стоял — всё равно новый такт для таймера")
    }

    // MARK: 7–8. студийный час: двоеточие и «Позвонить админу»

    @Test func theColonIsLiftedSoItsMiddleMeetsTheMiddleOfTheDigits() {
        for (size, weight) in [(25.0, 700), (18.0, 700), (40.0, 400)] {
            let font = webPlatformFont(size, weight) as CTFont
            func mid(_ ch: Character) -> CGFloat {
                var u = Array(String(ch).utf16), g = [CGGlyph](repeating: 0, count: 1)
                #expect(CTFontGetGlyphsForCharacters(font, &u, &g, 1))
                var r = CGRect.zero
                CTFontGetBoundingRectsForGlyphs(font, .horizontal, g, &r, 1)
                return r.midY
            }
            let lift = StudioColon.lift(size: size, weight: weight)
            #expect(lift > 0.02 * size && lift < 0.2 * size, "двоеточие поднимается, не опускается (\(size): \(lift))")
            #expect(abs((mid(":") + lift) - mid("0")) < 0.01)
            for d in "0123456789" { #expect(abs(mid(d) - mid("0")) < size * 0.03, "цифры одной высоты: \(d)") }
        }
        let a = StudioColon.lift(size: 25, weight: 700), b = StudioColon.lift(size: 50, weight: 700)
        #expect(abs(b / a - 2) < 0.1, "подъём растёт вместе с кеглем")
    }

    private func studioApp(phone: String?) -> AppModel {
        var snap = CardPhaseTests.seed
        if let phone {
            for i in snap.studios.indices { snap.studios[i].phone = phone }
        } else {
            for i in snap.studios.indices { snap.studios[i].phone = "" }
        }
        let now = ISO8601DateFormatter().date(from: "2026-09-23T13:00:00+07:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    @Test func theCallAdminButtonDialsTheStudiosNumberAndNoNumberMeansNoButton() throws {
        let app = studioApp(phone: "+7 923 412-33-30")
        let s = app.sessions.first { $0.id == "sd_sep_now" }!
        let tel = try #require(StudioTileState.tel(s, app: app))
        #expect(StudioTileState.callURL(tel)?.absoluteString == "tel:+79234123330")
        let none = studioApp(phone: nil)
        #expect(StudioTileState.tel(none.sessions.first { $0.id == "sd_sep_now" }!, app: none) == nil, "у студии нет номера — нет кнопки")
    }

    @Test func theCallAdminWordExistsInEveryLanguage() {
        #expect(Lexicon("ru").t("studio.callAdmin") == "Позвонить админу")
        for lang in ["ru", "en", "es", "ja", "zh"] {
            let w = Lexicon(lang).t("studio.callAdmin")
            #expect(!w.isEmpty && w != "studio.callAdmin", Comment(rawValue: lang))
        }
    }
}
