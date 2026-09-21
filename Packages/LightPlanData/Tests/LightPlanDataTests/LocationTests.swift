import Foundation
import Testing
import LightPlanCore
@testable import LightPlanData

// MARK: - Замеры CLGeocoder

/// Ответы `CLGeocoder` (ru_RU), записанные на Mac 21.09.2026 — десять проверочных точек.
/// Пересобирать руками не нужно: это снимок, а не эталон. Эталон правил — бета.
private struct Recorded {
    let title: String
    let lat, lon: Double
    let locality, region, country, zone: String
    let city: String?, sub: String?
}

private let recorded: [Recorded] = [
    .init(title: "Москва", lat: 55.7558, lon: 37.6173, locality: "Москва", region: "Москва", country: "Россия", zone: "Europe/Moscow", city: "Москва", sub: ""),
    .init(title: "Петербург", lat: 59.9343, lon: 30.3351, locality: "Санкт-Петербург", region: "Санкт-Петербург", country: "Россия", zone: "Europe/Moscow", city: "Санкт-Петербург", sub: ""),
    .init(title: "Томск", lat: 56.489, lon: 84.952, locality: "Томск", region: "Томская область", country: "Россия", zone: "Asia/Tomsk", city: "Томск", sub: "Томская область"),
    .init(title: "Лобня", lat: 56.011, lon: 37.483, locality: "Лобня", region: "Московская Область", country: "Россия", zone: "Europe/Moscow", city: "Лобня", sub: "Московская Область"),
    .init(title: "Казань", lat: 55.7887, lon: 49.1221, locality: "Казань", region: "Татарстан", country: "Россия", zone: "Europe/Moscow", city: "Казань", sub: "Татарстан"),
    .init(title: "Севастополь", lat: 44.6167, lon: 33.5254, locality: "Севастополь", region: "Севастополь", country: "Украина", zone: "Europe/Moscow", city: "Севастополь", sub: ""),
    .init(title: "Берлин", lat: 52.52, lon: 13.405, locality: "Берлин", region: "Берлин", country: "Германия", zone: "Europe/Berlin", city: "Берлин", sub: ""),
    .init(title: "Каппадокия", lat: 38.6431, lon: 34.8289, locality: "Nevşehir Merkez", region: "Невшехир ил", country: "Турция", zone: "Europe/Istanbul", city: "Nevşehir Merkez", sub: "Невшехир ил"),
    .init(title: "Дели", lat: 28.6139, lon: 77.209, locality: "Нью-Дели", region: "Дели", country: "Индия", zone: "Asia/Kolkata", city: "Нью-Дели", sub: "Дели"),
    .init(title: "Барселона", lat: 41.3874, lon: 2.1686, locality: "Барселона", region: "Barcelona", country: "Испания", zone: "Europe/Madrid", city: "Барселона", sub: "Barcelona"),
]

struct RecordedPlacemarkTests {
    @Test func tenPointsGiveTheNamesTheRulesPromise() {
        #expect(recorded.count == 10)
        for r in recorded {
            let got = PlaceNameRules.name(locality: r.locality, region: r.region, country: r.country)
            #expect(got?.city == r.city, "\(r.title)")
            #expect(got?.sub == r.sub, "\(r.title)")
            // Город из ответа и город, который вернул бы веб для той же строки, — одно и то же
            let web = LocationOracle.file.clean.first { $0.in == r.locality }?.out
            #expect(web == r.city, "\(r.title): веб \(web ?? "нет в эталоне")")
            #expect(ZoneID(r.zone) != nil, "\(r.title): \(r.zone)")
        }
    }

    @Test func noCityMeansNoName() {
        // Пустой город — нет имени, остаются координаты
        #expect(PlaceNameRules.name(locality: nil, region: "Томская область", country: "Россия") == nil)
        #expect(PlaceNameRules.name(locality: "Зольский район", region: "КБР", country: "Россия") == nil)
        #expect(PlaceNameRules.name(locality: "Место не определено", region: nil, country: nil) == nil)
        // Уточнение: регион, иначе страна; пустая строка регионом не считается
        #expect(PlaceNameRules.name(locality: "Ницца", region: "", country: "Франция")?.sub == "Франция")
        #expect(PlaceNameRules.name(locality: "Ницца", region: nil, country: nil)?.sub == "")
    }
}

// MARK: - Ручной ввод

struct ManualCoordinatesTests {
    private func parse(_ a: String, _ b: String) -> Result<GeoCoordinate, ManualCoordinates.Failure> {
        ManualCoordinates.parse(latitude: a, longitude: b)
    }

