import Foundation
import LightPlanCore
import LightPlanData

/// Что приложение помнит о своём месте между запусками (шаг 29.8в.12). Слово Алексея 18.10: выбрал Томск,
/// перезапустил — снова Москва; выбор руками не писался никуда, а при пустом «Моём городе» и без доступа к
/// геопозиции старт брал столицу по языку. Флаг устройства, как калибровка AR: в снимок съёмок и в облако не
/// уходит — где стоит телефон, другим устройствам знать незачем.
struct PlaceMemoryRecord: Codable, Equatable {
    /// «Следовать за мной». Включено, пока место не выбрали руками (ответ Алексея 18.10, п. 1).
    var following = true
    /// Слежение выключилось само — место выбрали руками; выключенное переключателем — `false`.
    var offByChoice = false
    /// Последнее место приложения: с ним приложение и открывается, если не следит за телефоном.
    var place: Saved?
    /// Последняя точка телефона и когда она пришла («обновлено N мин назад» под «Я здесь»).
    var phone: PhoneFix?

    struct Saved: Codable, Equatable {
        var latitude: Double
        var longitude: Double
        var name: String?
        var sub: String?
        /// Настоящий пояс места, если геокодер уже ответил: без него Томск после перезапуска считался бы по
        /// долготе (+6 вместо +7).
        var zone: String?

        var coordinate: GeoCoordinate { GeoCoordinate(latitude: latitude, longitude: longitude) }
    }

    struct PhoneFix: Codable, Equatable {
        var latitude: Double
        var longitude: Double
        var at: Date
        /// Имя места телефона, если оно уже известно (город и область от геокодера).
        var name: String?

        var coordinate: GeoCoordinate { GeoCoordinate(latitude: latitude, longitude: longitude) }
    }
}

@MainActor
protocol PlaceMemory: AnyObject {
    var record: PlaceMemoryRecord { get set }
}

/// Память на время запуска: тесты и снимки пар, которые не должны видеть друг друга.
@MainActor
final class InMemoryPlaceMemory: PlaceMemory {
    var record: PlaceMemoryRecord
    init(_ record: PlaceMemoryRecord = PlaceMemoryRecord()) { self.record = record }
}

/// Память телефона: одна запись JSON в `UserDefaults`.
@MainActor
final class DevicePlaceMemory: PlaceMemory {
    static let key = "lightplan.native.place.memory"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var record: PlaceMemoryRecord {
        get {
            defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(PlaceMemoryRecord.self, from: $0) }
                ?? PlaceMemoryRecord()
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key) }
    }
}

/// Правила слежения без вида и без телефона — чтобы их держали тесты.
enum PlaceFollow {
    /// Телефон сместился меньше — место приложения стоит: свет и погода не пересчитываются от шума точки.
    static let moveKm = 0.5

    static func shouldMove(from current: GeoCoordinate, to phone: GeoCoordinate) -> Bool {
        kmBetween(current, phone) > moveKm
    }

    /// Состояние переключателя «Следовать за мной», как его видит человек.
    enum Shown: Equatable {
        /// Включено, доступ есть: место приложения — место телефона.
        case on
        /// Выключено переключателем.
        case off
        /// Выключилось само: место выбрали руками.
        case offByChoice
        /// Хочет следить, но доступа ещё не спрашивали: касание покажет системное окно.
        case needsAccess
        /// Хочет следить, но доступа нет: касание ведёт в настройки телефона.
        case denied
    }

    static func shown(following: Bool, offByChoice: Bool, access: LocationAccess) -> Shown {
        guard following else { return offByChoice ? .offByChoice : .off }
        switch access {
        case .granted: return .on
        case .notAsked: return .needsAccess
        case .denied: return .denied
        }
    }

    /// «обновлено N мин назад»: ключ словаря и число. Меньше минуты — «только что».
    static func ago(_ at: Date, now: Date) -> (key: String, n: Int) {
        let s = max(0, now.timeIntervalSince(at))
        if s < 60 { return ("loc.fixNow", 0) }
        if s < 3600 { return ("loc.fixMin", Int(s / 60)) }
        if s < 86_400 { return ("loc.fixHour", Int(s / 3600)) }
        return ("loc.fixDay", Int(s / 86_400))
    }
}

