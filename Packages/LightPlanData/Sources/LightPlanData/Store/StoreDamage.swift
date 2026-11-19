import Foundation

/// Что `Store.load` нашёл не так с файлом данных (31.11). Файла нет — это не порча (первый запуск): `damage == nil`.
///
/// До 31.11 любой сбой чтения превращался на старте в пустой снимок, и первая же запись старта клала его поверх
/// файла без копии — пропадали все съёмки, клиенты, мудборды (DECISIONS 05.11, «Замечено, не правилось»).
public struct StoreDamage: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Файл не разобрался совсем: не JSON, оборван, нет ключа `sessions`, раздел не массивом. Приложение
        /// стартует пустым; исходные байты — в `copy`.
        case damaged
        /// Разобралась большая часть: `dropped` записей и полей выпало, остальное прочитано. Исходник — в `copy`.
        case salvaged(dropped: Int)
        /// Байты файла не прочитались вовсе (нет доступа, ошибка диска): копии сделать нечем, запись держится.
        case unreadable
    }

    public let kind: Kind
    /// Копия исходных байтов рядом с файлом (`light-plan.broken-ГГГГ-ММ-ДД-ЧЧммсс.json`); `nil` — копию сделать не
    /// вышло, и тогда `Store` до конца запуска ничего не пишет поверх файла.
    public let copy: URL?

    public init(kind: Kind, copy: URL?) {
        self.kind = kind
        self.copy = copy
    }

    /// Файл на месте не тронут, и `Store` его не тронет: ни копии, ни права писать.
    public var writesHeld: Bool { copy == nil }
}
