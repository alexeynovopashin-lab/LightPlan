import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import LightPlanCore
import LightPlanDomain

// MARK: - Опросник клиенту: строка карточки и лист (итерация 28, шаг 9)

/// Знак QR системным генератором: матрица модулей, уровень M, как у `qr.js` беты.
enum QuestQR {
    /// Модулей вокруг знака: белое поле входит в стандарт, читалка без него не находит знак.
    static let quiet = 4

    /// Матрица модулей (`true` — тёмный); `nil` — генератор не справился (лист тогда оставляет ссылку без знака).
    static func matrix(_ text: String) -> [[Bool]]? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let img = f.outputImage else { return nil }
        let w = Int(img.extent.width), h = Int(img.extent.height)
        guard w > 0, w == h, let cg = CIContext().createCGImage(img, from: img.extent) else { return nil }
        var px = [UInt8](repeating: 255, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (0..<h).map { y in (0..<w).map { x in px[y * w + x] < 128 } }
    }
}

/// Знак на белой карточке 260×260: поля 14, знак 232, белый и в тёмной теме.
struct QuestQRView: View {
    let modules: [[Bool]]

    var body: some View {
        let n = modules.count, span = n + 2 * QuestQR.quiet
        Canvas { ctx, size in
            let m = size.width / CGFloat(span)
            for (y, row) in modules.enumerated() {
                for (x, on) in row.enumerated() where on {
                    // Чуть шире модуля, чтобы между соседними не оставалось волосяной щели.
                    ctx.fill(Path(CGRect(x: CGFloat(x + QuestQR.quiet) * m, y: CGFloat(y + QuestQR.quiet) * m,
                                         width: m + 0.5, height: m + 0.5)), with: .color(.black))
                }
            }
        }
        .frame(width: 232, height: 232)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Строка на карточке (`#cdQuestWrap`)

/// Плитка `--sheet-3`, радиус 14, под блоками, зазор 12; крестик 22×22 справа, в режиме перестановки — тумблер.
struct CardQuestRow: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette

    var body: some View {
        let tuning = app.cardTuning
        if tuning ? QuestFlow.fits(s, phase: phase) : app.questRowShown(s, phase: phase) {
            let words = app.questRowWords(s)
            let sent = s.questSent != nil
            HStack(spacing: 4) {
                Button { app.openQuest(for: s) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(words.title).font(webFont(15, sent ? 500 : 600)).foregroundStyle(sent ? pal.ink3 : pal.brass)
                        Text(words.sub).font(webFont(12)).foregroundStyle(pal.ink4)
                    }
                    .padding(.horizontal, 15).padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressFade())
                .opacity(tuning && s.questOff ? 0.4 : 1)
                .disabled(tuning)
                .shotNode("card.quest.row", text: words.title)
                if tuning {
                    Toggle("", isOn: Binding(get: { !s.questOff }, set: { app.setQuestOff(!$0, for: s) }))
                        .labelsHidden().tint(pal.brass).scaleEffect(0.784).frame(width: 49, height: 22)
                        .shotNode("card.quest.toggle", text: s.questOff ? "off" : "on")
                } else {
                    Button { app.setQuestOff(true, for: s) } label: {
                        Path { p in
                            p.move(to: CGPoint(x: 7.5, y: 7.5)); p.addLine(to: CGPoint(x: 16.5, y: 16.5))
                            p.move(to: CGPoint(x: 16.5, y: 7.5)); p.addLine(to: CGPoint(x: 7.5, y: 16.5))
                        }
                        .stroke(pal.sheet, style: StrokeStyle(lineWidth: 2.4 * 15 / 24, lineCap: .round))
                        .frame(width: 24, height: 24)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(pal.ink8))
                    }
                    .buttonStyle(PressFade())
                    .accessibilityLabel(app.lexicon.t("quest.off"))
                    .shotNode("card.quest.off")
                }
            }
            .padding(.trailing, 12)
            .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 12)
            .shotNode("card.quest")
        }
    }
}

