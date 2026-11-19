import Foundation
import LightPlanCore

/// Файл-копия, каким его пишет и понимает веб (`backupPayload`, `docs/17` § 6:
/// «файл экспорта веб уже пишет в расчёте на Swift»): `{app, format: 1,
/// exported, data}`. Экспорт натива пишет то же самое.
struct BackupFile: Codable {
    var app: String
    var format: Int
    var exported: String
    var data: Snapshot

    init(snapshot: Snapshot, exportedAt: Date = Date()) {
        app = "Light Plan"
        format = 1
        exported = SnapshotDate.format(exportedAt)
        data = snapshot
    }
}

/// Разбор файла, отданного человеком: конверт `{data: {...}}` или «голый»
/// дамп самого снимка — веб `restoreBackup` терпит оба, и это тоже часть
/// «формата, который читает натив». Ключ `sessions` отличает снимок от
/// произвольного JSON (веб: `if (!data || ... || !("sessions" in data))`).
///
/// Форму (конверт/голый дамп) отличаем через `JSONSerialization` — только
/// затем, что там есть ключ `sessions`, значения не берём оттуда. Сам снимок
/// декодируется прямо из `raw` через `Snapshot.init(from:)`: узнать форму
/// и потом заново кодировать её в `Data` нельзя было бы без потери денег —
/// `JSONValue.number` держит `Double`, и `Decimal` точнее двоичной дроби
/// не пережил бы такой крюк (замерено, `StoreTests.decimalRoundTrips…`).
enum ImportedFile {
    private struct Envelope: Decodable { let data: Snapshot }

    /// Щадящее чтение своего файла (31.11), когда строгое `decode` уже упало: та же форма (конверт или голый дамп,
    /// ключ `sessions` обязателен), но неразобранные записи выпадают поштучно. Годится, только если ни один раздел
    /// не пропал целиком — иначе `nil`: снимок без всех съёмок нельзя выдавать за «часть не прочиталась».
    /// Ответ — снимок и сколько записей и полей выпало.
    static func salvage(_ raw: Data) -> (snapshot: Snapshot, dropped: Int)? {
        guard !raw.isEmpty,
              let top = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { return nil }
        let log = SnapshotSalvage()
        let decoder = JSONDecoder()
        decoder.userInfo[SnapshotSalvage.key] = log
        let snapshot: Snapshot?
        if let data = top["data"] as? [String: Any], data["sessions"] != nil {
            snapshot = try? decoder.decode(Envelope.self, from: raw).data
        } else if top["sessions"] != nil {
            snapshot = try? decoder.decode(Snapshot.self, from: raw)
        } else {
            snapshot = nil
        }
        guard let snapshot, log.lostSections.isEmpty else { return nil }
        return (snapshot, log.dropped + log.fields)
    }

    static func decode(_ raw: Data) throws -> Snapshot {
        guard !raw.isEmpty else { throw StoreError.truncated }

        let top: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                throw StoreError.corrupted(underlying: "верхний уровень не объект")
            }
            top = obj
        } catch let e as StoreError {
            throw e
        } catch {
            throw StoreError.corrupted(underlying: String(describing: error))
        }

        do {
            if let data = top["data"] as? [String: Any], data["sessions"] != nil {
                return try JSONDecoder().decode(Envelope.self, from: raw).data
            }
            guard top["sessions"] != nil else {
                throw StoreError.corrupted(underlying: "нет ключа sessions — это не копия Light Plan")
            }
            return try JSONDecoder().decode(Snapshot.self, from: raw)
        } catch let e as StoreError {
            throw e
        } catch {
            throw StoreError.corrupted(underlying: String(describing: error))
        }
    }
}
