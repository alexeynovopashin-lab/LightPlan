import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Шаг 29.8в.12: «Я здесь», «Следовать за мной», место помнится между запусками. Слово Алексея 18.10: выбрал
/// Томск в «Где снимаем», перезапустил — снова Москва (на старом коде: столица 55.7558, 37.6173, пояс Москвы).
@MainActor
struct PlaceFollowTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }

    /// Геокодер, который всякую точку зовёт Томском с настоящим поясом +7.
    private struct TomskGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: "Томск", region: "Томская область", country: "Россия", zoneIdentifier: "Asia/Tomsk")
        }
    }

    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }

    /// Телефон: доступ, точка, слежение. Первый вопрос без доступа отвечает так, как ответил бы человек в окне.
    private final class Phone: DeviceLocating {
        var state: LocationAccess
        var fix: GeoCoordinate
        let grantOnAsk: Bool
        private(set) var asked = 0
        private(set) var stops = 0
        private(set) var watcher: (@MainActor (GeoCoordinate) -> Void)?

        init(_ state: LocationAccess, at fix: GeoCoordinate, grantOnAsk: Bool = true) {
            self.state = state; self.fix = fix; self.grantOnAsk = grantOnAsk
        }
        var isAlreadyAuthorized: Bool { state == .granted }
        var needsPermission: Bool { state == .notAsked }
        func currentFix() async -> DeviceFix {
            asked += 1
            if state == .notAsked { state = grantOnAsk ? .granted : .denied }
            return state == .granted ? .fix(fix) : .denied
        }
        func startWatching(_ onFix: @escaping @MainActor (GeoCoordinate) -> Void) { watcher = onFix }
        func stopWatching() { watcher = nil; stops += 1 }
    }

    private let zone = TimeZone(identifier: "Asia/Tomsk")!
    private let tomsk = GeoCoordinate(latitude: 56.4846, longitude: 84.9476)
    private let lagerny = GeoCoordinate(latitude: 56.4560, longitude: 84.9550)   // Лагерный сад, ~3,2 км к югу
    private let moscow = GeoCoordinate(latitude: 55.7558, longitude: 37.6173)
    private let now = ISO8601DateFormatter().date(from: "2026-10-18T09:33:00+07:00")!

    private func model(_ phone: Phone, memory: PlaceMemory = InMemoryPlaceMemory(), snapshot: Snapshot = Snapshot(),
                       store: Store? = nil, clock: (@Sendable () -> Date)? = nil) -> AppModel {
        let fixed = now
        return AppModel(snapshot: snapshot, store: store, language: "ru", zone: zone, locator: phone,
                        geocoder: TomskGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather(),
                        placeMemory: memory, now: clock ?? { fixed })
    }

    private func settle(_ app: AppModel, until done: () -> Bool = { false }) async {
        for _ in 0..<100 where !done() { await Task.yield() }
    }

    // MARK: - Слежение включено по умолчанию

    @Test func followingIsOnByDefaultAndTakesThePhone() async {
        let phone = Phone(.granted, at: tomsk)
        let app = model(phone)
        #expect(app.following)
        await settle(app) { app.place.coordinate == tomsk }
        #expect(app.followShown == .on)
        #expect(app.followingLive)
        #expect(app.light.placeFollowing)                  // стрелка в шапке сплошная
        #expect(app.place.coordinate == tomsk)
        #expect(app.citySource == .device)
        #expect(phone.watcher != nil)                      // слежение за смещением запущено
    }

    /// «Мой город» при слежении — запасной: свет стоит там, где телефон (раньше город настроек побеждал).
    @Test func phoneBeatsHomeCityWhileFollowing() async {
        var snap = Snapshot()
        snap.extra["me"] = .object(["city": .string("Москва"), "cityLat": .number(moscow.latitude),
                                    "cityLon": .number(moscow.longitude), "met": .bool(true)])
        let app = model(Phone(.granted, at: tomsk), snapshot: snap)
        await settle(app) { app.place.coordinate == tomsk }
        #expect(app.place.coordinate == tomsk)
    }

    // MARK: - Ручной выбор выключает слежение

    @Test func pickingByHandTurnsFollowingOff() async {
        let phone = Phone(.granted, at: tomsk)
        let app = model(phone)
        await settle(app) { app.place.coordinate == tomsk }
        app.movePlace(to: moscow)
        #expect(!app.following)
        #expect(app.followShown == .offByChoice)           // подпись «Выключено: место выбрано вручную»
        #expect(!app.light.placeFollowing)                 // стрелка контурная
        #expect(phone.watcher == nil && phone.stops >= 1)
        // Телефон уехал на километры — место приложения стоит, где выбрали.
        phone.fix = lagerny
        app.phoneArrived(lagerny)
        #expect(app.place.coordinate == moscow)
    }

    @Test func movingTheMapByHandTurnsFollowingOff() async {
        let app = model(Phone(.granted, at: tomsk))
        await settle(app) { app.place.coordinate == tomsk }
        app.moveFromMap(latitude: lagerny.latitude, longitude: lagerny.longitude)
        #expect(app.followShown == .offByChoice)
    }

    /// Переключатель снова включён — место сразу на телефоне, без порога 500 м.
    @Test func turningFollowingBackOnJumpsToThePhone() async {
        let phone = Phone(.granted, at: tomsk)
        let app = model(phone)
        await settle(app) { app.place.coordinate == tomsk }
        app.movePlace(to: moscow)
        await app.setFollowing(true)
        #expect(app.followShown == .on)
        #expect(app.place.coordinate == tomsk)
        #expect(phone.watcher != nil)
    }

    // MARK: - Перезапуск помнит место и переключатель

    @Test func restartKeepsHandPickedPlaceAndSwitch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-29-8v12-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir, debounce: .milliseconds(1))
        let memory = InMemoryPlaceMemory()
        var snap = Snapshot()
        snap.extra["me"] = .object(["met": .bool(true)])
        // Как у Алексея: доступа к геопозиции нет, «Мой город» пуст, Томск выбран в листе.
        let first = model(Phone(.denied, at: tomsk), memory: memory, snapshot: snap, store: store)
        #expect(first.light.locationName == "Москва")
        first.movePlace(to: tomsk)
        await first.place.settled()
        await settle(first) { first.light.locationName == "Томск" }
        await first.flush()

        let second = model(Phone(.denied, at: tomsk), memory: memory, snapshot: try await store.load(), store: store)
        #expect(second.place.coordinate == tomsk)
        #expect(second.light.locationName == "Томск")
        #expect(second.light.timebar.place.zone.identifier == "Asia/Tomsk")   // пояс помнится, не оценка +6
        #expect(second.citySource == .saved)
        #expect(!second.following)
        #expect(second.followShown == .offByChoice)
    }

    /// Запись на устройстве переживает пересоздание объекта памяти (та же папка настроек).
    @Test func deviceMemoryRoundTrips() {
        let suite = "lp-29-8v12-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DevicePlaceMemory(defaults: defaults).record == PlaceMemoryRecord())
        var rec = PlaceMemoryRecord()
        rec.following = false
        rec.offByChoice = true
        rec.place = .init(latitude: tomsk.latitude, longitude: tomsk.longitude, name: "Томск", sub: "Томская область",
                          zone: "Asia/Tomsk")
        rec.phone = .init(latitude: lagerny.latitude, longitude: lagerny.longitude, at: now, name: "Томск")
        DevicePlaceMemory(defaults: defaults).record = rec
        #expect(DevicePlaceMemory(defaults: defaults).record == rec)
    }

    /// Пустой «Мой город», слежение включено, доступ был: старт — последняя точка телефона, а не столица, ещё до
    /// свежей точки.
    @Test func startWithEmptyHomeTakesLastPhoneSpotNotCapital() {
        var rec = PlaceMemoryRecord()
        rec.phone = .init(latitude: tomsk.latitude, longitude: tomsk.longitude, at: now, name: nil)
        let phone = Phone(.granted, at: tomsk)
        let app = model(phone, memory: InMemoryPlaceMemory(rec))
        #expect(app.place.coordinate == tomsk)
        #expect(app.light.locationName != "Москва")
        #expect(app.citySource == .device)
    }

    // MARK: - Без доступа — честный отказ

    @Test func deniedAccessIsSaidHonestly() async {
        let phone = Phone(.denied, at: tomsk)
        let app = model(phone)
        #expect(app.following)                           // желание следить помнится
        #expect(app.followShown == .denied)              // «Нет доступа к геопозиции», ведёт в настройки
        #expect(!app.followingLive && !app.light.placeFollowing)
        await app.setFollowing(true)
        #expect(phone.asked == 0)                        // системного окна нет: отказано — значит в настройки
        #expect(app.place.coordinate == moscow)          // место не выдумано
        #expect(phone.watcher == nil)
    }

    @Test func notAskedAccessAsksOnTheSwitch() async {
        let phone = Phone(.notAsked, at: tomsk)
        let app = model(phone)
        #expect(app.followShown == .needsAccess)
        #expect(phone.asked == 0)                        // на старте не спрашиваем
        await app.setFollowing(true)
        #expect(phone.asked == 1)
        #expect(app.followShown == .on)
        #expect(app.place.coordinate == tomsk)
    }

    @Test func refusedInTheWindowStaysHonest() async {
        let phone = Phone(.notAsked, at: tomsk, grantOnAsk: false)
        let app = model(phone)
        await app.setFollowing(true)
        #expect(app.followShown == .denied)
        #expect(app.place.coordinate == moscow)
    }

    // MARK: - Порог 500 м

    @Test func smallMovesDoNotMoveThePlace() async throws {
        let phone = Phone(.granted, at: tomsk)
        let app = model(phone)
        await settle(app) { app.place.coordinate == tomsk }
        let watcher = try #require(phone.watcher)
        let near = GeoCoordinate(latitude: tomsk.latitude + 0.003, longitude: tomsk.longitude)   // ~334 м
        #expect(kmBetween(tomsk, near) < PlaceFollow.moveKm)
        watcher(near)
        #expect(app.place.coordinate == tomsk)
        #expect(app.phoneFix?.coordinate == near)        // точка запомнена: «обновлено только что»
        watcher(lagerny)                                 // ~3,2 км
        #expect(app.place.coordinate == lagerny)
    }

    @Test func agoWords() {
        #expect(PlaceFollow.ago(now, now: now.addingTimeInterval(30)) == ("loc.fixNow", 0))
        #expect(PlaceFollow.ago(now, now: now.addingTimeInterval(180)) == ("loc.fixMin", 3))
        #expect(PlaceFollow.ago(now, now: now.addingTimeInterval(7300)) == ("loc.fixHour", 2))
        #expect(PlaceFollow.ago(now, now: now.addingTimeInterval(200_000)) == ("loc.fixDay", 2))
    }

    // MARK: - AR открывается на «сейчас»

    @Test func arEntryIsAlwaysNow() async throws {
        let app = model(Phone(.granted, at: tomsk))
        await settle(app) { app.place.coordinate == tomsk }
        let tb = app.light.timebar
        for _ in 0..<200 where tb.place.longitude < 80 { try await Task.sleep(for: .milliseconds(10)) }
        tb.show(day: tb.machine.selectedDate, minute: 21 * 60)          // на карте выбран вечер
        app.enterSunAR()
        for _ in 0..<200 where app.sunAR == nil { try await Task.sleep(for: .milliseconds(10)) }
        let target = try #require(app.sunAR)
        #expect(target.moment == Moment(now))
        // Плашка «вы далеко» несёт тот же момент: место приложения руками в Москве, телефон в Томске.
        app.closeSunAR()
        app.movePlace(to: moscow)
        for _ in 0..<200 where app.light.timebar.place.longitude > 40 { try await Task.sleep(for: .milliseconds(10)) }
        tb.show(day: tb.machine.selectedDate, minute: 21 * 60)
        app.enterSunAR()
        for _ in 0..<200 where app.sunAREntry == nil || app.sunAREntry?.reason == .locating {
            try await Task.sleep(for: .milliseconds(10))
        }
        let entry = try #require(app.sunAREntry)
        #expect(entry.moment == Moment(now))
        #expect(app.sunAR == nil)
    }
}
