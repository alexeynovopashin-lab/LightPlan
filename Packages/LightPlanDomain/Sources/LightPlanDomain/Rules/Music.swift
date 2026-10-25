import Foundation
import LightPlanCore

// MARK: - Плеер и плейлист

/// Плеер по умолчанию (веб `MUSIC`, `musicApp`). Адреса сервисов — только `https`:
/// universal link открывает приложение, если оно стоит, и сайт, если нет, —
/// откат писать не нужно. `host` служит и обратно: по домену ссылки узнаётся
/// её сервис. «Выкл» плеером не бывает — это его отсутствие (`nil`).
public enum MusicApp: String, CaseIterable, Sendable {
    case yandex, spotify, apple

    /// Имя сервиса: подпись кнопки без плейлиста и имя безымянного плейлиста.
    public var name: String {
        switch self {
        case .yandex: "Яндекс Музыка"
        case .spotify: "Spotify"
        case .apple: "Apple Music"
        }
    }

    /// Главная страница сервиса — то, что откроет кнопка у съёмки без плейлиста.
    public var url: String {
        switch self {
        case .yandex: "https://music.yandex.ru"
        case .spotify: "https://open.spotify.com"
        case .apple: "https://music.apple.com"
        }
    }

    /// Какому сервису принадлежит ссылка. Не узнали — не беда: ссылку всё равно
    /// открываем, просто называем её нейтрально. Домен сравнивается без учёта
    /// регистра и с поддоменами (`/(^|\.)spotify\.com$/i`).
    public static func of(url: String) -> MusicApp? {
        guard let host = URLComponents(string: url)?.host?.lowercased(), !host.isEmpty else { return nil }
        func under(_ d: String) -> Bool { host == d || host.hasSuffix("." + d) }
        if ["ru", "com", "by", "kz", "uz"].contains(where: { under("music.yandex." + $0) }) { return .yandex }
        if under("spotify.com") { return .spotify }
        if under("music.apple.com") { return .apple }
        return nil
    }
}

/// Плейлист из общей библиотеки (веб `playlists[]`, `{n, u}`). Съёмка помнит
/// выбор **именем**, не номером — как оборудование: правка списка не должна
/// портить старые записи.
public struct Playlist: Sendable, Hashable, Codable {
    /// `n`.
    public var name: String
    /// `u`.
    public var url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }

    enum CodingKeys: String, CodingKey { case name = "n", url = "u" }
}

/// Что откроет кнопка: подпись и ссылка.
public struct MusicChoice: Sendable, Hashable {
    public var name: String
    public var href: String

    public init(name: String, href: String) {
        self.name = name
        self.href = href
    }
}

// MARK: - Библиотека

/// Общая библиотека плейлистов и правила выбора ссылки (веб `playlists`,
/// `playlistOf`, `musicHref`, `musicName`, `musicOpen`, `renderPlaylists`).
public enum Music {
    /// Десять — потолок: барабан длиннее перестаёт быть выбором и становится поиском (`PL_MAX`).
    public static let maxPlaylists = 10

    /// Окно кнопки кончается за пять минут до конца (`MUSIC_TAIL`): дальше сборы,
    /// и убрать кнопку должно приложение, а не фотограф (Алексей, 2 сентября 2026).
    public static let tail = 5

    /// Прочитать из снимка: записи без имени или без адреса отбрасываются, лишнее
    /// сверх десяти — тоже (веб при чтении так же; следующее сохранение запишет остаток).
    public static func clean(_ raw: [Playlist]) -> [Playlist] {
        Array(raw.filter { !$0.name.isEmpty && !$0.url.isEmpty }.prefix(maxPlaylists))
    }

    /// Плейлист по имени; точное совпадение, как у веба: «Сборы» и «сборы», «Ёлка» и «Елка» — разные.
    public static func playlist(named name: String?, in list: [Playlist]) -> Playlist? {
        guard let name, !name.isEmpty else { return nil }
        return list.first { $0.name == name }
    }

