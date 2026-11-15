import Foundation
import Testing
import LightPlanCore
@testable import LightPlanData

/// 30и.1: поиск места. Сеть тут не нужна — проверяются правила разбора ответа, которые не зависят от
/// геокодера. Метки ниже — записанные ответы `CLGeocoder` (iOS Simulator, регион телефона «Россия»,
/// 14.11.2026), не придуманные.
struct PlaceSearchTests {
    private let tokyo = GeoCoordinate(latitude: 35.6895, longitude: 139.6917)
    private let toki = GeoCoordinate(latitude: 35.35, longitude: 137.17)

    // «Tokyo» → name «Toкиo» (T, o, o — латиница), locality нет, administrativeArea «Toкиo».
    private var tokyoMark: PlaceMark {
        PlaceMark(name: "Toкиo", locality: nil, region: "Toкиo", country: "Япония", coordinate: tokyo)
    }
    private var tokiMark: PlaceMark {
        PlaceMark(name: "Токи", locality: "Токи", region: "Гифу", country: "Япония", coordinate: toki)
    }

    // MARK: - Двойники букв

    @Test func mixedScriptWordIsHealedOnlyWhenEveryLatinLetterHasATwin() {
        #expect(PlaceQuery.cleaned("Toкиo") == "Токио")
        #expect(PlaceQuery.cleaned("Москва-City") == "Москва-City")           // у «i» двойника нет
        #expect(PlaceQuery.cleaned("iPhone") == "iPhone")                      // нет кириллицы — не трогаем
        #expect(PlaceQuery.cleaned("Tokyo") == "Tokyo")
        #expect(PlaceQuery.cleaned("Кропоткино") == "Кропоткино")
        #expect(PlaceQuery.cleaned("проспект Ленина, 1") == "проспект Ленина, 1")
    }

    @Test func foldedMakesTypedAndStoredNamesComparable() {
        #expect(PlaceQuery.folded("Токио") == PlaceQuery.folded("Toкиo"))
        #expect(PlaceQuery.folded("Кёто") == PlaceQuery.folded("кето"))
        #expect(PlaceQuery.folded("  Нью-Йорк ") == "нью-йорк")
    }

    // MARK: - Токио кириллицей

    @Test func tokyoIsShownAsTokyoWithItsCountryAndIsItsOwnCity() {
        let hits = ApplePlaceSearch.hits([tokyoMark], homeCountry: "Россия")
        #expect(hits.count == 1)
        #expect(hits[0].name == "Токио")                  // не «Toкиo» и не район
        #expect(hits[0].area == "Япония")                 // страну видно, когда она не домашняя
        #expect(hits[0].city == PlaceName(city: "Токио", sub: ""))
    }

    @Test func homeCountryIsNotRepeated() {
        let tomsk = PlaceMark(name: "Томск", locality: "Томск", region: "Томская область", country: "Россия",
                              coordinate: GeoCoordinate(latitude: 56.49, longitude: 84.95))
        let hit = ApplePlaceSearch.hits([tomsk], homeCountry: "Россия")[0]
        #expect(hit.area == "Томская область")
        #expect(hit.city == PlaceName(city: "Томск", sub: "Томская область"))
        // страны телефона нет — страна пишется всегда
        #expect(ApplePlaceSearch.hits([tomsk], homeCountry: nil)[0].area == "Томская область, Россия")
    }

    @Test func exactNameGoesFirstSoTokioBeatsToki() {
        // Регион «Россия»: на «Токио» прямой запрос отвечает «Токи», запасной (Tokio) — Токио.
        let marks = [tokiMark, tokyoMark]
        let ordered = PlaceQuery.exactFirst(marks, query: "Токио")
        #expect(ordered.map(\.name) == ["Toкиo", "Токи"])
        let hits = ApplePlaceSearch.hits(ordered, homeCountry: "Россия")
        #expect(hits.map(\.name) == ["Токио", "Токи"])
        #expect(hits[1].area == "Гифу, Япония")
    }

    @Test func exactNameLeavesOrderAloneWhenNothingMatches() {
        let marks = [tokiMark, tokyoMark]
        #expect(PlaceQuery.exactFirst(marks, query: "Киото") == marks)
    }

