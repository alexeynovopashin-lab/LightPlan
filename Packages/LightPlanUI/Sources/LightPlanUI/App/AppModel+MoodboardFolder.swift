import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

// MARK: - Папка мудборда (итерация 28, шаг 5б)

/// Сетка и подписи одной папки, посчитанные из библиотеки один раз за отрисовку.
struct MbFolderScene {
    var board: RefBoard
    var list: [RefFrame]
    var sections: [MbFolderView.Section]
    var tag: String?
    var shown: [RefFrame]
    var filtered: Bool
    var label: MbFolderView.GridLabel
    var title: String
    var sub: String
    var genre: String?
}

extension AppModel {

    // MARK: чтение

    func mbFolderScene(_ lib: RefLibrary) -> MbFolderScene? {
        guard let id = mb.folder, let board = lib.board(id) else { return nil }
        let list = MbFolderView.frames(of: board, in: lib.shots)
        let genre = mbFolderGenre(board)
        let sections = MbFolderView.sections(list, genre: genre)
        let tag = MbFolderView.activeTag(mb.folderTag, in: sections)
        let shown = MbFolderView.shown(list, tag: tag, query: mb.folderQuery, sort: board.sort, tagName: mbTagName)
        let filtered = MbFolderView.isFiltered(tag: tag, query: mb.folderQuery)
        let head = mbFolderHead(board)
        return MbFolderScene(board: board, list: list, sections: sections, tag: tag, shown: shown, filtered: filtered,
                             label: MbFolderView.gridLabel(total: list.count, shown: shown.count, filtered: filtered,
                                                           picked: mb.pick?.count),
                             title: head.title, sub: head.sub, genre: genre)
    }

    /// Жанр папки: у съёмки — жанр записи, у жанровой папки — её жанр (веб `mbGenre`).
    func mbFolderGenre(_ b: RefBoard) -> String? {
        if b.kind == .shoot { return sessions.first { $0.id == b.sid }?.genre?.rawValue ?? b.genre }
        return b.genre
    }

    /// Шапка папки (веб `mbTitle`, `mbSub`): съёмка — «Имя клиента» и «Тип · 1 окт 2026 · место»;
    /// жанр — имя жанра и имя папки (у основной — «Жанровая подборка»).
    func mbFolderHead(_ b: RefBoard) -> MbLabels {
        let facts = PlannerFacts(app: self, dark: true)
        if b.kind == .shoot, let s = sessions.first(where: { $0.id == b.sid }) {
            let who = facts.words.clientName(s)
            let type = facts.words.typeName(s)
            var sub = type + " · " + facts.dates.dMonYear(facts.date(s.day))
            let place = (s.placeText.split(separator: ",", omittingEmptySubsequences: false).first.map(String.init) ?? "")
                .trimmingCharacters(in: .whitespaces)
            if !place.isEmpty { sub += " · " + place }
            return MbLabels(title: who.isEmpty ? type : who, sub: sub)
        }
        return MbLabels(title: mbGenreName(b.genre), sub: b.name ?? lexicon.t("mb.genreSet"))
    }

    // MARK: слои

    /// Открыть папку: чужой запрос и раздел не переезжают, выбор сброшен (веб `openMbFolder`).
    func openMbFolder(boardId: String) {
        mb.folder = boardId
        resetMbFolderInput()
    }

    /// «Назад»: режим выбора живёт не дольше папки; опустевшая подборка съёмки без имени
    /// исчезает (веб `boardPrune` в `mbFolderBack`). Пустая жанровая остаётся.
    func closeMbFolder() {
        if let id = mb.folder {
            pinFolderClosing(id)
            if !pinImportRunning(into: id) { mbEdit { lib, _ in lib.prune(id) } }
        }
        mb.folder = nil
        resetMbFolderInput()
    }

    private func resetMbFolderInput() {
        mb.folderQuery = ""; mb.folderTag = nil; mb.folderSearchOpen = false
        mb.pick = nil; mb.pager = nil; mb.viewerIds = []
    }

    /// Лупа: раскрывает поле; повторный тап очищает его и сворачивает (веб `mbSearchBtn`).
    func toggleMbFolderSearch() {
        if mb.folderSearchOpen { mb.folderQuery = ""; mb.folderSearchOpen = false } else { mb.folderSearchOpen = true }
    }

    func setMbFolderTag(_ tag: String?) { mb.folderTag = mb.folderTag == tag ? nil : tag }

    // MARK: выбор

    func toggleMbPicking() { mb.pick = mb.pick == nil ? MbPick() : nil }

    func toggleMbPick(_ id: String) { mb.pick?.toggle(id) }

    func toggleMbPickAll(_ shown: [RefFrame]) { mb.pick?.toggleAll(shown: shown.map(\.id)) }

