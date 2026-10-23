import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг 30.6: «прогноз переменился» без открытой карточки — баннер при запуске и возврате, уведомление из фона,
/// одна память `wxTold` на оба канала. Прогноз — подставной (ясно или дождь на три недели), система — пустышка.
@MainActor
struct WeatherWatchModelTests {

    private struct SkySource: WeatherSource {
        let rain: Bool
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            var time: [String] = []
            let d0 = CivilDate(year: 2026, month: 9, day: 15)
            for k in 0..<21 {
                let d = d0.adding(days: k)
                for h in 0..<24 { time.append(String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, h)) }
            }
            let n = time.count
            return HourlyWeather(time: time, cloud: Array(repeating: rain ? 95 : 5, count: n),
                                 temperature: Array(repeating: 12, count: n), windSpeed: Array(repeating: 2, count: n),
                                 precipitation: Array(repeating: rain ? 3 : 0, count: n),
                                 weatherCode: Array(repeating: rain ? 61 : 0, count: n))
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

    /// Система уведомлений «сейчас»: принимает или отказывает (нет права).
    private actor Poster: InstantNotifying {
        let accept: Bool
        private(set) var got: [InstantAlert] = []
        init(accept: Bool = true) { self.accept = accept }
        func deliver(_ alert: InstantAlert) -> Bool { if accept { got.append(alert) }; return accept }
    }

    /// Право уведомлять: что ответит система и сколько раз звали системное окно.
    private actor Center: NotificationCentering {
        var status: NotificationAuthorization
        private(set) var asked = 0
        init(_ status: NotificationAuthorization) { self.status = status }
        func authorization() -> NotificationAuthorization { status }
        func requestAuthorization() -> Bool { asked += 1; status = .allowed; return true }
        func pending() -> [PendingAlert] { [] }
        func add(_ alert: ScheduledAlert) -> Bool { true }
        func remove(ids: [String]) {}
    }

    private static let now = "2026-09-20T12:00:00+03:00"

    private static func shoot(_ id: String, day: Int, start: Int = 1080, kind: RecordKind = .shoot,
                              persons: [String] = []) -> Session {
        var s = Session(id: id, kind: kind, day: CivilDate(year: 2026, month: 9, day: day),
                        start: start, end: start + 120, duration: 120, genre: kind == .shoot ? .portrait : nil)
        s.latitude = 55.75; s.longitude = 37.62
        s.persons = persons.map { Person(name: $0, phone: "") }
        return s
    }

    private static func mark(_ q: String, _ sc: Int?) -> JSONValue {
        .object(["q": .string(q), "sc": sc.map { .number(Double($0)) } ?? .null])
    }

