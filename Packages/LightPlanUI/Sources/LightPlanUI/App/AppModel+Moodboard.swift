import Foundation
import LightPlanCore
import LightPlanDomain

// MARK: - Мудборд: правки подборок и состав экранов (итерация 28, шаг 5а)

/// Что открыто и набрано в мудборде. Галерея и полка — слои поверх вкладок (веб `#mbOverlay`,
/// `#mbShelfOverlay`); поле и чип — два независимых входа поиска (веб `mbActiveTag`).
struct MoodboardState: Equatable {
    var galleryOpen = false
    /// Ключ подписи стрелки «назад» галереи: откуда пришли — с «Съёмок» или из «Настроек».
    var backKey = "nav.shoots"
    var shelf: String?
    var query = ""
    var tag: String?
    /// Открытая папка — id её подборки; поле, раздел и выбор живут, пока папка открыта
    /// (веб: `mbOpen`, `mbTag`, `mbPicked` — `openMbFolder` и «назад» их сбрасывают).
    var folder: String?
    var folderQuery = ""
    var folderTag: String?
    var folderSearchOpen = false
    var pick: MbPick?
    /// Просмотрщик папки: список кадров на момент открытия (только картинки, в порядке сетки).
    var viewerIds: [String] = []
    var pager: RefPager?
    /// Открытый лист мудборда (шаг 5в): меню, «Добавить в…», «Новая подборка», обложка, карточка, кадр.
    var sheet: MbSheet?
    /// Системный выбор «Фото» открыт (шаг 5г): его просят кнопка «Фото» и лист «+».
    var photoPicker = false
    /// Доска Pinterest, что читается, ждёт «Добавить» или качается (28м); `nil` — ничего не идёт.
    var pin: PinFlow?
    /// Строка под кнопками папки: пин без превью, нет связи, ключа нет (28м).
    var pinNote: PinNote?
    var isOpen: Bool { galleryOpen || shelf != nil || folder != nil }
}

/// Названия плитки: заголовок и подпись (веб `mbTitle`, `mbSubTile`).
struct MbLabels {
    let title: String
    let sub: String
}

extension AppModel {

    // MARK: чтение

    func mbLibrary() -> RefLibrary { RefLibrary(extra: snapshot.extra) }

    /// Чем рисуется кадр: файл на телефоне, надпись «сайт / хвост пути» или штриховка (шаг 5д).
    func refFace(_ f: RefFrame) -> RefFrame.Face {
        f.face(hasFile: { refImages?.exists($0) ?? false })
    }

    /// Плитки ленты: съёмки с кадрами и по полке на включённый жанр.
    func mbFolders(_ lib: RefLibrary) -> [MbFolder] {
        Moodboard.folders(library: lib, sessions: sessions, genresOn: Set(Moodboard.enabledGenres(snapshot.genres).map(\.rawValue)))
    }

    /// Полоса свёрнута (`mbStripFold` снимка — тот же ключ, что у веба).
    var mbStripFolded: Bool {
        get { if case .bool(let on)? = snapshot.extra["mbStripFold"] { return on } else { return false } }
        set {
            guard newValue != mbStripFolded else { return }
            snapshot.extra["mbStripFold"] = .bool(newValue)
            persist()
        }
    }

    private var mbFacts: PlannerFacts { PlannerFacts(app: self, dark: true) }

    func mbSession(_ f: MbFolder) -> Session? { sessions.first { $0.id == f.sessionId } }

    func mbGenreName(_ code: String?) -> String {
        guard let code else { return "" }
        let v = lexicon.t("genre." + code)
        return v == "genre." + code ? code : v
    }

    func mbTagName(_ code: String) -> String {
        let v = lexicon.t("tag." + code)
        return v == "tag." + code ? code : v
    }

