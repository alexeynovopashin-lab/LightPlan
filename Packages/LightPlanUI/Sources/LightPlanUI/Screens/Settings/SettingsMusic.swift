import SwiftUI
import LightPlanDomain

/// «Музыка» и «Плейлисты» в «Настройки → Съёмки» (веб `#musicSeg`, `#plList`, `#plAdd`). Плеер по умолчанию —
/// настройка фотографа, а не съёмки: он отвечает за кнопку у съёмки без плейлиста. Плейлисты живут здесь, а не в
/// съёмке: их готовят заранее и пользуются весь сезон, съёмка из списка только выбирает.

/// Плеер по умолчанию: «Выкл» / «Яндекс» / «Spotify» / «Apple Music» и подпись по выбору.
struct MusicPlayerSection: View {
    @Bindable var app: AppModel
    /// Номера подписи, сегмента и пояснения в главе для пары снимков (`sec.N`, `seg.N`, `note.N`).
    var index: Int? = nil

    var body: some View {
        let t = app.lexicon
        let app = app
        SecLabel(text: t.t("set.music"), node: index.map { "sec.\($0)" })
        WebSeg(options: [(t.t("set.musicOff"), MusicApp?.none), ("Яндекс", .yandex), ("Spotify", .spotify), ("Apple Music", .apple)],
               selection: Binding(get: { app.musicApp }, set: { app.setMusicApp($0) }), lines: 2)
            .shotNode(index.map { "seg.\($0)" } ?? "")
            .padding(.horizontal, 24).padding(.top, 12)
        SetNote(text: t.t(app.musicApp == nil ? "set.musicNoteOff" : "set.musicNote"), node: index.map { "note.\($0)" })
    }
}

/// Список плейлистов: имя, ссылка, крестик на месте; внизу — строка нового и «＋».
struct PlaylistsSection: View {
    @Bindable var app: AppModel
    var index: Int? = nil

    @State private var newName = ""
    @State private var newURL = ""
    /// Устойчивые ключи строк: строка помнит черновик и фокус под своим ключом, а не под номером,
    /// иначе после удаления строки выше текст одной записи ушёл бы в другой плейлист.
    @State private var keys: [UUID]
    @FocusState private var focus: Field?
    @Environment(\.colorScheme) private var scheme

    init(app: AppModel, index: Int? = nil) {
        self.app = app
        self.index = index
        _keys = State(initialValue: app.playlists.map { _ in UUID() })
    }

    enum Field: Hashable { case newName, newURL }

    var body: some View {
        let t = app.lexicon
        let pal = Palette(scheme)
        let list = app.playlists
        let full = list.count >= Music.maxPlaylists
        SecLabel(text: t.t("set.playlists"), node: index.map { "sec.\($0)" })
        if list.isEmpty {
            // `.pl-empty`: 12 `--ink-6`, поля 10 · 24 · 0.
            Text(t.t("set.plEmpty")).font(.system(size: 12)).foregroundStyle(pal.ink6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 10)
                .shotNode("pl.empty", text: t.t("set.plEmpty"))
        } else {
            ForEach(list.indices, id: \.self) { i in
                let key = keys.indices.contains(i) ? keys[i] : nil
                PlaylistRow(app: app, index: i, playlist: list[i]) { remove(i) }
                    .id(key)
                    .shotNode("pl.item")
            }
        }
        newRow(t, pal, full: full)
        SetNote(text: t.t(full ? "set.plFull" : "set.plNote"), node: index.map { "note.\($0)" })
    }

