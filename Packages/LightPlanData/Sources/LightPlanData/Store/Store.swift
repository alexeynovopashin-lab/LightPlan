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

    private let previousURL: URL
    private let now: @Sendable () -> Date

    private var pendingWrite: Task<Void, Never>?
    private var lastKnownGood: Snapshot?
    /// Файл на диске в этом запуске прочитался строго — его прежний вид можно держать как последний хороший.
    private var openedClean = false
    /// Последний хороший вид уже отложен в этом запуске (один раз за запуск).
    private var previousKept = false

    /// Что не так с файлом данных, по последнему `load` (31.11); `nil` — прочитан или его ещё нет.
    public private(set) var damage: StoreDamage?

    /// Сколько копий повреждённого файла держим рядом с ним (31.11): новая вытесняет самую старую.
    public static let brokenKept = 3

    /// Папка вложений: файлы под теми же именами, что у блобов IndexedDB
    /// веба (`docs/17` § 6). Итерация 12 только заводит её — сами вложения
    /// переносит более поздняя итерация.
    public var attachmentsDirectory: URL { attachmentsURL }

    /// `directory` — папка приложения (документы или контейнер группы);
    /// файлы снимка, вложений и резервных копий устройства кладутся внутри.
    public init(directory: URL, fileName: String = "light-plan.json", debounce: Duration = .milliseconds(400),
                now: @escaping @Sendable () -> Date = { Date() }) {
        fileURL = directory.appendingPathComponent(fileName)
        previousURL = directory.appendingPathComponent(Self.stem(fileName) + ".prev.json")
        self.now = now
        attachmentsURL = directory.appendingPathComponent("attachments", isDirectory: true)
        backupsURL = directory.appendingPathComponent("backups", isDirectory: true)
        self.debounce = debounce
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
    }

    /// Снимок с диска. Файла ещё нет (первый запуск) — пустой снимок, без
    /// ошибки и без `damage`. Файл есть, но не разобрался — бросает `StoreError`: решает
    /// вызывающий, а не `Store` (пустой экран, строка, что показать).
    ///
    /// 31.11: прежде чем бросить, исходные байты ложатся копией рядом (`keepBroken`), и `damage` говорит, что
    /// случилось. Строгое чтение упало, но щадящее собрало снимок без потери целых разделов — он и возвращается
    /// (`damage.kind == .salvaged`): лучше съёмки без одной битой, чем пустое приложение. Байты не прочитались
    /// вовсе — копии нет, и запись поверх держится до конца запуска (`StoreDamage.writesHeld`).
    public func load() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            damage = nil
            return Snapshot()
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            damage = StoreDamage(kind: .unreadable, copy: nil)
            openedClean = false
            throw error
        }
        do {
            let snapshot = try ImportedFile.decode(data)
            lastKnownGood = snapshot
            damage = nil
            openedClean = true
            return snapshot
        } catch {
            openedClean = false
            let copy = keepBroken(data)
            if let part = ImportedFile.salvage(data) {
                damage = StoreDamage(kind: .salvaged(dropped: part.dropped), copy: copy)
                return part.snapshot
            }
            damage = StoreDamage(kind: .damaged, copy: copy)
            throw error
        }
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
        // Файл не прочитался и копии нет (31.11): поверх не пишем — лучше потерять правку этого запуска, чем файл.
        if damage?.writesHeld == true {
            throw StoreError.writeFailed(underlying: "файл данных не прочитан и не скопирован — поверх не пишем")
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            throw StoreError.writeFailed(underlying: String(describing: error))
        }
        keepPreviousOnce()
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
        try importArchive(data: Data(contentsOf: url))
    }

    /// То же из байтов — копия, забранная из облака (31.1): свой снимок сначала уходит в `backups/`.
    public func importArchive(data raw: Data) throws -> Snapshot {
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

    // MARK: - Копии (31.11)

    /// Последний хороший вид файла — `light-plan.prev.json` рядом с ним: перед первой записью запуска, если файл в этом
    /// запуске прочитался строго. Один файл, раз за запуск: жёсткая ссылка на прежний файл (атомарная запись кладёт
    /// новый файл на его место, старые байты остаются под вторым именем) — без копирования байтов; не вышла ссылка —
    /// копия. Сбой тут запись не останавливает: это страховка сверху, файл данных пишется атомарно и без неё.
    private func keepPreviousOnce() {
        guard openedClean, !previousKept else { return }
        previousKept = true
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        try? fm.removeItem(at: previousURL)
        do {
            try fm.linkItem(at: fileURL, to: previousURL)
        } catch {
            try? fm.copyItem(at: fileURL, to: previousURL)
        }
    }

    /// Исходные байты повреждённого файла — рядом с ним, `light-plan.broken-ГГГГ-ММ-ДД-ЧЧммсс.json`, никогда не
    /// перезаписываются. Такие же байты уже лежат копией (тот же файл при следующем запуске) — новой не будет.
    /// Держим `brokenKept` последних. `nil` — копию положить не вышло.
    private func keepBroken(_ data: Data) -> URL? {
        let fm = FileManager.default
        let existing = brokenCopies()
        if let same = existing.first(where: { (try? Data(contentsOf: $0)) == data }) { return same }
        let dir = fileURL.deletingLastPathComponent()
        let base = Self.stem(fileURL.lastPathComponent) + ".broken-" + Self.stamp(now())
        var url = dir.appendingPathComponent(base + ".json")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(base + "-\(n).json")
            n += 1
        }
        do {
            try data.write(to: url, options: [.withoutOverwriting])
        } catch {
            return nil
        }
        for old in brokenCopies().filter({ $0 != url }).dropLast(Self.brokenKept - 1) {
            try? fm.removeItem(at: old)
        }
        return url
    }

    /// Копии повреждённого файла, старые первыми (по времени создания, потом по имени).
    func brokenCopies() -> [URL] {
        let dir = fileURL.deletingLastPathComponent()
        let prefix = Self.stem(fileURL.lastPathComponent) + ".broken-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let urls = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }.map { dir.appendingPathComponent($0) }
        func born(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
        return urls.sorted { (born($0), $0.lastPathComponent) < (born($1), $1.lastPathComponent) }
    }

    private static func stem(_ fileName: String) -> String { (fileName as NSString).deletingPathExtension }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: date)
    }

    /// Файл «Поделиться копией» — тот же конверт, что пишет веб.
    public func exportArchive() throws -> Data {
        try Self.archive(load())
    }

    /// Конверт копии из готового снимка (облако, 31.1: снимок в памяти правдивее файла под отложенной записью).
    public static func archive(_ snapshot: Snapshot, exportedAt: Date = Date()) throws -> Data {
        try JSONEncoder().encode(BackupFile(snapshot: snapshot, exportedAt: exportedAt))
    }
}
