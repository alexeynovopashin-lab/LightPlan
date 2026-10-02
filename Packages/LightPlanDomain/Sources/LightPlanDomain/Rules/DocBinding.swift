import Foundation
import LightPlanCore

/// Что предложить сверху в списках привязки быстрого «+» (итерация 28д, справка § 6.3): пять последних
/// съёмок — две ближайшие будущие и три последние прошедшие — и пять организаций по дню последней съёмки.
public enum DocBinding {
    public static let recentSessionsFuture = 2
    public static let recentSessionsPast = 3
    public static let recentOrgsLimit = 5

    private static func key(_ d: CivilDate) -> Int { d.year * 10_000 + d.month * 100 + d.day }

    /// Съёмки, к которым можно привязать бумагу: живые, не из корзины съёмок.
    public static func live(_ lib: DocLibrary) -> [Session] {
        lib.sessions.filter { lib.isLive(.session($0.id)) }
    }

    /// Две ближайшие будущие (сегодня — будущая), затем три последние прошедшие: порядок «ближайшие
    /// будущие по возрастанию, потом прошедшие от новых».
    public static func recentSessions(_ lib: DocLibrary, today: CivilDate) -> [Session] {
        let all = live(lib)
        let future = all.filter { key($0.day) >= key(today) }.sorted { key($0.day) < key($1.day) }
        let past = all.filter { key($0.day) < key(today) }.sorted { key($0.day) > key($1.day) }
        return Array(future.prefix(recentSessionsFuture)) + Array(past.prefix(recentSessionsPast))
    }

    /// Организации по дню последней съёмки, новые первыми; без съёмок — по алфавиту после.
    public static func recentOrgs(_ lib: DocLibrary, limit: Int = recentOrgsLimit) -> [Org] {
        let live = live(lib)
        func last(_ o: Org) -> Int? { live.filter { $0.orgId == o.id }.map { key($0.day) }.max() }
        let withDay = lib.orgs.compactMap { o in last(o).map { (o, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
        let without = lib.orgs.filter { last($0) == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return Array((withDay + without).prefix(limit))
    }
}