    @Test func readsWhatTheAppPrints() throws {
        for (la, lo) in [(56.011, 37.483), (-33.869, 151.209), (59.934, -30.335), (0.0, 0.0), (-0.001, -0.001)] {
            let c = GeoCoordinate(latitude: la, longitude: lo)
            let parts = c.text.components(separatedBy: " · ")
            let back = try parse(parts[0], parts[1]).get()
            #expect(back.latitude == la && back.longitude == lo, "\(c.text)")
        }
    }

    @Test func acceptsHumanSpellings() throws {
        #expect(try parse("56,011", "37.483").get() == GeoCoordinate(latitude: 56.011, longitude: 37.483))
        #expect(try parse(" 56.011° ", "84.952 E").get() == GeoCoordinate(latitude: 56.011, longitude: 84.952))
        #expect(try parse("33.5 s", "70.6 w").get() == GeoCoordinate(latitude: -33.5, longitude: -70.6))
        #expect(try parse("\u{2212}12.5", "+7").get() == GeoCoordinate(latitude: -12.5, longitude: 7))
        #expect(try parse("90", "180").get() == GeoCoordinate(latitude: 90, longitude: 180))
    }

    @Test func rejectsWithAReason() {
        #expect(parse("", "1") == .failure(.empty(.latitude)))
        #expect(parse("1", "  ") == .failure(.empty(.longitude)))
        #expect(parse("abc", "1") == .failure(.notANumber(.latitude)))
        #expect(parse("1e2", "1") == .failure(.notANumber(.latitude)))
        #expect(parse("0x10", "1") == .failure(.notANumber(.latitude)))
        #expect(parse("1.2.3", "1") == .failure(.notANumber(.latitude)))
        #expect(parse("1", "--5") == .failure(.notANumber(.longitude)))
        #expect(parse("-33.8 S", "1") == .failure(.notANumber(.latitude)))
        #expect(parse("90.0001", "0") == .failure(.outOfRange(.latitude)))
        #expect(parse("0", "-180.5") == .failure(.outOfRange(.longitude)))
        #expect(parse("56 E", "37") == .failure(.wrongHemisphere(.latitude)))
        #expect(parse("56", "37 N") == .failure(.wrongHemisphere(.longitude)))
        #expect(parse("56 X", "37") == .failure(.notANumber(.latitude)))
    }
}

// MARK: - Зоны и закладки

struct ZoneTests {
    @Test func estimateIsAFixedOffsetZone() {
        let d = CivilDate(year: 2026, month: 7, day: 1)
        #expect(ZoneEstimate.zone(longitude: 37.48).utcOffsetHours(on: d) == 3)
        #expect(ZoneEstimate.zone(longitude: 84.952).utcOffsetHours(on: d) == 6)   // реально +7: запасной путь
        #expect(ZoneEstimate.zone(longitude: -74).utcOffsetHours(on: d) == -4)     // Нью-Йорк летом; зимой оценка ошибётся на час
        #expect(ZoneEstimate.zone(longitude: 179).utcOffsetHours(on: d) == 12)
    }

