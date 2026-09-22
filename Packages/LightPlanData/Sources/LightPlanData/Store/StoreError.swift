import Foundation

/// Ошибки `Store` (итерация 12). Ни одна не должна ронять приложение:
/// вызывающий показывает пустое состояние и строку из `LocalizedError`.
public enum StoreError: Error, Sendable {
    /// Файл прочитан, но не разобрался как JSON, или в разобранном нет
    /// ключа `sessions` — значит это не снимок Light Plan (веб
    /// `restoreBackup`, «`errNotBackup`»).
    case corrupted(underlying: String)
    /// Файл читаемый, но пустой/усечённый настолько, что JSON не закрылся.
    case truncated
    /// Атомарная запись не удалась (диск полон, нет прав).
    case writeFailed(underlying: String)
}

extension StoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .corrupted: "Файл повреждён или это не копия Light Plan"
        case .truncated: "Файл оборван — скопирован не до конца"
        case .writeFailed: "Не удалось записать на диск"
        }
    }
}
