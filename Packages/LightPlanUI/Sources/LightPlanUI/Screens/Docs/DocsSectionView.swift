import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Раздел «Документов» (итерация 28д, шаг 3а; справка § 3)

/// Содержимое одного раздела. Область и группы задаёт раздел, три вида (список · таблица · по месяцам)
/// и их выбор — как в 12б, один на все разделы. «Требуют внимания» и «Корзина» — не полка бумаг:
/// у них свои строки и нет переключателя видов. Правка, удаление и возврат из корзины — шаг 3б и дальше.
struct DocsSectionView: View {
    @Bindable var app: AppModel
    let section: DocSection
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var note: String?

    private var t: Lexicon { app.lexicon }
    private var isShelf: Bool { section != .attention && section != .bin }

    var body: some View {
        let pal = Palette(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: t.t("doc.stripTitle"), node: "docs.sec.back") {
                    app.closeDocSection()
                }
                Text(app.docSectionTitle(section)).font(webFont(26, 650)).tracking(-0.4).foregroundStyle(pal.ink)
                    .padding(.top, 10).accessibilityAddTraits(.isHeader)
                content(pal)
                if let note {
                    Text(note).font(.system(size: 12)).foregroundStyle(pal.ink4).lineSpacing(5).padding(.top, 10)
                }
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

    /// Удалённые бумаги по `deletedAt`, новые сверху; вместо даты — «удалена 28 сен». Кнопка «Вернуть»
    /// и лист строки — шаг 3б и дальше.
    @ViewBuilder private func bin(_ pal: Palette) -> some View {
        let rows = app.docBinRows()
        if rows.isEmpty {
            emptyPlate("trash", "doc.emptyBin", pal)
        } else {
            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, x in
                    HStack(spacing: 10) {
                        Text(x.row.kindLabel).font(webFont(11)).tracking(0.2)
                            .foregroundStyle(pal.brass).fixedSize(horizontal: false, vertical: true).frame(width: 72, alignment: .leading)
                        Text(x.row.title).font(webFont(14)).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text(app.docDeletedText(x.trashed)).font(webFont(11.5)).foregroundStyle(pal.ink6).lineLimit(1)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7).frame(minHeight: 41)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
                    .shotNode("docs.binRow.\(i)", text: x.row.title)
                }
            }
            .padding(.top, 18)
        }
    }

    // MARK: полка бумаг

    @ViewBuilder private func shelf(_ pal: Palette) -> some View {
        let area = app.docArea(section)
        let chips = OrgBook.shelfKinds(area, practice: app.dealPractice, selected: app.org.shelfKind)
        if area.isEmpty {
            emptyPlate(AppModel.docSectionIcon(section), app.docEmptyKey(section), pal)
        } else {
            layoutSwitch(pal).padding(.top, 14)
            if !chips.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(chips, id: \.kind) { c in kindChip(c.kind, c.count, pal) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            }
            switch app.org.docs.layout {
            case .list: list(pal)
            case .table:
                table(app.docTableRows(for: section), pal).padding(.top, 14)
            case .months:
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(app.docMonths(for: section), id: \.id) { g in month(g, pal) }
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
            columnHeads(sortable: true, pal).padding(.top, 10)
            VStack(spacing: 8) {
                ForEach(app.docGroups(for: section), id: \.id) { g in group(id: g.id, label: g.label, rows: g.rows, pal) }
            }
            .padding(.top, 6)
        } else {
            columnHeads(sortable: sortable, pal).padding(.top, 10)
            VStack(spacing: 6) {
                ForEach(Array(app.docFlatRows(for: section).enumerated()), id: \.offset) { i, r in docRow(r, i, pal) }
            }
            .padding(.top, 6)
        }
    }

    /// Переключатель видов, как в Finder: три сегмента со знаками; выбранный на `--press`. Вид один
    /// на все разделы и запоминается (`DocsPrefs.layout`).
    private func layoutSwitch(_ pal: Palette) -> some View {
        HStack(spacing: 6) {
            ForEach([(DocsLayout.list, "view_day", "doc.layList"), (.table, "view_month", "doc.layTable"),
                     (.months, "view_week", "doc.layMonths")], id: \.0) { lay, icon, key in
                let on = app.org.docs.layout == lay
                Button { app.editDocsPrefs { $0.layout = lay } } label: {
                    Icon(icon, size: 19, line: 1.6).foregroundStyle(on ? pal.ink : pal.ink4)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? pal.press : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.t(key))
                .shotNode("docs.layout." + lay.rawValue, text: on ? "on" : "off")
            }
        }
    }

    /// Заголовки колонок: «Название» и «Дата» сортируют, тот же тап меняет направление. У «Недавних»
    /// порядок задан временем — заголовки подписи без тапа.
    private func columnHeads(sortable: Bool, _ pal: Palette) -> some View {
        HStack(spacing: 10) {
            Text(t.t("doc.colKind")).font(webFont(11)).foregroundStyle(pal.ink6).frame(width: 72, alignment: .leading)
            head(.title, "doc.title", sortable, pal)
            Spacer(minLength: 0)
            head(.date, "doc.colDate", sortable, pal)
        }
        .padding(.horizontal, 14)
    }

    private func head(_ key: DocSortKey, _ word: String, _ sortable: Bool, _ pal: Palette) -> some View {
        let on = sortable && app.org.docs.sortKey == key
        return Button { app.editDocsPrefs { $0.tapColumn(key) } } label: {
            Text(t.t(word) + (on ? (app.org.docs.ascending ? " ↑" : " ↓") : ""))
                .font(webFont(11, on ? 500 : 400)).foregroundStyle(on ? pal.ink3 : pal.ink6)
                .frame(minHeight: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!sortable)
        .shotNode("docs.sort." + key.rawValue, text: on ? (app.org.docs.ascending ? "asc" : "desc") : "")
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
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in docRow(r, i, pal) }
            }
        }
    }

    // MARK: вид Б — таблица

    /// Колонки на узком экране: «Вид» 54, «Организация» 76, «Дата» 58; «Название» берёт остаток.
    private func table(_ rows: [DocShelf.Row], _ pal: Palette) -> some View {
        let sortable = section != .recent
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                tableHead(.kind, "doc.colKind", sortable, pal).frame(width: 54, alignment: .leading)
                tableHead(.title, "doc.title", sortable, pal).frame(maxWidth: .infinity, alignment: .leading)
                tableHead(.org, "org.one", sortable, pal).frame(width: 76, alignment: .leading)
                tableHead(.date, "doc.colDate", sortable, pal).frame(width: 58, alignment: .leading)
            }
            .padding(.horizontal, 12)
            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in tableRow(r, i, pal) }
            }
            .padding(.top, 4)
        }
    }

    private func tableHead(_ key: DocSortKey, _ word: String, _ sortable: Bool, _ pal: Palette) -> some View {
        let on = sortable && app.org.docs.sortKey == key
        return Button { app.editDocsPrefs { $0.tapColumn(key) } } label: {
            Text(t.t(word) + (on ? (app.org.docs.ascending ? " ↑" : " ↓") : ""))
                .font(webFont(11, on ? 500 : 400)).foregroundStyle(on ? pal.ink3 : pal.ink6)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(minHeight: 30, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!sortable)
        .shotNode("docs.tsort." + key.rawValue, text: on ? (app.org.docs.ascending ? "asc" : "desc") : "")
    }

    private func tableRow(_ r: DocShelf.Row, _ i: Int, _ pal: Palette) -> some View {
        Button { open(r.shelf.doc) } label: {
            HStack(alignment: .center, spacing: 8) {
                Text(r.kindLabel).font(webFont(11)).foregroundStyle(pal.brass).fixedSize(horizontal: false, vertical: true)
                    .frame(width: 54, alignment: .leading)
                Text(r.title).font(webFont(13)).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(r.ownerLabel ?? "—").font(webFont(11.5)).foregroundStyle(pal.ink4).fixedSize(horizontal: false, vertical: true)
                    .frame(width: 76, alignment: .leading)
                Text(r.dateText ?? "—").font(webFont(11.5)).foregroundStyle(pal.ink6).lineLimit(2)
                    .frame(width: 58, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("docs.tableRow.\(i)", text: r.title)
    }

    // MARK: вид В — по месяцам

    @ViewBuilder private func month(_ g: DocShelf.Group, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(g.label).font(webFont(15, 500)).foregroundStyle(pal.ink).lineLimit(1)
                Text("· " + t.count("unit.doc", g.rows.count)).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 30)
            .shotNode("docs.month." + g.id, text: String(g.rows.count))
            ForEach(Array(g.rows.enumerated()), id: \.offset) { i, r in docRow(r, i, pal) }
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

    /// Строка бумаги от 41 pt высотой: вид · название · дата; вид и название переносятся на вторую строку.
    private func docRow(_ r: DocShelf.Row, _ i: Int, _ pal: Palette) -> some View {
        Button { open(r.shelf.doc) } label: {
            HStack(spacing: 10) {
                Text(r.kindLabel).font(webFont(11)).tracking(0.2)
                    .foregroundStyle(pal.brass).fixedSize(horizontal: false, vertical: true).frame(width: 72, alignment: .leading)
                Text(r.title).font(webFont(14)).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(r.dateText ?? "—").font(webFont(11.5)).foregroundStyle(pal.ink6).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 7).frame(minHeight: 41)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("docs.row.\(i)", text: r.title)
    }

    /// Ссылка — в браузере; файл без облака — сообщение (облако — итерация 30). Экран бумаги — шаг 3б.
    private func open(_ d: Attachment) {
        if d.source == .link, let u = d.url.flatMap(URL.init(string:)) { openURL(u); note = nil; return }
        note = t.t("doc.openFail")
    }
}
