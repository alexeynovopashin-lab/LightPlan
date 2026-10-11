import Foundation
import LightPlanCore
import LightPlanDomain

// MARK: - Корзина мудборда съёмки (итерация 29б)

/// Слова Алексея (07.10, 11.10): корзина — плитка внутри мудборда, привязанного к съёмке; у обычных подборок
/// жанра её нет. Логика хранения и очистки — чистая, в `RefBin.swift` домена; здесь часы приложения, запись
/// в снимок, журнал `-LPBinStoreLog` и входы экранов.
extension AppModel {

    // MARK: часы съёмки

    /// Съёмка подборки уже кончилась: по часам места, дата + конец записи (или отметка «завершена»).
    /// Ручное завершение не ждём — слово Алексея «после окончания съёмки» про время, не про кнопку.
    func mbShootEnded(_ b: RefBoard) -> Bool {
        guard b.kind == .shoot, let s = sessions.first(where: { $0.id == b.sid }) else { return false }
        return EventPhase.of(s, now: wallNow(at: s), manualEnd: false) == .after
    }

    func mbBoardShootEnded(_ boardId: String) -> Bool { mbLibrary().board(boardId).map(mbShootEnded) ?? false }

    // MARK: убрать, вернуть, стереть

    /// Убрать кадры из подборки. У мудборда съёмки — в его корзину (режим «Удалять сразу» — насовсем, как до
    /// корзины); у обычной подборки жанра — как прежде. Ответ — кадры, ушедшие из фонда насовсем.
    @discardableResult
    func mbDiscard(_ ids: [String], from board: String) -> [String] {
        let ended = mbBoardShootEnded(board)
        let before = mbLibrary()
        let gone = mbEdit { lib, now in lib.discard(ids, from: board, now: now, shootEnded: ended) }
        BinStoreLog.note("discard", board: board, before: before, after: mbLibrary(), at: now())
        return gone
    }

    /// «Вернуть»: кадры встают на прежние места в этот же мудборд.
    func mbBinRestore(_ ids: [String], into board: String) {
        let before = mbLibrary()
        mbEdit { lib, now in lib.restore(ids, into: board, now: now) }
        BinStoreLog.note("restore", board: board, before: before, after: mbLibrary(), at: now())
    }

    /// «Очистить корзину» после подтверждения: уходят ровно те записи, о которых спросили (за время полёта в
    /// корзину могло что-то добавиться или вернуться и уйти снова — это не трогаем).
    func mbBinPurge(_ asked: [RefBinned], of board: String) {
        let before = mbLibrary()
        mbEdit { lib, now in lib.purgeBin(asked, of: board, now: now) }
        BinStoreLog.note("purge", board: board, before: before, after: mbLibrary(), at: now())
    }

    func mbSetBinMode(_ mode: RefBinMode, of board: String) {
        mbEdit { lib, now in lib.setBinMode(mode, of: board, now: now) }
        mb.sheet = .bin(board)
    }

    // MARK: самоочистка

    /// Очистить корзины, чей срок вышел: вызывается при запуске, при возврате на экран и при открытии мудборда
    /// или корзины. Ничего не истекло — снимок не пишется.
    func sweepMbBins() {
        let lib = mbLibrary()
        guard lib.boards.contains(where: { $0.kind == .shoot && !$0.bin.isEmpty }) else { return }
        var probe = lib
        let at = Double(nowMs)
        probe.sweepBins(now: at) { mbShootEnded($0) }
        guard probe != lib else { return }
        mbEdit { l, now in l.sweepBins(now: now) { mbShootEnded($0) } }
        BinStoreLog.note("sweep", board: "*", before: lib, after: mbLibrary(), at: now())
    }

    // MARK: входы экранов

    func openMbBin(_ boardId: String) {
        sweepMbBins()
        mb.sheet = .bin(boardId)
    }

    /// Подпись режима («Через 7 дней»).
    func mbBinModeTitle(_ m: RefBinMode) -> String {
        switch m {
        case .now: lexicon.t("mb.binModeNow")
        case .week: lexicon.t("mb.binModeWeek")
        case .shoot: lexicon.t("mb.binModeShoot")
        case .never: lexicon.t("mb.binModeNever")
        }
    }

    /// «Уйдёт через 3 дня» / «после окончания съёмки» / «лежит, пока вы не очистите».
    func mbBinLeftText(_ left: RefLibrary.BinLeft) -> String {
        switch left {
        case .kept: return lexicon.t("mb.binLeftKeep")
        case .atShootEnd: return lexicon.t("mb.binLeftShoot")
        case .ms(let ms):
            let days = Int((ms / RefLibrary.binDayMs).rounded(.up))
            if days >= 1 { return lexicon.t("mb.binLeft", ["n": lexicon.count("unit.day", days)]) }
            let hours = max(1, Int((ms / 3_600_000).rounded(.up)))
            return lexicon.t("mb.binLeft", ["n": lexicon.count("unit.hour", hours)])
        }
    }

    /// Что сказать в вопросе «Убрать из подборки?»: у мудборда съёмки с корзиной — куда уйдёт убранное и когда
    /// пропадёт; у жанровой подборки и при «Удалять сразу» — прежнее слово беты (`fallback`).
    func mbBinGoText(board: String?, fallback: String) -> String {
        guard let board, let b = mbLibrary().board(board), b.kind == .shoot else { return fallback }
        switch b.effectiveBinMode {
        case .now: return fallback
        case .week: return lexicon.t("mb.binGoWeek")
        case .shoot: return lexicon.t("mb.binGoShoot")
        case .never: return lexicon.t("mb.binGoNever")
        }
    }
}

/// Журнал корзины мудборда (Debug, `-LPBinStoreLog <файл>`; имя без «/» — файл в `Documents`): строка на событие —
/// что произошло, подборка, сколько в корзине и в фонде до и после, часы приложения. Для замеров на симуляторе
/// (29б): убрал кадр — +1, вернул — −1, часы сдвинуты на 7 суток — очистка.
enum BinStoreLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPBinStoreLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    /// Те же строки для тестов.
    @MainActor private(set) static var journal: [String] = []
    @MainActor static func reset() { journal.removeAll() }
    #endif

    @MainActor static func note(_ event: String, board: String, before: RefLibrary, after: RefLibrary, at: Date) {
        #if DEBUG
        func bins(_ l: RefLibrary) -> Int { l.boards.reduce(0) { $0 + $1.bin.count } }
        let line = "\(event) board=\(board) bin=\(bins(before))→\(bins(after)) fund=\(before.shots.count)→\(after.shots.count)"
            + " now=\(Int64((at.timeIntervalSince1970 * 1000).rounded(.down)))"
        journal.append(line)
        guard let url, let data = (line + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}
