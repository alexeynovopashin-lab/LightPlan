import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Корзина мудборда съёмки (итерация 29б)

/// Экран корзины — лист мудборда: строка «Самоочистка» (выбор срока), список убранных кадров с «Вернуть»,
/// «Очистить корзину». Круг стирания выезжает здесь же (`BinFlight.Host.mbBin`): лист закрывает оболочку.
/// Настройка живёт на самом экране корзины, а не в меню подборки: меню меняет вид папки (порядок, обложка),
/// а срок касается только корзины — рядом с тем, чего он касается.
struct MbBinSheet: View {
    @Bindable var app: AppModel
    let boardId: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = app.lexicon
        let pal = Palette(scheme)
        let lib = app.mbLibrary()
        if let b = lib.board(boardId), b.kind == .shoot {
            let list = lib.binned(boardId)
            MbSheetFrame(title: t.t("card.bin"), sub: t.t("mb.binSub"), node: "mbs.bin", full: list.count > 3) {
                FormGroup {
                    MbRow(title: t.t("mb.binAuto"), sub: app.mbBinModeTitle(b.effectiveBinMode), node: "mbs.bin.mode") {
                        app.mb.sheet = .binMode(boardId)
                    }
                }
                if list.isEmpty {
                    Text(t.t("bin.empty")).font(webFont(14)).foregroundStyle(pal.ink6)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2).padding(.top, 16)
                        .shotNode("mbs.bin.empty")
                } else {
                    FormGroup {
                        ForEach(list, id: \.id) { e in row(e, lib, b, pal) }
                    }
                    .padding(.top, 12)
                    FormGroup {
                        MbRow(title: t.t("bin.clear"), danger: true, node: "mbs.bin.clear") {
                            app.mb.sheet = .binClear(board: boardId, shots: list.map(\.id))
                        }
                    }
                    .padding(.top, 12)
                }
                MbCancel(app: app, key: "card.close")
            }
            .overlay { BinTarget(flight: app.binFlight, host: .mbBin, lift: 24) }
        } else { Color.clear.onAppear { app.mb.sheet = nil } }
    }

    /// Кадр 48×48, «уйдёт через …», слова кадра или адрес ссылки и «Вернуть» справа.
    private func row(_ e: RefBinned, _ lib: RefLibrary, _ b: RefBoard, _ pal: Palette) -> some View {
        let t = app.lexicon
        let frame = lib.shot(e.id)
        let words = frame.map { f -> String in
            if f.kind == .link, let u = f.url { return RefLink.host(u) ?? u }
            return f.tags.map(app.mbTagName).joined(separator: ", ")
        } ?? ""
        let left = app.mbBinLeftText(lib.binLeft(e, in: b, now: Double(app.nowMs)))
        return HStack(spacing: 12) {
            RefPicture(frame: frame, images: app.refImages, pal: pal, radius: 9)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(left).font(webFont(15)).foregroundStyle(pal.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if !words.isEmpty { Text(words).font(webFont(13)).foregroundStyle(pal.ink4).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Button { app.mbBinRestore([e.id], into: b.id) } label: {
                Text(t.t("mb.binBack")).font(webFont(14, 600)).foregroundStyle(pal.brass)
                    .padding(.horizontal, 12).frame(minHeight: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain).shotNode("mbs.bin.back.\(e.id)", text: e.id)
        }
        .padding(.horizontal, 15).padding(.vertical, 8).frame(minHeight: 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .binSubject(app, "binframe." + e.id)
    }
}

/// «Самоочистка»: четыре режима галочкой, как «Порядок» в меню папки.
struct MbBinModeSheet: View {
    @Bindable var app: AppModel
    let boardId: String
    var body: some View {
        let t = app.lexicon
        let cur = app.mbLibrary().board(boardId)?.effectiveBinMode ?? .standard
        MbSheetFrame(title: t.t("mb.binAuto"), node: "mbs.binMode") {
            FormGroup {
                ForEach(RefBinMode.allCases, id: \.self) { m in
                    MbRow(title: app.mbBinModeTitle(m), on: cur == m, node: "mbs.binMode.\(m.rawValue)") {
                        app.mbSetBinMode(m, of: boardId)
                    }
                }
            }
            MbCancel(app: app, back: .bin(boardId))
        }
    }
}

/// Вопрос «Очистить корзину»: список кадров зафиксирован в момент вопроса (`shots`), стирается он же, а не
/// то, что окажется в корзине за время полёта. Движение и звук — как на любом стирании (29.7).
struct MbBinClearSheet: View {
    @Bindable var app: AppModel
    let boardId: String
    let shots: [String]
    var body: some View {
        let t = app.lexicon
        AskYesSheet(title: t.t("bin.clear"),
                    sub: t.t("bin.wipeAsk", ["n": t.count("unit.frame", shots.count)]),
                    ok: t.t("ask.wipe"), cancel: t.t("ask.cancel")) { yes in
            guard yes else { app.mb.sheet = .bin(boardId); return }
            let ids = shots
            app.mb.sheet = .bin(boardId)
            app.flyToBin(Set(ids.map { "binframe." + $0 }), host: .mbBin) { app.mbBinPurge(ids, of: boardId) }
        }
    }
}