    func mbLabels(_ f: MbFolder, _ lib: RefLibrary) -> MbLabels {
        let facts = mbFacts
        switch f.kind {
        case .shoot:
            guard let s = mbSession(f) else { return MbLabels(title: "", sub: "") }
            let who = facts.words.clientName(s)
            let type = facts.words.typeName(s)
            return MbLabels(title: who.isEmpty ? type : who,
                            sub: facts.dates.dMonShort(facts.date(s.day)) + " · " + type.lowercased())
        case .genre:
            let n = f.boardIds.count
            return MbLabels(title: mbGenreName(f.genre),
                            sub: n > 1 ? lexicon.count("unit.folder", n) : lexicon.t("mb.setShort"))
        }
    }

    /// Названия подборок, где лежит кадр — по ним ищут (веб `shotBoardTitles`).
    func mbBoardTitles(_ shot: RefFrame, _ lib: RefLibrary) -> [String] {
        let facts = mbFacts
        return lib.boards.filter { $0.items.contains(shot.id) }.compactMap { b in
            if b.kind == .shoot {
                guard let s = sessions.first(where: { $0.id == b.sid }) else { return nil }
                let who = facts.words.clientName(s)
                return who.isEmpty ? facts.words.typeName(s) : who
            }
            return b.name ?? mbGenreName(b.genre)
        }.filter { !$0.isEmpty }
    }

    // MARK: слои

    func openMbGallery(backKey: String = "nav.shoots") { mb.backKey = backKey; mb.galleryOpen = true }

    func closeMbGallery() {
        mb.galleryOpen = false; mb.query = ""; mb.tag = nil; mb.pager = nil; mb.viewerIds = []
    }

    func openMbShelf(_ genre: String) { mb.shelf = genre }
    func closeMbShelf() { mb.shelf = nil }

    /// Тап по плитке: жанр с несколькими папками — полка; папка — экран папки.
    func openMbFolder(_ f: MbFolder) {
        switch Moodboard.openTarget(f, in: mbLibrary()) {
        case .shelf(let g): openMbShelf(g)
        case .folder(let id): openMbFolder(boardId: id)
        }
    }

    // MARK: правка подборок (операции шага 4 — записываются сразу)

    /// Одна правка библиотеки: разбор, действие, запись в снимок, сохранение.
    @discardableResult
    func mbEdit<T>(_ body: (inout RefLibrary, Double) -> T) -> T {
        let before = mbLibrary()
        var lib = before
        let r = body(&lib, Double(nowMs))
        lib.write(into: &snapshot.extra)
        // Кадр ушёл из последней подборки — его файл тоже (шаг 5г), но только когда снимок без кадра
        // уже записан; кадр в другой подборке файл держит.
        let gone = RefLibrary.orphanImages(before: before, after: lib)
        if gone.isEmpty { persist() } else {
            let images = refImages
            persist { for name in gone { images?.delete(name) } }
        }
        return r
    }

    @discardableResult
    func mbPut(_ shot: String, into board: String) -> Bool { mbEdit { $0.put(shot, into: board, now: $1) } }

    @discardableResult
    func mbTake(_ shot: String, from board: String) -> Bool { mbEdit { $0.take(shot, from: board, now: $1) } }

    /// «Добавить в…» / «Переместить…» пачкой (веб L22228–22240).
    @discardableResult
    func mbMove(_ shots: [String], from: String?, to: String, remove: Bool) -> [String] {
        mbEdit { $0.move(shots, from: from, to: to, remove: remove, now: $1) }
    }

    /// Удалить подборку; ответ — кадры, ушедшие насовсем (для подписи «N только здесь»).
    @discardableResult
    func mbDeleteBoard(_ id: String) -> [String] { mbEdit { lib, _ in lib.dropWithShots(id) } }

    @discardableResult
    func mbMerge(_ from: String, into: String) -> [String] { mbEdit { $0.merge(from, into: into, now: $1) } }

    /// Новая папка жанра с именем; пустое имя — `nil`, ничего не пишется.
    @discardableResult
    func mbAddFolder(genre: String, name: String) -> String? {
        mbEdit { lib, now in lib.addFolder(genre: genre, name: name, id: UUID().uuidString.lowercased(), now: now)?.id }
    }
}