    @Test func aMarkIsNamedByItsLocalityToo() {
        let street = PlaceMark(name: "проспект Ленина, 1", locality: "Томск", region: "Томская область",
                               coordinate: tokyo)
        #expect(PlaceQuery.names(street, query: "томск"))
        #expect(!PlaceQuery.names(street, query: "Токио"))
    }

    // MARK: - Запасной запрос латиницей

    @Test func transliterationOnlyForCityLikeCyrillicQueries() {
        #expect(PlaceQuery.transliteration(of: "Токио") == "Tokio")
        #expect(PlaceQuery.transliteration(of: "Париж") == "Pariz")
        #expect(PlaceQuery.transliteration(of: "Красная Поляна") != nil)
        // латиница — уже латиница
        #expect(PlaceQuery.transliteration(of: "Tokyo") == nil)
        // адреса, номера, запятые, три слова и больше — латиница их не лечит
        #expect(PlaceQuery.transliteration(of: "Ленина 1 Томск") == nil)
        #expect(PlaceQuery.transliteration(of: "Томск, Россия") == nil)
        #expect(PlaceQuery.transliteration(of: "Лагерный сад Томск") == nil)
        // слишком коротко для запроса
        #expect(PlaceQuery.transliteration(of: "То") == nil)
    }

    @Test func softSignsDoNotLeaveModifierLettersInTheQuery() {
        let q = PlaceQuery.transliteration(of: "Нью-Йорк")
        #expect(q != nil)
        #expect(q?.unicodeScalars.allSatisfy { $0.value < 0x2B0 } == true)
    }

    @Test func twoSignsAreEnoughOnlyForCjkNames() {
        #expect(PlaceQuery.isAskable("東京") && PlaceQuery.isAskable("北京") && PlaceQuery.isAskable("서울"))
        #expect(PlaceQuery.isAskable("Рим") && PlaceQuery.isAskable("  Рим "))
        #expect(!PlaceQuery.isAskable("То") && !PlaceQuery.isAskable("ab") && !PlaceQuery.isAskable("東a"))
        #expect(!PlaceQuery.isAskable("京") && !PlaceQuery.isAskable(""))
    }

    // MARK: - Прежнее поведение разбора

    @Test func searchHitsNameAreaAndCap() {
        let c = GeoCoordinate(latitude: 56.45, longitude: 84.95)
        let marks: [PlaceMark] =
            [PlaceMark(name: "Лагерный сад", locality: "Томск", region: "Томская область", coordinate: c),
             PlaceMark(name: "Лагерный сад", locality: "Томск", region: "Томская область", coordinate: c),   // дубль
             PlaceMark(name: nil, locality: "Томск", region: "Томская область", coordinate: c),               // без имени — город
             PlaceMark(name: "  ", locality: nil, region: nil, coordinate: c)]                                // пустое — мимо
            + (0..<8).map { PlaceMark(name: "Улица \($0)", locality: "Томск", region: nil, coordinate: c) }
        let hits = ApplePlaceSearch.hits(marks)
        #expect(hits.count == 6)
        #expect(hits[0] == PlaceHit(name: "Лагерный сад", area: "Томск, Томская область", coordinate: c,
                                    city: PlaceName(city: "Томск", sub: "Томская область")))
        #expect(hits[1] == PlaceHit(name: "Томск", area: "Томская область", coordinate: c,
                                    city: PlaceName(city: "Томск", sub: "Томская область")))
        #expect(hits[2].name == "Улица 0" && hits[2].area == "Томск")
    }

    // MARK: - Район виден, только когда его набрали

    @Test func districtIsShownOnlyWhenItIsTheNameOfTheAnswer() {
        // «Синдзюку» набрали — Apple отвечает районом как городом.
        let shinjuku = PlaceMark(name: "Синдзюку", locality: "Синдзюку", region: "Toкиo", country: "Япония",
                                 coordinate: tokyo)
        let hit = ApplePlaceSearch.hits([shinjuku], homeCountry: "Россия")[0]
        #expect(hit.name == "Синдзюку")
        #expect(hit.city?.city == "Синдзюку")
        #expect(hit.area == "Токио, Япония")
        // «Tokyo» набрали — района нет нигде: ни в имени, ни в городе, ни в уточнении.
        let t = ApplePlaceSearch.hits([tokyoMark], homeCountry: "Россия")[0]
        #expect(![t.name, t.area, t.city?.city, t.city?.sub].compactMap { $0 }.contains { $0.contains("Синдзюку") })
    }
}

