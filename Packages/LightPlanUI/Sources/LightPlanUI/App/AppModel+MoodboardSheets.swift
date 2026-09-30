import Foundation
import LightPlanCore
import LightPlanDomain

// MARK: - Листы мудборда (итерация 28, шаг 5в)

/// Один лист мудборда поверх экранов; экран внутри листа меняется на месте (меню → «Порядок» → назад),
/// потому что сам лист один (`MbSheetHost`). Подтверждения — тоже состояния листа.
enum MbSheet: Equatable {
    case menu(String)
    case sortPick(String)
    case mergePick(String)
    case mergeConfirm(from: String, to: String)
    case rename(String)
    case newFolder(genre: String)
    case add(MbAddMode)
    case loneConfirm(shot: String, board: String)
    case new
    case cover(String)
    case board(String)
    case item(shot: String, board: String, overView: Bool)
}

/// Что лист «Добавить в…» делает с тапом: один кадр (галочки) или пачка (добавить / переместить).
struct MbAddMode: Equatable {
    var shot: String?
    var many: [String] = []
    var move = false
    /// Папка, из которой берут пачку; в списке её нет.
    var from: String?
}

extension AppModel {

    // MARK: входы

    func openMbMenu(_ boardId: String) { mb.sheet = .menu(boardId) }
    func openMbNew() { mb.sheet = .new }
    func openMbBoardCard(_ boardId: String) { mb.sheet = .board(boardId) }
    func openMbAdd(shot: String) { mb.sheet = .add(MbAddMode(shot: shot)) }
    func openMbNewFolder(genre: String) { mb.sheet = .newFolder(genre: genre) }
    func closeMbSheet() { mb.sheet = nil }

    /// «Добавить в…» / «Переместить…» из выбора в папке (веб `mbSelAdd`, `mbSelMove`).
    func openMbAddPicked(move: Bool) {
        guard let from = mb.folder, let ids = mb.pick?.ids, !ids.isEmpty else { return }
        mb.sheet = .add(MbAddMode(many: ids, move: move, from: from))
    }

    /// Обложка папки: лист есть, только когда в папке есть кадры (веб: долгий тап по обложке).
    func openMbCover() { if let id = mb.folder { mb.sheet = .cover(id) } }

    func openMbItem(shot: String) {
        guard let board = mb.folder else { return }
        mb.sheet = .item(shot: shot, board: board, overView: false)
    }

    // MARK: чтение

    func mbGenresOn() -> [String] { Moodboard.enabledGenres(snapshot.genres).map(\.rawValue) }

    /// Название подборки самой по себе (веб `boardTitle`): съёмка — клиент или тип, папка — имя или жанр.
    func mbBoardTitle(_ b: RefBoard) -> String {
        if b.kind == .shoot {
            guard let s = sessions.first(where: { $0.id == b.sid }) else { return lexicon.t("mb.sets") }
            let f = PlannerFacts(app: self, dark: true)
            let who = f.words.clientName(s)
            return who.isEmpty ? f.words.typeName(s) : who
        }
        return b.name ?? mbGenreName(b.genre)
    }

    /// Подпись под названием в меню: жанровая — «Жанровая подборка» или имя, съёмка — «Тип · дата · место».
    func mbBoardSub(_ b: RefBoard) -> String { mbFolderHead(b).sub }
    func mbBoardMenuTitle(_ b: RefBoard) -> String { mbFolderHead(b).title }

    /// «3 кадра · 2 только здесь» / «все только здесь» / «Пока пусто» (веб `openMbBoardSheet`).
    func mbBoardCardSub(_ b: RefBoard) -> String {
        let n = b.items.count
        guard n > 0 else { return lexicon.t("mb.empty") }
        let lone = mbLibrary().loneCount(b.id)
        let say = lone == 0 ? "" : (lone == n ? lexicon.t("mb.delAllLone") : lexicon.t("mb.delLone", ["n": "\(lone)"]))
        return lexicon.count("unit.frame", n) + (say.isEmpty ? "" : " · " + say)
    }

    /// Жанр, чьи слова подсказывает лист кадра.
    func mbSheetGenre(_ b: RefBoard) -> String? { mbFolderGenre(b) }

    /// Жанр строки «Добавить в подборку «жанр»» — только у подборки съёмки, и по нынешней записи, а не по
    /// жанру, записанному на подборке при создании: жанр съёмки могли поменять (ревью GPT к `7b1aac7`).
    func mbItemToGenreTarget(_ b: RefBoard) -> String? { b.kind == .shoot ? mbFolderGenre(b) : nil }

    /// «Смотреть фото» на листе кадра: просмотрщик по картинкам папки в порядке сетки.
    func mbOpenViewer(_ shot: String) {
        if let sc = mbFolderScene(mbLibrary()) { _ = openMbFrame(shot, shown: sc.shown) }
    }

    func mbAddRows(_ mode: MbAddMode, _ lib: RefLibrary) -> [MbSheets.AddRow] {
        MbSheets.addRows(lib, genresOn: mbGenresOn(), shot: mode.shot, excluding: mode.from,
                         shootTitle: { b in
                             guard sessions.contains(where: { $0.id == b.sid }) else { return nil }
                             return mbBoardTitle(b)
                         },
                         genreName: mbGenreName)
    }

    // MARK: меню подборки

