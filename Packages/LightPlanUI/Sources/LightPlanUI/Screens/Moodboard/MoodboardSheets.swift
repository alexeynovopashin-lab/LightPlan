import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Листы мудборда (итерация 28, шаг 5в)

extension View {
    /// Один лист мудборда поверх любого экрана (`RootView`); что в нём — решает `app.mb.sheet`.
    func mbSheets(_ app: AppModel) -> some View {
        sheet(isPresented: Binding(get: { app.mb.sheet != nil }, set: { if !$0 { app.mb.sheet = nil } })) {
            MbSheetContent(app: app)
        }
    }
}

/// Содержимое листа по состоянию; пока лист уезжает, держит последнее, чтобы не мигать пустым.
struct MbSheetContent: View {
    @Bindable var app: AppModel
    @State private var last: MbSheet?

    var body: some View {
        Group {
            switch app.mb.sheet ?? last {
            case .menu(let id)?: MbMenuSheet(app: app, boardId: id)
            case .sortPick(let id)?: MbSortSheet(app: app, boardId: id)
            case .mergePick(let id)?: MbMergePickSheet(app: app, boardId: id)
            case .mergeConfirm(let from, let to)?: MbMergeConfirmSheet(app: app, from: from, to: to)
            case .rename(let id)?: MbRenameSheet(app: app, boardId: id)
            case .newFolder(let g)?: MbNewFolderSheet(app: app, genre: g)
            case .add(let mode)?: MbAddSheet(app: app, mode: mode)
            case .loneConfirm(let shot, let board)?: MbLoneSheet(app: app, shot: shot, board: board)
            case .new?: MbNewSheet(app: app)
            case .addWhat?: MbAddWhatSheet(app: app)
            case .addLink?: MbAddLinkSheet(app: app)
            case .cover(let id)?: MbCoverSheet(app: app, boardId: id)
            case .board(let id)?: MbBoardSheet(app: app, boardId: id)
            case .item(let shot, let board, let over)?: MbItemSheet(app: app, shot: shot, board: board, overView: over)
            case nil: Color.clear
            }
        }
        .onAppear { last = app.mb.sheet }
        .onChange(of: app.mb.sheet) { _, n in if let n { last = n } }
    }
}

// MARK: - Каркас

/// Ручка, заголовок 19/650, подпись 13 и тело; высота листа — по содержимому, но не выше 86 % окна.
private struct MbSheetFrame<Body: View>: View {
    let title: String
    var sub: String?
    var node = ""
    var full = false
    @ViewBuilder var content: Body
    @State private var height: CGFloat = 320
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(pal.edge).frame(width: 38, height: 4).frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 18)
                Text(title).font(webFont(19, 650)).tracking(-0.2).foregroundStyle(pal.ink)
                    .fixedSize(horizontal: false, vertical: true).shotNode(node + ".title", text: title)
                if let sub, !sub.isEmpty {
                    Text(sub).font(webFont(13)).foregroundStyle(pal.ink4).padding(.top, 5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content.padding(.top, 16)
            }
            .padding(.horizontal, 24).padding(.bottom, 34)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(full ? [.large] : [.height(min(height, 700))])
        .presentationDragIndicator(.hidden)
        .shotNode(node)
    }
}

/// Строка списка: 52 (63 с подписью), ✓ справа, тап (`.row` веба).
private struct MbRow: View {
    let title: String
    var sub: String?
    var on = false
    var danger = false
    var node = ""
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(webFont(16)).foregroundStyle(danger ? pal.terra2 : pal.ink).lineLimit(1)
                    if let sub, !sub.isEmpty { Text(sub).font(webFont(13)).foregroundStyle(pal.ink4).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if on { Icon("check", size: 18, line: 2).foregroundStyle(pal.brass) }
            }
            .padding(.horizontal, 15).frame(minHeight: (sub ?? "").isEmpty ? 52 : 63)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).shotNode(node, text: title)
    }
}

private struct MbCancel: View {
    @Bindable var app: AppModel
    var back: MbSheet?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button { app.mb.sheet = back } label: {
            Text(app.lexicon.t("ask.cancel")).font(webFont(15)).foregroundStyle(Palette(scheme).ink4)
                .frame(maxWidth: .infinity, minHeight: 45).contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.top, 6).shotNode("mbs.cancel")
    }
}