    /// Строка нового плейлиста (`.pl-item` с `#plNewName`, `#plNewUrl`, `#plAdd`).
    private func newRow(_ t: Lexicon, _ pal: Palette, full: Bool) -> some View {
        PlaylistFrame {
            field(t.t("set.plName"), text: $newName, pal: pal)
                .focused($focus, equals: .newName)
                .submitLabel(.next)
                .onSubmit { focus = .newURL }
        } url: {
            urlField(t.t("set.plUrl"), text: $newURL, pal: pal)
                .focused($focus, equals: .newURL)
                .submitLabel(.done)
                .onSubmit(add)
        } trailing: {
            Button(action: add) {
                Text(t.t("kit.add")).font(.system(size: 15)).foregroundStyle(full ? pal.ink8 : pal.brass)
                    .frame(width: 30, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(full)
            .accessibilityLabel(t.t("set.plAdd"))
            .shotNode("pl.add")
        }
        .shotNode("pl.new")
    }

    /// Крестик: строка уходит вместе со своим ключом, остальные сохраняют черновики и фокус.
    private func remove(_ i: Int) {
        if keys.indices.contains(i) { keys.remove(at: i) }
        app.removePlaylist(at: i)
    }

    /// Без адреса плейлиста нет: «＋» просто возвращает курсор в поле адреса.
    private func add() {
        if app.addPlaylist(name: newName, url: newURL) {
            keys.append(UUID())
            newName = ""; newURL = ""; focus = .newName
        } else if app.playlists.count < Music.maxPlaylists {
            focus = .newURL
        }
    }
}

/// Одна строка списка. Поля держат свой черновик: пустое имя в модель не пишется (по нему съёмку не найти),
/// а поле при этом не должно прыгать назад под пальцем. Ушёл фокус — черновик снова равен записанному.
private struct PlaylistRow: View {
    @Bindable var app: AppModel
    let index: Int
    let playlist: Playlist
    let onRemove: () -> Void

    @State private var name: String
    @State private var url: String
    @FocusState private var focus: Bool?
    @Environment(\.colorScheme) private var scheme

    init(app: AppModel, index: Int, playlist: Playlist, onRemove: @escaping () -> Void) {
        self.app = app; self.index = index; self.playlist = playlist; self.onRemove = onRemove
        _name = State(initialValue: playlist.name); _url = State(initialValue: playlist.url)
    }

    var body: some View {
        let t = app.lexicon
        let pal = Palette(scheme)
        PlaylistFrame {
            field("", text: Binding(get: { name }, set: { v in name = v; app.renamePlaylist(at: index, to: v) }), pal: pal)
                .focused($focus, equals: true)
        } url: {
            urlField("", text: Binding(get: { url }, set: { v in url = v; app.setPlaylistURL(at: index, to: v) }), pal: pal)
                .focused($focus, equals: false)
        } trailing: {
            Button(action: onRemove) {
                Text("✕").font(.system(size: 15)).foregroundStyle(pal.ink6)
                    .frame(width: 30, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.t("gen.removeAria"))
        }
        // Модель поменялась снаружи (строку выше убрали, имя поправила другая правка): без фокуса следуем ей.
        .onChange(of: playlist) { _, p in
            if focus == nil { name = p.name; url = p.url }
        }
        .onChange(of: focus) { _, f in
            if f == nil { name = playlist.name; url = playlist.url }
        }
    }
}

/// Раскладка `.pl-item`: имя — 34 % ширины колонки (место нужнее адресу), адрес — остальное, справа кнопка 30 × 44.
private struct PlaylistFrame<Name: View, URL: View, Trailing: View>: View {
    let name: Name
    let url: URL
    let trailing: Trailing

    init(@ViewBuilder name: () -> Name, @ViewBuilder url: () -> URL, @ViewBuilder trailing: () -> Trailing) {
        self.name = name(); self.url = url(); self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 6) {
            name.containerRelativeFrame(.horizontal) { w, _ in (w - 48) * 0.34 }
            url.frame(maxWidth: .infinity)
            trailing
        }
        .frame(height: 44)
        .padding(.horizontal, 24).padding(.top, 10)
    }
}

// MARK: - Поля `.pl-item input`

/// Поле: подложка `--sheet`, радиус 10, поля 12, 14 `--ink`, подсказка `--ink-8`.
private func field(_ placeholder: String, text: Binding<String>, pal: Palette) -> some View {
    TextField("", text: text, prompt: Text(placeholder).foregroundStyle(pal.ink8))
        .font(.system(size: 14)).foregroundStyle(pal.ink)
        .padding(12)
        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
}

/// Адрес: без автозаглавных, без поправок, клавиатура для адресов.
private func urlField(_ placeholder: String, text: Binding<String>, pal: Palette) -> some View {
    field(placeholder, text: text, pal: pal)
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.URL)
        #endif
}
