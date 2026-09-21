import Foundation

/// Затмение из таблицы: день, вид и где идёт полоса.
///
/// `whereKey` — ключ словаря (`eclW.2026-08-12`): где проходит полоса, словами,
/// по-русски и по-английски; перевод берёт итерация 14. Локальной фазы («у вас
/// закроет 43 %») здесь нет и не будет: таблица её не даёт, а посчитать нечем.
public struct Eclipse: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case annular = "ecl.annular"
        case total = "ecl.total"
        case partial = "ecl.partial"
    }

    public let date: CivilDate
    public let kind: Kind
    public let whereKey: String
}

/// Затмения таблицей, а не расчётом.
///
/// Расчёт пробовали трижды и отвергли (DECISIONS): приближение Меёса ошибается
/// на полградуса, а весь вопрос затмения решается в пределах полуградуса.
/// 12 августа 2026 модель утверждала обратное тому, что было на небе. Поэтому
/// здесь данные — `Resources/eclipses.json`, каталог NASA до 2030 года,
/// продлевается одной строкой.
///
/// Таблица — то же, что `ECLIPSES` в вебе; расхождение ловит стенд паритета
/// (`Fixtures/eclipse.json`). Веб продлил таблицу — тест падает, строку
/// копируют сюда.
public enum EclipseTable {

    /// Вся таблица в порядке файла.
    public static let all: [Eclipse] = load()

    /// Затмение этого дня, если оно есть в таблице (`eclipseOn`).
    public static func on(_ day: CivilDate) -> Eclipse? {
        all.first { $0.date == day }
    }

    /// Ближайшее вперёд, включая сегодняшнее (`nextEclipse`). После конца
    /// таблицы — `nil`.
    public static func next(from day: CivilDate) -> Eclipse? {
        var best: Eclipse?
        for e in all where e.date >= day {
            if best == nil || e.date < best!.date { best = e }
        }
        return best
    }

    // MARK: - Загрузка

    private struct Row: Decodable {
        let d: String
        let kind: String
        let `where`: String
    }

    /// Ресурс — часть пакета: его отсутствие или порча — ошибка сборки, а не
    /// состояние, с которым можно жить, поэтому падаем громко, с именем файла.
    private static func load() -> [Eclipse] {
        guard let url = Bundle.module.url(forResource: "eclipses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Row].self, from: data)
        else { fatalError("LightPlanCore: нет или не читается Eclipse/Resources/eclipses.json") }
        return rows.map { row in
            let p = row.d.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3, let kind = Eclipse.Kind(rawValue: row.kind) else {
                fatalError("LightPlanCore: eclipses.json, строка «\(row.d)»: дата или вид не разобраны")
            }
            return Eclipse(date: CivilDate(year: p[0], month: p[1], day: p[2]), kind: kind, whereKey: row.where)
        }
    }
}
