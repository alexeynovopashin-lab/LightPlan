import Foundation
import LightPlanCore

// MARK: - Корзина мудборда съёмки (итерация 29б)

/// Слова Алексея (07.10, 11.10): корзина — плитка внутри мудборда, привязанного к съёмке; у обычных подборок
/// жанра её нет. Убранный кадр — снятая ссылка: он ложится в `bin` этой подборки, а в общем фонде остаётся
/// там, где лежал ещё. Кадр, которого больше нигде нет, после срока самоочистки уходит насовсем, в фонд не
/// переносится («у пользователя есть механизм сохранения, он сам решит»).
///
/// Часы — снаружи: каждый метод берёт `now` (мс) и, где нужно, «съёмка закончилась»; `Date()` здесь нет.
extension RefLibrary {

    /// Сутки в миллисекундах — срок режима «через 7 дней» берёт семь таких.
    public static let binDayMs: Double = 86_400_000
    public static let binWeekMs: Double = 7 * binDayMs

    // MARK: Запросы

    /// Кадры фонда без тех, что лежат только в корзине: поиск и счёт слов галереи их не видят.
    public var liveShots: [RefFrame] {
        let binned = Set(boards.flatMap { $0.bin.map(\.id) })
        if binned.isEmpty { return shots }
        let linked = Set(boards.flatMap(\.items))
        // Подборка неизвестного рода тоже держит кадр на виду: её ссылку читать не умеем, но рвать нельзя.
        return shots.filter { !binned.contains($0.id) || linked.contains($0.id) || isUsedByForeign($0.id) }
    }

    /// Записи корзины подборки, новые убранные первыми.
    public func binned(_ boardId: String) -> [RefBinned] {
        (board(boardId)?.bin ?? []).sorted { $0.at > $1.at }
    }

    /// Сколько осталось кадру в корзине.
    public enum BinLeft: Equatable, Sendable {
        /// Уйдёт через столько мс (режим «через 7 дней»).
        case ms(Double)
        /// Уйдёт, когда кончится съёмка.
        case atShootEnd
        /// Лежит, пока человек не очистит сам («Не удалять», а при «Удалять сразу» — кадры прежних режимов).
        case kept
    }

    public func binLeft(_ e: RefBinned, in b: RefBoard, now: Double) -> BinLeft {
        switch b.effectiveBinMode {
        case .now, .never: return .kept
        case .week: return .ms(max(0, e.at + Self.binWeekMs - now))
        case .shoot: return .atShootEnd
        }
    }

    /// Пора ли записи уходить. «Удалять сразу» и «Не удалять» сами не стирают: у первого записи не копятся
    /// (убранное уходит при снятии), а оставшееся от прежнего режима ждёт руки человека — смена настройки
    /// ничего не стирает. Граница недели — ровно семь суток: через 7 суток минус миллисекунда ещё лежит.
    func binExpired(_ e: RefBinned, in b: RefBoard, now: Double, shootEnded: Bool) -> Bool {
        switch b.effectiveBinMode {
        case .now, .never: return false
        case .week: return now - e.at >= Self.binWeekMs
        case .shoot: return shootEnded
        }
    }

    // MARK: Убрать из подборки

    /// Убрать кадры из подборки (веб «Убрать из мудборда», «Убрать N»). У подборки съёмки с режимом, кроме
    /// «Удалять сразу», кадр ложится в её корзину; иначе — как раньше: ссылка снята, кадр, что нигде не лежит,
    /// уходит насовсем. Ответ — кадры, ушедшие из фонда насовсем (при корзине — только те, чей срок уже вышел:
    /// «после окончания съёмки» после конца съёмки).
    @discardableResult
    public mutating func discard(_ shotIds: [String], from boardId: String, now: Double,
                                 shootEnded: Bool = false) -> [String] {
        guard let b = board(boardId) else { return [] }
        guard b.kind == .shoot, b.effectiveBinMode != .now else {
            return remove(shotIds, from: boardId, now: now)
        }
        for id in shotIds {
            guard let i = boards.firstIndex(where: { $0.id == boardId }),
                  let at = boards[i].items.firstIndex(of: id) else { continue }
            boards[i].items.remove(at: at)
            boards[i].mt = now
            guard shot(id) != nil else { continue }          // ссылка висела в пустоту — класть в корзину нечего
            boards[i].bin.removeAll { $0.id == id }
            boards[i].bin.append(RefBinned(id: id, at: now, pos: at))
        }
        let gone = sweepBin(of: boardId, now: now, shootEnded: shootEnded)
        prune(boardId)
        return gone
    }

