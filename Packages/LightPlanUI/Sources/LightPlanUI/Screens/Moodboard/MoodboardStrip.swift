import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Полоса мудборда на «Съёмках» (`#mbStrip`, итерация 28, шаг 5а)

/// Под лентой дня и тремя кнопками: ручка-сводка и тело с плитками «Съёмки» и «Подборки».
/// Свёрнутая ручка — карточка с веером трёх обложек; раскрытая — тонкая подпись со
/// стрелкой (справка 28, п. 2.1). Подсказка про сортировку не показывается: переставлять
/// в 5а нечего, жест — итерация 29 (ошибка веба 24 в нативе не повторяется).
struct MoodboardStrip: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    @Environment(\.colorScheme) private var scheme

    private static let fold = Animation.timingCurve(0.25, 1, 0.4, 1, duration: 0.45)

    var body: some View {
        let pal = Palette(scheme)
        let lib = app.mbLibrary()
        let folders = app.mbFolders(lib)
        let open = !app.mbStripFolded
        VStack(spacing: 0) {
            head(pal, folders, open: open)
            if open { tiles(pal, folders, lib) }
        }
        .padding(.horizontal, 24).padding(.top, 22)
        .shotNode("mb.strip", text: "\(folders.count)")
    }

    // MARK: ручка

    private func head(_ pal: Palette, _ folders: [MbFolder], open: Bool) -> some View {
        let t = f.t
        let frames = folders.reduce(0) { $0 + $1.frameCount }
        return Button {
            withAnimation(Self.fold) { app.mbStripFolded = open }
        } label: {
            HStack(spacing: open ? 0 : 14) {
                if !open { fan(folders, pal) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.t("mb.stripTitle")).font(webFont(open ? 13 : 16, 650)).tracking(open ? 0 : -0.2)
                        .foregroundStyle(open ? pal.ink3 : pal.ink)
                    if !open {
                        Text(folders.isEmpty ? t.t("mb.stripEmpty")
                             : t.count("unit.board", folders.count) + " · " + t.count("unit.frame", frames))
                            .font(webFont(12.5)).foregroundStyle(pal.ink4).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Icon("chevron", size: 16, line: 2.4).foregroundStyle(pal.ink4)
                    .rotationEffect(.degrees(open ? -90 : 90))
            }
            .padding(.horizontal, open ? 2 : 14)
            .padding(.top, open ? 9 : 12).padding(.bottom, open ? 12 : 12)
            .background {
                if !open {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.sheet4)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(pal.hairline, lineWidth: 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("mb.head", text: open ? "open" : "fold")
    }

    /// Веер из первых трёх обложек (веб `mbFanHtml`): лист 42, радиус 13, сдвиг 23, наклон −5°/0/5°.
    @ViewBuilder private func fan(_ folders: [MbFolder], _ pal: Palette) -> some View {
        let top = Array(folders.prefix(3))
        if top.isEmpty {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(pal.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .overlay { Icon("plus", size: 22, line: 1.6).foregroundStyle(pal.ink5) }
                .frame(width: 42, height: 42)
        } else {
            ZStack(alignment: .topLeading) {
                ForEach(Array(top.enumerated().reversed()), id: \.element.id) { i, fo in
                    MbCover(boardId: fo.boardId, genre: fo.genre, radius: 13, mark: 0.56, stroke: 1.9)
                        .frame(width: 42, height: 42)
                        .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
                        .rotationEffect(.degrees(i == 0 ? -5 : i == 2 ? 5 : 0))
                        .offset(x: 23 * CGFloat(i))
                }
            }
            .frame(width: CGFloat(42 + 23 * (top.count - 1) + 2), height: 42, alignment: .topLeading)
        }
    }

    // MARK: тело

    @ViewBuilder private func tiles(_ pal: Palette, _ folders: [MbFolder], _ lib: RefLibrary) -> some View {
        let t = f.t
        let shoots = Moodboard.stripShoots(folders, sessions: app.sessions, today: f.today)
        let sets = folders.filter { $0.kind == .genre }
        VStack(alignment: .leading, spacing: 0) {
            if !shoots.isEmpty {
                MbSectionLabel(text: t.t("nav.shoots"))
                row(shoots, withAdd: false, all: shoots, lib, node: "mb.s")
            }
            MbSectionLabel(text: t.t("mb.sets"), top: shoots.isEmpty ? 0 : 18)
            row(sets, withAdd: true, all: sets, lib, node: "mb.g")
        }
        .transition(.opacity)
    }

    private func row(_ list: [MbFolder], withAdd: Bool, all: [MbFolder], _ lib: RefLibrary, node: String) -> some View {
        let t = f.t
        let r = Moodboard.row(list, withAdd: withAdd)
        return MbTileGrid {
            if withAdd {
                MbAddTile(title: t.t("mb.newTitle"), node: "mb.add") { app.openMbNew() }
            }
            ForEach(Array(r.shown.enumerated()), id: \.element.id) { i, fo in
                let l = app.mbLabels(fo, lib)
                MbTile(boardId: fo.boardId, genre: fo.genre, count: fo.frameCount, title: l.title, sub: l.sub,
                       node: "\(node).\(i)",
                       hold: fo.kind == .shoot ? { app.openMbBoardCard(fo.boardId) } : nil) {
                    withAnimation(overlaySlide) { app.openMbFolder(fo) }
                }
            }
            if let badge = r.badge {
                MbMoreTile(cells: Moodboard.mosaic(hidden: r.hidden, all: all), badge: badge, title: t.t("mb.all"),
                           node: "\(node).more") {
                    withAnimation(overlaySlide) { app.openMbGallery() }
                }
            }
        }
    }
}