extension AppModel {
    /// Переключатель листа «Где снимаем», как его видит человек.
    var followShown: PlaceFollow.Shown {
        PlaceFollow.shown(following: following, offByChoice: followOffByChoice, access: locationAccess)
    }

    /// Значок-стрелка в шапке: сплошная — место приложения следует за телефоном.
    public var followingLive: Bool { followShown == .on }

    /// Последняя точка телефона, пришедшая в этот или прошлый запуск.
    var phoneFix: PlaceMemoryRecord.PhoneFix? { placeMemoryRecord.phone }

    /// Переключатель «Следовать за мной». Включение без доступа: ещё не спрашивали — системное окно здесь же;
    /// отказано — ничего не выдумываем, вид ведёт в настройки телефона (`followShown == .denied`).
    /// Включили — место сразу встаёт туда, где телефон, без порога 500 м.
    func setFollowing(_ on: Bool) async {
        guard on else {
            following = false
            followOffByChoice = false
            locator.stopWatching()
            remember()
            return
        }
        following = true
        followOffByChoice = false
        remember()
        guard locator.access != .denied else { refreshLocationAccess(); return }
        let fix = await locator.currentFix()
        refreshLocationAccess()
        guard following else { return }
        if case .fix(let c) = fix { phoneArrived(c, force: true) }
        startWatchingIfFollowing()
    }

    /// Доступ мог смениться в настройках телефона — сверяем, когда приложение снова на экране, и берём свежую
    /// точку, если следим.
    func placeBecameActive() {
        let before = locationAccess
        refreshLocationAccess()
        startWatchingIfFollowing()
        guard followingLive else { return }
        if before != .granted || phoneFix == nil || now().timeIntervalSince(phoneFix!.at) > 300 {
            Task { await self.followFreshFix() }
        }
    }

    func refreshLocationAccess() {
        let a = locator.access
        if locationAccess != a { locationAccess = a }
    }

    func startWatchingIfFollowing() {
        if followingLive {
            locator.startWatching { [weak self] c in self?.phoneArrived(c) }
        } else {
            locator.stopWatching()
        }
    }

    /// Старт со слежением: место телефона спрашивается сразу (доступ уже дан — без системного окна).
    func followFreshFix() async {
        guard followingLive else { return }
        if case .fix(let c) = await locator.currentFix() { phoneArrived(c, force: true) }
    }

    /// Пришла точка телефона (слежение, «Я здесь», вход в AR). Запоминается всегда; место приложения едет за
    /// ней, только пока слежение включено и телефон ушёл дальше 500 м (`force` — без порога).
    func phoneArrived(_ c: GeoCoordinate, force: Bool = false) {
        var rec = placeMemoryRecord
        let keepName = rec.phone.map { !PlaceFollow.shouldMove(from: $0.coordinate, to: c) } ?? false
        rec.phone = .init(latitude: c.latitude, longitude: c.longitude, at: now(), name: keepName ? rec.phone?.name : nil)
        placeMemoryRecord = rec
        guard following else { remember(); return }
        if force || PlaceFollow.shouldMove(from: place.coordinate, to: c) {
            place.move(to: c)
            citySource = .device
        }
        remember()
    }

    /// Место выбрали руками (лист, «Мои места», карта пальцем): слежение выключается само.
    func choseByHand() {
        guard following else { return }
        following = false
        followOffByChoice = true
        locator.stopWatching()
    }

    /// Записать нынешнее место и состояние слежения. Имя — только когда оно уже пришло для этой точки.
    func remember() {
        var rec = placeMemoryRecord
        rec.following = following
        rec.offByChoice = followOffByChoice
        let c = place.coordinate
        let named = !place.isNameStale
        rec.place = .init(latitude: c.latitude, longitude: c.longitude,
                          name: named ? place.name?.city : nil, sub: named ? place.name?.sub : nil,
                          zone: place.zones.zone(at: c)?.identifier)
        if named, let ph = rec.phone, !PlaceFollow.shouldMove(from: ph.coordinate, to: c), let n = place.name {
            rec.phone?.name = n.sub.isEmpty ? n.city : n.city + ", " + n.sub
        }
        placeMemoryRecord = rec
    }
}
