import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// 30и.11: шторка «Мои жанры» (вариант A листа) и имя в шапке настроек.
@MainActor
struct GenreSheetAndAccountTests {

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

    private func model() -> AppModel {
        AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                 locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
    }

    // MARK: - Какой жанр правят

    @Test func pickedGenreWinsEvenWhenItIsOff() {
        #expect(GenreSheet.edited(.street, form: .portrait, enabled: [.portrait, .wedding]) == .street)
    }

    @Test func withoutPickTheFormGenreIsEditedWhenOn() {
        #expect(GenreSheet.edited(nil, form: .wedding, enabled: [.portrait, .wedding]) == .wedding)
    }

    @Test func withoutPickAnOffFormGenreNeverNamesTheBlock() {
        // Было: блок называл жанр формы, даже серый. Теперь — первый включённый.
        #expect(GenreSheet.edited(nil, form: .portrait, enabled: [.wedding, .party]) == .wedding)
        #expect(GenreSheet.edited(nil, form: nil, enabled: [.party]) == .party)
    }

    // MARK: - Включение

    @Test func turningOffReportsSuccessAndTheLastOneRefuses() {
        let app = model()
        #expect(app.toggleGenre(.street))
        #expect(!app.enabledGenres.contains(.street))
        for g in Genre.allCases.dropFirst() where app.enabledGenres.contains(g) { #expect(app.toggleGenre(g)) }
        #expect(app.enabledGenres == [Genre.allCases[0]])
        #expect(!app.toggleGenre(Genre.allCases[0]), "последний не выключается — шторка скажет словами")
        #expect(app.enabledGenres == [Genre.allCases[0]])
        #expect(app.toggleGenre(.street) && app.enabledGenres.contains(.street), "включение возвращает true")
    }

    @Test func offGenreKeepsItsDefaultsForTheBlock() {
        let app = model()
        app.setGenreRate(.street, 4200)
        app.setGenreDuration(.street, 90)
        app.toggleGenre(.street)
        #expect(app.genreRate(.street) == 4200 && app.genreDuration(.street) == 90, "правка выключенного жанра сохраняется")
    }

    // MARK: - Имя

    @Test func nameIsStoredAsTypedAndBlankMeansNone() {
        let app = model()
        #expect(app.myName.isEmpty)
        app.setMyName("Анна ")
        #expect(app.myName == "Анна ")
        app.setMyName("   ")
        #expect(app.myName.isEmpty)
    }

    @Test func initialsAreTheFirstTwoWords() {
        #expect(AppModel.initials(of: "Анна Иванова") == "АИ")
        #expect(AppModel.initials(of: "  анна  ") == "А")
        #expect(AppModel.initials(of: "Анна Мария Иванова") == "АМ")
        #expect(AppModel.initials(of: "").isEmpty)
    }
}