    // MARK: Вернуть

    /// «Вернуть»: кадр встаёт на прежнее место в эту же подборку. Подборки нет или кадра больше нет в фонде —
    /// запись остаётся как была (кадра нет — её убирают: возвращать нечего). Ответ — вернувшиеся.
    @discardableResult
    public mutating func restore(_ shotIds: [String], into boardId: String, now: Double? = nil) -> [String] {
        guard let i = boards.firstIndex(where: { $0.id == boardId }) else { return [] }
        var back: [String] = []
        for id in shotIds {
            guard let e = boards[i].bin.first(where: { $0.id == id }) else { continue }
            guard shot(id) != nil else { boards[i].bin.removeAll { $0.id == id }; continue }
            let at = min(e.pos ?? boards[i].items.count, boards[i].items.count)
            if put(id, into: boardId, at: at, now: now) { back.append(id) }
        }
        return back
    }

    // MARK: Стереть

    /// «Очистить корзину» (или её часть): записи уходят, кадры, что нигде больше не лежат, — насовсем.
    /// Ответ — кадры, ушедшие из фонда. Какие записи — решает вызывающий в момент подтверждения: стирается
    /// запись, у которой совпали и кадр, и время «убрано». Кадр, что за время полёта вернули и убрали снова,
    /// — другая запись, её подтверждение не покрывало (ревью GPT к c4b4c07).
    @discardableResult
    public mutating func purgeBin(_ confirmed: [RefBinned], of boardId: String, now: Double? = nil) -> [String] {
        guard let i = boards.firstIndex(where: { $0.id == boardId }) else { return [] }
        let ask = Set(confirmed.map { Key(id: $0.id, at: $0.at) })
        let going = boards[i].bin.filter { ask.contains(Key(id: $0.id, at: $0.at)) }.map(\.id)
        guard !going.isEmpty else { return [] }
        boards[i].bin.removeAll { ask.contains(Key(id: $0.id, at: $0.at)) }
        if let now { boards[i].mt = now }
        var gone: [String] = []
        for id in going where !isUsed(id) && dropShot(id) { gone.append(id) }
        prune(boardId)
        return gone
    }

    private struct Key: Hashable { let id: String; let at: Double }

    // MARK: Самоочистка

    /// Режим самоочистки подборки съёмки. Подборки нет или она жанровая — `false`.
    @discardableResult
    public mutating func setBinMode(_ mode: RefBinMode, of boardId: String, now: Double? = nil) -> Bool {
        guard let i = boards.firstIndex(where: { $0.id == boardId }), boards[i].kind == .shoot else { return false }
        guard boards[i].binMode != mode else { return true }
        boards[i].binMode = mode
        if let now { boards[i].mt = now }
        return true
    }

    /// Очистка одной подборки: что истекло по её режиму — уходит; запись без кадра в фонде — тоже.
    /// Ответ — кадры, ушедшие из фонда насовсем.
    @discardableResult
    public mutating func sweepBin(of boardId: String, now: Double, shootEnded: Bool) -> [String] {
        guard let i = boards.firstIndex(where: { $0.id == boardId }), !boards[i].bin.isEmpty else { return [] }
        let b = boards[i]
        let stale = b.bin.filter { shot($0.id) == nil }.map(\.id)
        let due = b.bin.filter { binExpired($0, in: b, now: now, shootEnded: shootEnded) }.map(\.id)
        let out = Set(stale + due)
        guard !out.isEmpty else { return [] }
        boards[i].bin.removeAll { out.contains($0.id) }
        boards[i].mt = now
        var gone: [String] = []
        for id in due where !isUsed(id) && dropShot(id) { gone.append(id) }
        return gone
    }

    /// Очистка всех подборок съёмок: запуск, возврат на экран, открытие мудборда. `shootEnded` отвечает по подборке.
    @discardableResult
    public mutating func sweepBins(now: Double, shootEnded: (RefBoard) -> Bool) -> [String] {
        var gone: [String] = []
        for b in boards where b.kind == .shoot && !b.bin.isEmpty {
            gone += sweepBin(of: b.id, now: now, shootEnded: b.effectiveBinMode == .shoot && shootEnded(b))
            prune(b.id)
        }
        return gone
    }
}
