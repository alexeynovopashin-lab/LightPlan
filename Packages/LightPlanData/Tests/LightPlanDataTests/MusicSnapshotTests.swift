import Testing
import Foundation
@testable import LightPlanData
import LightPlanDomain

/// Шаг «Музыка»: плеер и библиотека плейлистов в снимке веба (`musicApp`, `playlists`, `saveAll`).
struct MusicSnapshotTests {

    func decode(_ json: String) throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }
    func keys(_ s: Snapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
    }

    @Test func webPlayerAndPlaylistsSurviveReadWrite() throws {
        let web = #"""
        {"musicApp":"spotify","playlists":[{"n":"Сборы","u":"https://open.spotify.com/playlist/a"},
        {"n":"Вечер","u":"https://music.yandex.ru/users/x/playlists/1"}],
        "sessions":[{"id":"s1","date":"2026-10-25","min":900,"dur":120,"playlist":"Сборы"}]}
        """#
        let a = try decode(web)
        #expect(a.musicApp == "spotify" && a.playlists.count == 2)
        #expect(a.extra["musicApp"] == nil && a.extra["playlists"] == nil, "ключи не лежат в `extra` дважды")
        #expect(a.sessions.first?.playlist == "Сборы")
        // круг: запись → чтение даёт то же
        let b = try decode(String(decoding: JSONEncoder().encode(a), as: UTF8.self))
        #expect(b.musicApp == a.musicApp && b.playlists == a.playlists && b.sessions.first?.playlist == "Сборы")
        let out = try keys(a)
        #expect(out["musicApp"] as? String == "spotify")
        let pl = try #require(out["playlists"] as? [[String: String]])
        #expect(pl == [["n": "Сборы", "u": "https://open.spotify.com/playlist/a"],
                       ["n": "Вечер", "u": "https://music.yandex.ru/users/x/playlists/1"]], "ключи `n` и `u`, как у веба")
        #expect(AppSettings(snapshot: a).musicApp == .spotify)
    }

    @Test func offAndMissingPlayerBothMeanOff() throws {
        #expect(AppSettings(snapshot: try decode(#"{"musicApp":"off"}"#)).musicApp == nil)
        #expect(AppSettings(snapshot: try decode("{}")).musicApp == nil)
        #expect(AppSettings(snapshot: try decode(#"{"musicApp":7}"#)).musicApp == nil, "не строка — как выкл")
    }

    @Test func unknownPlayerStringIsKeptAsWritten() throws {
        var snap = try decode(#"{"musicApp":"deezer"}"#)
        let s = AppSettings(snapshot: snap)
        #expect(s.musicApp == nil)
        s.apply(to: &snap)                       // безобидное сохранение настроек
        #expect(snap.musicApp == "deezer")
        var changed = s; changed.musicApp = .apple
        changed.apply(to: &snap)
        #expect(snap.musicApp == "apple")
        var off = changed; off.musicApp = nil
        off.apply(to: &snap)
        #expect(snap.musicApp == "off", "выбрали «Выкл» — пишем, как пишет веб")
    }

    @Test func brokenEntriesAreDroppedLikeTheWebDoes() throws {
        let a = try decode(#"{"playlists":[{"n":"","u":"https://a.b"},{"n":"Без адреса"},"мусор",null,{"n":"Ок","u":"https://c.d"}]}"#)
        #expect(a.playlists == [Playlist(name: "Ок", url: "https://c.d")])
        #expect(try decode(#"{"playlists":"не список"}"#).playlists.isEmpty)
        let many = (1...13).map { #"{"n":"П\#($0)","u":"https://a.b/\#($0)"}"# }.joined(separator: ",")
        #expect(try decode(#"{"playlists":[\#(many)]}"#).playlists.count == 10, "потолок — десять")
    }

    @Test func emptyLibraryAndPlayerLeaveTheFileAsBefore() throws {
        let out = try keys(try decode("{}"))
        #expect(out["playlists"] == nil && out["musicApp"] == nil)
    }
}
