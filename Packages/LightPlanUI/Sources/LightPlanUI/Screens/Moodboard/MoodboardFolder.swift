import SwiftUI
import PhotosUI
import LightPlanCore
import LightPlanDomain

// MARK: - Папка мудборда (`#mbFolderOverlay`, итерация 28, шаг 5б)

/// Шапка папки, лупа и поле, разделы, подпись, масонри в две колонки, выбор кадров и просмотрщик.
/// Числа — замер беты (справка 28, п. 2.4 и раздел 4): колонка 158 при отступе 39 от края.
/// Картинок нет до 30 (решение Алексея 1Б): ссылка — квадрат «сайт / хвост пути», остальное — штриховка.
/// Шестерёнка открывает меню подборки (лист, шаг 5в); в выборе — «Добавить в…», «Переместить…», «Убрать N»;
/// долгий тап по кадру и тап по ссылке без картинки — лист кадра; долгий тап по обложке — лист обложки.
/// Плитка «+» (лист «Фото / Ссылка») последней в сетке и кнопки «Фото» / «Ссылка» внизу — шаг 5г
/// (решение Алексея 30.09, «кнопка Фото должна работать»); картинки в плитках вместо штриховки — 5д.
struct MoodboardFolder: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var tiles: [String: CGRect] = [:]
    /// Ширина сетки: экран минус поля 24 и отступ сетки 15 с каждой стороны (`.mb-grid`, `padding 12 15 0`).
    @State private var gridW: CGFloat = 324
    @State private var scrollable: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var window: CGFloat = 800
    @State private var position = ScrollPosition(edge: .top)
    @State private var confirmRemove = false
    @State private var picked: [PhotosPickerItem] = []
    @FocusState private var focused: Bool

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        let lib = app.mbLibrary()
        if let sc = app.mbFolderScene(lib) {
            ZStack {
                content(sc, pal)
                if app.mb.pager != nil { RefViewerLayer(app: app, source: viewerSource(sc, lib), tiles: tiles) }
            }
            .coordinateSpace(name: "mbf")
            .background(pal.surface.ignoresSafeArea())
            .shotNode("mb.folder", text: "\(sc.list.count)")
        } else {
            pal.surface.ignoresSafeArea()
        }
    }

    private func viewerSource(_ sc: MbFolderScene, _ lib: RefLibrary) -> RefViewerSource {
        let id = app.mbViewerFrameId
        // Тег могли снять из листа поверх кадра: при фильтре по нему кадра нет в сетке, но он в фонде.
        return RefViewerSource(frameId: id, frame: id.flatMap { id in sc.list.first { $0.id == id } ?? lib.shot(id) },
                               pager: app.mb.pager,
                               swipe: { dx, dy in app.mbViewerSwipe(dx: dx, dy: dy) },
                               close: { app.closeMbViewer() },
                               editTags: { app.openMbItem(shot: $0, overView: true) })
    }

    // MARK: полотно

    private func content(_ sc: MbFolderScene, _ pal: Palette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar(sc, pal)
                head(sc, pal)
                toolRow(sc, pal)
                if app.mb.folderSearchOpen { field(pal) }
                if !sc.sections.isEmpty { rail(sc, pal) }
                gridLabel(sc, pal)
                grid(sc, pal)
                if app.mb.pick != nil { pickActions(pal) } else { addRow(pal) }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
            .onGeometryChange(for: CGFloat.self) { $0.size.width - 48 - 30 } action: { gridW = $0 }
        }
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Metrics.self) {
            Metrics(offset: $0.contentOffset.y, scrollable: max(0, $0.contentSize.height - $0.containerSize.height),
                    window: $0.containerSize.height)
        } action: { _, m in offset = m.offset; scrollable = m.scrollable; window = m.window }
        .overlay(alignment: .bottomTrailing) { jump(pal) }
        .photosPicker(isPresented: Binding(get: { app.mb.photoPicker }, set: { app.mb.photoPicker = $0 }),
                      selection: $picked, matching: .images, photoLibrary: .shared())
        .onChange(of: picked) { _, items in
            guard !items.isEmpty, let board = app.mb.folder else { return }
            let tag = app.mb.folderTag
            picked = []
            Task {
                var blobs: [Data] = []
                for item in items { if let d = try? await item.loadTransferable(type: Data.self) { blobs.append(d) } }
                app.mbAddPhotos(blobs, to: board, tag: tag)
            }
        }
        .alert(t.t("mb.selDelTitle", ["n": "\(app.mb.pick?.count ?? 0)"]), isPresented: $confirmRemove) {
            Button(t.t("ask.cancel"), role: .cancel) {}
            Button(t.t("mb.selDelOk"), role: .destructive) { app.mbRemovePicked() }
        } message: { Text(t.t("mb.selDelSub")) }
    }

    private struct Metrics: Equatable { var offset: CGFloat; var scrollable: CGFloat; var window: CGFloat }

    // MARK: верхняя строка и шапка

    /// «‹» назад 20×28 и справа дверь «настройки» 30×30 (`.mb-topbar`, y 14, h 38). Дверь «хранение» и
    /// строка «на устройстве / в облаке» — про файлы, их нет до 30 (решения Алексея 1Б, 2А).
    private func topBar(_ sc: MbFolderScene, _ pal: Palette) -> some View {
        HStack(spacing: 0) {
            Button {
                focused = false
                withAnimation(overlaySlide) { app.closeMbFolder() }
            } label: {
                Icon("chevron", size: 16, line: 2.4).rotationEffect(.degrees(180)).foregroundStyle(pal.ink4)
                    .frame(width: 20, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(t.t("card.close")).shotNode("mb.folderBack")
            Spacer(minLength: 0)
            if app.mb.pick == nil {
                Button { focused = false; app.openMbMenu(sc.board.id) } label: {
                    Icon("sliders", size: 20, line: 1.6).foregroundStyle(pal.ink4)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.t("mb.pick")).shotNode("mb.folderCog")
            }
        }
        .frame(height: 38)
    }

    /// Обложка 58×58, радиус 14, тот же градиент и знак, что у плитки; справа заголовок 22/650 и подпись 14.
    private func head(_ sc: MbFolderScene, _ pal: Palette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MbCover(boardId: sc.board.id, genre: sc.genre, radius: 14, mark: 0.42, stroke: 1.5)
                .frame(width: 58, height: 58).shotNode("mb.folderHero")
                .onLongPressGesture(minimumDuration: 0.42, maximumDistance: 8) {
                    if !app.mbLibrary().coverCandidates(sc.board.id).isEmpty { app.openMbCover() }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(sc.title).font(webFont(22, 650)).tracking(-0.5).foregroundStyle(pal.ink).lineLimit(1)
                    .shotNode("mb.folderTitle", text: sc.title)
                Text(sc.sub).font(webFont(14)).foregroundStyle(pal.ink4).lineLimit(1)
                    .shotNode("mb.folderSub", text: sc.sub)
            }
            .padding(.top, 9)
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    // MARK: лупа, поле, разделы

    /// Лупа 16×16 и в выборе — «Выбрать все / Снять все» и «Готово» 12,5 (`#mbToolRow`, padding 12 2 2, gap 16).
    private func toolRow(_ sc: MbFolderScene, _ pal: Palette) -> some View {
        HStack(spacing: 16) {
            if let pick = app.mb.pick {
                let on = pick.allOn(shown: sc.shown.map(\.id))
                toolButton(t.t(on ? "mb.selNone" : "mb.selAll"), pal, node: "mb.selAll") { app.toggleMbPickAll(sc.shown) }
                toolButton(t.t("mb.pickDone"), pal, node: "mb.pickDone") { app.toggleMbPicking() }
            } else {
                Button { app.toggleMbFolderSearch(); focused = app.mb.folderSearchOpen } label: {
                    MbLens().stroke(app.mb.folderSearchOpen ? pal.brass : pal.brassSoft,
                                    style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(width: 16, height: 16).padding(.trailing, 2).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(t.t("mb.folderSearchPh")).shotNode("mb.folderLens")
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12).padding(.horizontal, 2).padding(.bottom, 2)
        .frame(minHeight: 30)
    }

    private func toolButton(_ title: String, _ pal: Palette, node: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(webFont(12.5)).foregroundStyle(pal.brassSoft) }
            .buttonStyle(.plain).shotNode(node, text: title)
    }

    private func field(_ pal: Palette) -> some View {
        TextField("", text: $app.mb.folderQuery, prompt: Text(t.t("mb.folderSearchPh")).foregroundStyle(pal.ink8))
            .font(.system(size: 16)).foregroundStyle(pal.ink)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($focused)
            .padding(.horizontal, 15).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet))
            .padding(.top, 10)
            .shotNode("mb.folderSearch")
    }

    /// Рейл в одну строку, прокручивается вбок: «Все N» и только использованные разделы (`#mbTags`, h 44).
    private func rail(_ sc: MbFolderScene, _ pal: Palette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(t.t("refs.all"), n: sc.list.count, on: sc.tag == nil, pal, node: "mb.fchip.all") { app.mb.folderTag = nil }
                ForEach(sc.sections, id: \.tag) { s in
                    chip(app.mbTagName(s.tag), n: s.n, on: sc.tag == s.tag, pal, node: "mb.fchip.\(s.tag)") {
                        app.setMbFolderTag(s.tag)
                    }
                }
            }
        }
        .frame(height: 44, alignment: .top)
        .shotNode("mb.ftags", text: "\(sc.sections.count)")
    }

    private func chip(_ title: String, n: Int, on: Bool, _ pal: Palette, node: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(webFont(13)).foregroundStyle(on ? pal.onBrass : pal.ink3)
                if n > 0 { Text("\(n)").font(webFont(13)).monospacedDigit().foregroundStyle(on ? pal.onBrass.opacity(0.6) : pal.ink6) }
            }
            .padding(.horizontal, 13).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? pal.brass : Color.clear))
            .overlay { if !on { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(pal.press, lineWidth: 1) } }
        }
        .buttonStyle(.plain).shotNode(node, text: "\(n)")
    }

    // MARK: подпись и сетка

    /// «10 КАДРОВ» 10/600 разрядка 1,2; под фильтром «3 ИЗ 10 КАДРОВ», в выборе «ВЫБРАНО: 2» (`.mb-grid-lbl`).
    @ViewBuilder private func gridLabel(_ sc: MbFolderScene, _ pal: Palette) -> some View {
        let text: String? = switch sc.label {
        case .hidden: nil
        case .count(let n): t.count("unit.frame", n)
        case .some(let shown, let total): t.t("mb.gridSome", ["n": "\(shown)", "total": t.count("unit.frame", total)])
        case .picked(let n): t.t("mb.selN", ["n": "\(n)"])
        }
        if let text {
            Text(text).textCase(.uppercase).tracking(1.2).font(webFont(10, 600)).foregroundStyle(pal.ink7)
                .padding(.horizontal, 2).padding(.top, 8).frame(height: 20, alignment: .bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shotNode("mb.gridLabel", text: text)
        }
    }

    @ViewBuilder private func grid(_ sc: MbFolderScene, _ pal: Palette) -> some View {
        Group {
            if sc.list.isEmpty {
                ghosts(sc, pal)
            } else if sc.shown.isEmpty {
                Text(app.mb.folderQuery.trimmingCharacters(in: .whitespaces).isEmpty
                     ? t.t("mb.sectionEmpty", ["section": sc.tag.map(app.mbTagName) ?? ""]) : t.t("mb.searchNothing"))
                    .font(webFont(14)).foregroundStyle(pal.ink6).padding(.horizontal, 2).padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                masonry(sc, pal)
            }
        }
        .padding(.top, 16).padding(.horizontal, 15)   // margin-top 4 + padding-top 12; поля сетки 15
    }

    /// `column-count: 2`, зазор 8, ширина колонки 158: первая колонка сверху вниз, потом вторая.
    /// Плитка «+» последней — шаг 5в (`MbFolderView.showsAddTile` решает, когда она стоит).
    private func masonry(_ sc: MbFolderScene, _ pal: Palette) -> some View {
        let w = (gridW - 8) / 2
        let frames = sc.shown
        let adds = MbFolderView.showsAddTile(filtered: sc.filtered, picking: app.mb.pick != nil, shownCount: frames.count)
        let hs = frames.map { MbFolderView.tileHeight($0, width: Double(w)) } + (adds ? [Double(w)] : [])
        let n = RefColumns.firstColumnCount(heights: hs)
        func col(_ a: ArraySlice<Double>) -> Double { a.reduce(0, +) + Double(max(0, a.count - 1)) * 8 }
        // «+» — последний в порядке колонок: в первой, если она вместила всё, иначе последней во второй.
        func column(_ range: Range<Int>) -> some View {
            VStack(spacing: 8) {
                ForEach(Array(range), id: \.self) { i in
                    Group {
                        if i < frames.count { tile(frames[i], sc, pal) } else { addTile(pal) }
                    }
                    .frame(width: w, height: CGFloat(hs[i]))
                }
                Spacer(minLength: 0)
            }
        }
        return HStack(alignment: .top, spacing: 8) {
            column(0..<n)
            column(n..<hs.count)
        }
        .frame(height: CGFloat(max(col(hs[..<n]), col(hs[n...]))), alignment: .top)
        .shotNode("mb.fgrid", text: "\(frames.count)")
    }

    /// Плитка «+»: пунктир 1 `#1C1913`, радиус 10; тап — лист «Фото / Ссылка» (`openMbAddWhat`).
    private func addTile(_ pal: Palette) -> some View {
        Button { focused = false; app.openMbAddWhat() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(pal.press, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                Icon("plus", size: 22, line: 1.8).foregroundStyle(pal.ink6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityLabel(t.t("mb.addWhat")).shotNode("mb.addTile")
    }

    /// Внизу две кнопки «Фото» и «Ссылка» (`#mbAddRow`, `padding 12 15`, gap 8; 158×39, радиус 10, 14).
    private func addRow(_ pal: Palette) -> some View {
        func button(_ title: String, node: String, _ go: @escaping () -> Void) -> some View {
            Button { focused = false; go() } label: {
                Text(title).font(webFont(14)).foregroundStyle(pal.ink3)
                    .frame(maxWidth: .infinity).frame(height: 39)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pal.sheet))
            }
            .buttonStyle(.plain).shotNode(node, text: title)
        }
        return VStack(spacing: 0) {
            MbPinStrip(app: app)
            HStack(spacing: 8) {
                button(t.t("ref.photo"), node: "mb.addPhoto") { app.requestMbPhotoPicker() }
                button(t.t("ref.link"), node: "mb.addLink") { app.openMbAddLink() }
            }
            .padding(.top, 12).padding(.horizontal, 15)
        }
    }

    private func tile(_ f: RefFrame, _ sc: MbFolderScene, _ pal: Palette) -> some View {
        let picked = app.mb.pick?.contains(f.id) ?? false
        let hidden = app.mbViewerFrameId == f.id && app.mb.pager != nil
        let tap = {
            if app.mb.pick != nil { app.toggleMbPick(f.id); return }
            // Ссылка без картинки открывает лист кадра, а не сайт (веб `openMbItem`); адрес — строка листа.
            if MbFolderView.isBareLink(f) { app.openMbItem(shot: f.id); return }
            _ = app.openMbFrame(f.id, shown: sc.shown)
        }
        // Удержание 0,42 с — лист кадра; сдвиг больше 8 pt его отменяет (веб `MB_HOLD`). В выборе — только отметка.
        return ZStack(alignment: .topTrailing) {
            if MbFolderView.isBareLink(f), let u = f.url { linkTile(u, pal) }
            else { RefPicture(frame: f, images: app.refImages, pal: pal, radius: 10).opacity(picked ? 0.55 : 1) }
            if picked { check(pal) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .gesture(LongPressGesture(minimumDuration: 0.42, maximumDistance: 8).onEnded { _ in
            if app.mb.pick == nil { app.openMbItem(shot: f.id) }
        }.exclusively(before: TapGesture().onEnded { tap() }))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap() }
        .opacity(hidden ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("mbf")) } action: { tiles[f.id] = $0 }
        .shotNode("mb.ftile.\(sc.shown.firstIndex { $0.id == f.id } ?? 0)", text: f.id)
    }

    /// Ссылка без картинки: «сайт» 9,5/700 капсом и хвост пути 11, `padding 10`, фон `sheet-4` (`.ref-card.link`).
    private func linkTile(_ url: String, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text((RefLink.host(url) ?? t.t("ref.link")).uppercased()).font(webFont(9.5, 700)).tracking(0.4)
                .foregroundStyle(pal.brass).lineLimit(1).padding(.trailing, 22)
            Text(RefLink.tail(url)).font(webFont(11)).foregroundStyle(pal.ink4).lineSpacing(1.5).lineLimit(4)
            // Pinterest или прямая ссылка на фото без картинки: плитка честно говорит, что превью нет (картинка не придумывается).
            if PinterestLink.kind(url) != .other || ImageLink.kind(url) == .image {
                Spacer(minLength: 0)
                Text(t.t("pin.previewOff")).font(webFont(9.5)).foregroundStyle(pal.ink4.opacity(0.8)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(pal.sheet4)
    }

    /// «✓» выбора: круг 22 `brass`, справа сверху 7, тень `0 1 4 .35`.
    private func check(_ pal: Palette) -> some View {
        Icon("check", size: 13, line: 2).foregroundStyle(pal.onBrass)
            .frame(width: 22, height: 22).background(Circle().fill(pal.brass))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .padding(.top, 7).padding(.trailing, 7)
    }

    /// Пустая папка: подпись 13 и коллаж призраков в две колонки «h v h» и «v h h» (`mbGhostGrid`).
    private func ghosts(_ sc: MbFolderScene, _ pal: Palette) -> some View {
        let w = (gridW - 8) / 2
        let from = MbSky.index(sc.board.id)
        let cols: [[Bool]] = [[false, true, false], [true, false, false]]   // true — вертикальный 2:3
        let firstOfCol = [0, cols[0].count]
        return VStack(alignment: .leading, spacing: 0) {
            Text(t.t("mb.empty")).font(webFont(13)).foregroundStyle(pal.ink8).lineSpacing(5)
                .padding(.horizontal, 2).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .top, spacing: 8) {
                ForEach(cols.indices, id: \.self) { c in
                    VStack(spacing: 8) {
                        ForEach(cols[c].indices, id: \.self) { r in
                            let pair = MbSkyColors.pairs[(from + firstOfCol[c] + r) % MbSkyColors.pairs.count]
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(colors: [Color(hex: pair.0, alpha: 0.72), Color(hex: pair.1, alpha: 0.72)],
                                                     startPoint: UnitPoint(x: 0.1, y: -0.07), endPoint: UnitPoint(x: 0.9, y: 1.07)))
                                .frame(width: w, height: cols[c][r] ? w * 1.5 : w / 1.5)
                        }
                    }
                }
            }
        }
        .shotNode("mb.fghosts")
    }

    // MARK: выбор

    /// В выборе вместо «Фото/Ссылка» — три кнопки над выбранным: «Добавить в…», «Переместить…», «Убрать N»
    /// (`#mbSelActs`, каждая 56 высотой). Пока ничего не отмечено, они приглушены и молчат.
    private func pickActions(_ pal: Palette) -> some View {
        let n = app.mb.pick?.count ?? 0
        func button(_ title: String, node: String, color: Color, _ go: @escaping () -> Void) -> some View {
            Button { if n > 0 { go() } } label: {
                Text(title).font(webFont(14)).foregroundStyle(color).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pal.sheet))
                    .opacity(n > 0 ? 1 : 0.45)
            }
            .buttonStyle(.plain).shotNode(node, text: "\(n)")
        }
        return HStack(spacing: 8) {
            button(t.t("mb.selAdd"), node: "mb.selAdd", color: pal.ink3) { app.openMbAddPicked(move: false) }
            button(t.t("mb.selMove"), node: "mb.selMove", color: pal.ink3) { app.openMbAddPicked(move: true) }
            button(t.t("mb.selDel") + (n > 0 ? " \(n)" : ""), node: "mb.selDel", color: Color(hex: 0xB9603D)) { confirmRemove = true }
        }
        .padding(.top, 12).padding(.horizontal, 15)
    }

    // MARK: прыжок

    @ViewBuilder private func jump(_ pal: Palette) -> some View {
        if Moodboard.jumpVisible(scrollable: scrollable, screen: window) {
            let down = Moodboard.jumpGoesDown(offset: offset, scrollable: scrollable)
            Button {
                withAnimation(.easeInOut(duration: 0.35)) { position.scrollTo(edge: down ? .bottom : .top) }
            } label: {
                Icon("chevron", size: 18, line: 2.2).rotationEffect(.degrees(down ? 90 : -90)).foregroundStyle(pal.ink3)
                    .frame(width: 38, height: 38).glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel(t.t(down ? "mb.jumpEnd" : "mb.jumpTop"))
            .shotNode("mb.fjump", text: down ? "down" : "up")
            .padding(.trailing, 24).padding(.bottom, 24)
        }
    }
}

/// Лупа `#mbSearchBtn`: круг r 6,5 в (11, 11) и ручка до (20,5; 20,5) в сетке 24.
struct MbLens: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 24
        var p = Path()
        p.addEllipse(in: CGRect(x: 4.5 * k, y: 4.5 * k, width: 13 * k, height: 13 * k))
        p.move(to: CGPoint(x: 16 * k, y: 16 * k)); p.addLine(to: CGPoint(x: 20.5 * k, y: 20.5 * k))
        return p
    }
}
