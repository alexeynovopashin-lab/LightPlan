import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Шаг «Музыка»: библиотека плейлистов и плеер в приложении — правка, запись в снимок, кнопка в карточке по часам места,
/// форма, узнающая об удалённом плейлисте. Записи — посев сезона (`CardPhaseTests`): портрет в студии 12:20–13:50 по Томску.
@MainActor
struct MusicAppTests {
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

    static let seed = CardPhaseTests.seed

    private func app(_ iso: String, tomsk: Bool = true, edit: (inout Snapshot) -> Void = { _ in }) -> AppModel {
        var snap = Self.seed
        if case .object(var z)? = snap.extra["zones"] {
            z["56.5,85.0"] = tomsk ? JSONValue.string("Asia/Tomsk") : nil
            snap.extra["zones"] = .object(z)
        }
        edit(&snap)
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    private let id = "sd_sep_now"
    private func withMusic(_ s: inout Snapshot, playlist: String? = "Сборы", player: String? = nil) {
        s.playlists = [Playlist(name: "Сборы", url: "https://open.spotify.com/playlist/a"),
                       Playlist(name: "Вечер", url: "https://music.yandex.ru/users/x/playlists/1")]
        s.musicApp = player
        if let i = s.sessions.firstIndex(where: { $0.id == "sd_sep_now" }) { s.sessions[i].playlist = playlist }
    }
    private func session(_ a: AppModel) -> Session { a.sessions.first { $0.id == id }! }

    // MARK: Кнопка в карточке по часам места

    @Test func buttonLivesInTheWindowOfTheShoot() {
        let at = { (t: String) in
            let a = self.app("2026-09-23T\(t):00+07:00") { self.withMusic(&$0) }
            return a.musicButton(for: self.session(a))
        }
        #expect(at("12:19") == nil, "до начала")
        #expect(at("12:20")?.name == "Сборы")
        #expect(at("13:44")?.href == "https://open.spotify.com/playlist/a")
        #expect(at("13:45") == nil, "конец минус пять")
        #expect(at("14:30") == nil, "после")
    }

    @Test func buttonFollowsThePlaceClockNotThePhone() {
        // Часы места без записанного пояса — оценка по долготе (+6): в 13:00 телефона у студии 12:00, съёмка ещё впереди.
        let a = app("2026-09-23T13:00:00+07:00", tomsk: false) { withMusic(&$0) }
        #expect(a.musicButton(for: session(a)) == nil)
    }

    @Test func playerAloneGivesAButtonOnlyWhenThereIsAPlayer() {
        let on = app("2026-09-23T13:00:00+07:00") { withMusic(&$0, playlist: nil, player: "spotify") }
        #expect(on.musicButton(for: session(on)) == MusicChoice(name: "Spotify", href: "https://open.spotify.com"))
        let off = app("2026-09-23T13:00:00+07:00") { withMusic(&$0, playlist: nil, player: "off") }
        #expect(off.musicButton(for: session(off)) == nil)
    }

    @Test func meetingGetsNoButtonEvenWithPlayer() {
        let a = app("2026-09-23T18:30:00+07:00") { s in
            s.musicApp = "spotify"
            s.playlists = [Playlist(name: "Сборы", url: "https://open.spotify.com/playlist/a")]
        }
        let meet = a.sessions.first { $0.id == "sd_sep_meet" }!
        #expect(a.musicButton(for: meet) == nil)
    }

    // MARK: Правка из настроек

    @Test func playerChoiceGoesIntoTheSnapshotAsTheWebWritesIt() {
        let a = app("2026-09-23T13:00:00+07:00")
        a.setMusicApp(.apple)
        #expect(a.snapshot.musicApp == "apple" && a.musicApp == .apple)
        a.setMusicApp(nil)
        #expect(a.snapshot.musicApp == "off" && a.musicApp == nil)
    }

    @Test func addRenameRemoveKeepSessionsInStep() {
        let a = app("2026-09-23T13:00:00+07:00") { withMusic(&$0) }
        #expect(!a.addPlaylist(name: "Пусто", url: "  "), "без адреса плейлиста нет")
        #expect(a.addPlaylist(name: "", url: "music.apple.com/ru/playlist/p"))
        #expect(a.playlists.last == Playlist(name: "Apple Music", url: "https://music.apple.com/ru/playlist/p"))
        // «Выкл» ↔ ошибка ввода: пустое имя и тёзка при переименовании не принимаются
        #expect(a.renamePlaylist(at: 0, to: "  ") == nil && a.renamePlaylist(at: 0, to: "Вечер") == nil)
        #expect(a.renamePlaylist(at: 0, to: "Утро") == "Утро")
        #expect(session(a).playlist == "Утро")
        a.removePlaylist(at: 0)
        #expect(a.playlists.map(\.name) == ["Вечер", "Apple Music"])
        #expect(session(a).playlist == "Утро", "запись помнит имя; плейлиста нет — своей музыки нет")
        #expect(a.musicButton(for: session(a)) == nil, "и плеера нет — кнопки нет")
    }

    @Test func renameReachesTheBinToo() {
        let a = app("2026-09-23T13:00:00+07:00") { s in
            withMusic(&s)
            let i = s.sessions.firstIndex { $0.id == "sd_sep_now" }!
            s.trashed = [TrashedItem(record: s.sessions[i], index: 0, deletedAt: 1)]
        }
        #expect(a.renamePlaylist(at: 0, to: "Утро") == "Утро")
        #expect(a.snapshot.trashed.first?.record.playlist == "Утро")
    }

    @Test func openFormForgetsADeletedPlaylist() {
        let a = app("2026-09-23T13:00:00+07:00") { withMusic(&$0) }
        a.openForm(editing: id)
        #expect(a.form?.playlist == "Сборы")
        a.removePlaylist(at: 0)
        #expect(a.form?.playlist == "", "открытая форма узнаёт об удалении")
        // запись с призраком открывается без него
        a.closeForm()
        a.openForm(editing: id)
        #expect(a.form?.playlist == "")
    }

    @Test func toggleAndWheelWriteTheFormField() {
        let a = app("2026-09-23T13:00:00+07:00") { withMusic(&$0, playlist: nil) }
        a.openForm(editing: id)
        a.toggleFormPlaylist()
        #expect(a.form?.playlist == "Сборы")
        a.pickFormPlaylist(at: 1)
        #expect(a.form?.playlist == "Вечер")
        a.toggleFormPlaylist()
        #expect(a.form?.playlist == "")
    }
}
