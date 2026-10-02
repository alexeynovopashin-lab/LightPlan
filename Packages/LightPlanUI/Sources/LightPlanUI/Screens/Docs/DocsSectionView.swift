import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Раздел «Документов» (итерация 28д, шаг 3а; справка § 3)

/// Содержимое одного раздела. Область и группы задаёт раздел, три вида (список · таблица · по месяцам)
/// и их выбор — как в 12б, один на все разделы. «Требуют внимания» и «Корзина» — не полка бумаг:
/// у них свои строки и нет переключателя видов. Поиск (шаг 3б) идёт по всей полке и подменяет
/// содержимое раздела результатами. Корзина: «Вернуть», «Удалить навсегда» и «Очистить корзину» с вопросом (шаг 4).
struct DocsSectionView: View {
    @Bindable var app: AppModel
    let section: DocSection
    @Environment(\.colorScheme) private var scheme

    private var t: Lexicon { app.lexicon }
    private var isShelf: Bool { section != .attention && section != .bin }

    var body: some View {
        let pal = Palette(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: t.t("doc.stripTitle"), node: "docs.sec.back") {
                    app.closeDocSection()
                }
                HStack(spacing: 12) {
                    Text(app.docSectionTitle(section)).font(webFont(26, 650)).tracking(-0.4).foregroundStyle(pal.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if isShelf { DocPlusButton(app: app) }
                }
                .padding(.top, 10)
                if section != .bin { DocsSearchField(app: app).padding(.top, 14) }
                if app.docSearching && section != .bin { DocsResults(app: app) } else { content(pal) }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(pal.surface.ignoresSafeArea())
        .shotNode("docs.section", text: section.rawValue)
    }

    @ViewBuilder private func content(_ pal: Palette) -> some View {
        switch section {
        case .attention: attention(pal)
        case .bin: bin(pal)
        default: shelf(pal)
        }
    }

    // MARK: пустое

    /// Плашка вместо одинокой строки «пока пусто»: знак раздела и слово.
    private func emptyPlate(_ icon: String, _ key: String, _ pal: Palette) -> some View {
        VStack(spacing: 12) {
            Icon(icon, size: 24, line: 1.6).foregroundStyle(pal.ink5)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.press))
            Text(t.t(key)).font(.system(size: 14)).foregroundStyle(pal.ink3).lineSpacing(5).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
        .padding(.top, 18)
        .shotNode("docs.empty", text: section.rawValue)
    }

    // MARK: «Требуют внимания»