    @Test func cacheServesRealZoneOverEstimate() throws {
        var cache = ZoneCache()
        let tomsk = GeoCoordinate(latitude: 56.489, longitude: 84.952)
        let d = CivilDate(year: 2026, month: 7, day: 1)
        #expect(cache.zoneOrEstimate(at: tomsk).utcOffsetHours(on: d) == 6)
        cache.remember(try #require(ZoneID("Asia/Tomsk")), at: tomsk)
        #expect(cache.zoneOrEstimate(at: tomsk).utcOffsetHours(on: d) == 7)
        // Соседняя точка в той же клетке в полградуса берёт тот же ответ, дальняя — нет
        #expect(cache.zone(at: GeoCoordinate(latitude: 56.3, longitude: 84.8))?.identifier == "Asia/Tomsk")
        #expect(cache.zone(at: GeoCoordinate(latitude: 57.2, longitude: 84.8)) == nil)
    }

    @Test func gmtPlaceholderIsNotRemembered() throws {
        var cache = ZoneCache()
        cache.remember(try #require(ZoneID("GMT")), at: GeoCoordinate(latitude: 1, longitude: 1))
        #expect(cache.entries.isEmpty)
    }
}

private struct Pin: Located { let coordinate: GeoCoordinate }

struct SavedPointsTests {
    @Test func firstIndexUsesTheSixtyMetreTolerance() {
        let pins = [Pin(coordinate: .init(latitude: 10, longitude: 10)),
                    Pin(coordinate: .init(latitude: 56.011, longitude: 37.483)),
                    Pin(coordinate: .init(latitude: 56.0112, longitude: 37.4832))]
        #expect(SavedPoints.firstIndex(near: .init(latitude: 56.0115, longitude: 37.4835), in: pins) == 1)
        #expect(SavedPoints.firstIndex(near: .init(latitude: 56.02, longitude: 37.483), in: pins) == nil)
        #expect(SavedPoints.firstIndex(near: .init(latitude: 0, longitude: 0), in: [Pin]()) == nil)
    }
}

// MARK: - Имя с кэшем, повтором и отменой

private actor ScriptedGeocoder: ReverseGeocoding {
    enum Step { case answer(GeocodeAnswer), fail, slowAnswer(GeocodeAnswer, Duration) }
    private var script: [String: [Step]]
    private(set) var calls: [String] = []
    struct Boom: Error {}

    init(_ script: [String: [Step]]) { self.script = script }

    func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
        calls.append(c.nameKey)
        var steps = script[c.nameKey] ?? []
        let step = steps.isEmpty ? Step.fail : steps.removeFirst()
        if !steps.isEmpty { script[c.nameKey] = steps }
        switch step {
        case .answer(let a): return a
        case .fail: throw Boom()
        case .slowAnswer(let a, let d):
            try? await Task.sleep(for: d)        // намеренно глухо к отмене: как сеть, которой не сказали
            return a
        }
    }
    var callCount: Int { calls.count }
}

private func answer(_ city: String?, region: String? = "Область", zone: String? = nil) -> GeocodeAnswer {
    GeocodeAnswer(locality: city, region: region, country: "Россия", zoneIdentifier: zone)
}

private let lobnya = GeoCoordinate(latitude: 56.011, longitude: 37.483)
private let tomsk = GeoCoordinate(latitude: 56.489, longitude: 84.952)

struct PlaceNamerTests {
    @Test func secondAskForTheSamePlaceDoesNotGoToTheNetwork() async throws {
        let g = ScriptedGeocoder([lobnya.nameKey: [.answer(answer("Лобня"))]])
        let namer = PlaceNamer(geocoder: g, retryDelay: .zero)
        let first = try await namer.lookup(lobnya)
        // Тот же ключ до тысячной градуса — другой сдвиг в 4-м знаке
        let second = try await namer.lookup(GeoCoordinate(latitude: 56.01102, longitude: 37.48298))
        #expect(first.name?.city == "Лобня" && second == first)
        #expect(await g.callCount == 1)
    }

    @Test func oneRetryThenSuccess() async throws {
        let g = ScriptedGeocoder([lobnya.nameKey: [.fail, .answer(answer("Лобня"))]])
        let got = try await PlaceNamer(geocoder: g, retryDelay: .zero).lookup(lobnya)
        #expect(got.name?.city == "Лобня")
        #expect(await g.callCount == 2)
    }

    @Test func twoFailuresLeaveCoordinatesAndAreNotCached() async throws {
        let g = ScriptedGeocoder([lobnya.nameKey: [.fail, .fail, .answer(answer("Лобня"))]])
        let namer = PlaceNamer(geocoder: g, retryDelay: .zero)
        #expect(try await namer.lookup(lobnya).name == nil)
        #expect(await g.callCount == 2)
        // Сеть вернулась — спрашиваем заново, а не помним отказ
        #expect(try await namer.lookup(lobnya).name?.city == "Лобня")
    }

    @Test func emptyAnswerIsFinalAndCached() async throws {
        let g = ScriptedGeocoder([lobnya.nameKey: [.answer(answer(nil))]])
        let namer = PlaceNamer(geocoder: g, retryDelay: .zero)
        #expect(try await namer.lookup(lobnya).name == nil)
        #expect(try await namer.lookup(lobnya).name == nil)
        #expect(await g.callCount == 1)
    }

    @Test func realZoneComesWithTheName() async throws {
        let g = ScriptedGeocoder([tomsk.nameKey: [.answer(answer("Томск", zone: "Asia/Tomsk"))]])
        let got = try await PlaceNamer(geocoder: g, retryDelay: .zero).lookup(tomsk)
        #expect(got.zone?.identifier == "Asia/Tomsk")
    }

