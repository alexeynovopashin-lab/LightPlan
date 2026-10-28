import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг 30б.3: приложение приводит плашку на экране блокировки к данным — запускает, когда съёмка началась, обновляет, закрывает,
/// продлевает длинный день, переходит в студию по нажатию на «Студийный час» и принимает ссылки кнопок. Система подставная: тест
/// читает, что у неё попросили. Записи — посев сезона (`CardPhaseTests`): портрет в студии 12:20–13:50 по Томску 23.09.2026.
@MainActor
struct ActivityAppTests {
    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
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

    /// Подставная система экрана активности: помнит, что у неё просили.
    @MainActor final class FakeHost: ActivityHosting {
        var allowed = true
        var shown: ActivityShown?
        var onDismissed: ((String) -> Void)?
        var log: [String] = []
        func start(_ frame: ActivityFrame, startedAt: Date) throws {
            shown = ActivityShown(shootId: frame.shootId, startedAt: startedAt, frame: frame)
            log.append("start")
        }
        func update(_ frame: ActivityFrame) async { shown?.frame = frame; log.append("update") }
        func end() async { shown = nil; log.append("end") }
    }

    final class Clock: @unchecked Sendable { var date: Date; init(_ d: Date) { date = d } }

    private let id = "sd_sep_now"

