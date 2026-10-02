import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Экран отдельной бумаги (итерация 28д, шаг 3б; справка § 2.3 и 6.2)

/// Что за бумага: вид, название, дата, к чему привязана (съёмка, организация, реквизиты или «Мои»);
/// у бумаги съёмки — её звено в цепочке сделки (тот же блок, что в карточке съёмки). Ссылка
/// открывается в браузере, файл без облака — сообщением (облако — итерация 30). «Править» открывает лист
/// бумаги (вид, название, ссылка, день, привязка), «Удалить» уводит её в корзину документов (шаг 4;
/// у реквизитов-файла правки нет). Каркас как у раздела: поля 24, сверху 14, снизу 34, фон `surface`.
struct DocPaperScreen: View {
    @Bindable var app: AppModel
    let doc: OrgBook.ShelfDoc
    let backTitle: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        let p = app.docPaper(doc)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: backTitle, node: "docs.paper.back") {
                    withAnimation(overlaySlide) { app.closeDocPaper() }
                }
                Text(p.headline).font(webFont(26, 650)).tracking(-0.4).foregroundStyle(pal.ink)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    .accessibilityAddTraits(.isHeader).shotNode("docs.paper.title", text: p.headline)
                facts(p, pal).padding(.top, 18)
                if let step = p.step { stepLine(step, pal).padding(.top, 14) }
                if p.deal != nil, let sid = p.sessionId, let s = app.docLibrary.sessions.first(where: { $0.id == sid }) {
                    CardDealBlock(app: app, s: s, pal: pal)
                }
                actions(p, pal).padding(.top, 18)
                if let note = app.docsNav.paperNote {
                    Text(note).font(.system(size: 12)).foregroundStyle(pal.ink4).lineSpacing(5).padding(.top, 10)
                        .shotNode("docs.paper.note", text: note)
                }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(pal.surface.ignoresSafeArea())
        .shotNode("docs.paper", text: p.row.title)
    }

    // MARK: факты

    /// Плитка из строк «подпись — значение»: вид, дата, привязка, источник.
    private func facts(_ p: AppModel.DocPaper, _ pal: Palette) -> some View {
        let date = p.row.dateText ?? t.t("doc.noDate")
        var rows: [(id: String, key: String, value: String)] = [
            ("kind", t.t("doc.colKind"), p.row.kindLabel),
            ("date", t.t("doc.colDate"), date),
            ("owner", t.t("doc.paperOwner"), ownerValue(p)),
        ]
        rows.append(("source", t.t("doc.paperSource"), source(p)))
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.key).font(webFont(11)).tracking(0.2).foregroundStyle(pal.ink6)
                    Text(r.value).font(webFont(14)).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .shotNode("docs.paper.\(r.id)", text: r.value)
                if i < rows.count - 1 { Rectangle().fill(pal.hairline).frame(height: 1).padding(.leading, 14) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.sheet))
    }

    /// «Съёмка · 5 окт · Портрет · Иванова», «Организация · Название», «Мои».
    private func ownerValue(_ p: AppModel.DocPaper) -> String {
        switch p.owner {
        case .session: [t.t("doc.ownerSession"), p.ownerText].filter { !$0.isEmpty }.joined(separator: " · ")
        case .org: [t.t("doc.ownerOrg"), p.ownerText].filter { !$0.isEmpty }.joined(separator: " · ")
        case .requisites: [t.t("doc.ownerReq"), p.ownerText].filter { !$0.isEmpty }.joined(separator: " · ")
        case .mine: t.t("doc.secMine")
        }
    }

    private func source(_ p: AppModel.DocPaper) -> String {
        if doc.doc.source == .link {
            if doc.doc.url == nil { return t.t("doc.srcNone") }
            let host = DocLabel.host(doc.doc.url ?? "")
            return host.isEmpty ? t.t("doc.srcLinkBare") : t.t("doc.srcLink", ["host": host])
        }
        let name = doc.doc.name ?? ""
        return name.isEmpty ? t.t("doc.file") : t.t("doc.srcFile", ["name": name])
    }

    // MARK: сделка

    /// «Закрывает звено сделки: Договор».
    private func stepLine(_ step: DealStep, _ pal: Palette) -> some View {
        let text = t.t("doc.paperStep", ["step": t.t("dealN." + step.rawValue)])
        return Text(text).font(webFont(13)).foregroundStyle(pal.ink3).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .shotNode("docs.paper.step", text: step.rawValue)
    }

    // MARK: действия

    @ViewBuilder private func actions(_ p: AppModel.DocPaper, _ pal: Palette) -> some View {
        VStack(spacing: 8) {
            if p.url != nil || doc.doc.source != .link {
                button(t.t("doc.paperOpen"), "docs.paper.open", pal) {
                    if let u = p.url { app.docsNav.paperNote = nil; openURL(u) } else { app.noteDocNotOpened() }
                }
            }
            if p.owner != .requisites {
                button(t.t("doc.paperEdit"), "docs.paper.edit", pal) { app.openDocEdit(doc.doc.id) }
            }
            if let sid = p.sessionId {
                button(t.t("doc.paperOpenShoot"), "docs.paper.shoot", pal) {
                    withAnimation(overlaySlide) { app.openCard(id: sid) }
                }
            }
            Button { withAnimation(overlaySlide) { app.trashDoc(doc.doc.id) } } label: {
                Text(t.t("doc.paperDelete")).font(webFont(14.5, 500)).foregroundStyle(pal.badInk)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, 10).shotNode("docs.paper.delete")
        }
    }

    private func button(_ title: String, _ node: String, _ pal: Palette, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 12) {
                Text(title).font(webFont(14.5, 500)).foregroundStyle(pal.ink).lineLimit(1)
                Spacer(minLength: 0)
                Icon("chevron", size: 13, line: 2.4).foregroundStyle(pal.ink4)
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode(node)
    }
}
