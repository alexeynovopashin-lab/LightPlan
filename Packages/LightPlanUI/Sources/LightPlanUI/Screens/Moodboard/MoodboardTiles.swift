import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Плитки мудборда (`.mb-tile`, итерация 28, шаг 5а)

/// Пары цвета неба обложки (веб `MB_SKY`); выбор пары — `MbSky.index`.
enum MbSkyColors {
    private static let deep: UInt32 = 0x3D5878, blue: UInt32 = 0x5B77A0, pink: UInt32 = 0xC9698F
    private static let scarlet: UInt32 = 0xD8502F, gold: UInt32 = 0xE2A44C, amber: UInt32 = 0xD9AC6B
    private static let silver: UInt32 = 0xEFEAE0, night: UInt32 = 0x687EA8
    static let pairs: [(UInt32, UInt32)] = [(deep, blue), (blue, pink), (pink, scarlet), (scarlet, gold),
                                            (gold, amber), (night, deep), (blue, night), (amber, silver)]
}

/// Обложка без картинки: градиент неба 145°, α 0,85, и белый знак жанра с мягкой тенью
/// (веб `mbCover`, `mbGenreMark`). Картинок в нативе нет до 30 (решение 30.09, 1Б).
struct MbCover: View {
    let boardId: String
    let genre: String?
    var radius: CGFloat = 12
    /// Доля знака от обложки и толщина штриха: плитка 42 %/1,5, веер и мозаика 56 %/1,9.
    var mark: CGFloat = 0.42
    var stroke: CGFloat = 1.5
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let pair = MbSkyColors.pairs[MbSky.index(boardId)]
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        GeometryReader { g in
            shape.fill(pal.sheet)
                .overlay {
                    shape.fill(LinearGradient(colors: [Color(hex: pair.0, alpha: 0.85), Color(hex: pair.1, alpha: 0.85)],
                                              startPoint: UnitPoint(x: 0.100, y: -0.070), endPoint: UnitPoint(x: 0.900, y: 1.070)))
                }
                .overlay {
                    if let genre {
                        Icon(genre: genre, size: g.size.width * mark, line: stroke)
                            .foregroundStyle(Color.white.opacity(0.7))
                            .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                    }
                }
                .overlay { shape.strokeBorder(pal.hairline, lineWidth: 1) }
        }
    }
}

/// Обложка на стопке из двух листов и кружок-счётчик поверх (веб `mbTileArt`).
struct MbArt: View {
    let boardId: String
    let genre: String?
    let count: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                leaf(pal.sheet, pal).frame(width: w - 10, height: w - 5)
                    .rotationEffect(.degrees(-3.5)).offset(x: 5, y: 5 - 6)
                leaf(pal.sheet4, pal).frame(width: w - 6, height: w - 3)
                    .rotationEffect(.degrees(2.5)).offset(x: 3, y: 3 - 3)
                MbCover(boardId: boardId, genre: genre)
                    .shadow(color: .black.opacity(0.18), radius: 7, y: 4)
                    .frame(width: w, height: w)
                if count > 0 {
                    Text("\(count)").font(webFont(10.5, 600)).foregroundStyle(.white).monospacedDigit()
                        .padding(.horizontal, 5).frame(minWidth: 19, minHeight: 19)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .frame(width: w, height: w, alignment: .topTrailing)
                        .padding(.top, 6).padding(.trailing, -6)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func leaf(_ fill: Color, _ pal: Palette) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(pal.hairline, lineWidth: 1))
    }
}

/// Плитка ленты: обложка, название 12,5/600, подпись 11 (веб `.mb-tile`).
struct MbTile: View {
    let boardId: String
    let genre: String?
    let count: Int
    let title: String
    let sub: String
    var node = ""
    /// Удержание 0,42 с (веб `MB_HOLD`): у съёмок — карточка подборки; у жанров до 29 удержанию нечего делать.
    var hold: (() -> Void)? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let face = VStack(alignment: .leading, spacing: 0) {
            MbArt(boardId: boardId, genre: genre, count: count)
            Text(title).font(webFont(12.5, 600)).foregroundStyle(pal.ink2).lineLimit(1).padding(.top, 7)
            Text(sub).font(webFont(11)).foregroundStyle(pal.ink5).lineLimit(1).padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        if let hold {
            face
                .gesture(LongPressGesture(minimumDuration: 0.42, maximumDistance: 8).onEnded { _ in hold() }
                    .exclusively(before: TapGesture().onEnded { action() }))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
                .shotNode(node, text: title)
        } else {
            Button(action: action) { face }.buttonStyle(.plain).shotNode(node, text: title)
        }
    }
}

/// Рамка «+» — пустая рамка и есть кнопка (веб `.mb-tile.add`, пунктир 1 `--ink-10`).
struct MbAddTile: View {
    let title: String
    var node = ""
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(pal.ink10, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .overlay { Icon("plus", size: 24, line: 1.6).foregroundStyle(pal.ink5) }
                    .aspectRatio(1, contentMode: .fit)
                Text(title).font(webFont(12.5, 600)).foregroundStyle(pal.ink4).lineLimit(1).padding(.top, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode(node, text: title)
    }
}

/// Плитка «Все»: мозаика 2×2 из подборок, что не влезли в ряд, и кружок `+N` (веб `.mb-tile.more`).
struct MbMoreTile: View {
    let cells: [MbFolder]
    let badge: Int
    let title: String
    var node = ""
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { g in
                    let w = g.size.width
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(pal.sheet)
                            .frame(width: w - 10, height: w - 5).rotationEffect(.degrees(-3.5)).offset(x: 5, y: -1)
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(pal.sheet4)
                            .frame(width: w - 6, height: w - 3).rotationEffect(.degrees(2.5)).offset(x: 3, y: 0)
                        mosaic(w)
                        Text("+\(badge)").font(webFont(10.5, 600)).foregroundStyle(.white).monospacedDigit()
                            .padding(.horizontal, 5).frame(minWidth: 19, minHeight: 19)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .frame(width: w, height: w, alignment: .topTrailing)
                            .padding(.top, 6).padding(.trailing, -6)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                Text(title).font(webFont(12.5, 600)).foregroundStyle(pal.ink2).lineLimit(1).padding(.top, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode(node, text: "+\(badge)")
    }

    /// Ячейки 2×2 без зазора; меньше четырёх — растягиваются по месту (веб `.mb-cover.mo`).
    private func mosaic(_ w: CGFloat) -> some View {
        let rows = stride(from: 0, to: cells.count, by: 2).map { Array(cells[$0..<min($0 + 2, cells.count)]) }
        return VStack(spacing: 2) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(rows[r]) { f in
                        MbCover(boardId: f.boardId, genre: f.genre, radius: 6, mark: 0.56, stroke: 1.9)
                    }
                }
            }
        }
        .frame(width: w, height: w)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 7, y: 4)
    }
}

/// Сетка плиток: три колонки, зазор 10 (веб `.mb-tiles`).
struct MbTileGrid<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3),
                  alignment: .leading, spacing: 10) { content }
    }
}

/// Подпись раздела «СЪЁМКИ» / «ПОДБОРКИ» (веб `.mb-lbl`, `.sec-label`).
struct MbSectionLabel: View {
    let text: String
    var top: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text.uppercased()).font(webFont(10, 600)).tracking(1.2)
            .foregroundStyle(Palette(scheme).ink7).padding(.top, top).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