    private func model(_ list: [Session], seen: [String: JSONValue]? = nil, told: [String: JSONValue]? = nil,
                       notif: JSONValue? = nil, rain: Bool = true, poster: Poster? = nil) -> AppModel {
        var snap = Snapshot()
        snap.sessions = list
        snap.practice = "ru"
        if let seen { snap.extra["wxSeen"] = .object(seen) }
        if let told { snap.extra["wxTold"] = .object(told) }
        if let notif { snap.extra["notif"] = notif }
        let now = ISO8601DateFormatter().date(from: Self.now)!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: SkySource(rain: rain), now: { now })
        app.wxPoster = poster
        return app
    }

    private func told(_ app: AppModel) -> [String: SkySnap] { WeatherMemory.read(WeatherMemory.toldKey, in: app.snapshotForTests) }
    private func seen(_ app: AppModel) -> [String: SkySnap] { WeatherMemory.read(WeatherMemory.seenKey, in: app.snapshotForTests) }

    // MARK: - Баннер

    /// Две съёмки испортились: баннер про ближнюю, вторая — «И ещё 1»; обе помечены сказанными.
    @Test func bannerTellsNearestAndCountsTheRest() async {
        let app = model([Self.shoot("a", day: 23), Self.shoot("b", day: 21, persons: ["Анна Петрова", "Илья"])],
                        seen: ["a": Self.mark("excellent", 90), "b": Self.mark("excellent", 90)])
        let said = await app.runWeatherWatch(force: true, channel: .banner)
        #expect(said.map(\.id) == ["b", "a"])
        #expect(app.notices.current?.title == "21 сентября · прогноз испортился")
        #expect(app.notices.current?.sessionId == "b")
        #expect(app.noticeText?.hasPrefix("«Анна и Илья»: балл заката был 90 из 100, стал") == true)
        #expect(app.noticeText?.hasSuffix(" И ещё 1.") == true)
        #expect(Set(told(app).keys) == ["a", "b"])
        // Тот же прогноз на следующем заходе — молчим.
        app.notices.advance()
        let again = await app.announceWeather(.banner)
        #expect(again.isEmpty && app.notices.current == nil)
    }

    /// Первый запуск (память пуста) и первое знакомство — молча: `wxSeen` пишется, сказать нечего.
    @Test func firstSightIsSilent() async {
        let app = model([Self.shoot("a", day: 21)])
        let said = await app.runWeatherWatch(force: true, channel: .banner)
        #expect(said.isEmpty && app.notices.current == nil)
        #expect(seen(app)["a"] != nil)
        #expect(told(app).isEmpty)
    }

    /// Молчит: после съёмки, без прогноза (дальше окна), у встречи, при выключенных уведомлениях о погоде.
    @Test func silentWhereThereIsNothingToTell() async {
        let rainy = ["a": Self.mark("excellent", 90)]
        let after = model([Self.shoot("a", day: 20, start: 480)], seen: rainy)
        #expect(await after.runWeatherWatch(force: true, channel: .banner).isEmpty)
        let far = model([Self.shoot("a", day: 20 + 20)], seen: rainy)
        #expect(await far.runWeatherWatch(force: true, channel: .banner).isEmpty)
        let meet = model([Self.shoot("a", day: 21, kind: .meet)], seen: rainy)
        #expect(await meet.runWeatherWatch(force: true, channel: .banner).isEmpty)
        let off = model([Self.shoot("a", day: 21)], seen: rainy, notif: .object(["all": .bool(true), "wx": .bool(false)]))
        #expect(await off.runWeatherWatch(force: true, channel: .banner).isEmpty)
        let allOff = model([Self.shoot("a", day: 21)], seen: rainy, notif: .object(["all": .bool(false)]))
        #expect(await allOff.runWeatherWatch(force: true, channel: .banner).isEmpty)
        for app in [after, far, meet, off, allOff] { #expect(app.notices.current == nil && told(app).isEmpty) }
    }

    /// Возврат в приложение раньше получаса после обхода в сеть не ходит и не говорит.
    @Test func returnWithinHalfHourSkips() async {
        let app = model([Self.shoot("a", day: 21)], seen: ["a": Self.mark("excellent", 90)])
        app.wxWatchAt = ISO8601DateFormatter().date(from: "2026-09-20T11:45:00+03:00")
        #expect(await app.runWeatherWatch(force: false, channel: .banner).isEmpty)
        #expect(await app.runWeatherWatch(force: true, channel: .banner).map(\.id) == ["a"])
    }

    /// Фон обновил прогноз, но система уведомление не приняла; открыли приложение через 10 минут — в сеть не идём,
    /// но несказанное говорим по уже полученному прогнозу (ревью GPT к 58e88fd).
    @Test func returnWithinHalfHourStillTellsWhatBackgroundCouldNot() async {
        let app = model([Self.shoot("a", day: 21)], seen: ["a": Self.mark("excellent", 90)], poster: Poster(accept: false))
        #expect(await app.runWeatherWatch(force: true, channel: .notification).isEmpty)
        #expect(await app.runWeatherWatch(force: false, channel: .banner).map(\.id) == ["a"])
        #expect(app.notices.current?.sessionId == "a")
    }

    /// Пока шёл прогноз, приложение ушло в фон: баннер не ставится и сказанным не помечается.
    @Test func bannerSilentWhenSceneIsNotActive() async {
        let app = model([Self.shoot("a", day: 21)], seen: ["a": Self.mark("excellent", 90)])
        app.sceneActive = false
        #expect(await app.runWeatherWatch(force: true, channel: .banner).isEmpty)
        #expect(app.notices.current == nil && told(app).isEmpty)
        app.sceneActive = true
        #expect(await app.announceWeather(.banner).map(\.id) == ["a"])
    }

    /// Отметку `wxSeen`, которую эта версия не читает, обход не затирает знакомством (ревью GPT к 58e88fd).
    @Test func unreadableSeenMarkIsNotOverwritten() async {
        let app = model([Self.shoot("a", day: 21)], seen: ["a": .object(["q": .string("storm-v2"), "sc": .number(40)])])
        #expect(await app.runWeatherWatch(force: true, channel: .banner).isEmpty)
        guard case .object(let o)? = app.snapshotForTests.extra["wxSeen"], case .object(let m)? = o["a"] else {
            Issue.record("отметка пропала"); return
        }
        #expect(m["q"] == .string("storm-v2"))
    }

    // MARK: - Уведомление и два канала

    /// Фон: по уведомлению на съёмку, слова те же, что у баннера; потом открытие приложения молчит.
    @Test func notificationThenBannerDoesNotRepeat() async {
        let poster = Poster()
        let app = model([Self.shoot("a", day: 21), Self.shoot("b", day: 22)],
                        seen: ["a": Self.mark("excellent", 90), "b": Self.mark("excellent", 90)], poster: poster)
        let said = await app.runWeatherWatch(force: true, channel: .notification)
        #expect(said.count == 2)
        let got = await poster.got
        #expect(got.map(\.id) == ["lp.wx.a", "lp.wx.b"])
        #expect(got.first?.title == "21 сентября · прогноз испортился")
        #expect(got.first?.body.hasPrefix("«Портрет»: балл заката был 90 из 100") == true)
        #expect(Set(told(app).keys) == ["a", "b"])
        let banner = await app.runWeatherWatch(force: true, channel: .banner)
        #expect(banner.isEmpty && app.notices.current == nil)
    }

    /// Баннер сказал — фон не повторяет.
    @Test func bannerThenNotificationDoesNotRepeat() async {
        let poster = Poster()
        let app = model([Self.shoot("a", day: 21)], seen: ["a": Self.mark("excellent", 90)], poster: poster)
        #expect(await app.runWeatherWatch(force: true, channel: .banner).count == 1)
        #expect(await app.runWeatherWatch(force: true, channel: .notification).isEmpty)
        #expect(await poster.got.isEmpty)
    }

    /// Права уведомлять нет — фон не сказал и не помечает; открытие приложения скажет баннером.
    @Test func refusedNotificationLeavesItToTheBanner() async {
        let poster = Poster(accept: false)
        let app = model([Self.shoot("a", day: 21)], seen: ["a": Self.mark("excellent", 90)], poster: poster)
        #expect(await app.runWeatherWatch(force: true, channel: .notification).isEmpty)
        #expect(told(app).isEmpty)
        #expect(await app.runWeatherWatch(force: true, channel: .banner).map(\.id) == ["a"])
    }

    /// Закрытие карточки стирает «сказанное» (`wxAck`): смена после этого — снова новость.
    @Test func cardCloseResetsToldForTheNextChange() async {
        let app = model([Self.shoot("a", day: 21)], seen: ["a": Self.mark("excellent", 90)])
        _ = await app.runWeatherWatch(force: true, channel: .banner)
        app.openCard(id: "a")
        app.closeCard()
        #expect(told(app)["a"] == nil)
        #expect(seen(app)["a"]?.quality == .poor)
    }

    // MARK: - Плашка «Сообщать и когда закрыто?» (30.6b)

    /// Модель с системой уведомлений и короткими баннерами; одна смена прогноза у съёмки «a».
    private func askModel(_ status: NotificationAuthorization, notif: JSONValue? = nil) -> (AppModel, Center) {
        let center = Center(status)
        let app = model([Self.shoot("a", day: 21)], seen: ["a": Self.mark("excellent", 90)], notif: notif)
        app.alertCenter = center
        app.noticeTiming = (.milliseconds(5), .milliseconds(5))
        return (app, center)
    }

    /// Баннер отыграл — дождаться очереди и проверки системы.
    private func bannerPass(_ app: AppModel) async {
        _ = await app.runWeatherWatch(force: true, channel: .banner)
        await app.noticeTask?.value
        await app.wxOfferTask?.value
    }

    /// После первого баннера, пока система не спрашивала, — плашка; системное окно не зовётся до «Да».
    @Test func plateFollowsFirstBannerOnce() async {
        let (app, center) = askModel(.notDetermined)
        #expect(!app.weatherAlertAsk)
        await bannerPass(app)
        #expect(app.weatherAlertAsk)
        #expect(await center.asked == 0)
        app.answerWeatherAlertAsk(yes: false)                 // «Не сейчас»
        #expect(!app.weatherAlertAsk && app.weatherAlertAsked)
        // Прогноз сменился снова — баннер есть, плашки нет.
        WeatherMemory.write(WeatherMemory.toldKey, ["a": nil], in: &app.snapshot)
        await bannerPass(app)
        #expect(app.notices.current == nil && !app.weatherAlertAsk)
        #expect(await center.asked == 0)
    }

    /// Система уже ответила (разрешили или отказали) — плашка не нужна; выключенная погода — тоже.
    @Test func plateSilentWhenAnsweredOrOff() async {
        for status in [NotificationAuthorization.allowed, .denied] {
            let (app, _) = askModel(status)
            await bannerPass(app)
            #expect(!app.weatherAlertAsk)
        }
        let (off, _) = askModel(.notDetermined, notif: .object(["wx": .bool(false)]))
        await bannerPass(off)
        off.offerWeatherAlerts()
        await off.wxOfferTask?.value
        #expect(!off.weatherAlertAsk)
        // Без баннера (прогноз не менялся) плашки нет.
        let center = Center(.notDetermined)
        let calm = model([Self.shoot("a", day: 21)])
        calm.alertCenter = center
        await bannerPass(calm)
        #expect(!calm.weatherAlertAsk)
    }

    /// «Да» — системное окно; разрешили — плашка больше не нужна.
    @Test func yesAsksTheSystem() async {
        let (app, center) = askModel(.notDetermined)
        await bannerPass(app)
        app.answerWeatherAlertAsk(yes: true)
        await app.wxOfferTask?.value
        #expect(await center.asked == 1)
        #expect(app.alertAuth == .allowed && app.weatherAlertAsked && !app.weatherAlertAsk)
    }

    /// «Уже спрашивали» живёт в памяти телефона и переживает перезапуск; в общий снимок не пишется.
    @Test func askedLivesOnTheDevice() async {
        let suite = "lp.test.wxAsk.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (first, _) = askModel(.notDetermined)
        first.wxAskDefaults = defaults
        await bannerPass(first)
        first.answerWeatherAlertAsk(yes: false)
        #expect(first.snapshotForTests.extra["notif"] == nil)
        let (second, _) = askModel(.notDetermined)
        second.wxAskDefaults = defaults
        await bannerPass(second)
        #expect(!second.weatherAlertAsk)
    }

    // MARK: - Настройки

    /// Тумблер пишет только `wx` (и `all` при включении); незнакомые поля `notif` проходят насквозь.
    @Test func toggleKeepsForeignNotifFields() {
        let app = model([], notif: .object(["clash": .bool(false), "srv": .bool(true), "future": .string("x")]))
        #expect(app.weatherAlertsWanted)
        app.setWeatherAlerts(false)
        #expect(!app.weatherAlertsWanted)
        guard case .object(let o)? = app.snapshotForTests.extra["notif"] else { Issue.record("нет notif"); return }
        #expect(o["wx"] == .bool(false) && o["clash"] == .bool(false) && o["future"] == .string("x"))
        app.setWeatherAlerts(true)
        #expect(app.weatherAlertsWanted)
    }
}
