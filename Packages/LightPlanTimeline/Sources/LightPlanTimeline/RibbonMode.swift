/// Чем показаны сутки под ползунком (веб `ribbonMode`, DECISIONS «Барабан:
/// знак в ячейке, барабан и лента на одном треке»).
public enum RibbonMode: String, Sendable, Equatable, CaseIterable {
    /// Полоса: трое суток шириной в экран, время течёт непрерывно.
    case lane
    /// Ячейки по 50 pt, время суток не трогает вовсе. По умолчанию в вебе.
    case drum
}