    func mbSetSort(_ sort: Int, of id: String) {
        mbEdit { $0.setSort(sort, of: id, now: $1) }
        mb.sheet = nil
    }

    func mbRename(_ id: String, to name: String) {
        mbEdit { $0.rename(id, to: name, now: $1) }
        mb.sheet = nil
    }

    func mbSetCover(_ shot: String?, of id: String) {
        mbEdit { $0.setCover(shot, of: id, now: $1) }
        mb.sheet = nil
    }

    /// «Объединить с…» после подтверждения: стоим внутри исчезающей подборки — выходим из неё до слияния
    /// (веб `mbMergeBoards`).
    func mbConfirmMerge(from: String, into: String) {
        if mb.folder == from { closeFolderNoPrune() }
        mbMerge(from, into: into)
        mb.sheet = nil
    }

    /// «Удалить подборку» из карточки (веб `mbBoardDel`): из папки выходим до удаления.
    func mbConfirmDelete(_ id: String) {
        if mb.folder == id { closeFolderNoPrune() }
        mbDeleteBoard(id)
        mb.sheet = nil
    }

    private func closeFolderNoPrune() {
        mb.folder = nil
        mb.folderQuery = ""; mb.folderTag = nil; mb.folderSearchOpen = false
        mb.pick = nil; mb.pager = nil; mb.viewerIds = []
    }

    // MARK: «Новая подборка»

    /// Тап по жанру: выключенный включается; есть папки — спросить имя новой, нет — открыть пустую основную
    /// (веб `openMbNew`).
    func mbNewPick(_ genre: Genre) {
        if !enabledGenres.contains(genre) { toggleGenre(genre) }
        let g = genre.rawValue
        switch MbSheets.newAction(genre: g, in: mbLibrary()) {
        case .askFolderName: mb.sheet = .newFolder(genre: g)
        case .openEmpty:
            let id = mbEdit { lib, now in lib.ensureGenreBoard(g, id: UUID().uuidString.lowercased(), now: now) }
            mb.sheet = nil
            openMbFolder(boardId: id)
        }
    }

    /// Имя новой папки принято: папка записана и открыта; пустое имя — ничего (веб `mbNewFolder`).
    func mbCreateFolder(genre: String, name: String) {
        mb.sheet = nil
        guard let id = mbAddFolder(genre: genre, name: name) else { return }
        openMbFolder(boardId: id)
    }

    // MARK: «Добавить в…» / «Переместить…»

    /// Тап по строке листа. Пачка — кладёт (и снимает с исходной при переносе), лист закрывается, выбор
    /// кончается. Один кадр — ставит или снимает галочку; снять последнее место кадра — сперва вопрос.
    func mbAddTap(_ row: MbSheets.AddRow, mode: MbAddMode) {
        if let shot = mode.shot {
            let lib = mbLibrary()
            guard case .board(let id) = row.target, lib.board(id) != nil else {
                mbEdit { lib, now in
                    if case .newGenre(let g) = row.target {
                        let to = lib.ensureGenreBoard(g, id: UUID().uuidString.lowercased(), now: now)
                        lib.put(shot, into: to, now: now)
                    }
                }
                return
            }
            if lib.board(id)?.items.contains(shot) == true {
                if lib.isUsed(shot, except: id) { mbEdit { $0.remove([shot], from: id, now: $1) } }
                else { mb.sheet = .loneConfirm(shot: shot, board: id) }
            } else {
                mbPut(shot, into: id)
            }
            return
        }
        let from = mode.from
        mbEdit { lib, now in
            let to: String
            switch row.target {
            case .board(let id): to = id
            case .newGenre(let g): to = lib.ensureGenreBoard(g, id: UUID().uuidString.lowercased(), now: now)
            }
            lib.move(mode.many, from: from, to: to, remove: mode.move, now: now)
        }
        mb.sheet = nil
        mb.pick = nil
        if let from, mbLibrary().board(from) == nil { closeFolderNoPrune() }
    }

    /// «Убрать» последнее место кадра подтверждено: кадр уходит совсем (веб `askYes` `mb.loneTitle`).
    func mbConfirmLone(shot: String, board: String) {
        mbEdit { $0.remove([shot], from: board, now: $1) }
        mb.sheet = nil
    }

    // MARK: лист кадра

    func mbToggleTag(_ code: String, on shot: String) { mbEdit { $0.toggleTag(code, on: shot, now: $1) } }

    func mbAddTypedTag(_ word: String, to shot: String) {
        mbEdit { $0.addTag(word, to: shot, tagName: mbTagName, now: $1) }
    }

    /// «Добавить в подборку «жанр»» — только у кадра съёмки: кадр остаётся и в съёмке (веб `mbItemMove`).
    func mbItemToGenre(shot: String, genre: String) {
        mbEdit { lib, now in
            let to = lib.ensureGenreBoard(genre, id: UUID().uuidString.lowercased(), now: now)
            lib.put(shot, into: to, now: now)
        }
        mb.sheet = nil
    }

    /// «Убрать из мудборда» на листе кадра (веб `mbItemRemove`): просмотрщик закрывается, опустевшая
    /// подборка съёмки исчезает вместе с папкой.
    func mbItemRemove(shot: String, board: String) {
        mbEdit { $0.remove([shot], from: board, now: $1) }
        mb.sheet = nil
        mb.pager = nil; mb.viewerIds = []
        if mbLibrary().board(board) == nil { closeFolderNoPrune() }
    }
}
