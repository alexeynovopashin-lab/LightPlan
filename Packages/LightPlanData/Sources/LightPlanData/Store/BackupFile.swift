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
