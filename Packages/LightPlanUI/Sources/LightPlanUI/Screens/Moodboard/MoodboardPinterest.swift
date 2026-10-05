import SwiftUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

// MARK: - Pinterest в мудборде (итерация 28м, шаг 3)

/// Лист доски Pinterest: читаем → «Добавить доску?» → «12 из 80» с «Остановить» → итог. Одно состояние
/// (`mb.pin`) на лист и на строку в папке: лист можно закрыть, закачка идёт дальше.
struct MbPinBoardSheet: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = app.lexicon
        if let f = app.mb.pin {
            switch f.phase {
            case .loading:
                MbSheetFrame(title: t.t("pin.boardLoading"), node: "pin.loading") {
                    FormGroup { MbRow(title: t.t("ask.cancel"), node: "pin.cancel") { app.closePinFlow() } }
                }
            case .ask:
                if f.all.isEmpty {
                    MbSheetFrame(title: t.t("pin.boardNothing"), sub: notes(f, t), node: "pin.nothing") {
                        FormGroup { MbRow(title: t.t("mb.pickDone"), node: "pin.ok") { app.closePinFlow() } }
                    }
                } else {
                    AskYesSheet(title: t.t("pin.boardAskTitle", ["name": f.name.isEmpty ? "Pinterest" : f.name]),
                                sub: ([t.t("pin.boardAskSub", ["n": "\(f.all.count)", "size": app.pinMegabytes(f.megabytes)])]
                                      + noteLines(f, t)).joined(separator: "\n"),
                                ok: t.t("pin.boardAdd"), cancel: t.t("ask.cancel")) { yes in
                        if yes { app.confirmPinBoard() } else { app.closePinFlow() }
                    }
                }
            case .running:
                MbSheetFrame(title: t.t("pin.boardProgress", ["done": "\(f.done)", "total": "\(f.all.count)"]),
                             sub: noteLines(f, t).joined(separator: "\n"), node: "pin.running") {
                    PinBar(done: f.done, total: f.all.count)
                    FormGroup { MbRow(title: t.t("pin.boardStop"), danger: true, node: "pin.stop") { app.stopPinImport() } }
                        .padding(.top, 14)
                }
            case .ended:
                MbSheetFrame(title: app.pinEndText(f), sub: noteLines(f, t).joined(separator: "\n"), node: "pin.ended") {
                    FormGroup {
                        if !f.pending.isEmpty { MbRow(title: t.t("pin.retry"), node: "pin.retry") { app.confirmPinBoard() } }
                        MbRow(title: t.t("mb.pickDone"), node: "pin.ok") { app.closePinFlow() }
                    }
                }
            case .failed(let why):
                MbSheetFrame(title: app.pinText(why), node: "pin.failed") {
                    FormGroup {
                        if why != .notConfigured && why != .boardNotFound && why != .badLink {
                            MbRow(title: t.t("pin.retry"), node: "pin.retry") { app.loadPinBoard() }
                        }
                        MbRow(title: t.t("ask.cancel"), node: "pin.cancel") { app.closePinFlow() }
                    }
                }
            }
        } else {
            Color.clear.onAppear { app.mb.sheet = nil }
        }
    }

    private func notes(_ f: PinFlow, _ t: Lexicon) -> String { noteLines(f, t).joined(separator: "\n") }

    /// Честные строки под заголовком: потолок, дубли, на чём встали.
    private func noteLines(_ f: PinFlow, _ t: Lexicon) -> [String] {
        var out: [String] = []
        if f.truncated { out.append(t.t("pin.boardTruncated", ["n": "\(min(f.all.count + f.already, AppModel.pinCeiling))", "total": "\(f.pinCount)"])) }
        if f.already > 0 { out.append(t.t("pin.boardAlready", ["n": "\(f.already)"])) }
        if f.phase == .ended, let why = f.interrupted { out.append(app.pinText(why)) }
        return out
    }
}

