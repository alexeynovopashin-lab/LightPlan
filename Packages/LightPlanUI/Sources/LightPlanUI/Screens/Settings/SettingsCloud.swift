import SwiftUI
import LightPlanData

/// Раздел «Облако» главы «Данные и облако» (31.1) — порт `#cloudSeg` веба с нативной ролью облака: копия туда и
/// обратно по кнопке, а не хранилище. Сегмент «Выкл / Яндекс / Google / Dropbox»; работает Яндекс, Google и Dropbox
/// честно «скоро». Подключено — строки «Подключение» и «Последняя выгрузка», кнопки «Сохранить копию на Диск»,
/// «Восстановить из облака», «Отключить облако»; под ними — строка хода работы или итога.
struct CloudSection: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let t = app.lexicon
        let pal = Palette(colorScheme)
        let c = app.cloud
        SecLabel(text: t.t("cloud.title"), node: "sec.cloud")
        WebSeg(options: [(t.t("set.off"), CloudChoice.off), (t.t("cloud.name.yandex"), .kind(.yandex)),
                         (t.t("cloud.name.google"), .kind(.google)), (t.t("cloud.name.dropbox"), .kind(.dropbox))],
               selection: Binding(get: { CloudChoice(app.cloudSegment) }, set: { app.pickCloud($0.kind) }),
               nodes: ["cloud.off", "cloud.yandex", "cloud.google", "cloud.dropbox"])
            .padding(.horizontal, 24).padding(.top, 12)
            .disabled(c.busy != nil)
        SetItemRow(icon: nil, title: t.t("cloud.connection"), value: connection(t), chevron: false)
            .shotNode("cloud.state", text: connection(t))
        if c.connected {
            SetItemRow(icon: nil, title: t.t("cloud.lastUpload"),
                       value: c.record.lastUpload.map(app.cloudWhen) ?? t.t("cloud.never"), chevron: false)
                .shotNode("cloud.when")
            Button { app.pushCloud() } label: { Text(t.t("cloud.n.push")) }
                .buttonStyle(DataButtonStyle()).disabled(c.busy != nil).opacity(c.busy != nil ? 0.45 : 1)
                .shotNode("cloud.push", text: t.t("cloud.n.push"))
            Button { app.askRestoreCloud() } label: { Text(t.t("cloud.pull")) }
                .buttonStyle(DataButtonStyle()).disabled(c.busy != nil).opacity(c.busy != nil ? 0.45 : 1)
                .shotNode("cloud.pull", text: t.t("cloud.pull"))
            Button { app.forgetCloud() } label: { Text(t.t("cloud.forget")) }
                .buttonStyle(DataButtonStyle()).disabled(c.busy != nil).opacity(c.busy != nil ? 0.45 : 1)
                .shotNode("cloud.forget", text: t.t("cloud.forget"))
        } else if c.picked == .yandex, c.busy == nil {
            // Вход сорвался — повторить, не перещёлкивая сегмент.
            Button { app.connectCloud() } label: { Text(t.t("cloud.n.connect")) }
                .buttonStyle(DataButtonStyle())
                .shotNode("cloud.connect", text: t.t("cloud.n.connect"))
        }
        if let line = c.line {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if c.busy != nil { ProgressView().controlSize(.mini) }
                Text(line).font(.system(size: 13))
                    .foregroundStyle(c.error ? pal.brassDeep : pal.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24).padding(.top, 12)
            .shotNode("cloud.line", text: line)
        }
        SetNote(text: t.t(c.connected ? "cloud.note.yandex" : "cloud.n.noteOff"), node: "note.cloud")
            .confirmationDialog(c.confirm.map { ask(t, $0) } ?? "", isPresented: Binding(
                get: { app.cloud.confirm != nil }, set: { if !$0 { app.cancelRestoreCloud() } }),
                titleVisibility: .visible) {
                Button(t.t("cloud.n.pullYes"), role: .destructive) { app.restoreCloud() }
                Button(t.t("ask.cancel"), role: .cancel) { app.cancelRestoreCloud() }
            } message: {
                Text(t.t("cloud.n.pullAskNote"))
            }
            .modifier(RestoredCover(shown: app.cloud.restored, text: t.t("cloud.n.restored")))
    }

    private func connection(_ t: Lexicon) -> String {
        guard let kind = app.cloud.record.kind else { return t.t("cloud.off") }
        let name = t.t("cloud.name." + kind.rawValue)
        return app.cloud.record.account.map { name + " · " + $0 } ?? name
    }

    private func ask(_ t: Lexicon, _ item: CloudItem) -> String {
        t.t("cloud.n.pullAsk", ["when": item.modified.map(app.cloudWhen) ?? "—"])
    }
}

/// Значение сегмента: «Выкл» или поставщик.
enum CloudChoice: Hashable {
    case off
    case kind(CloudKind)
    init(_ k: CloudKind?) { self = k.map { .kind($0) } ?? .off }
    var kind: CloudKind? { if case .kind(let k) = self { k } else { nil } }
}

/// Плашка на весь экран (на Mac — лист: `fullScreenCover` там нет).
private struct RestoredCover: ViewModifier {
    let shown: Bool
    let text: String
    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: .constant(shown)) { RestoredPlate(text: text) }
        #else
        content.sheet(isPresented: .constant(shown)) { RestoredPlate(text: text) }
        #endif
    }
}

/// Копия легла в файл данных: дальше — только открыть приложение заново. Закрыть плашку нельзя нарочно: под ней
/// прежние данные, которые приложение уже не запишет.
private struct RestoredPlate: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let pal = Palette(colorScheme)
        VStack(spacing: 18) {
            Icon("cloud", size: 44, line: 1.6).foregroundStyle(pal.brass)
            Text(text).font(.system(size: 17, weight: .medium)).foregroundStyle(pal.ink)
                .multilineTextAlignment(.center)
                .shotNode("cloud.restored", text: text)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pal.surface.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}