// MARK: - Меню подборки (`askPick` шестерёнки)

private struct MbMenuSheet: View {
    @Bindable var app: AppModel
    let boardId: String

    var body: some View {
        let t = app.lexicon
        let lib = app.mbLibrary()
        if let b = lib.board(boardId) {
            let frames = MbFolderView.frames(of: b, in: lib.shots).count
            let merge = MbSheets.mergeTargets(of: b, in: lib)
            let items = MbSheets.menu(b, frames: frames, mergeTargets: merge.count)
            MbSheetFrame(title: app.mbBoardMenuTitle(b), sub: app.mbBoardSub(b), node: "mbs.menu") {
                FormGroup {
                    ForEach(items, id: \.self) { it in row(it, b, t) }
                }
                MbCancel(app: app)
            }
        } else { Color.clear.onAppear { app.mb.sheet = nil } }
    }

    @ViewBuilder private func row(_ it: MbSheets.MenuItem, _ b: RefBoard, _ t: Lexicon) -> some View {
        switch it {
        case .sort:
            MbRow(title: t.t("mb.sortWord"), sub: t.t(MbSheets.sortKeys[min(max(b.sort, 0), 2)]), node: "mbs.m.sort") {
                app.mb.sheet = .sortPick(b.id)
            }
        case .cover:
            MbRow(title: t.t(b.cover == nil ? "mb.pickCover" : "mb.coverChange"), node: "mbs.m.cover") {
                app.mb.sheet = .cover(b.id)
            }
        case .pick:
            MbRow(title: t.t("mb.pick"), node: "mbs.m.pick") { app.mb.sheet = nil; app.mb.pick = MbPick() }
        case .rename:
            MbRow(title: t.t("mb.rename"), sub: b.name, node: "mbs.m.rename") { app.mb.sheet = .rename(b.id) }
        case .newFolder:
            MbRow(title: t.t("mb.newFolder"), sub: app.mbGenreName(b.genre), node: "mbs.m.newFolder") {
                app.mb.sheet = .newFolder(genre: b.genre ?? "")
            }
        case .merge:
            MbRow(title: t.t("mb.mergeInto"), node: "mbs.m.merge") { app.mb.sheet = .mergePick(b.id) }
        case .delete:
            MbRow(title: t.t("mb.delBoard"), node: "mbs.m.delete") { app.mb.sheet = .board(b.id) }
        }
    }
}

private struct MbSortSheet: View {
    @Bindable var app: AppModel
    let boardId: String
    var body: some View {
        let t = app.lexicon
        let cur = app.mbLibrary().board(boardId)?.sort ?? 0
        MbSheetFrame(title: t.t("mb.sortWord"), node: "mbs.sort") {
            FormGroup {
                ForEach(Array(MbSheets.sortKeys.enumerated()), id: \.offset) { i, k in
                    MbRow(title: t.t(k), on: cur == i, node: "mbs.sort.\(i)") { app.mbSetSort(i, of: boardId) }
                }
            }
            MbCancel(app: app, back: .menu(boardId))
        }
    }
}

private struct MbMergePickSheet: View {
    @Bindable var app: AppModel
    let boardId: String
    var body: some View {
        let t = app.lexicon
        let lib = app.mbLibrary()
        let targets = lib.board(boardId).map { MbSheets.mergeTargets(of: $0, in: lib) } ?? []
        MbSheetFrame(title: t.t("mb.mergeInto"), node: "mbs.mergePick") {
            FormGroup {
                ForEach(targets, id: \.id) { to in
                    MbRow(title: app.mbBoardTitle(to), sub: app.mbGenreName(to.genre), node: "mbs.merge.\(to.id)") {
                        app.mb.sheet = .mergeConfirm(from: boardId, to: to.id)
                    }
                }
            }
            MbCancel(app: app, back: .menu(boardId))
        }
    }
}

