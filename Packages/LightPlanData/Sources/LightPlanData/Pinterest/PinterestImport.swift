import Foundation

/// Что скачано и ждёт записи в подборку.
public struct PinFetched: Sendable {
    public let pin: PinterestPin
    public let data: Data
}

/// Что сделала запись с одним скачанным пином.
public enum PinCommit: Sendable, Equatable {
    case added
    case duplicate
    /// Не записалось (картинка не разобралась, файл не лёг, подборки уже нет): пин остаётся «не добавлен».
    case rejected
}

public struct PinImportResult: Sendable, Equatable {
    public var added = 0
    public var duplicates = 0
    /// Пытались и не вышло (после одного повтора).
    public var failed = 0
    /// Человек нажал «Остановить»: то, что не начато, не считается сбоем.
    public var stopped = false
    /// Очередь остановлена сбоем всей связи (нет сети, ключ, просьба подождать) или подряд идущими сбоями.
    public var interrupted: PinterestFailure?
    /// Всё, что не добавлено и не дубль — для кнопки «Повторить».
    public var pending: [PinterestPin] = []
    public var total = 0
    public var done: Bool { !stopped && interrupted == nil && pending.isEmpty }
}

/// Закачка пинов доски очередью (итерация 28м, шаг 3): несколько запросов `?img=` одновременно, а не все сто сразу
/// (читалка держит 240 вызовов в минуту на адрес, `docs/pinterest_reference.md` § 3.4). Скачанное складывается пачками:
/// `commit` вызывается на каждые `batchSize` картинок и в конце; отмена `Task` не бросает скачанное — остаток пачки
/// тоже записывается, недокачанное не заводится. Уже принятое не дублируется при повторе: за дубли отвечает `commit`.
///
/// - `retryDelay` — пауза перед единственным повтором временного сбоя;
/// - `maxStreak` — столько сбоев подряд без единой удачи останавливают очередь (связь так тонка, что идти дальше незачем).
public func runPinImport(
    pins: [PinterestPin],
    reader: any PinterestReading,
    concurrency: Int = 5,
    batchSize: Int = 6,
    retryDelay: Duration = .milliseconds(600),
    maxStreak: Int = 6,
    progress: @MainActor @Sendable (_ processed: Int, _ total: Int) -> Void = { _, _ in },
    commit: @MainActor @Sendable ([PinFetched]) -> [PinCommit]
) async -> PinImportResult {
    var seen = Set<String>()
    let list = pins.filter { seen.insert($0.id).inserted }
    var result = PinImportResult()
    result.total = list.count
    var finished = Set<String>()   // записано или уже было
    var buffer: [PinFetched] = []
    var processed = 0
    var streak = 0
    var next = 0

    func flush() async {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer = []
        let out = await commit(batch)
        for (i, f) in batch.enumerated() {
            switch i < out.count ? out[i] : .rejected {
            case .added: result.added += 1; finished.insert(f.pin.id)
            case .duplicate: result.duplicates += 1; finished.insert(f.pin.id)
            case .rejected: result.failed += 1
            }
        }
    }

    @Sendable func fetch(_ pin: PinterestPin) async -> Result<Data, PinterestFailure> {
        var attempt = 0
        while true {
            do { return .success(try await reader.image(at: pin.image)) }
            catch is CancellationError { return .failure(.timeout) }   // отмена: сюда не засчитывается, см. ниже
            catch {
                let f = (error as? PinterestFailure) ?? .serverDown
                if attempt == 0, f.isTransient, !Task.isCancelled {
                    attempt += 1
                    try? await Task.sleep(for: retryDelay)
                    if Task.isCancelled { return .failure(f) }
                    continue
                }
                return .failure(f)
            }
        }
    }

    await withTaskGroup(of: (PinterestPin, Result<Data, PinterestFailure>).self) { group in
        func launch() -> Bool {
            guard next < list.count, !Task.isCancelled, result.interrupted == nil else { return false }
            let pin = list[next]; next += 1
            group.addTask { (pin, await fetch(pin)) }
            return true
        }
        for _ in 0..<max(1, concurrency) { if !launch() { break } }
        while let (pin, outcome) = await group.next() {
            if Task.isCancelled {
                // Остановили: что уже пришло — берём, остальное нет и сбоем не считается.
                if case .success(let data) = outcome { buffer.append(PinFetched(pin: pin, data: data)); processed += 1 }
                continue
            }
            processed += 1
            switch outcome {
            case .success(let data):
                streak = 0
                buffer.append(PinFetched(pin: pin, data: data))
                if buffer.count >= batchSize { await flush() }
            case .failure(let f):
                if f.isSystemic { if result.interrupted == nil { result.interrupted = f } }
                else {
                    result.failed += 1
                    if f.isTransient {
                        streak += 1
                        if streak >= maxStreak, result.interrupted == nil { result.interrupted = f }
                    }
                }
            }
            let shown = processed
            await progress(shown, list.count)
            _ = launch()
        }
    }
    result.stopped = Task.isCancelled
    await flush()
    await progress(processed, list.count)
    // «Не добавлено»: упавшие и те, до кого очередь не дошла (остановка, обрыв связи). Записанное и дубли — нет.
    result.pending = list.filter { !finished.contains($0.id) }
    return result
}
