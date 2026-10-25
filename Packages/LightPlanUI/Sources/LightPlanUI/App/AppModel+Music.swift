import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Музыка (шаг «Музыка», 25.10): плеер по умолчанию и общая библиотека плейлистов в «Настройки → Съёмки»,
/// кнопка в карточке, выбор в форме. Правила — `Music` (Domain); здесь — снимок и сохранение.
extension AppModel {

    /// Библиотека плейлистов (веб `playlists`).
    public var playlists: [Playlist] { snapshot.playlists }

    /// Плеер по умолчанию; `nil` — «Выкл».
    public var musicApp: MusicApp? { settings.musicApp }

    public func setMusicApp(_ app: MusicApp?) {
        update { $0.musicApp = app }
    }

    /// «＋» в настройках (веб `#plAdd`). `false` — адреса нет или список полон: поле остаётся как было.
    @discardableResult
    public func addPlaylist(name: String, url: String) -> Bool {
        var list = snapshot.playlists
        guard Music.add(name: name, url: url, to: &list, fallback: lexicon.t("form.playlist")) else { return false }
        snapshot.playlists = list
        persist()
        return true
    }

    /// Имя правится на месте: идёт в съёмки и в корзину. Возвращает записанное имя; `nil` — имя не изменилось
    /// (пустое или занятое другим плейлистом).
    @discardableResult
    public func renamePlaylist(at i: Int, to name: String) -> String? {
        var list = snapshot.playlists, sessions = snapshot.sessions, trashed = snapshot.trashed
        guard let now = Music.rename(at: i, to: name, list: &list, sessions: &sessions, trashed: &trashed) else { return nil }
        snapshot.playlists = list
        snapshot.sessions = sessions
        snapshot.trashed = trashed
        form?.refreshPlaylist(in: list)
        persist()
        return now
    }

    public func setPlaylistURL(at i: Int, to url: String) {
        var list = snapshot.playlists
        guard Music.setURL(at: i, to: url, list: &list) else { return }
        snapshot.playlists = list
        persist()
    }

    /// Крестик: плейлист уходит из библиотеки, съёмки остаются без своей музыки; открытая форма
    /// узнаёт об этом (веб `refreshMusicRow`).
    public func removePlaylist(at i: Int) {
        var list = snapshot.playlists
        guard Music.remove(at: i, from: &list) != nil else { return }
        snapshot.playlists = list
        form?.refreshPlaylist(in: list)
        persist()
    }

    // MARK: - Форма

    public func toggleFormPlaylist() {
        guard var f = form else { return }
        f.togglePlaylist(in: snapshot.playlists)
        form = f
        formChanged()
    }

    public func pickFormPlaylist(at i: Int) {
        guard var f = form else { return }
        f.pickPlaylist(at: i, in: snapshot.playlists)
        form = f
        formChanged()
    }

    // MARK: - Карточка

    /// Кнопка музыки в карточке (веб `renderCardMusic`): только в окне съёмки, по часам её места.
    public func musicButton(for s: Session) -> MusicChoice? {
        Music.button(for: s, now: wallNow(at: s), app: settings.musicApp, playlists: snapshot.playlists)
    }
}