/// «Объединить подборки?» — `askYes` веба: сколько кадров переедет и куда.
private struct MbMergeConfirmSheet: View {
    @Bindable var app: AppModel
    let from: String
    let to: String
    var body: some View {
        let t = app.lexicon
        let lib = app.mbLibrary()
        if let a = lib.board(from), let b = lib.board(to) {
            let moving = MbSheets.mergeMoving(a, into: b)
            let sub = moving > 0
                ? t.t("mb.mergeConfirmSub", ["n": t.count("unit.frame", moving), "name": app.mbBoardTitle(b)])
                : t.t("mb.mergeConfirmNone", ["name": app.mbBoardTitle(b)])
            AskYesSheet(title: t.t("mb.mergeConfirm"), sub: sub, ok: t.t("mb.mergeOk"), cancel: t.t("ask.cancel")) { yes in
                if yes { app.mbConfirmMerge(from: from, into: to) } else { app.mb.sheet = .mergePick(from) }
            }
        } else { Color.clear.onAppear { app.mb.sheet = nil } }
    }
}

// MARK: - Имя (переименовать, новая папка)

private struct MbRenameSheet: View {
    @Bindable var app: AppModel
    let boardId: String
    var body: some View {
        let t = app.lexicon
        AskTextSheet(title: t.t("mb.renameAsk"), ok: t.t("mb.pickDone"), cancel: t.t("ask.cancel"), keyboard: .default,
                     initial: app.mbLibrary().board(boardId)?.name ?? "", allowEmpty: true) { name in
            if let name { app.mbRename(boardId, to: name) } else { app.mb.sheet = .menu(boardId) }
        }
    }
}

private struct MbNewFolderSheet: View {
    @Bindable var app: AppModel
    let genre: String
    var body: some View {
        let t = app.lexicon
        AskTextSheet(title: t.t("mb.newFolderAsk"), ok: t.t("mb.pickDone"), cancel: t.t("ask.cancel"), keyboard: .default) { name in
            if let name { app.mbCreateFolder(genre: genre, name: name) } else { app.mb.sheet = nil }
        }
    }
}

// MARK: - «Фото / Ссылка» (плитка «+», `openMbAddWhat`) и адрес ссылки

private struct MbAddWhatSheet: View {
    @Bindable var app: AppModel
    var body: some View {
        let t = app.lexicon
        MbSheetFrame(title: t.t("mb.addWhat"), node: "mbs.addWhat") {
            FormGroup {
                MbRow(title: t.t("ref.photo"), node: "mbs.addWhat.photo") { app.requestMbPhotoPicker() }
                MbRow(title: t.t("ref.link"), node: "mbs.addWhat.link") { app.openMbAddLink() }
            }
            MbCancel(app: app, back: nil)
        }
    }
}

private struct MbAddLinkSheet: View {
    @Bindable var app: AppModel
    var body: some View {
        let t = app.lexicon
        AskTextSheet(title: t.t("ref.linkAsk"), ok: t.t("mb.pickDone"), cancel: t.t("ask.cancel")) { raw in
            if let raw { app.mbAddLink(raw) } else { app.mb.sheet = nil }
        }
    }
}

// MARK: - «Добавить в…» / «Переместить…» (`#mbAddSheet`)

private struct MbAddSheet: View {
    @Bindable var app: AppModel
    let mode: MbAddMode
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = app.lexicon
        let lib = app.mbLibrary()
        let rows = app.mbAddRows(mode, lib)
        MbSheetFrame(title: t.t(mode.move ? "mb.moveToTitle" : "mb.addToTitle"), node: "mbs.add", full: rows.count > 9) {
            if rows.isEmpty {
                Text(t.t("mb.noBoards")).font(webFont(14)).foregroundStyle(Palette(scheme).ink6).padding(.vertical, 14)
            } else {
                FormGroup {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        MbRow(title: r.title, on: r.checked, node: "mbs.add.\(i)") { app.mbAddTap(r, mode: mode) }
                    }
                }
            }
            MbCancel(app: app)
        }
    }
}