    private func make(_ iso: String, defaults: UserDefaults? = nil, clock shared: Clock? = nil,
                      edit: (inout Snapshot) -> Void = { _ in }) -> (AppModel, FakeHost, Clock) {
        var snap = CardPhaseTests.seed
        if case .object(var z)? = snap.extra["zones"] {
            z["56.5,85.0"] = JSONValue.string("Asia/Tomsk")
            snap.extra["zones"] = .object(z)
        }
        edit(&snap)
        let clock = shared ?? Clock(ISO8601DateFormatter().date(from: iso)!)
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), now: { clock.date })
        let host = FakeHost()
        // Память плашки — в своих настройках теста, чтобы не трогать настройки самого приложения и чтобы «перезапуск» делил их с прежним.
        app.activityDefaults = defaults ?? UserDefaults(suiteName: "lp-activity-test-\(UUID().uuidString)")
        app.useActivityHost(host)
        return (app, host, clock)
    }
    private func at(_ clock: Clock, _ iso: String) { clock.date = ISO8601DateFormatter().date(from: iso)! }
    private func sync(_ app: AppModel, _ reason: ActivityRules.Reason = .change) async {
        app.syncActivity(reason)
        await app.settleActivity()
    }
    private func withMusic(_ s: inout Snapshot) {
        s.playlists = [Playlist(name: "Сборы", url: "https://open.spotify.com/playlist/a")]
        if let i = s.sessions.firstIndex(where: { $0.id == "sd_sep_now" }) { s.sessions[i].playlist = "Сборы" }
    }

    // MARK: Старт, обновление, конец

    @Test func theActivityStartsWhenTheShootBeginsAndNotBefore() async {
        let (app, host, clock) = make("2026-09-23T12:10:00+07:00")
        await sync(app)
        #expect(host.log.isEmpty && host.shown == nil, "до начала плашки нет")
        at(clock, "2026-09-23T12:30:00+07:00")
        await sync(app)
        #expect(host.log == ["start"])
        #expect(host.shown?.shootId == id && host.shown?.frame.mode == .route && host.shown?.startedAt == clock.date)
        #expect(host.shown?.frame.call == nil, "лента кнопок не несёт")
    }

    @Test func aSecondCheckWithNothingNewSendsNothing() async {
        let (app, host, clock) = make("2026-09-23T12:30:00+07:00")
        await sync(app)
        await sync(app)
        at(clock, "2026-09-23T12:31:00+07:00")   // минута прошла, а лента и точки те же — шлём только если кадр другой
        await sync(app)
        #expect(host.log.filter { $0 == "start" }.count == 1)
        #expect(!host.log.contains("end"))
    }

    @Test func theEndOfTheShootTakesThePlateAway() async {
        let (app, host, clock) = make("2026-09-23T13:00:00+07:00")
        await sync(app)
        #expect(host.shown != nil)
        at(clock, "2026-09-23T13:51:00+07:00")
        await sync(app)
        #expect(host.log == ["start", "end"] && host.shown == nil)
    }

    @Test func finishingByHandTakesThePlateAway() async {
        let (app, host, _) = make("2026-09-23T13:00:00+07:00") { $0.manualEnd = true }
        await sync(app)
        #expect(host.shown != nil, "незакрытая вручную идёт, пока не нажмут")
        app.finishSession(id: id)
        await app.settleActivity()
        #expect(host.shown == nil, "после «Завершить» плашки нет: \(host.log)")
    }

    @Test func aPlateThePersonSwipedAwayIsNotStartedAgain() async {
        let (app, host, _) = make("2026-09-23T13:00:00+07:00")
        await sync(app)
        host.shown = nil
        host.onDismissed?(id)   // так сообщает настоящая система: плашку смахнули; обработчик ставит приложение
        #expect(app.activityDismissed[id] != nil)
        await sync(app, .foreground)
        #expect(host.log == ["start"] && host.shown == nil)
    }

    @Test func aSwipeThatTheSystemNeverReportedIsRecognisedByTheMissingPlate() async {
        let (app, host, _) = make("2026-09-23T13:00:00+07:00")
        await sync(app)
        host.shown = nil   // события не было (приложение было закрыто), плашки нет, а мы её не закрывали
        await sync(app, .foreground)
        #expect(host.log == ["start"] && host.shown == nil)
    }

    @Test func aPlateTheSystemEndedAfterItsEightHoursComesBack() async {
        let (app, host, clock) = make("2026-09-23T13:00:00+07:00") { $0.manualEnd = true }
        await sync(app)
        host.shown = nil
        at(clock, "2026-09-23T21:30:00+07:00")   // больше восьми часов: плашку убрала система, а не человек
        await sync(app, .foreground)
        #expect(host.log == ["start", "start"], "\(host.log)")
    }

    @Test func theSwipeIsRememberedAcrossARestartOfTheApp() async {
        let defaults = UserDefaults(suiteName: "lp-activity-test-\(UUID().uuidString)")
        let (app, host, clock) = make("2026-09-23T13:00:00+07:00", defaults: defaults)
        await sync(app)
        host.shown = nil
        host.onDismissed?(id)
        let (again, host2, _) = make("2026-09-23T13:10:00+07:00", defaults: defaults, clock: clock)
        await sync(again, .foreground)
        #expect(host2.log.isEmpty, "после перезапуска плашка не возвращается: \(host2.log)")
    }

    @Test func aSwipeWhileTheAppWasClosedIsRecognisedAfterTheRestart() async {
        let defaults = UserDefaults(suiteName: "lp-activity-test-\(UUID().uuidString)")
        let (app, host, clock) = make("2026-09-23T13:00:00+07:00", defaults: defaults)
        await sync(app)
        #expect(host.log == ["start"])
        host.shown = nil   // приложение закрыто, плашку смахнули, события нет
        let (again, host2, _) = make("2026-09-23T13:10:00+07:00", defaults: defaults, clock: clock)
        #expect(again.activityMarks[id] != nil, "метки пережили загрузку памяти")
        await sync(again, .foreground)
        #expect(host2.log.isEmpty, "после перезапуска плашка не возвращается: \(host2.log)")
    }

    @Test func theStudioModeSurvivesARestartBecauseThePlateItselfRemembersIt() async {
        let (app, host, _) = make("2026-09-23T13:00:00+07:00")
        app.switchActivityToStudio(sessionId: id)
        await app.settleActivity()
        #expect(host.shown?.frame.mode == .studio)
        app.activityStudioFor = nil   // перезапуск: в памяти приложения режима нет, плашка стоит с ним
        await sync(app, .foreground)
        #expect(host.shown?.frame.mode == .studio && app.activityStudioFor == id)
    }

    @Test func noPermissionNoRequest() async {
        let (app, host, _) = make("2026-09-23T13:00:00+07:00")
        host.allowed = false
        await sync(app)
        #expect(host.log.isEmpty)
    }

    // MARK: Длинный день

    @Test func aLongDayIsRestartedOnEveryReturnToTheApp() async {
        // Свадьба 10:00–20:00 по часам места: больше восьми часов — продлевается перезапуском.
        let (app, host, clock) = make("2026-09-23T13:00:00+07:00") { s in
            s.sessions.removeAll { $0.id == "sd_sep_now" }
            var w = Session(id: "long", day: CivilDate(year: 2026, month: 9, day: 23), start: 10 * 60, end: 20 * 60, genre: .wedding)
            w.route = [RoutePoint(start: 10 * 60, name: "Сборы"), RoutePoint(start: 15 * 60, name: "Церемония")]
            s.sessions.append(w)
        }
        await sync(app)
        let first = host.shown?.startedAt
        guard first != nil else { Issue.record("плашка не запустилась: \(host.log)"); return }
        at(clock, "2026-09-23T13:30:00+07:00")
        await sync(app, .change)
        #expect(!host.log.contains("end"), Comment(rawValue: "правка данных не продлевает: \(host.log)"))
        await sync(app, .foreground)
        #expect(Array(host.log.suffix(2)) == ["end", "start"], Comment(rawValue: "возврат на экран продлевает: \(host.log)"))
        #expect((host.shown?.startedAt ?? .distantPast) > (first ?? .distantFuture))
    }

    // MARK: Студия

    @Test func theTapOnStudioHourSwitchesToTheStudioModeWithButtons() async {
        let (app, host, _) = make("2026-09-23T13:00:00+07:00") { s in
            withMusic(&s)
            // Посевная съёмка без точек: лента студии — три точки дня (12:20 студия, 13:50 прогулка, 15:00 дом).
            if let i = s.sessions.firstIndex(where: { $0.id == "sd_sep_now" }) {
                s.sessions[i].route = [RoutePoint(start: 12 * 60 + 20, name: "Студия"), RoutePoint(start: 13 * 60 + 50, name: "Прогулка"),
                                       RoutePoint(start: 15 * 60, name: "Дом")]
            }
        }
        await sync(app)
        #expect(host.shown?.frame.mode == .route)
        #expect(host.shown?.frame.exit != nil, "выход из зала на ленте с самого начала")
        app.switchActivityToStudio(sessionId: id)
        await app.settleActivity()
        let f = host.shown?.frame
        #expect(f?.mode == .studio && f?.rentActive == true)
        #expect(f?.call == app.lexicon.t("studio.callAdmin") && f?.playlist == app.lexicon.t("activity.playlist"))
        #expect(f?.points.count == 3, "лента в студии на месте")
    }

    @Test func aStudioShootWithoutPointsGetsNoLaneButKeepsTheExitAndButtons() async {
        let (app, host, _) = make("2026-09-23T13:00:00+07:00") { withMusic(&$0) }
        app.switchActivityToStudio(sessionId: id)
        await app.settleActivity()
        let f = host.shown?.frame
        #expect(f?.points.isEmpty == true && f?.status == app.lexicon.t("day.running"))
        #expect(f?.exit != nil && f?.call != nil && f?.playlist != nil)
    }

    @Test func theTapStartsThePlateInStudioModeWhenThereWasNone() async {
        let (app, host, _) = make("2026-09-23T13:00:00+07:00")
        app.switchActivityToStudio(sessionId: id)
        await app.settleActivity()
        #expect(host.log == ["start"] && host.shown?.frame.mode == .studio)
    }

    @Test func studioModeEndsWithTheShoot() async {
        let (app, host, clock) = make("2026-09-23T13:00:00+07:00")
        app.switchActivityToStudio(sessionId: id)
        await app.settleActivity()
        at(clock, "2026-09-23T13:51:00+07:00")
        await sync(app)
        #expect(host.shown == nil && app.activityStudioFor == nil)
    }

    // MARK: Ссылки кнопок

    @Test func theCallButtonDialsTheAdminOfTheRunningStudioShoot() async {
        let (app, host, _) = make("2026-09-23T13:00:00+07:00")
        var opened: [URL] = []
        app.activityOpen = { opened.append($0) }
        await sync(app)
        #expect(app.openActivityLink(ActivityLink.admin.url))
        #expect(opened.map(\.absoluteString) == ["tel:+79618878078"], "\(opened)")
        #expect(host.shown != nil)
    }

    @Test func thePlaylistButtonOpensThePlaylistOfTheShoot() async {
        let (app, _, _) = make("2026-09-23T13:00:00+07:00") { withMusic(&$0) }
        var opened: [URL] = []
        app.activityOpen = { opened.append($0) }
        await sync(app)
        #expect(app.openActivityLink(ActivityLink.playlist.url))
        #expect(opened.map(\.absoluteString) == ["https://open.spotify.com/playlist/a"])
    }

    @Test func foreignLinksAreNotOurs() {
        let (app, _, _) = make("2026-09-23T13:00:00+07:00")
        #expect(!app.openActivityLink(URL(string: "lightplan://day/2026-09-23")!))
        #expect(!app.openActivityLink(URL(string: "lightplan://activity/other")!))
    }

    @Test func noRunningShootNoCall() {
        let (app, _, _) = make("2026-09-23T10:00:00+07:00")
        var opened: [URL] = []
        app.activityOpen = { opened.append($0) }
        #expect(app.openActivityLink(ActivityLink.admin.url), "ссылка наша, звонить некому")
        #expect(opened.isEmpty)
    }

    // MARK: Слова

    @Test func theFrameCarriesTheWordsOfTheApp() async {
        let (app, host, _) = make("2026-09-23T13:00:00+07:00")
        await sync(app)
        let f = host.shown?.frame
        #expect(f?.exit?.label == app.lexicon.t("activity.exit"))
        #expect(f?.status.hasPrefix(app.lexicon.t("day.nowAt").replacingOccurrences(of: "{name}", with: "")) == true || f?.status == app.lexicon.t("day.running"))
        #expect(app.activityWords().untilName == "до {name}")
    }
}
