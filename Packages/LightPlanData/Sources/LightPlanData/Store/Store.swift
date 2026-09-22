import Foundation
import LightPlanCore

/// Единственная точка записи на диск (`docs/17` § 4). Снимок — файл, папка
/// вложений — рядом, как решено в § 4.4 плана и § 6 архитектуры: пишем
/// атомарно, читаем терпимо к порче, импорт не трогает исходный файл.
///
/// Актор — не ради параллельной записи (её и не бывает: сохранение зовёт UI
/// одной цепочкой), а чтобы дебаунс и атомарная запись жили в одном месте
/// и не гонялись с чтением того же файла.
public actor Store {
    private let fileURL: URL
    private let attachmentsURL: URL
    private let backupsURL: URL
    private let debounce: Duration

    private var pendingWrite: Task<Void, Never>?
    private var lastKnownGood: Snapshot?

    /// Папка вложений: файлы под теми же именами, что у блобов IndexedDB
    /// веба (`docs/17` § 6). Итерация 12 только заводит её — сами вложения
    /// переносит более поздняя итерация.
    public var attachmentsDirectory: URL { attachmentsURL }

    /// `directory` — папка приложения (документы или контейнер группы);
    /// файлы снимка, вложений и резервных копий устройства кладутся внутри.
    public init(directory: URL, fileName: String = "light-plan.json", debounce: Duration = .milliseconds(400)) {
        fileURL = directory.appendingPathComponent(fileName)
        attachmentsURL = directory.appendingPathComponent("attachments", isDirectory: true)
        backupsURL = directory.appendingPathComponent("backups", isDirectory: true)
        self.debounce = debounce
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
    }

    /// Снимок с диска. Файла ещё нет (первый запуск) — пустой снимок, без
    /// ошибки. Файл есть, но не разобрался — бросает `StoreError`: решает
    /// вызывающий, а не `Store` (пустой экран, строка, что показать).
    public func load() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Snapshot() }
        let data = try Data(contentsOf: fileURL)
        let snapshot = try ImportedFile.decode(data)
        lastKnownGood = snapshot
        return snapshot
    }

    /// Немедленная запись — ждёт своего завершения (для теста и для мест,
    /// где дальше сразу читают файл, например перед `exportArchive`).
    public func saveNow(_ snapshot: Snapshot) throws {
        pendingWrite?.cancel()
        pendingWrite = nil
        try write(snapshot)
    }

    /// Отложенная запись (веб `saveAll` зовётся на каждую правку, диск — нет):
    /// новый вызов отменяет прежний невыполненный и переносит время вперёд —
    /// пишется только последний снимок, дебаунс, не троттлинг.
    public func save(_ snapshot: Snapshot) {
        pendingWrite?.cancel()
        pendingWrite = Task { [debounce] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            try? self.write(snapshot)
        }
    }

    /// Дождаться отложенной записи (тестам и выходу из приложения).
    public func flush() async {
        await pendingWrite?.value
    }

    private func write(_ snapshot: Snapshot) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            throw StoreError.writeFailed(underlying: String(describing: error))
        }
        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw StoreError.writeFailed(underlying: String(describing: error))
        }
        lastKnownGood = snapshot
    }

    /// Импорт архива веба: только читает `url`, исходный файл не трогает.
    /// Перед перезаписью своего снимка кладёт его копию в `backups/` —
    /// риск потери живых данных лечится и так, и тем, что импорт вообще
    /// не пишет исходник (итерация 12, «Риски»).
    public func importArchive(from url: URL) throws -> Snapshot {
        let raw = try Data(contentsOf: url)
        let snapshot = try ImportedFile.decode(raw)
        try backupCurrentFileIfPresent()
        try saveNow(snapshot)
        return snapshot
    }

    private func backupCurrentFileIfPresent() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let name = "before-import-" + SnapshotDate.format(Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "-") + ".json"
        let dest = backupsURL.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: fileURL, to: dest)
        } catch {
            // Резервная копия — часть страховки импорта («Риски», итерация
            // 12): не вышла копия — не пишем и новый снимок, лучше отказ
            // импорта, чем свежие данные без подстраховки.
            throw StoreError.writeFailed(underlying: String(describing: error))
        }
    }

    /// Файл «Поделиться копией» — тот же конверт, что пишет веб.
    public func exportArchive() throws -> Data {
        let snapshot = try load()
        let backup = BackupFile(snapshot: snapshot)
        return try JSONEncoder().encode(backup)
    }
}
