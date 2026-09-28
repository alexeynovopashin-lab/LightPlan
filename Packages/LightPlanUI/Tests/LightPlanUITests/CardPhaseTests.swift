import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 25, шаг 2: фазы карточки на записях посева сезона
/// (`Fixtures/shots/seed_planner.json`, часы посева — 23.09.2026 13:00 +07),
/// «Завершать вручную» и кнопка «Завершить».
@MainActor
struct CardPhaseTests {

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

    static let seed: Snapshot = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        u.appendPathComponent("Fixtures/shots/seed_planner.json")
        do { return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: u)) }
        catch { fatalError("нет или не читается \(u.path): \(error)") }
    }()

    /// Пояс Томска: телефон узнаёт его от геокодера, когда место приложения —
    /// Томск. В посеве его нет — там только Барнаул.
    private static let tomskZone = ["56.5,85.0": JSONValue.string("Asia/Tomsk")]

    /// Приложение посева в момент `iso`; телефон в Барнауле.
    private func app(_ iso: String, manualEnd: Bool = false, tomsk: Bool = true,
                     edit: (inout Snapshot) -> Void = { _ in }) -> AppModel {
        var snap = Self.seed
        if tomsk, case .object(var z)? = snap.extra["zones"] {
            for (k, v) in Self.tomskZone { z[k] = v }
            snap.extra["zones"] = .object(z)
        }
        snap.manualEnd = manualEnd
        edit(&snap)
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private func rec(_ app: AppModel, _ id: String) -> Session {
        app.sessions.first { $0.id == id }!
    }

    private func phase(_ app: AppModel, _ id: String) -> EventPhase { app.phase(of: rec(app, id)) }

    // MARK: - Три фазы на записях посева

    /// В 13:00 посева: портрет в студии (12:20–13:50) идёт, встреча вечером и
    /// свадьба завтра — впереди, августовские и лавстори 17.09 — прошли.
    @Test func seedPhasesAtSeedClock() {
        let a = app("2026-09-23T13:00:00+07:00")
        #expect(rec(a, "sd_sep_now").day == CivilDate(year: 2026, month: 9, day: 23))
        #expect(phase(a, "sd_sep_now") == .during)
        #expect(phase(a, "sd_sep_meet") == .before)
        #expect(phase(a, "sd_sep_wed") == .before)
        #expect(phase(a, "sd_oct_street") == .before)
        #expect(phase(a, "sd_sep_love") == .after)
        #expect(phase(a, "sd_aug_wed") == .after)
    }

    /// «Во время» — ровно записанные рамки: минута начала и минута конца
    /// включительно, ни минуты запаса (веб убрал `TAIL_MIN` 29.08.2026).
    @Test func duringIsExactlyTheRecordedFrame() {
        let at = { (t: String) in self.phase(self.app("2026-09-23T\(t):00+07:00"), "sd_sep_now") }
        #expect(at("12:19") == .before)
        #expect(at("12:20") == .during)
        #expect(at("13:50") == .during)
        #expect(at("13:51") == .after)
    }

    /// Свадьба с пятью точками: банкет кончается в 22:00 вместе с записью —
    /// точки маршрута «во время» не продлевают.
    @Test func routeDoesNotStretchDuring() {
        let at = { (t: String) in self.phase(self.app("2026-09-24T\(t):00+07:00"), "sd_sep_wed") }
        #expect(at("10:59") == .before)
        #expect(at("11:00") == .during)
        #expect(at("22:00") == .during)
        #expect(at("22:01") == .after)
    }

    /// Часы — места съёмки, не телефона. Пояс Томска в посеве не записан, и
    /// оценка по долготе даёт +6: в 13:00 телефона у студии 12:00, портрет
    /// ещё впереди. Так же считает веб (`tzAt`).
    @Test func studioWithoutKnownZoneUsesLongitudeEstimate() {
        let a = app("2026-09-23T13:00:00+07:00", tomsk: false)
        #expect(phase(a, "sd_sep_now") == .before)
    }

    /// Съёмка в Москве, телефон в Барнауле (+4 к Москве). В 18:30 по Москве
    /// (22:30 телефона) она идёт; по часам телефона вышла бы прошедшей.
    @Test func phaseReadsShootPlaceClockNotPhone() {
        let a = app("2026-09-23T18:30:00+03:00", edit: moscowShoot)
        #expect(phase(a, "msk") == .during)
    }

    /// Москва 18:00–19:00 23.09, пояс Москвы известен.
    private func moscowShoot(_ s: inout Snapshot) {
        var r = Session(id: "msk", day: CivilDate(year: 2026, month: 9, day: 23), start: 1080, end: 1140, genre: .portrait)
        r.latitude = 55.7558; r.longitude = 37.6173
        s.sessions.append(r)
        if case .object(var z)? = s.extra["zones"] {
            z["56.0,37.5"] = .string("Europe/Moscow")
            s.extra["zones"] = .object(z)
        }
    }

    // MARK: - «Завершать вручную» и «Завершить»

    /// Ручной режим держит «во время» за записанным концом до нажатия; на
    /// следующие сутки съёмка «после» и без нажатия (веб `shootMin` = `null`).
    @Test func manualEndHoldsDuringUntilMidnight() {
        #expect(phase(app("2026-09-23T14:30:00+07:00", manualEnd: true), "sd_sep_now") == .during)
        #expect(phase(app("2026-09-23T23:59:00+07:00", manualEnd: true), "sd_sep_now") == .during)
        #expect(phase(app("2026-09-24T00:10:00+07:00", manualEnd: true), "sd_sep_now") == .after)
        #expect(phase(app("2026-09-23T14:30:00+07:00", manualEnd: false), "sd_sep_now") == .after)
    }

    /// «Завершить» есть только у идущей съёмки и только в ручном режиме.
    @Test func finishIsOfferedOnlyToRunningShootWithManualEnd() {
        let on = app("2026-09-23T14:30:00+07:00", manualEnd: true)
        #expect(on.canFinish(rec(on, "sd_sep_now")))
        #expect(!on.canFinish(rec(on, "sd_sep_wed")))          // завтра — «до»
        #expect(!on.canFinish(rec(on, "sd_sep_love")))         // прошла
        let off = app("2026-09-23T13:00:00+07:00", manualEnd: false)
        #expect(off.phase(of: rec(off, "sd_sep_now")) == .during)
        #expect(!off.canFinish(rec(off, "sd_sep_now")))        // режим выключен
        // Встреча не завершается кнопкой (`notWork`), даже когда идёт.
        let meet = app("2026-09-23T19:30:00+07:00", manualEnd: true)
        #expect(meet.phase(of: rec(meet, "sd_sep_meet")) == .during)
        #expect(!meet.canFinish(rec(meet, "sd_sep_meet")))
    }

    /// Нажатие пишет минуту шкалы съёмки по часам места — съёмка сразу «после».
    @Test func finishTurnsShootToAfter() {
        let a = app("2026-09-23T14:30:00+07:00", manualEnd: true)
        a.finishSession(id: "sd_sep_now")
        #expect(rec(a, "sd_sep_now").doneAt == 870)
        #expect(rec(a, "sd_sep_now").modifiedAt == AppModel.ms(ISO8601DateFormatter().date(from: "2026-09-23T14:30:00+07:00")!))
        #expect(a.phase(of: rec(a, "sd_sep_now")) == .after)
        #expect(!a.canFinish(rec(a, "sd_sep_now")))
    }

    /// Ошибка веба, которую не переносим: он пишет `doneAt` часами телефона.
    /// Телефон в Барнауле (+4 к Москве), съёмка в Москве, нажали в 19:30 по
    /// Москве — веб записал бы 23:30 (1410) и держал «во время» ещё 4 часа.
    @Test func finishInForeignZoneUsesShootPlaceClock() {
        let a = app("2026-09-23T19:30:00+03:00", manualEnd: true, edit: moscowShoot)
        #expect(a.phase(of: rec(a, "msk")) == .during)
        a.finishSession(id: "msk")
        #expect(rec(a, "msk").doneAt == 1170)
        #expect(a.phase(of: rec(a, "msk")) == .after)
    }

    /// Свадьба через полночь (19:10 → 03:10): в 00:31 вторых суток нажатие
    /// пишет 1471 — ту же шкалу, с которой сравнивает фаза.
    @Test func finishAfterMidnightUsesShootScale() {
        let a = app("2026-09-25T00:31:00+07:00", manualEnd: true) { s in
            var w = Session(id: "late", day: CivilDate(year: 2026, month: 9, day: 24), start: 1150, end: 1630, genre: .wedding)
            w.latitude = 53.3548; w.longitude = 83.7698
            s.sessions.append(w)
        }
        #expect(a.phase(of: rec(a, "late")) == .during)
        a.finishSession(id: "late")
        #expect(rec(a, "late").doneAt == 1471)
        #expect(a.phase(of: rec(a, "late")) == .after)
    }

    /// Выключение режима снимает все отметки: иначе завершённая руками съёмка
    /// осталась бы завершённой без кнопки (веб, L33940).
    @Test func turningManualEndOffClearsFinishMarks() {
        let a = app("2026-09-23T14:30:00+07:00", manualEnd: true)
        a.finishSession(id: "sd_sep_now")
        #expect(a.settings.manualEnd)
        a.update { $0.manualEnd = false }
        #expect(a.sessions.allSatisfy { $0.doneAt == nil })
        #expect(!a.snapshotForTests.manualEnd)
        #expect(a.phase(of: rec(a, "sd_sep_now")) == .after)   // 14:30 — за концом 13:50
    }

    /// Ключ веба `manualEnd` читается и пишется снимком.
    @Test func manualEndTravelsWithSnapshot() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"manualEnd":true}"#.utf8))
        #expect(s.manualEnd)
        #expect(AppSettings(snapshot: s).manualEnd)
        #expect(s.extra["manualEnd"] == nil)
        let back = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(s))
        #expect(back.manualEnd)
        #expect(!AppSettings(snapshot: Snapshot()).manualEnd)
    }

    // MARK: - Открытие карточки

    @Test func cardOpensAndClosesByRecord() {
        let a = app("2026-09-23T13:00:00+07:00")
        #expect(a.card == nil)
        a.openCard(id: "sd_sep_now")
        #expect(a.card?.id == "sd_sep_now")
        a.closeCard()
        #expect(a.card == nil)
        a.openCard(id: "нет такой")
        #expect(a.card == nil)
    }

    /// Запись ушла в корзину — карточке показывать нечего.
    @Test func cardClosesWhenItsRecordIsBinned() {
        let a = app("2026-09-23T13:00:00+07:00")
        a.openCard(id: "sd_sep_now")
        a.trashSession(id: "sd_sep_now")
        #expect(a.card == nil)
    }
}