// MARK: - Лист (`#qSheet`)

extension View {
    /// Лист опросника поверх любого экрана (`RootView`): открыт, пока `app.quest.isOpen`.
    func questSheet(_ app: AppModel) -> some View {
        sheet(isPresented: Binding(get: { app.quest.isOpen }, set: { if !$0 { app.closeQuest() } })) {
            QuestSheet(app: app)
        }
    }
}

struct QuestSheet: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var pasting: Bool

    var body: some View {
        let pal = Palette(scheme), t = app.lexicon
        let url = app.questURL()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(pal.edge).frame(width: 38, height: 4).frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 18)
                Text(t.t("quest.title")).font(webFont(19, 650)).tracking(-0.2).foregroundStyle(pal.ink)
                    .shotNode("quest.title", text: t.t("quest.title"))
                Text(t.t("quest.sub")).font(webFont(13)).foregroundStyle(pal.ink4).padding(.top, 5)
                    .fixedSize(horizontal: false, vertical: true)
                if let url, let m = QuestQR.matrix(url.absoluteString) {
                    QuestQRView(modules: m).frame(maxWidth: .infinity).padding(.top, 16)
                        .shotNode("quest.qr", text: "\(m.count)")
                }
                send(pal, url).padding(.top, 16)
                if app.quest.copied {
                    Text(t.t("quest.copiedTitle") + ". " + t.t("quest.copiedText")).font(webFont(12)).foregroundStyle(pal.ink4)
                        .padding(.top, 8).fixedSize(horizontal: false, vertical: true).shotNode("quest.copied")
                }
                FormGroupLabel(text: t.t("quest.pasteTitle")).padding(.top, -8)
                paste(pal)
                Button { pasting = false; app.applyPastedQuest() } label: {
                    Text(t.t("quest.pasteBtn")).font(webFont(16, 650)).foregroundStyle(pal.onBrass)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(pal.brass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressFade()).padding(.top, 10).shotNode("quest.apply")
                Button { app.closeQuest() } label: {
                    Text(t.t("pick.done")).font(webFont(14)).foregroundStyle(pal.ink4)
                        .frame(maxWidth: .infinity, minHeight: 45).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.top, 10).shotNode("quest.done")
            }
            .padding(.horizontal, 24).padding(.bottom, 34)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .shotNode("quest.sheet")
    }

    /// «Отправить ссылку»: системный лист, адрес полем `url` (AirDrop отдаёт страницу, а не текст), подпись отдельно.
    /// Долгое нажатие — запасной путь, ссылка в буфер.
    @ViewBuilder private func send(_ pal: Palette, _ url: URL?) -> some View {
        let label = Text(app.lexicon.t("quest.sendLink")).font(webFont(16, 650)).foregroundStyle(pal.onBrass)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(pal.brass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        if let url {
            ShareLink(item: url, message: Text(app.lexicon.t("quest.shareCaption"))) { label }
                .buttonStyle(PressFade())
                .simultaneousGesture(TapGesture().onEnded { if let id = app.quest.recordId { app.markQuestSent(id) } })
                .contextMenu { Button(app.lexicon.t("quest.copiedTitle")) { app.copyQuestLink() } }
                .shotNode("quest.send")
        }
    }

    /// Поле вставки с рамкой (в вебе рамки нет — ошибка А1). Под ним — что не так с вставленным.
    private func paste(_ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(app.lexicon.t("quest.pastePh"), text: $app.quest.paste, axis: .vertical)
                .lineLimit(2...5).font(webFont(16)).foregroundStyle(pal.ink)
                .focused($pasting).autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(pasting ? pal.brass : pal.edge, lineWidth: 1))
                .onChange(of: app.quest.paste) { _, _ in app.quest.message = nil }
                .shotNode("quest.paste")
            if let m = app.quest.message {
                Text(m).font(webFont(12.5)).foregroundStyle(pal.warnInk).fixedSize(horizontal: false, vertical: true)
                    .shotNode("quest.message", text: m)
            }
        }
    }
}