    @Test func cancelledQuestionThrowsInsteadOfAnsweringLate() async {
        let g = ScriptedGeocoder([lobnya.nameKey: [.slowAnswer(answer("Лобня"), .milliseconds(80))]])
        let namer = PlaceNamer(geocoder: g, retryDelay: .zero)
        let task = Task { try await namer.lookup(lobnya) }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

// MARK: - «Где мы»

@MainActor
private final class StubLocator: DeviceLocating {
    var result: DeviceFix
    var asked = 0
    init(_ r: DeviceFix) { result = r }
    func currentFix() async -> DeviceFix { asked += 1; return result }
}

@MainActor
struct CurrentPlaceTests {
    private func make(_ g: ScriptedGeocoder, _ locator: StubLocator, name: PlaceName? = PlaceName(city: "Лобня", sub: "Московская Область")) -> CurrentPlace {
        CurrentPlace(initial: lobnya, name: name, namer: PlaceNamer(geocoder: g, retryDelay: .zero),
                     locator: locator, debounce: .zero)
    }

    @Test func denialLeavesTheLastSavedPlaceUntouched() async {
        let g = ScriptedGeocoder([:])
        for verdict in [DeviceFix.denied, .restricted, .unavailable] {
            let locator = StubLocator(verdict)
            let here = make(g, locator)
            await here.useDeviceLocation()
            #expect(here.coordinate == lobnya)
            #expect(here.name?.city == "Лобня")
            #expect(!here.isNameStale)
            #expect(here.lastDeviceResult == verdict)
            #expect(locator.asked == 1)
        }
        #expect(await g.callCount == 0)
    }

    @Test func fixMovesThePlaceAndNamesIt() async {
        let g = ScriptedGeocoder([tomsk.nameKey: [.answer(answer("Томск", region: "Томская область", zone: "Asia/Tomsk"))]])
        let here = make(g, StubLocator(.fix(tomsk)))
        await here.useDeviceLocation()
        #expect(here.coordinate == tomsk)
        #expect(here.isNameStale)                       // имя ещё в пути
        #expect(here.name?.city == "Лобня")             // держится прежнее
        #expect(here.zone.utcOffsetHours(on: CivilDate(year: 2026, month: 7, day: 1)) == 6)   // пока оценка
        await here.settled()
        #expect(here.name == PlaceName(city: "Томск", sub: "Томская область"))
        #expect(!here.isNameStale)
        #expect(here.zone.identifier == "Asia/Tomsk")
        #expect(here.zones.zone(at: tomsk)?.identifier == "Asia/Tomsk")
    }

    @Test func noNameAfterTwoFailuresFallsBackToCoordinates() async {
        let g = ScriptedGeocoder([:])                   // молчит всё
        let here = make(g, StubLocator(.denied))
        here.move(to: tomsk)
        await here.settled()
        #expect(here.name == nil)
        #expect(!here.isNameStale)
        #expect(here.coordinate.text == "56.489 N · 84.952 E")
    }

    @Test func lateAnswerForAnOldPlaceNeverOverridesTheNewOne() async {
        let g = ScriptedGeocoder([
            lobnya.nameKey: [.slowAnswer(answer("Лобня"), .milliseconds(120))],
            tomsk.nameKey: [.answer(answer("Томск"))],
        ])
        let here = CurrentPlace(initial: GeoCoordinate(latitude: 0, longitude: 0), namer: PlaceNamer(geocoder: g, retryDelay: .zero),
                                locator: StubLocator(.denied), debounce: .zero)
        here.move(to: lobnya)
        try? await Task.sleep(for: .milliseconds(30))   // вопрос про Лобню уже в пути
        here.move(to: tomsk)
        await here.settled()
        try? await Task.sleep(for: .milliseconds(200))  // ждём, пока медленный ответ придёт и будет выброшен
        #expect(here.coordinate == tomsk)
        #expect(here.name?.city == "Томск")
    }

    @Test func manualEntryMovesOnlyOnValidInput() async {
        let g = ScriptedGeocoder([tomsk.nameKey: [.answer(answer("Томск"))]])
        let here = make(g, StubLocator(.denied))
        #expect(here.setManual(latitude: "99", longitude: "84.952") == .outOfRange(.latitude))
        #expect(here.coordinate == lobnya && !here.isNameStale)
        #expect(here.setManual(latitude: "56,489", longitude: "84.952 E") == nil)
        await here.settled()
        #expect(here.coordinate == tomsk && here.name?.city == "Томск")
    }

    @Test func placeForTheSolarEngineCarriesTheZone() {
        let here = make(ScriptedGeocoder([:]), StubLocator(.denied))
        let p = here.place
        #expect(p.latitude == lobnya.latitude && p.longitude == lobnya.longitude)
        #expect(p.zone.utcOffsetHours(on: CivilDate(year: 2026, month: 7, day: 1)) == 3)
    }
}