/// Снять последнее место кадра: вопрос, пока кадр не пропал молча (веб `mb.loneTitle`).
private struct MbLoneSheet: View {
    @Bindable var app: AppModel
    let shot: String
    let board: String
    var body: some View {
        let t = app.lexicon
        AskYesSheet(title: t.t("mb.loneTitle"), sub: t.t("mb.loneSub"), ok: t.t("mb.selDelOk"), cancel: t.t("ask.cancel")) { yes in
            if yes { app.mbConfirmLone(shot: shot, board: board) } else { app.mb.sheet = .add(MbAddMode(shot: shot)) }
        }
    }
}

// MARK: - «Новая подборка» (`#mbNewSheet`)

private struct MbNewSheet: View {
    @Bindable var app: AppModel
    var body: some View {
        let t = app.lexicon
        MbSheetFrame(title: t.t("mb.newTitle"), sub: t.t("mb.newSub"), node: "mbs.new") {
            // Все жанры: выключенные приглушены, тап включает (Алексей, 31.08.2026).
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Genre.allCases, id: \.self) { g in
                    let on = app.enabledGenres.contains(g)
                    GenreTile(genre: g, name: t.t("genre." + g.rawValue), on: on) { app.mbNewPick(g) }
                        .opacity(on ? 1 : 0.4)
                        .shotNode("mbs.new.\(g.rawValue)")
                }
            }
        }
    }
}

// MARK: - Обложка (`#mbCoverSheet`)

private struct MbCoverSheet: View {
    @Bindable var app: AppModel
    let boardId: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = app.lexicon
        let pal = Palette(scheme)
        let lib = app.mbLibrary()
        let cur = lib.board(boardId)?.cover
        let pics = lib.coverCandidates(boardId)
        MbSheetFrame(title: t.t("mb.coverTitle"), sub: t.t("mb.coverSub"), node: "mbs.cover", full: pics.count > 5) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                Button { app.mbSetCover(nil, of: boardId) } label: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pal.sheet)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            MbImageMark().stroke(pal.ink5, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                .frame(width: 28, height: 28)
                        }
                        .overlay(alignment: .topTrailing) { if cur == nil { tick(pal) } }
                }
                .buttonStyle(.plain).shotNode("mbs.cover.auto", text: cur == nil ? "on" : "off")
                ForEach(pics, id: \.id) { f in
                    Button { app.mbSetCover(f.id, of: boardId) } label: {
                        RefPicture(frame: f, images: app.refImages, pal: pal, radius: 10).aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .topTrailing) { if cur == f.id { tick(pal) } }
                    }
                    .buttonStyle(.plain).shotNode("mbs.cover.\(f.id)")
                }
            }
        }
    }

    private func tick(_ pal: Palette) -> some View {
        Icon("check", size: 13, line: 2).foregroundStyle(pal.onBrass)
            .frame(width: 22, height: 22).background(Circle().fill(pal.brass))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1).padding(7)
    }
}

// MARK: - Карточка подборки (`#mbBoardSheet`)

/// Название, «N кадров · все только здесь», «Отмена» и терракотовое «Удалить подборку»: одно окно вместо двух.
private struct MbBoardSheet: View {
    @Bindable var app: AppModel
    let boardId: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = app.lexicon
        let pal = Palette(scheme)
        if let b = app.mbLibrary().board(boardId) {
            MbSheetFrame(title: app.mbBoardTitle(b), sub: app.mbBoardCardSub(b), node: "mbs.board") {
                HStack(spacing: 10) {
                    Button { app.mb.sheet = nil } label: {
                        Text(t.t("ask.cancel")).font(webFont(14)).foregroundStyle(pal.ink4)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet))
                    }
                    .buttonStyle(.plain).shotNode("mbs.board.cancel")
                    Button { app.mbConfirmDelete(boardId) } label: {
                        Text(t.t("mb.delBoard")).font(webFont(15)).foregroundStyle(Color(hex: 0xB9603D))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet))
                    }
                    .buttonStyle(.plain).shotNode("mbs.board.delete")
                }
            }
        } else { Color.clear.onAppear { app.mb.sheet = nil } }
    }
}

// MARK: - Лист кадра (`#mbItemSheet`)