/// «Токио», выбранное в поиске, не должно превращаться в «Синдзюку» (30и.1, слово Алексея 13.11): точка
/// Токио — здание ратуши в этом районе, и обратный геокодер называет район (замер 14.11.2026).
@MainActor
struct ChosenNameTests {
    private actor Reverse: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: "Синдзюку", region: "Токио", country: "Япония", zoneIdentifier: "Asia/Tokyo")
        }
    }
    private struct Nowhere: DeviceLocating {
        func currentFix() async -> DeviceFix { .unavailable }
    }
    private let tokyo = GeoCoordinate(latitude: 35.6895, longitude: 139.6917)
    private func make() -> CurrentPlace {
        CurrentPlace(initial: GeoCoordinate(latitude: 56.489, longitude: 84.952), name: PlaceName(city: "Томск", sub: ""),
                     namer: PlaceNamer(geocoder: Reverse(), retryDelay: .zero), locator: Nowhere(), debounce: .zero)
    }

    @Test func chosenNameSurvivesTheReverseAnswerButZoneComesFromIt() async {
        let here = make()
        here.move(to: tokyo, chosenName: PlaceName(city: "Токио", sub: ""))
        #expect(here.name?.city == "Токио" && !here.isNameStale)
        await here.settled()
        #expect(here.name == PlaceName(city: "Токио", sub: ""))       // не «Синдзюку»
        #expect(here.zone.identifier == "Asia/Tokyo")                  // настоящая зона всё же пришла
    }

    @Test func plainMoveStillTakesTheReverseName() async {
        // «Я здесь» и сдвиг пальцем: район — то, что нужно, как было.
        let here = make()
        here.move(to: tokyo)
        await here.settled()
        #expect(here.name?.city == "Синдзюку")
    }

    @Test func aLaterPlainMoveForgetsTheChosenName() async {
        let here = make()
        here.move(to: tokyo, chosenName: PlaceName(city: "Токио", sub: ""))
        await here.settled()
        here.move(to: GeoCoordinate(latitude: 35.7, longitude: 139.7))
        await here.settled()
        #expect(here.name?.city == "Синдзюку")
    }
}

/// 30и.12: поиск города («Город» в Настройках, «Откуда вы работаете») берёт метки тем же путём, что «Где снимаем».
struct CitySearchTests {
    private let tokyo = GeoCoordinate(latitude: 35.6895, longitude: 139.6917)

    private func hits(_ marks: [PlaceMark], _ q: String) -> [CityHit] {
        AppleCityLookup.hits(marks, query: q, deviceRegion: "RU", locale: Locale(identifier: "ru_RU"))
    }

    // Записанный ответ: у Токио нет locality, имя смешанными буквами.
    @Test func tokyoWithoutLocalityIsACityInAnyAlphabet() {
        let mark = PlaceMark(name: "Toкиo", locality: nil, region: "Toкиo", country: "Япония", isoCode: "JP", coordinate: tokyo)
        for q in ["Токио", "Tokyo", "東京"] {
            let h = hits([mark], q)
            #expect(h.map(\.name) == ["Токио"], "запрос \(q)")
            #expect(h.first?.countryCode == "jp")
        }
    }

    @Test func aStreetOrCafeWithoutCityIsStillNotACity() {
        let lake = PlaceMark(name: "Озеро Байкал", locality: nil, region: "Иркутская область", country: "Россия", coordinate: tokyo)
        #expect(hits([lake], "Байкал").isEmpty)
    }

    @Test func aMarkWithLocalityStaysAsBefore() {
        let m = PlaceMark(name: "Барнаул", locality: "Барнаул", region: "Алтайский край", country: "Россия", isoCode: "RU", coordinate: tokyo)
        #expect(hits([m], "Барнаул").map(\.name) == ["Барнаул"])
    }

    @Test func twoCharacterCJKAndCyrillicFallbackAreAskable() {
        #expect(PlaceQuery.isAskable("東京"))
        #expect(PlaceQuery.transliteration(of: "Бали") == "Bali")
    }
}