    // MARK: Адрес и имя

    /// Адрес без схемы — обычный способ его продиктовать, дописываем сами (веб `normUrl`).
    /// Пусто — пусто.
    public static func normalizedURL(_ raw: String) -> String {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "" }
        if v.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil { return v }
        return "https://" + v
    }

    /// Имя необязательно: подставляем сервис по адресу (веб `autoPlName`), на
    /// незнакомом сайте — его домен без `www.`, на нечитаемом адресе — `fallback`
    /// («Плейлист»). Занятое имя получает номер: «Spotify 2», «Spotify 3».
    public static func autoName(for url: String, existing: [Playlist], fallback: String) -> String {
        let base: String
        if let app = MusicApp.of(url: url) {
            base = app.name
        } else if let host = URLComponents(string: url)?.host, !host.isEmpty {
            base = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        } else {
            base = fallback
        }
        var name = base, i = 2
        while playlist(named: name, in: existing) != nil { name = base + " \(i)"; i += 1 }
        return name
    }

    // MARK: Правка библиотеки

    /// Новый плейлист (веб `#plAdd`). Без адреса или в полном списке — ничего (`false`).
    /// Пустое имя — сервис по адресу; тёзок в списке не держим: выбирают по имени,
    /// занятое получает « ·» до тех пор, пока не станет свободным.
    @discardableResult
    public static func add(name rawName: String, url rawURL: String, to list: inout [Playlist], fallback: String) -> Bool {
        guard list.count < maxPlaylists else { return false }
        let url = normalizedURL(rawURL)
        guard !url.isEmpty else { return false }
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = autoName(for: url, existing: list, fallback: fallback) }
        while playlist(named: name, in: list) != nil { name += " ·" }
        list.append(Playlist(name: name, url: url))
        return true
    }

    /// Переименование (веб `renamePlaylist`). Идёт и в съёмки, и в корзину: имя —
    /// единственная нить между съёмкой и адресом, рвать её молча значило бы отнимать
    /// музыку у съёмки за поправленную опечатку. Пустое имя не пишем (по нему съёмку
    /// не найти); занятое другим плейлистом — тоже (иначе два слились бы в один).
    /// Возвращает записанное имя или `nil`, если ничего не изменилось.
    @discardableResult
    public static func rename(at i: Int, to raw: String, list: inout [Playlist],
                              sessions: inout [Session], trashed: inout [TrashedItem]) -> String? {
        guard list.indices.contains(i) else { return nil }
        let was = list[i].name
        let now = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !now.isEmpty, now != was else { return nil }
        guard !list.indices.contains(where: { $0 != i && list[$0].name == now }) else { return nil }
        for k in sessions.indices where sessions[k].playlist == was { sessions[k].playlist = now }
        for k in trashed.indices where trashed[k].record.playlist == was { trashed[k].record.playlist = now }
        list[i].name = now
        return now
    }

    /// Правка адреса на месте: без схемы — `https://` (веб `.pl-u`). Пустой адрес
    /// плейлист оставил бы без смысла, поэтому пустое поле не пишем.
    @discardableResult
    public static func setURL(at i: Int, to raw: String, list: inout [Playlist]) -> Bool {
        guard list.indices.contains(i) else { return false }
        let url = normalizedURL(raw)
        guard !url.isEmpty, url != list[i].url else { return false }
        list[i].url = url
        return true
    }

    /// Крестик у плейлиста. Съёмки не трогаем: имя в записи остаётся, но без плейлиста в
    /// библиотеке съёмка просто без своей музыки (кнопка ведёт в плеер по умолчанию).
    @discardableResult
    public static func remove(at i: Int, from list: inout [Playlist]) -> Playlist? {
        guard list.indices.contains(i) else { return nil }
        return list.remove(at: i)
    }

    // MARK: Кнопка в карточке

    /// Что откроет кнопка у этой съёмки: свой плейлист, если он выбран и есть в
    /// библиотеке, иначе плеер по умолчанию. Ни того ни другого — `nil`, кнопки нет.
    /// Плейлист ищется по имени, а не по сервису: плейлист с именем «Spotify» и
    /// ссылкой Apple Music открывает Apple Music, а не плеер из настроек.
    /// Ссылка, которая не читается как адрес, кнопки не даёт.
    public static func choice(for s: Session, app: MusicApp?, playlists: [Playlist]) -> MusicChoice? {
        let pick: MusicChoice?
        if let pl = playlist(named: s.playlist, in: playlists) {
            pick = MusicChoice(name: pl.name, href: pl.url)
        } else if let app {
            pick = MusicChoice(name: app.name, href: app.url)
        } else {
            pick = nil
        }
        guard let pick, let u = URL(string: pick.href), u.host?.isEmpty == false else { return nil }
        return pick
    }

    /// Конец окна: записанная отметка «Завершить», иначе записанный конец (веб `musicEndOf`).
    /// Съёмка, которую завершают вручную и которая идёт сверх плана, теряет кнопку по записанному
    /// концу: другого конца приложение не знает.
    public static func windowEnd(of s: Session) -> Int { s.doneAt ?? s.endMinute }

    /// Открыто ли окно кнопки (веб `musicOpen`): только у работы (встреча музыки не получает —
    /// это разговор), от начала до «конец минус пять минут». Считается по шкале съёмки (`minute(at:)`),
    /// поэтому свадьба 19:00–03:00 держит кнопку и после полуночи (слово Алексея 25.10: «до конца съёмки
    /// (минус 5 минут), даже после полуночи»; веб гасит её в полночь — «в её день»). Съёмка завтра и
    /// съёмка, уже кончившаяся, вне шкалы — кнопки нет. `now` — настенные часы места съёмки, те же, что у фазы карточки.
    public static func isOpen(_ s: Session, now: WallTime) -> Bool {
        guard s.kind.isWork, let m = s.minute(at: now) else { return false }
        return m >= s.start && m < windowEnd(of: s) - tail
    }

    /// Кнопка карточки целиком: окно открыто и есть что открывать.
    public static func button(for s: Session, now: WallTime, app: MusicApp?, playlists: [Playlist]) -> MusicChoice? {
        isOpen(s, now: now) ? choice(for: s, app: app, playlists: playlists) : nil
    }
}