private struct MbItemSheet: View {
    @Bindable var app: AppModel
    let shot: String
    let board: String
    let overView: Bool
    @State private var typed = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let t = app.lexicon
        let pal = Palette(scheme)
        let lib = app.mbLibrary()
        if let f = lib.shot(shot), let b = lib.board(board) {
            let genre = app.mbSheetGenre(b)
            let words = MbSheets.itemTags(f, genre: genre)
            MbSheetFrame(title: t.t("mb.freeTags"), node: "mbs.item") {
                FlowLayout(spacing: 7) {
                    ForEach(words, id: \.self) { w in
                        let on = MbSheets.hasTag(f, w)
                        Button { app.mbToggleTag(w, on: shot) } label: {
                            Text(app.mbTagName(w)).font(webFont(13)).foregroundStyle(on ? pal.onBrass : pal.ink3)
                                .padding(.horizontal, 13).frame(height: 34)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? pal.brass : .clear))
                                .overlay { if !on { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(pal.press, lineWidth: 1) } }
                        }
                        .buttonStyle(.plain).shotNode("mbs.tag.\(w)", text: on ? "on" : "off")
                    }
                }
                typedField(pal, t)
                FormGroup {
                    if !overView || f.kind == .link { open(f, pal, t) }
                    if let g = app.mbItemToGenreTarget(b) {
                        MbRow(title: t.t("mb.moveTo", ["genre": app.mbGenreName(g).lowercased()]), node: "mbs.item.toGenre") {
                            app.mbItemToGenre(shot: shot, genre: g)
                        }
                    }
                }
                .padding(.top, 14)
                Button { app.mbItemRemove(shot: shot, board: board) } label: {
                    Text(t.t("mb.remove")).font(webFont(15)).foregroundStyle(Color(hex: 0xB9603D))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet))
                }
                .buttonStyle(.plain).padding(.top, 14).shotNode("mbs.item.remove")
            }
        } else { Color.clear.onAppear { app.mb.sheet = nil } }
    }

    /// «Свой тег» и круглое «+» справа; три двери в одну запись — «+», ввод и уход из поля (веб `mbAddTypedTag`).
    private func typedField(_ pal: Palette, _ t: Lexicon) -> some View {
        HStack(spacing: 8) {
            TextField("", text: $typed, prompt: Text(t.t("mb.addTagPh")).foregroundStyle(pal.ink8))
                .font(.system(size: 16)).foregroundStyle(pal.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused).submitLabel(.done).onSubmit(commit)
                .shotNode("mbs.tagInput")
            Button(action: commit) {
                Icon("plus", size: 18, line: 2).foregroundStyle(pal.onBrass)
                    .frame(width: 34, height: 34).background(Circle().fill(pal.brass))
            }
            .buttonStyle(.plain).shotNode("mbs.tagAdd")
        }
        .padding(.leading, 15).padding(.trailing, 6).frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet))
        .padding(.top, 14)
        .onChange(of: focused) { _, on in if !on { commit() } }
    }

    private func commit() {
        let v = typed
        typed = ""
        if !v.trimmingCharacters(in: .whitespaces).isEmpty { app.mbAddTypedTag(v, to: shot) }
    }

    @ViewBuilder private func open(_ f: RefFrame, _ pal: Palette, _ t: Lexicon) -> some View {
        MbRow(title: t.t(f.kind == .link ? "mb.openLink" : "mb.viewPhoto"), node: "mbs.item.open") {
            app.mb.sheet = nil
            if f.kind == .link { if let u = f.url.flatMap(URL.init(string:)), u.scheme != nil { openURL(u) } }
            else { app.mbOpenViewer(shot) }
        }
    }
}

/// Знак «Автоматически»: горка и солнце в сетке 24 (веб `M4 16l4.5-4.5 3 3L18 8l2 2` и круг r 1,6 в (8, 8)).
struct MbImageMark: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 4 * k, y: 16 * k)); p.addLine(to: CGPoint(x: 8.5 * k, y: 11.5 * k))
        p.addLine(to: CGPoint(x: 11.5 * k, y: 14.5 * k)); p.addLine(to: CGPoint(x: 18 * k, y: 8 * k))
        p.addLine(to: CGPoint(x: 20 * k, y: 10 * k))
        p.addEllipse(in: CGRect(x: 6.4 * k, y: 6.4 * k, width: 3.2 * k, height: 3.2 * k))
        return p
    }
}
