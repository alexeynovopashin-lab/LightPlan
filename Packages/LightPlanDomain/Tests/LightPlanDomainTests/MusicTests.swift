import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Шаг «Музыка» (25.10): окно кнопки в карточке, выбор ссылки, библиотека плейлистов, поле в форме.
/// Эталон — веб `musicOpen`, `musicHref`, `musicName`, `renderPlaylists`, `autoPlName`.
@Suite struct MusicTests {
    let day = CivilDate(year: 2026, month: 10, day: 25)
    let lib = [Playlist(name: "Сборы", url: "https://open.spotify.com/playlist/a"),
               Playlist(name: "Вечер", url: "https://music.yandex.ru/users/x/playlists/1")]

    /// Съёмка 15:00–17:00 (900…1020), по умолчанию с плейлистом «Сборы».
    func shoot(_ kind: RecordKind = .shoot, playlist: String? = "Сборы", on d: CivilDate? = nil) -> Session {
        var s = Session(id: "s1", kind: kind, day: d ?? day, start: 900, duration: 120, genre: .portrait)
        s.playlist = playlist
        return s
    }
    func at(_ minutes: Int, _ d: CivilDate? = nil) -> WallTime { WallTime(day: d ?? day, minutes: minutes) }

    // MARK: Окно кнопки

    @Test func windowRunsFromStartToFiveMinutesBeforeTheEnd() {
        let s = shoot()
        #expect(!Music.isOpen(s, now: at(899)), "до начала")
        #expect(Music.isOpen(s, now: at(900)), "ровно в начале")
        #expect(Music.isOpen(s, now: at(960)), "в окне")
        #expect(Music.isOpen(s, now: at(1014)), "за шесть минут до конца ещё открыто")
        #expect(!Music.isOpen(s, now: at(1015)), "за пять минут до конца уже закрыто")
        #expect(!Music.isOpen(s, now: at(1016)), "за четыре минуты до конца")
        #expect(!Music.isOpen(s, now: at(1021)), "после конца")
    }

    @Test func meetingAndForeignEventNeverGetMusic() {
        #expect(!Music.isOpen(shoot(.meet), now: at(960)))
        #expect(!Music.isOpen(shoot(.event), now: at(960)))
    }

    @Test func onlyOnTheShootsOwnDay() {
        let s = shoot()
        #expect(!Music.isOpen(s, now: at(960, day.adding(days: -1))))
        #expect(!Music.isOpen(s, now: at(960, day.adding(days: 1))))
        // Веб смотрит на сегодняшнюю дату: свадьба до трёх ночи теряет кнопку в полночь.
        var night = shoot()
        night.start = 1140; night.end = 1620      // 19:00 → 03:00
        #expect(Music.isOpen(night, now: at(1300)))
        #expect(!Music.isOpen(night, now: at(30, day.adding(days: 1))))
    }

    @Test func manualFinishMarkEndsTheWindowThere() {
        var s = shoot()
        s.doneAt = 960                            // нажали «Завершить» в 16:00
        #expect(Music.isOpen(s, now: at(950)))
        #expect(!Music.isOpen(s, now: at(955)), "конец минус пять — от отметки")
        #expect(!Music.isOpen(s, now: at(980)))
    }

    @Test func shootWithoutRecordedEndLastsNinetyMinutes() {
        var s = Session(id: "s2", day: day, start: 600, genre: .portrait)   // ни конца, ни длительности
        s.playlist = "Сборы"
        #expect(Music.isOpen(s, now: at(684)))    // 600 + 90 − 5 = 685
        #expect(!Music.isOpen(s, now: at(685)))
    }

    // MARK: Выбор ссылки

    @Test func ownPlaylistBeatsThePlayer() {
        let c = Music.choice(for: shoot(), app: .apple, playlists: lib)
        #expect(c == MusicChoice(name: "Сборы", href: "https://open.spotify.com/playlist/a"))
    }