    /// Не бумаги, а съёмки: группы по самой срочной причине, строка — «дата · жанр · клиент», вторая
    /// причина словом, справа срок. Тап открывает карточку съёмки.
    @ViewBuilder private func attention(_ pal: Palette) -> some View {
        let groups = DocAttention.groups(app.docAttention())
        if groups.isEmpty {
            emptyPlate("check", "doc.emptyAttn", pal)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.reason) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(app.docReasonWord(g.reason)).font(webFont(14.5, 500)).foregroundStyle(pal.ink).lineLimit(1)
                            Text("· \(g.items.count)").font(webFont(12)).foregroundStyle(pal.ink6)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 30)
                        ForEach(Array(g.items.enumerated()), id: \.element.session.id) { i, item in attentionRow(item, i, g.reason, pal) }
                    }
                }
            }
            .padding(.top, 14)
        }
    }

    private func attentionRow(_ item: DocAttention.Item, _ i: Int, _ group: DocAttention.Reason, _ pal: Palette) -> some View {
        let more = item.reasons.filter { $0 != group }.map(app.docReasonWord).joined(separator: " · ")
        return Button {
            withAnimation(overlaySlide) { app.openCard(id: item.session.id) }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.docSessionTitle(item.session)).font(webFont(14)).foregroundStyle(pal.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !more.isEmpty {
                        Text(more).font(webFont(12)).foregroundStyle(pal.brassDeep).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Text(app.docAttentionTiming(item)).font(webFont(11.5)).foregroundStyle(pal.ink6).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 7).frame(minHeight: 41)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("docs.attn.\(group.rawValue).\(i)", text: item.session.id)
    }

    // MARK: «Корзина»

    /// Удалённые бумаги по `deletedAt`, новые сверху: строка «вид · название · удалена 28 сен» и под ней
    /// «Вернуть» и «Удалить навсегда» (с вопросом). Внизу — «Очистить корзину» (с вопросом).
    @ViewBuilder private func bin(_ pal: Palette) -> some View {
        let rows = app.docBinRows()
        if rows.isEmpty {
            emptyPlate("trash", "doc.emptyBin", pal)
        } else {
            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.element.trashed.doc.id) { i, x in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text(x.row.kindLabel).font(webFont(11)).tracking(0.2)
                                .foregroundStyle(pal.brass).fixedSize(horizontal: false, vertical: true).frame(width: 72, alignment: .leading)
                            Text(x.row.title).font(webFont(14)).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Text(app.docDeletedText(x.trashed)).font(webFont(11.5)).foregroundStyle(pal.ink6).lineLimit(1)
                        }
                        HStack(spacing: 18) {
                            binAction(t.t("doc.binRestore"), "docs.binRestore.\(i)", pal.brass) { withAnimation(.easeOut(duration: 0.2)) { app.restoreDoc(x.trashed.doc.id) } }
                            binAction(t.t("doc.binForever"), "docs.binForever.\(i)", pal.badInk) { app.askPurgeDoc(x.trashed.doc.id) }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 82)
                    }
                    .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 2).frame(minHeight: 41)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
                    .shotNode("docs.binRow.\(i)", text: x.row.title)
                }
            }
            .padding(.top, 18)
            Button { app.askClearDocBin() } label: {
                Text(t.t("doc.binClear")).font(webFont(14.5, 500)).foregroundStyle(pal.badInk)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, 14).shotNode("docs.binClear")
            .alert(app.docsNav.binAsk == .clear ? t.t("doc.binClear") : t.t("doc.binForever"),
                   isPresented: Binding(get: { app.docsNav.binAsk != nil }, set: { if !$0 { app.cancelBinAsk() } })) {
                Button(app.docsNav.binAsk == .clear ? t.t("doc.binClear") : t.t("doc.binForever"), role: .destructive) { app.confirmBinAsk() }
                Button(t.t("ask.cancel"), role: .cancel) { app.cancelBinAsk() }
            } message: { Text(t.t(app.docsNav.binAsk == .clear ? "doc.binClearAsk" : "doc.binForeverAsk")) }
        }
    }

    private func binAction(_ title: String, _ node: String, _ color: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title).font(webFont(12.5, 500)).foregroundStyle(color).frame(minHeight: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).shotNode(node)
    }

    // MARK: полка бумаг

    @ViewBuilder private func shelf(_ pal: Palette) -> some View {
        let area = app.docArea(section)
        let chips = OrgBook.shelfKinds(area, practice: app.dealPractice, selected: app.org.shelfKind)
        if area.isEmpty {
            emptyPlate(AppModel.docSectionIcon(section), app.docEmptyKey(section), pal)
        } else {
            DocLayoutSwitch(app: app).padding(.top, 14)
            if !chips.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(chips, id: \.kind) { c in kindChip(c.kind, c.count, pal) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            }
            switch app.org.docs.layout {
            case .list: list(pal)
            case .table:
                DocTable(app: app, rows: app.docTableRows(for: section), sortable: section != .recent).padding(.top, 14)
            case .months:
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(app.docMonths(for: section), id: \.id) { g in DocMonth(app: app, group: g) }
                }
                .padding(.top, 16)
            }
        }
    }

    /// Вид «список»: у разделов с группами — группы (сворачиваются); «По съёмкам» — группа на съёмку;
    /// «Недавние» и «Мои» — плоско.
    @ViewBuilder private func list(_ pal: Palette) -> some View {
        let sortable = section != .recent
        if section == .bySession {
            VStack(spacing: 8) {
                ForEach(app.docSessionGroups(), id: \.id) { g in
                    group(id: "s:" + g.id, label: g.title, rows: g.rows, pal)
                }
            }
            .padding(.top, 14)
        } else if app.docGrouping(of: section) != nil {
            DocColumnHeads(app: app, sortable: true).padding(.top, 10)
            VStack(spacing: 8) {
                ForEach(app.docGroups(for: section), id: \.id) { g in group(id: g.id, label: g.label, rows: g.rows, pal) }
            }
            .padding(.top, 6)
        } else {
            DocColumnHeads(app: app, sortable: sortable).padding(.top, 10)
            VStack(spacing: 6) {
                ForEach(Array(app.docFlatRows(for: section).enumerated()), id: \.offset) { i, r in DocRow(app: app, row: r, index: i) }
            }
            .padding(.top, 6)
        }
    }

    /// Группа как в Finder: «▸ Название · N бумаг»; тап сворачивает и разворачивает.
    @ViewBuilder private func group(id: String, label: String, rows: [DocShelf.Row], _ pal: Palette) -> some View {
        let open = !app.org.docs.collapsed.contains(id)
        Button { withAnimation(.easeOut(duration: 0.18)) { app.editDocsPrefs { $0.toggleGroup(id) } } } label: {
            HStack(spacing: 8) {
                Icon("chevron", size: 13, line: 2.4).foregroundStyle(pal.ink4)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 16)
                Text(label).font(webFont(14.5, 500)).foregroundStyle(pal.ink).lineLimit(1)
                Text("· " + t.count("unit.doc", rows.count)).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("docs.group." + id, text: (open ? "open " : "closed ") + String(rows.count))
        if open {
            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in DocRow(app: app, row: r, index: i) }
            }
        }
    }

    // MARK: чипы и строка

    private func kindChip(_ k: DocKind, _ n: Int, _ pal: Palette) -> some View {
        let on = app.org.shelfKind == k
        return Button { app.org.shelfKind = on ? nil : k } label: {
            HStack(spacing: 5) {
                Text(app.docKindName(k)).font(webFont(13)).foregroundStyle(on ? pal.onBrass : pal.ink3)
                Text("\(n)").font(webFont(13)).foregroundStyle(on ? pal.onBrass.opacity(0.6) : pal.ink6)
            }
            .padding(.horizontal, 13).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? pal.brass : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? pal.brass : pal.press, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .shotNode("docs.kind." + k.rawValue, text: "\(n)")
    }
}
