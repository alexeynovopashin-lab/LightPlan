import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

// MARK: - Pinterest в мудборде (итерация 28м, шаг 3)
//
// Всё идёт через нашу читалку (`lightplanogreader`): с мобильного Pinterest напрямую недоступен.
// Картинки лежат только на телефоне (`attachments/`), в нашем облаке не хранятся. Без ключа в сборке
// `pinterest == nil`: ссылка остаётся плиткой, под кнопками стоит «Pinterest не подключён в этой сборке».

/// Доска Pinterest от вставки ссылки до итога. Лист «Добавить доску?» и строка в папке показывают одно и то же.
struct PinFlow: Equatable {
    enum Phase: Equatable {
        case loading
        case ask
        case running
        case ended
        case failed(PinterestFailure)
    }
    var phase: Phase = .loading
    var link: String
    /// Папка мудборда, куда идут пины, и раздел, что был выбран при вставке (веб: `tags: [раздел]`).
    var boardId: String
    var tag: String?
    var name = ""
    /// Сколько пинов на доске у Pinterest и взяла ли читалка не все (потолок 100).
    var pinCount = 0
    var truncated = false
    /// Все пины, что предстоит добавить (дубли папки уже отброшены) и сколько уже лежало.
    var all: [PinterestPin] = []
    var already = 0
    /// Сколько из `all` обработано (в папке, уже было, не удалось) — «12 из 80».
    var done = 0
    var added = 0
    var failed = 0
    var pending: [PinterestPin] = []
    var stopped = false
    var interrupted: PinterestFailure?
    /// Номер запуска закачки: поздний ответ старой закачки не трогает новую (ревью GPT к 19e394e).
    var run = UUID()

    /// Оценка веса: по одному замеренному пину 736 px ≈ 70 КБ (`docs/pinterest_reference.md` § 3.5).
    var megabytes: Double { Double(all.count) * 0.07 }
}

/// Строка под кнопками папки про один пин: чем кончилось и что можно повторить.
enum PinNote: Equatable {
    case failure(PinterestFailure, retryFrame: String?)
    /// Картинка по прямой ссылке (28н.1) не легла.
    case image(ImageLinkFailure, retryFrame: String?)
}

extension AppModel {

    // MARK: надписи

    /// Единственное место, где решается «Pinterest сейчас доступен?»: в сборке нет ключа, либо человек выбрал
    /// «Только напрямую» (28л.6) — читалка это наш сервер. Причина — без запроса.
    func pinterestUnavailable() -> PinterestFailure? {
        pinterest == nil ? .notConfigured : netMode == .directOnly ? .serverOff : nil
    }

    func pinText(_ f: PinterestFailure) -> String {
        switch f {
        case .notConfigured, .rejected: lexicon.t("pin.notConnected")
        case .serverOff: lexicon.t("pin.serverOff")
        case .offline: lexicon.t("pin.offline")
        case .timeout, .serverDown, .badAnswer: lexicon.t("pin.serverDown")
        case .busy: lexicon.t("pin.busy")
        case .boardNotFound: lexicon.t("pin.boardNotFound")
        case .notFound: lexicon.t("pin.noPicture")
        case .badLink: lexicon.t("pin.badLink")
        }
    }

