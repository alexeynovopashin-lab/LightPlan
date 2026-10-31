import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Галерея мудборда (`#mbOverlay`, итерация 28, шаг 5а)

/// Поиск, чипы разделов и — либо плитки подборок, либо плоская сетка найденных кадров
/// (пустое поле и нет чипа — плитки; что-то набрано или выбран чип — кадры). Картинок нет:
/// ссылки — карточки «сайт / хвост пути», остальное — штриховка (решение Алексея 1Б).
/// «+» на найденном кадре открывает лист «Добавить в…»; «+ Новая подборка» — лист «Новая подборка» (шаг 5в).
struct MoodboardGallery: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var tiles: [String: CGRect] = [:]
    @FocusState private var focused: Bool

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        let lib = app.mbLibrary()
        let counts = Moodboard.tagCounts(lib.liveShots)
        let tag = Moodboard.activeTag(app.mb.tag, in: counts)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: t.t(app.mb.backKey), node: "mb.back") {
                    withAnimation(overlaySlide) { app.closeMbGallery() }
                }
                field(pal)
                if !counts.isEmpty { chips(counts, tag, pal) }
                if Moodboard.isSearching(query: app.mb.query, tag: tag) {
                    results(lib, tag, pal)
                } else {
                    tiles(lib, pal)
                }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollJump(t, node: "mb.jump", reserve: false)
        .overlay {
            // Просмотрщик найденных кадров; пока поверх лежит папка, она держит свой (общее состояние `mb.pager`).
            if app.mb.pager != nil, app.mb.folder == nil { RefViewerLayer(app: app, source: viewerSource(lib), tiles: tiles) }
        }
        .coordinateSpace(name: "mbg")
        .background(pal.surface.ignoresSafeArea())
        .shotNode("mb.gallery", text: "\(lib.boards.count)")
    }


    // MARK: поле и чипы

    private func field(_ pal: Palette) -> some View {
        TextField("", text: $app.mb.query, prompt: Text(t.t("mb.searchPh")).foregroundStyle(pal.ink8))
            .font(.system(size: 16)).foregroundStyle(pal.ink)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($focused)
            .padding(.horizontal, 15).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet))
            .shotNode("mb.search")
            .padding(.top, 14)
    }

    /// Чипы всех слов фонда со счётчиками, переносятся по строкам (веб `.rf-tag`, gap 7).
    private func chips(_ counts: [Moodboard.TagCount], _ active: String?, _ pal: Palette) -> some View {
        FlowLayout(spacing: 7) {
            ForEach(counts, id: \.tag) { c in
                let on = c.tag == active
                Button {
                    app.mb.tag = on ? nil : c.tag
                } label: {
                    HStack(spacing: 5) {
                        Text(app.mbTagName(c.tag)).font(webFont(13)).foregroundStyle(on ? pal.onBrass : pal.ink3)
                        Text("\(c.n)").font(webFont(13)).foregroundStyle(on ? pal.onBrass.opacity(0.6) : pal.ink6)
                    }
                    .padding(.horizontal, 13).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? pal.brass : Color.clear))
                    .overlay {
                        if !on { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(pal.press, lineWidth: 1) }
                    }
                }
                .buttonStyle(.plain)
                .shotNode("mb.chip.\(c.tag)", text: "\(c.n)")
            }
        }
        .padding(.top, 10)
        .shotNode("mb.tags", text: "\(counts.count)")
    }

    // MARK: плитки подборок

    @ViewBuilder private func tiles(_ lib: RefLibrary, _ pal: Palette) -> some View {
        let folders = app.mbFolders(lib)
        let shoots = Moodboard.galleryShoots(folders, sessions: app.sessions)
        let sets = folders.filter { $0.kind == .genre }
        let keys = sets.map { $0.genre ?? $0.boardId }
        MbSectionLabel(text: t.t("nav.shoots"), top: 30)
        if shoots.isEmpty {
            Text(t.t("mb.noShootFolders")).font(webFont(14)).foregroundStyle(pal.ink6).padding(.vertical, 8)
        } else {
            MbTileGrid { ForEach(Array(shoots.enumerated()), id: \.element.id) { tile($1, $0, lib, node: "mb.gs", row: nil, nth: $0 + 1) } }
        }
        MbSectionLabel(text: t.t("mb.sets"), top: 48)
        MbTileGrid {
            MbAddTile(title: t.t("mb.newTitle"), node: "mb.gadd") { focused = false; app.openMbNew() }
                .mbSortHit(app.mbSort, "gallery.add")
            ForEach(Array(sets.enumerated()), id: \.element.id) { tile($1, $0, lib, node: "mb.gg", row: "gallery.g", nth: $0 + 2) }
        }
        // Переставляются жанры (веб `mbGenreReorder` в `renderMbGallery`); съёмки — календарём.
        .mbSortRow(app.mbSort, row: "gallery.g", keys: keys, first: 1) { app.mbSetGenreOrder($0) }
        if sets.count > 1 { MbSortHint(app: app) }
    }

    private func tile(_ fo: MbFolder, _ i: Int, _ lib: RefLibrary, node: String, row: String?, nth: Int) -> some View {
        let l = app.mbLabels(fo, lib)
        let key = fo.genre ?? fo.boardId
        return MbTile(boardId: fo.boardId, genre: fo.genre, count: fo.frameCount, title: l.title, sub: l.sub,
                      node: "\(node).\(i)",
                      hold: fo.kind == .shoot ? { focused = false; app.openMbBoardCard(fo.boardId) } : nil,
                      sort: MbSortTile(sort: app.mbSort, row: row, key: key, nth: nth)) {
            focused = false
            app.mbTileTap(board: app.mbSheetBoard(fo)) { app.openMbFolderFlying(fo) }
        }
        .mbFlySource(app, fo.boardId)
        .modifier(MbSortSlot(sort: app.mbSort, row: row ?? "", key: row == nil ? "" : key))
        .mbSortHit(app.mbSort, "gallery.\(node).\(fo.boardId)")
        .binSubject(app, "board." + fo.boardId)
    }

    // MARK: плоская сетка найденных кадров

    private func viewerSource(_ lib: RefLibrary) -> RefViewerSource {
        let id = app.mbViewerFrameId
        return RefViewerSource(frameId: id, frame: id.flatMap(lib.shot), pager: app.mb.pager,
                               swipe: { dx, dy in app.mbViewerSwipe(dx: dx, dy: dy) },
                               close: { app.closeMbViewer() })
    }

    @ViewBuilder private func results(_ lib: RefLibrary, _ tag: String?, _ pal: Palette) -> some View {
        let found = Moodboard.search(lib.liveShots, query: app.mb.query, tag: tag, tagName: app.mbTagName,
                                     boardTitles: { app.mbBoardTitles($0, lib) })
        if found.isEmpty {
            Text(t.t("mb.searchNothing")).font(webFont(14)).foregroundStyle(pal.ink6)
                .frame(minHeight: 49.5, alignment: .center).padding(.top, 14)
                .shotNode("mb.nothing")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Array(found.enumerated()), id: \.element.id) { i, fr in
                    card(fr, found, pal).shotNode("mb.found.\(i)", text: fr.id)
                }
            }
            .padding(.top, 14)
            .shotNode("mb.grid", text: "\(found.count)")
        }
    }

    /// Карточка найденного кадра: тап — открыть (ссылка без картинки — сайт, картинка — просмотрщик по найденным),
    /// «+» справа сверху — лист «Добавить в…» (веб `#mbSearchGrid .plus`, 22 pt, латунь).
    private func card(_ fr: RefFrame, _ found: [RefFrame], _ pal: Palette) -> some View {
        let hidden = app.mbViewerFrameId == fr.id && app.mb.pager != nil
        return ZStack(alignment: .topTrailing) {
            Group {
                if MbFolderView.isBareLink(fr), let url = fr.url {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(RefLink.host(url) ?? t.t("ref.link")).font(webFont(13, 600)).foregroundStyle(pal.ink).lineLimit(1)
                        Text(RefLink.tail(url)).font(webFont(11)).foregroundStyle(pal.ink6).lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(10)
                    .aspectRatio(1, contentMode: .fit)
                    .background(pal.sheet, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    RefPicture(frame: fr, images: app.refImages, pal: pal).aspectRatio(1, contentMode: .fit)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focused = false
                if case .url(let u) = app.openMbFrame(fr.id, shown: found) { openURL(u) }
            }
            Button { focused = false; app.openMbAdd(shot: fr.id) } label: {
                Text("+").font(.system(size: 15)).foregroundStyle(pal.sheet)
                    .frame(width: 22, height: 22).background(Circle().fill(pal.brass))
                    .contentShape(Rectangle().inset(by: -11))
            }
            .buttonStyle(.plain).padding(.top, 4).padding(.trailing, 4)
            .shotNode("mb.plus.\(fr.id)")
        }
        .opacity(hidden ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("mbg")) } action: { tiles[fr.id] = $0 }
    }
}