    /// «Убрать N»: кадры снимаются с подборки, ушедшие насовсем — из фонда; выбор кончается
    /// (веб `mbSelDel`). Подборка исчезла (опустела) — папка закрывается.
    func mbRemovePicked() {
        guard let id = mb.folder, let picked = mb.pick?.ids, !picked.isEmpty else { return }
        mbEdit { lib, now in lib.remove(picked, from: id, now: now) }
        mb.pick = nil
        mb.pager = nil; mb.viewerIds = []
        if mbLibrary().board(id) == nil { mb.folder = nil; resetMbFolderInput() }
    }

    // MARK: просмотрщик

    /// Тап по кадру (веб `openRefAt`): картинка — в просмотрщик по списку «только картинки, в
    /// порядке сетки»; ссылка без картинки — её адрес (в папке такая ссылка открывает лист кадра —
    /// это решает экран папки, `MoodboardFolder.tile`); пустой кадр молчит.
    func openMbFrame(_ id: String, shown: [RefFrame]) -> RefTileOpen {
        guard let f = shown.first(where: { $0.id == id }) else { return .none }
        if MbFolderView.isBareLink(f), let u = f.url, let url = URL(string: u), url.scheme != nil { return .url(url) }
        let list = MbFolderView.viewerList(shown)
        guard let at = list.firstIndex(where: { $0.id == id }) else { return .none }
        mb.viewerIds = list.map(\.id)
        mb.pager = RefPager(count: list.count, start: at)
        return .viewer
    }

    var mbViewerFrameId: String? {
        guard let p = mb.pager, mb.viewerIds.indices.contains(p.index) else { return nil }
        return mb.viewerIds[p.index]
    }

    func mbViewerSwipe(dx: Double, dy: Double) {
        _ = mb.pager?.apply(RefPager.decide(dx: dx, dy: dy))
    }

    func closeMbViewer() { mb.pager = nil; mb.viewerIds = [] }
}

// MARK: - «Фото» и «Ссылка» (итерация 28, шаг 5г)

extension AppModel {

    /// Кнопка «Фото» (и строка листа «+»): лист закрыт, системный выбор открывается следом.
    func requestMbPhotoPicker() {
        guard mb.folder != nil else { return }
        mb.sheet = nil
        mb.photoPicker = true
    }

    /// Выбранные кадры: файл ложится под новым именем `im`, потом кадр — в папку `board`, что была
    /// открыта при выборе (веб `useRefBoard`): чтение фото долгое, за это время папку могли сменить
    /// или закрыть (ревью GPT к a2549e7). Не разобралась картинка, не записался файл, подборки уже нет —
    /// кадра нет и файла нет. Ответ — id новых кадров.
    @discardableResult
    func mbAddPhotos(_ blobs: [Data], to board: String, tag: String? = nil) -> [String] {
        guard let images = refImages else { return [] }
        var added: [String] = []
        for data in blobs {
            guard let size = RefImageStore.pixelSize(of: data) else { continue }
            let im = UUID().uuidString.lowercased()
            guard images.save(data, as: im) else { continue }
            let id = mbEdit { lib, now in lib.addPhoto(im: im, w: size.w, h: size.h, to: board, tag: tag, now: now) }
            if let id { added.append(id) } else { images.delete(im) }
        }
        return added
    }

    /// Кнопка «Ссылка» — лист с адресом (веб `askLink`).
    func openMbAddLink() { mb.sheet = .addLink }

    /// Адрес из листа: кадр-ссылка ложится в открытую папку. Мусор не пишется, лист остаётся; дубль
    /// в этой подборке — лист закрывается, второй плитки нет. Pinterest (28м): доска и короткая ссылка уходят
    /// в читалку (лист «Добавить доску?»), пин ложится плиткой и дотягивает картинку; без ключа в сборке —
    /// обычная плитка и честная строка.
    @discardableResult
    func mbAddLink(_ raw: String) -> RefLinkAdd {
        guard let board = mb.folder else { return .invalid }
        let tag = mb.folderTag
        let kind = PinterestLink.kind(raw)
        switch kind {
        case .board, .short:
            if pinterest != nil, let link = PinterestLink.secure(raw) {
                startPinBoard(link: link, board: board, tag: tag)
                return .added("")
            }
        case .pin(let id):
            if mbLibrary().pinKeys(in: board).contains(id) { mb.sheet = nil; return .duplicate }
        case .other: break
        }
        let r = mbEdit { lib, now in lib.addLink(raw, to: board, id: UUID().uuidString.lowercased(), tag: tag, now: now) }
        if r != .invalid { mb.sheet = nil }
        if case .added(let frame) = r {
            if kind != .other { startPinPreview(frame: frame, link: PinterestLink.secure(raw) ?? raw) }
            else {
                // Прямая ссылка на фото (28н.1): по расширению — сразу, без расширения — тихая проверка по ответу.
                let image = ImageLink.kind(raw)
                if image != .page { startImagePreview(frame: frame, link: PinterestLink.secure(raw) ?? raw, quiet: image == .maybe) }
            }
        }
        return r
    }
}