private struct PinBar: View {
    let done: Int
    let total: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(pal.press)
                Capsule().fill(pal.brass).frame(width: g.size.width * CGFloat(total > 0 ? min(1, Double(done) / Double(total)) : 0))
            }
        }
        .frame(height: 6).shotNode("pin.bar", text: "\(done)/\(total)")
    }
}

extension AppModel {
    /// Итог: «Добавлено 12 из 80», с «не удалось: K», если были сбои.
    func pinEndText(_ f: PinFlow) -> String {
        var s = lexicon.t("pin.boardDone", ["done": "\(f.added)", "total": "\(f.all.count + f.already)"])
        if f.failed > 0 { s += " · " + lexicon.t("pin.boardFailed", ["n": "\(f.failed)"]) }
        return s
    }
}

/// Строка под кнопками папки: идёт закачка, закачка кончилась, пин остался без превью. Под ней — то, что можно сделать.
struct MbPinStrip: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let flow = app.mb.pin.flatMap { $0.boardId == app.mb.folder && ($0.phase == .running || $0.phase == .ended) ? $0 : nil }
        if app.mb.sheet == .pinBoard && flow != nil {
            EmptyView()
        } else if let f = flow {
            VStack(alignment: .leading, spacing: 7) {
                if f.phase == .running {
                    HStack {
                        Text(t.t("pin.boardProgress", ["done": "\(f.done)", "total": "\(f.all.count)"]))
                            .font(webFont(13)).foregroundStyle(pal.ink3).monospacedDigit()
                        Spacer(minLength: 8)
                        action(t.t("pin.boardStop"), pal, node: "pin.strip.stop") { app.stopPinImport() }
                    }
                    PinBar(done: f.done, total: f.all.count)
                } else {
                    HStack {
                        Text(app.pinEndText(f) + (f.interrupted.map { " · " + app.pinText($0) } ?? ""))
                            .font(webFont(13)).foregroundStyle(pal.ink3).lineLimit(2)
                        Spacer(minLength: 8)
                        if !f.pending.isEmpty { action(t.t("pin.retry"), pal, node: "pin.strip.retry") { app.confirmPinBoard() } }
                        action("✕", pal, node: "pin.strip.close") { app.closePinFlow() }
                    }
                }
            }
            .padding(.top, 12).padding(.horizontal, 15)
            .shotNode("pin.strip", text: "\(f.done)/\(f.all.count)")
        } else if case .failure(let why, let frame)? = app.mb.pinNote {
            HStack {
                Text(app.pinText(why)).font(webFont(13)).foregroundStyle(pal.ink3).lineLimit(2)
                Spacer(minLength: 8)
                if frame != nil, why != .notFound, why != .notConfigured { action(t.t("pin.retry"), pal, node: "pin.note.retry") { app.retryPinNote() } }
                action("✕", pal, node: "pin.note.close") { app.dismissPinNote() }
            }
            .padding(.top, 12).padding(.horizontal, 15)
            .shotNode("pin.note", text: "\(why)")
        } else if case .image(let why, let frame)? = app.mb.pinNote {
            HStack {
                Text(app.imageLinkText(why)).font(webFont(13)).foregroundStyle(pal.ink3).lineLimit(3)
                Spacer(minLength: 8)
                if frame != nil, why == .offline || why == .unreachable || why == .busy { action(t.t("pin.retry"), pal, node: "img.note.retry") { app.retryImageNote() } }
                action("✕", pal, node: "img.note.close") { app.dismissPinNote() }
            }
            .padding(.top, 12).padding(.horizontal, 15)
            .shotNode("img.note", text: "\(why)")
        }
    }

    private func action(_ title: String, _ pal: Palette, node: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Text(title).font(webFont(13, 600)).foregroundStyle(pal.brass)
                .padding(.horizontal, 6).frame(minHeight: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain).shotNode(node, text: title)
    }
}