    /// «≈ 5,6 МБ»: до десяти — с десятой, дальше целое.
    func pinMegabytes(_ mb: Double) -> String {
        let v = mb < 10 ? max(0.1, (mb * 10).rounded() / 10) : mb.rounded()
        return lexicon.t("pin.boardSize", ["mb": v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: lexicon.code)))])
    }

    // MARK: один пин

    /// Плитка-ссылка уже в папке; картинка догоняет: `?url=` (короткую `pin.it` читалка раскрывает сама).
    /// Не вышло — плитка остаётся, картинка не придумывается, под кнопками честная строка с «Повторить».
    func startPinPreview(frame: String, link: String) {
        guard let reader = pinterest else { mb.pinNote = .failure(.notConfigured, retryFrame: nil); return }
        if case .failure(_, let r)? = mb.pinNote, r == frame { mb.pinNote = nil }
        Task { [weak self] in
            do {
                let data = try await reader.preview(of: link)
                self?.attachPinPicture(data, to: frame)
            } catch is CancellationError {
            } catch {
                self?.mb.pinNote = .failure((error as? PinterestFailure) ?? .serverDown, retryFrame: frame)
            }
        }
    }

    private func attachPinPicture(_ data: Data, to frame: String) {
        guard let images = refImages, let size = RefImageStore.pixelSize(of: data) else {
            mb.pinNote = .failure(.badAnswer, retryFrame: frame); return
        }
        let im = UUID().uuidString.lowercased()
        guard images.save(data, as: im) else { mb.pinNote = .failure(.badAnswer, retryFrame: frame); return }
        // Кадр могли убрать, пока читалка ходила, или картинка уже догнала — тогда файл не нужен.
        let ok = mbEdit { lib, now in lib.attachImage(im: im, w: size.w, h: size.h, toFrame: frame, now: now) }
        if !ok { images.delete(im) }
        else if case .failure(_, let r)? = mb.pinNote, r == frame { mb.pinNote = nil }
    }

    /// «Повторить» под строкой про один пин.
    func retryPinNote() {
        guard case .failure(let f, let frame)? = mb.pinNote else { return }
        guard let frame, let url = mbLibrary().shot(frame)?.url else { mb.pinNote = nil; return }
        _ = f
        startPinPreview(frame: frame, link: PinterestLink.secure(url) ?? url)
    }

    func dismissPinNote() { mb.pinNote = nil }

    // MARK: доска

    func startPinBoard(link: String, board: String, tag: String?) {
        pinTask?.cancel()
        mb.pinNote = nil
        mb.pin = PinFlow(link: link, boardId: board, tag: tag)
        mb.sheet = .pinBoard
        loadPinBoard()
    }

    /// Читает список пинов; потом лист спрашивает «Добавить?». Короткая ссылка, что оказалась пином (читалка:
    /// `badLink`), становится обычным пином — плиткой с картинкой.
    func loadPinBoard() {
        guard var flow = mb.pin, let reader = pinterest else { return }
        flow.phase = .loading
        mb.pin = flow
        let link = flow.link, board = flow.boardId
        pinTask?.cancel()
        pinTask = Task { [weak self] in
            do {
                let b = try await reader.board(link: link)
                guard let self, !Task.isCancelled, var f = self.mb.pin, f.link == link else { return }
                let have = self.mbLibrary().pinKeys(in: board)
                let capped = Array(b.pins.prefix(Self.pinCeiling))
                f.name = b.name; f.pinCount = b.pinCount; f.truncated = b.truncated || b.pinCount > capped.count
                f.all = capped.filter { !have.contains($0.id) }
                f.already = capped.count - f.all.count
                f.pending = f.all
                f.phase = .ask
                self.mb.pin = f
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled, self.mb.pin?.link == link else { return }
                let failure = (error as? PinterestFailure) ?? .serverDown
                if failure == .badLink, case .short = PinterestLink.kind(link) {
                    // pin.it без доски за ним: это пин. Плитка с картинкой, как у обычного пина.
                    let tag = self.mb.pin?.tag
                    self.mb.pin = nil; self.mb.sheet = nil
                    let r = self.mbEdit { lib, now in lib.addLink(link, to: board, id: UUID().uuidString.lowercased(), tag: tag, now: now) }
                    if case .added(let frame) = r { self.startPinPreview(frame: frame, link: link) }
                    return
                }
                self.mb.pin?.phase = .failed(failure)
            }
        }
    }

    /// Потолок читалки; клиент не берёт больше, даже если ответ длиннее.
    static let pinCeiling = 100

    /// «Добавить»: очередь закачки; пины ложатся пачками по мере готовности.
    func confirmPinBoard() {
        guard var flow = mb.pin, flow.phase == .ask || flow.phase == .ended, let reader = pinterest, !flow.pending.isEmpty else { return }
        let toRun = flow.pending
        let base = flow.all.count - toRun.count
        let run = UUID()
        flow.phase = .running; flow.stopped = false; flow.interrupted = nil; flow.done = base; flow.run = run
        mb.pin = flow
        let board = flow.boardId, tag = flow.tag
        pinTask?.cancel()
        pinTask = Task { [weak self] in
            let result = await runPinImport(
                pins: toRun, reader: reader,
                progress: { processed, _ in if self?.mb.pin?.run == run { self?.mb.pin?.done = base + processed } },
                commit: { batch in self?.commitPins(batch, board: board, tag: tag) ?? batch.map { _ in .rejected } })
            guard let self else { return }
            if var f = self.mb.pin, f.run == run {
                f.phase = .ended
                f.added += result.added
                f.failed = result.failed
                f.pending = result.pending
                f.stopped = result.stopped
                f.interrupted = result.interrupted
                f.done = f.all.count - result.pending.count
                self.mb.pin = f
            }
            // Своя закачка снимает ручку; чужую (новая запущена поверх) не трогаем.
            if self.mb.pin?.run == run || self.mb.pin == nil { self.pinTask = nil }
            // Закачка шла в папку, которую уже закрыли: опустевшая безымянная подборка уходит, как при закрытии.
            if self.mb.folder != board { self.mbEdit { lib, _ in lib.prune(board) } }
        }
    }

    /// Пачка скачанных пинов: файлы ложатся под новыми именами, кадры — в папку одной правкой; что не легло — файл стирается.
    func commitPins(_ batch: [PinFetched], board: String, tag: String?) -> [PinCommit] {
        guard let images = refImages else { return batch.map { _ in .rejected } }
        struct Slot { let index: Int; let im: String; let size: (w: Double, h: Double); let pin: PinterestPin }
        var out = [PinCommit](repeating: .rejected, count: batch.count)
        var slots: [Slot] = []
        for (i, f) in batch.enumerated() {
            guard let size = RefImageStore.pixelSize(of: f.data) else { continue }
            let im = UUID().uuidString.lowercased()
            guard images.save(f.data, as: im) else { continue }
            slots.append(Slot(index: i, im: im, size: size, pin: f.pin))
        }
        let adds: [PinAdd] = mbEdit { lib, now in
            slots.map { lib.addPin(permalink: $0.pin.permalink, im: $0.im, w: $0.size.w, h: $0.size.h, to: board, tag: tag, now: now) }
        }
        for (slot, add) in zip(slots, adds) {
            switch add {
            case .added: out[slot.index] = .added
            case .duplicate: out[slot.index] = .duplicate; images.delete(slot.im)
            case .invalid: images.delete(slot.im)
            }
        }
        return out
    }

    /// «Остановить»: что скачано — остаётся, остальное нет.
    func stopPinImport() { pinTask?.cancel() }

    func pinImportRunning(into board: String) -> Bool {
        guard let f = mb.pin else { return false }
        return f.boardId == board && f.phase == .running
    }

    /// Лист закрыли свайпом: пока ничего не качалось (читаем / спрашиваем / ошибка / итог) — доски больше нет;
    /// пока качается — идёт дальше, прогресс виден строкой в папке.
    func pinSheetClosed() {
        guard let f = mb.pin else { return }
        if f.phase != .running { pinTask?.cancel(); pinTask = nil; mb.pin = nil }
    }

    /// Закрывают папку: читаемое и неподтверждённое отпадает, качающееся идёт дальше.
    func pinFolderClosing(_ board: String) {
        guard let f = mb.pin, f.boardId == board else { return }
        if f.phase == .running { return }
        pinTask?.cancel(); pinTask = nil; mb.pin = nil
        if mb.sheet == .pinBoard { mb.sheet = nil }
    }

    func closePinFlow() {
        if mb.pin?.phase == .running { return }
        pinTask?.cancel(); pinTask = nil; mb.pin = nil
        if mb.sheet == .pinBoard { mb.sheet = nil }
    }
}
