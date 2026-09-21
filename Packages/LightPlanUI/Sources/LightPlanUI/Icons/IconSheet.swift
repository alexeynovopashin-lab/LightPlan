import SwiftUI

/// Контрольный лист: все знаки библиотеки разом, по наборам, с именами —
/// аналог `tools/icons.html` веба. Гоняют глазами после каждой правки набора
/// и снимком в тесте (`IconSheetTests`).
///
/// Толщина линии одна на весь лист: разная толщина у соседей — первый признак,
/// что знак пришёл из другой семьи.
public struct IconSheet: View {
    let size: CGFloat
    let line: CGFloat
    let columns: Int

    /// - Parameters:
    ///   - size: сторона знака в pt; 22 — как на листе веба.
    ///   - line: толщина линии в единицах холста 24×24; 1,5 — как на листе веба.
    ///   - columns: клеток в ряду.
    public init(size: CGFloat = 22, line: CGFloat = 1.5, columns: Int = 6) {
        self.size = size
        self.line = line
        self.columns = columns
    }

    /// Что показывать в наборе. Общий словарь затеняет часть имён («rings» из
    /// набора знаков перекрыт «rings» из точек дня), поэтому в общих наборах
    /// рисуется то, что увидит приложение, а не мёртвый рисунок.
    private func icon(group: String, name: String) -> Icon {
        switch group {
        case "genres": Icon(genre: name, size: size, line: line)
        case "wishes": Icon(wish: name, size: size, line: line)
        default: Icon(name, size: size, line: line)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(IconLibrary.sheet, id: \.group) { set in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(set.group) · \(set.names.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: columns),
                              alignment: .leading, spacing: 10) {
                        ForEach(set.names, id: \.self) { name in
                            VStack(spacing: 4) {
                                icon(group: set.group, name: name)
                                    .foregroundStyle(.tint)
                                Text(name)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

#Preview("Знаки, светлая") {
    ScrollView { IconSheet() }.preferredColorScheme(.light)
}

#Preview("Знаки, тёмная") {
    ScrollView { IconSheet() }.preferredColorScheme(.dark)
}