    @Test func noPlaylistFallsBackToThePlayer() {
        #expect(Music.choice(for: shoot(playlist: nil), app: .spotify, playlists: lib)
                == MusicChoice(name: "Spotify", href: "https://open.spotify.com"))
        #expect(Music.choice(for: shoot(playlist: ""), app: .yandex, playlists: lib)?.name == "Яндекс Музыка", "пустое имя — как нет")
        #expect(Music.choice(for: shoot(playlist: nil), app: .apple, playlists: [])?.href == "https://music.apple.com")
    }

    @Test func neitherPlaylistNorPlayerMeansNoButton() {
        #expect(Music.choice(for: shoot(playlist: nil), app: nil, playlists: lib) == nil)
        #expect(Music.button(for: shoot(playlist: nil), now: at(960), app: nil, playlists: lib) == nil)
    }

    @Test func removedPlaylistLeavesTheShootOnThePlayerOrBare() {
        let gone = shoot(playlist: "Удалённый")
        #expect(Music.choice(for: gone, app: .yandex, playlists: lib)?.name == "Яндекс Музыка")
        #expect(Music.choice(for: gone, app: nil, playlists: lib) == nil)
    }

    @Test func playlistNamedLikeAServiceKeepsItsOwnLink() {
        // Имя «Spotify» — служебное значение: плеер в настройках тоже Spotify, а ссылка у плейлиста — Apple Music.
        let tricky = [Playlist(name: "Spotify", url: "https://music.apple.com/ru/playlist/x")]
        let c = Music.choice(for: shoot(playlist: "Spotify"), app: .spotify, playlists: tricky)
        #expect(c == MusicChoice(name: "Spotify", href: "https://music.apple.com/ru/playlist/x"))
        // …а в библиотеке такого имени нет — открывается сам плеер.
        #expect(Music.choice(for: shoot(playlist: "Spotify"), app: .spotify, playlists: lib)?.href == "https://open.spotify.com")
    }

    @Test func unreadableLinkGivesNoButton() {
        let bad = [Playlist(name: "Сборы", url: "https://")]
        #expect(Music.choice(for: shoot(), app: nil, playlists: bad) == nil)
    }

    @Test func buttonNeedsBothWindowAndLink() {
        #expect(Music.button(for: shoot(), now: at(960), app: nil, playlists: lib)?.name == "Сборы")
        #expect(Music.button(for: shoot(), now: at(800), app: nil, playlists: lib) == nil)
        #expect(Music.button(for: shoot(.meet), now: at(960), app: .spotify, playlists: lib) == nil)
    }

    // MARK: Узнавание сервиса

    @Test func serviceIsRecognisedByHostWithoutCaseAndWithSubdomains() {
        #expect(MusicApp.of(url: "https://OPEN.Spotify.COM/playlist/1") == .spotify)
        #expect(MusicApp.of(url: "https://music.yandex.com/x") == .yandex)
        #expect(MusicApp.of(url: "https://music.yandex.kz/x") == .yandex)
        #expect(MusicApp.of(url: "https://music.apple.com/ru/playlist/p") == .apple)
        #expect(MusicApp.of(url: "https://notspotify.com/x") == nil, "чужой домен с тем же хвостом не сервис")
        #expect(MusicApp.of(url: "https://example.org") == nil)
        #expect(MusicApp.of(url: "не адрес") == nil)
    }

    // MARK: Адрес и имя

    @Test func addressWithoutSchemeGetsHttps() {
        #expect(Music.normalizedURL("open.spotify.com/x") == "https://open.spotify.com/x")
        #expect(Music.normalizedURL("  http://a.b/c ") == "http://a.b/c")
        #expect(Music.normalizedURL("HTTPS://A.B") == "HTTPS://A.B", "схема любого регистра — уже схема")
        #expect(Music.normalizedURL("   ") == "")
    }

    @Test func emptyNameBecomesTheServiceAndTwinsGetNumbers() {
        var list: [Playlist] = []
        #expect(Music.add(name: "", url: "open.spotify.com/a", to: &list, fallback: "Плейлист"))
        #expect(Music.add(name: "  ", url: "https://open.spotify.com/b", to: &list, fallback: "Плейлист"))
        #expect(Music.add(name: "", url: "https://open.spotify.com/c", to: &list, fallback: "Плейлист"))
        #expect(list.map(\.name) == ["Spotify", "Spotify 2", "Spotify 3"])
        // Занятый номер перешагивается.
        var l2 = [Playlist(name: "Spotify 2", url: "https://x.y")]
        Music.add(name: "", url: "https://open.spotify.com/a", to: &l2, fallback: "Плейлист")
        Music.add(name: "", url: "https://open.spotify.com/b", to: &l2, fallback: "Плейлист")
        #expect(l2.map(\.name) == ["Spotify 2", "Spotify", "Spotify 3"])
    }

    @Test func unknownSiteGetsItsHostAndGarbageGetsTheFallbackWord() {
        var list: [Playlist] = []
        Music.add(name: "", url: "https://www.example.org/mix", to: &list, fallback: "Плейлист")
        Music.add(name: "", url: "две слова", to: &list, fallback: "Плейлист")
        #expect(list.map(\.name) == ["example.org", "Плейлист"])
    }

    @Test func addRefusesEmptyAddressAndTheEleventh() {
        var list: [Playlist] = []
        #expect(!Music.add(name: "Имя", url: "  ", to: &list, fallback: "Плейлист"))
        #expect(list.isEmpty, "имя без адреса плейлистом не становится")
        for i in 1...10 { #expect(Music.add(name: "П\(i)", url: "a.b/\(i)", to: &list, fallback: "Плейлист")) }
        #expect(!Music.add(name: "Лишний", url: "a.b/11", to: &list, fallback: "Плейлист"))
        #expect(list.count == 10)
    }

    @Test func sameNameIsNotKeptTwice() {
        var list = [Playlist(name: "Сборы", url: "https://a.b")]
        Music.add(name: "Сборы", url: "https://c.d", to: &list, fallback: "Плейлист")
        Music.add(name: "Сборы", url: "https://e.f", to: &list, fallback: "Плейлист")
        #expect(list.map(\.name) == ["Сборы", "Сборы ·", "Сборы · ·"])
    }

    // MARK: ё/е и регистр

    @Test func namesDifferingByCaseOrYoAreDifferentPlaylists() {
        // Как у веба: выбор по точному имени. «Ёлка» и «Елка», «Сборы» и «сборы» — два плейлиста, у каждого свои съёмки.
        var list = [Playlist(name: "Ёлка", url: "https://a.b"), Playlist(name: "Елка", url: "https://c.d"),
                    Playlist(name: "Сборы", url: "https://e.f")]
        #expect(Music.add(name: "сборы", url: "https://g.h", to: &list, fallback: "Плейлист"))
        #expect(list.map(\.name) == ["Ёлка", "Елка", "Сборы", "сборы"])
        #expect(Music.playlist(named: "Елка", in: list)?.url == "https://c.d")
        #expect(Music.playlist(named: "елка", in: list) == nil)

        var sessions = [shoot(playlist: "Ёлка"), shoot(playlist: "Елка")]
        sessions[1].id = "s2"
        var trashed: [TrashedItem] = []
        Music.rename(at: 0, to: "Ёлочка", list: &list, sessions: &sessions, trashed: &trashed)
        #expect(sessions.map(\.playlist) == ["Ёлочка", "Елка"], "переименование не задевает тёзку по е/ё")
    }

    @Test func renameOnlyInCaseIsARealRename() {
        var list = [Playlist(name: "Сборы", url: "https://a.b")]
        var sessions = [shoot(playlist: "Сборы")]
        var trashed: [TrashedItem] = []
        #expect(Music.rename(at: 0, to: "сборы", list: &list, sessions: &sessions, trashed: &trashed) == "сборы")
        #expect(sessions[0].playlist == "сборы")
    }

    // MARK: Пустые поля

    @Test func emptyOptionalFieldsChangeNothing() {
        var list = [Playlist(name: "Сборы", url: "https://a.b")]
        var sessions = [shoot(playlist: "Сборы")]
        var trashed: [TrashedItem] = []
        #expect(Music.rename(at: 0, to: "   ", list: &list, sessions: &sessions, trashed: &trashed) == nil, "пустое имя не пишем")
        #expect(!Music.setURL(at: 0, to: " ", list: &list), "пустой адрес не пишем")
        #expect(list == [Playlist(name: "Сборы", url: "https://a.b")] && sessions[0].playlist == "Сборы")
        #expect(Music.rename(at: 5, to: "Х", list: &list, sessions: &sessions, trashed: &trashed) == nil)
        #expect(Music.remove(at: 5, from: &list) == nil)
        #expect(Music.playlist(named: nil, in: list) == nil && Music.playlist(named: "", in: list) == nil)
    }

    @Test func readingDropsEntriesWithoutNameOrAddressAndCapsAtTen() {
        let raw = [Playlist(name: "", url: "https://a.b"), Playlist(name: "Без адреса", url: ""), Playlist(name: "Ок", url: "https://c.d")]
        #expect(Music.clean(raw) == [Playlist(name: "Ок", url: "https://c.d")])
        let many = (1...14).map { Playlist(name: "П\($0)", url: "https://a.b/\($0)") }
        #expect(Music.clean(many).count == 10 && Music.clean(many).last?.name == "П10")
    }

    @Test func addressEditGetsHttpsAndKeepsTheName() {
        var list = [Playlist(name: "Сборы", url: "https://a.b")]
        #expect(Music.setURL(at: 0, to: "music.apple.com/x", list: &list))
        #expect(list[0] == Playlist(name: "Сборы", url: "https://music.apple.com/x"))
        #expect(!Music.setURL(at: 0, to: "https://music.apple.com/x", list: &list), "тот же адрес — не правка")
    }

    // MARK: Два действия подряд

    @Test func renameThenDeleteLeavesTheShootWithoutItsOwnMusic() {
        var list = lib
        var sessions = [shoot(playlist: "Сборы")]
        var trashed = [TrashedItem(record: shoot(playlist: "Сборы"), index: 0, deletedAt: 1)]
        #expect(Music.rename(at: 0, to: "Утро", list: &list, sessions: &sessions, trashed: &trashed) == "Утро")
        #expect(sessions[0].playlist == "Утро" && trashed[0].record.playlist == "Утро", "и в съёмки, и в корзину")
        Music.remove(at: 0, from: &list)
        // Запись хранит имя, плейлиста нет — своей музыки нет; кнопка ведёт в плеер, а без плеера её нет вовсе.
        #expect(sessions[0].playlist == "Утро")
        #expect(Music.choice(for: sessions[0], app: .spotify, playlists: list)?.name == "Spotify")
        #expect(Music.choice(for: sessions[0], app: nil, playlists: list) == nil)
        // Вернули плейлист под тем же именем — съёмка снова с ним (имя и есть нить, как у веба).
        Music.add(name: "Утро", url: "https://a.b", to: &list, fallback: "Плейлист")
        #expect(Music.choice(for: sessions[0], app: nil, playlists: list)?.href == "https://a.b")
    }

    @Test func renameIntoATakenNameIsRefused() {
        var list = lib
        var sessions = [shoot(playlist: "Сборы"), shoot(playlist: "Вечер")]
        sessions[1].id = "s2"
        var trashed: [TrashedItem] = []
        #expect(Music.rename(at: 0, to: "Вечер", list: &list, sessions: &sessions, trashed: &trashed) == nil)
        #expect(list.map(\.name) == ["Сборы", "Вечер"] && sessions.map(\.playlist) == ["Сборы", "Вечер"])
    }

    // MARK: Поле в форме

    @Test func playlistTravelsThroughTheForm() {
        let s = shoot(playlist: "Вечер")
        var f = EventForm.editing(s)
        #expect(f.playlist == "Вечер")
        #expect(f.session(orgName: nil, and: " и ").playlist == "Вечер")
        f.playlist = ""
        #expect(f.session(orgName: nil, and: " и ").playlist == nil, "пустое поле — нет поля")
        #expect(EventForm.editing(shoot(playlist: nil)).playlist.isEmpty)
    }

    @Test func formForgetsAPlaylistThatLeftTheLibrary() {
        // Веб при открытии формы (`refreshMusicRow`) сбрасывает выбор, которого в библиотеке нет, — призрак не записывается.
        var f = EventForm.editing(shoot(playlist: "Удалённый"))
        #expect(f.session(orgName: nil, and: " и ").playlist == "Удалённый", "пока форма не узнала о библиотеке")
        f.refreshPlaylist(in: lib)
        #expect(f.playlist.isEmpty && f.session(orgName: nil, and: " и ").playlist == nil)
        var g = EventForm.editing(shoot(playlist: "Вечер"))
        g.refreshPlaylist(in: lib)
        #expect(g.playlist == "Вечер", "живой выбор остаётся")
        var h = EventForm.editing(shoot(playlist: "Вечер"))
        h.refreshPlaylist(in: [])
        #expect(h.playlist.isEmpty, "библиотеку очистили — выбирать нечего")
    }

    @Test func toggleTakesTheFirstPlaylistAndSecondTapClears() {
        var f = EventForm.editing(shoot(playlist: nil))
        #expect(f.playlistRowShown(in: lib) && !f.playlistRowShown(in: []))
        f.togglePlaylist(in: [])
        #expect(f.playlist.isEmpty, "пустая библиотека — тумблеру нечего включать")
        f.togglePlaylist(in: lib)
        #expect(f.playlist == "Сборы" && f.playlistOn(in: lib))
        f.pickPlaylist(at: 1, in: lib)
        #expect(f.playlist == "Вечер")
        f.pickPlaylist(at: 9, in: lib)
        #expect(f.playlist == "Вечер", "номер вне списка — ничего")
        f.togglePlaylist(in: lib)
        #expect(f.playlist.isEmpty && !f.playlistOn(in: lib))
        // Имя-призрак тумблер читает как «выключено»: нажатие включает первый.
        var ghost = EventForm.editing(shoot(playlist: "Удалённый"))
        #expect(!ghost.playlistOn(in: lib))
        ghost.togglePlaylist(in: lib)
        #expect(ghost.playlist == "Сборы")
    }

    @Test func draftCarriesThePlaylist() throws {
        var f = EventForm.new(id: "k1", day: day, start: 900, fromLight: false, genre: .portrait, light: nil)
        f.playlist = "Сборы"
        let data = try #require(f.draftData())
        let back = try #require(EventForm.fromDraft(data))
        #expect(back.playlist == "Сборы" && back == f)
        f.playlist = ""
        let data2 = try #require(f.draftData())
        let back2 = try #require(EventForm.fromDraft(data2))
        #expect(back2.playlist.isEmpty)
    }

    @Test func repeatCopyKeepsThePlaylistOnlyWhenTheBlockIsOn() {
        let s = shoot(playlist: "Сборы")
        let home = RepeatHome(town: "Томск", latitude: 56.48, longitude: 84.95)
        let info = Repeat(group: "g", rule: .week, index: 1, count: 2)
        let day2 = day.adding(days: 7)
        let on = Repeats.copy(s, id: "b", day: day2, info: info, blocks: [.playlist], home: home)
        let off = Repeats.copy(s, id: "c", day: day2, info: info, blocks: [], home: home)
        #expect(on.playlist == "Сборы" && off.playlist == nil)
    }
}