// MARK: - Строка «Плейлист» в форме

extension EventForm {
    /// Выбран ли плейлист, который есть в библиотеке (веб `!!playlistOf(fPlaylist)`): тумблер
    /// горит только тогда. Имя, которого в библиотеке нет, — не выбор.
    public func playlistOn(in list: [Playlist]) -> Bool {
        Music.playlist(named: playlist, in: list) != nil
    }

    /// Строка есть, только пока в библиотеке есть из чего выбирать (веб `#fMusicRow`).
    public func playlistRowShown(in list: [Playlist]) -> Bool { !list.isEmpty }

    /// Форма узнаёт о библиотеке (веб `refreshMusicRow`): при открытии и после правки списка
    /// выбранный плейлист, которого уже нет, сбрасывается — иначе «Сохранить» записало бы имя-призрак.
    public mutating func refreshPlaylist(in list: [Playlist]) {
        if !playlist.isEmpty, Music.playlist(named: playlist, in: list) == nil { playlist = "" }
    }

    /// Тумблер: включает музыку первым плейлистом списка, а не спрашивает, каким — плейлист чаще
    /// один, и лишний барабан там нечего крутить. Выключает — убирает выбор. Пустой список — ничего.
    public mutating func togglePlaylist(in list: [Playlist]) {
        guard let first = list.first else { return }
        playlist = playlistOn(in: list) ? "" : first.name
    }

    /// Капсула-барабан: выбрать плейлист по номеру в библиотеке.
    public mutating func pickPlaylist(at i: Int, in list: [Playlist]) {
        guard list.indices.contains(i) else { return }
        playlist = list[i].name
    }
}
