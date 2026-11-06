import Foundation

/// Переключатель «Астро» (Алексей 31.10: «вкл и выкл луна/звезды/азимуты/термины/млечный путь»). Порядок — порядок строк в настройках.
public enum AstroSwitch: String, Sendable, CaseIterable {
    case moon, stars, azimuths, terms, milkyWay
}

/// Пять переключателей «Астро» (30г.4, `docs/30g2_modes_table.md` § 2, § 4). Хранится то, что выключено: нет записи — всё включено,
/// так первый вход в «Астро» и старые данные «Астро» дают все пять включёнными без особого случая.
public struct AstroSwitches: Sendable, Equatable {
    public private(set) var off: Set<AstroSwitch>

    public init(off: Set<AstroSwitch> = []) { self.off = off }

    public static let allOn = AstroSwitches()

    public subscript(_ s: AstroSwitch) -> Bool {
        get { !off.contains(s) }
        set { if newValue { off.remove(s) } else { off.insert(s) } }
    }

    /// Какие переключатели стоят. Как у режима (`AppMode.read`): свой ключ файла сильнее всего; веб при пересохранении
    /// его теряет — тогда решает память телефона; нет ни того, ни другого — все пять включены. Незнакомые имена пропускаются.
    public static func read(file: [String]?, remembered: AstroSwitches?) -> AstroSwitches {
        file.map { AstroSwitches(off: Set($0.compactMap(AstroSwitch.init(rawValue:)))) } ?? remembered ?? .allOn
    }

    /// Записать в снимок. Ключ пишется всегда, и пустым: так файл после записи читается без памяти телефона.
    public func write(to s: inout Snapshot) { s.astroOff = offNames }

    /// Выключенные по именам, в порядке строк настроек.
    public var offNames: [String] { AstroSwitch.allCases.filter { off.contains($0) }.map(\.rawValue) }
}
