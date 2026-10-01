import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Организации и документы (`#orgOverlay`, итерация 28, шаг 6)

/// Сегмент «Организации / Документы»: список организаций со строкой 392×64 и «+ Организация»,
/// либо общая полка бумаг с чипами видов. Порядок — как заведены, поиска нет (эталон заморожен,
/// ошибка веба 27). «+ Организация» открывает карточку-черновик: пустая запись в данные не ложится.
struct OrgListScreen: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var note: String?

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: t.t(app.org.backKey), node: "org.back") {
                    withAnimation(overlaySlide) { app.closeOrgs() }
                }
                segment(pal).padding(.top, 14)
                if app.org.tab == .orgs { orgs(pal) } else { shelf(pal) }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(pal.surface.ignoresSafeArea())
        .shotNode("org.list", text: "\(app.orgs.count)")
    }

    // MARK: сегмент

    /// `.org-seg`: две кнопки по половине, выбранная — на `--press`, скругление 12, 14 pt.
    private func segment(_ pal: Palette) -> some View {
        HStack(spacing: 8) {
            ForEach([(OrgState.Tab.orgs, "org.tabOrgs"), (.docs, "card.docs")], id: \.1) { tab, key in
                let on = app.org.tab == tab
                Button { app.org.tab = tab } label: {
                    Text(t.t(key)).font(webFont(14, on ? 500 : 400)).foregroundStyle(on ? pal.ink : pal.ink4)
                        .frame(maxWidth: .infinity).frame(height: 39)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? pal.press : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .shotNode("org.seg." + (tab == .orgs ? "orgs" : "docs"), text: t.t(key))
            }
        }
    }

    // MARK: организации

    @ViewBuilder private func orgs(_ pal: Palette) -> some View {
        VStack(spacing: 10) {
            if app.orgs.isEmpty {
                (Text(t.t("org.emptyHead")).foregroundStyle(pal.ink3) + Text(" " + t.t("org.empty")).foregroundStyle(pal.ink4))
                    .font(.system(size: 14)).lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                    .shotNode("org.empty")
            }
            ForEach(Array(app.orgs.enumerated()), id: \.element.id) { i, o in row(o, i, pal) }
        }
        .padding(.top, 10)
        Button { withAnimation(overlaySlide) { app.newOrg() } } label: {
            Text(t.t("org.add")).font(webFont(14.5)).foregroundStyle(pal.ink4)
                .frame(maxWidth: .infinity).frame(height: 31).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("org.add", text: t.t("org.add"))
        .padding(.top, 12)
    }

    /// `.org-item`: плитка знака 34, название 15, подпись 12, шеврон; 392×64, скругление 16, поле 14.
    private func row(_ o: Org, _ i: Int, _ pal: Palette) -> some View {
        Button { withAnimation(overlaySlide) { app.openOrgCard(id: o.id) } } label: {
            HStack(spacing: 14) {
                Icon("city", size: 18, line: 1.6).foregroundStyle(pal.ink4)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(pal.press))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.orgTitle(o)).font(webFont(15)).foregroundStyle(pal.ink).lineLimit(1)
                    Text(app.orgSubtitle(o)).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1)
                }
                Spacer(minLength: 0)
                Icon("chevron", size: 16, line: 2.4).foregroundStyle(pal.ink6)
            }
            .padding(14).frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("org.row.\(i)", text: app.orgTitle(o))
    }

    // MARK: полка бумаг

    @ViewBuilder private func shelf(_ pal: Palette) -> some View {
        let all = OrgBook.shelf(orgs: app.orgs, sessions: app.sessions)
        let chips = OrgBook.shelfKinds(all, practice: app.dealPractice, selected: app.org.shelfKind)
        let groups = app.docGroups()
        if !chips.isEmpty {
            FlowLayout(spacing: 7) {
                ForEach(chips, id: \.kind) { c in kindChip(c.kind, c.count, pal) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
        }
        if all.isEmpty {
            (Text(t.t("doc.allEmptyHead")).foregroundStyle(pal.ink3) + Text(" " + t.t("doc.allEmpty")).foregroundStyle(pal.ink4))
                .font(.system(size: 14)).lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                .shotNode("org.docsEmpty")
        } else {
            grouping(pal).padding(.top, 14)
            columnHeads(pal).padding(.top, 10)
            VStack(spacing: 8) {
                ForEach(groups, id: \.id) { g in group(g, pal) }
            }
            .padding(.top, 6)
        }
        if let note {
            Text(note).font(.system(size: 12)).foregroundStyle(pal.ink4).lineSpacing(5).padding(.top, 10)
        }
    }

    /// Группировка: организация · месяц · вид. Три слова в ряд, выбранное — на `--press`.
    private func grouping(_ pal: Palette) -> some View {
        HStack(spacing: 6) {
            ForEach([(DocGrouping.org, "doc.groupOrg"), (.month, "doc.groupMonth"), (.kind, "doc.groupKind")], id: \.1) { g, key in
                let on = app.org.docs.grouping == g
                Button { app.editDocsPrefs { $0.grouping = g } } label: {
                    Text(t.t(key)).font(webFont(13, on ? 500 : 400)).foregroundStyle(on ? pal.ink : pal.ink4)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? pal.press : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .shotNode("org.group." + g.rawValue, text: t.t(key))
            }
        }
    }

    /// Заголовки колонок: «Название» и «Дата» сортируют, тот же тап меняет направление.
    private func columnHeads(_ pal: Palette) -> some View {
        HStack(spacing: 10) {
            Text(t.t("doc.colKind")).font(webFont(11)).foregroundStyle(pal.ink6).frame(width: 64, alignment: .leading)
            head(.title, "doc.title", pal)
            Spacer(minLength: 0)
            head(.date, "doc.colDate", pal)
        }
        .padding(.horizontal, 14)
    }

    private func head(_ key: DocSortKey, _ word: String, _ pal: Palette) -> some View {
        let on = app.org.docs.sortKey == key
        return Button { app.editDocsPrefs { $0.tapColumn(key) } } label: {
            Text(t.t(word) + (on ? (app.org.docs.ascending ? " ↑" : " ↓") : ""))
                .font(webFont(11, on ? 500 : 400)).foregroundStyle(on ? pal.ink3 : pal.ink6)
                .frame(minHeight: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("org.sort." + key.rawValue, text: on ? (app.org.docs.ascending ? "asc" : "desc") : "")
    }

    /// Группа как в Finder: «▸ Организация · N бумаг»; тап сворачивает и разворачивает.
    @ViewBuilder private func group(_ g: DocShelf.Group, _ pal: Palette) -> some View {
        let open = !app.org.docs.collapsed.contains(g.id)
        Button { withAnimation(.easeOut(duration: 0.18)) { app.editDocsPrefs { $0.toggleGroup(g.id) } } } label: {
            HStack(spacing: 8) {
                Icon("chevron", size: 13, line: 2.4).foregroundStyle(pal.ink4)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 16)
                Text(g.label).font(webFont(14.5, 500)).foregroundStyle(pal.ink).lineLimit(1)
                Text("· " + t.count("unit.doc", g.rows.count)).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("org.docGroup." + g.id, text: (open ? "open " : "closed ") + String(g.rows.count))
        if open {
            VStack(spacing: 6) {
                ForEach(Array(g.rows.enumerated()), id: \.offset) { i, r in docRow(r, i, pal) }
            }
        }
    }

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
        .shotNode("org.kind." + k.rawValue, text: "\(n)")
    }

    /// Строка бумаги 392×41: вид · название · дата. Хвост ссылки именем не бывает.
    private func docRow(_ r: DocShelf.Row, _ i: Int, _ pal: Palette) -> some View {
        Button { open(r.shelf.doc) } label: {
            HStack(spacing: 10) {
                Text(r.kindLabel).font(webFont(11)).tracking(0.2)
                    .foregroundStyle(pal.brass).lineLimit(1).minimumScaleFactor(0.8).frame(width: 64, alignment: .leading)
                Text(r.title).font(webFont(14)).foregroundStyle(pal.ink).lineLimit(1)
                Spacer(minLength: 0)
                Text(r.dateText ?? "—").font(webFont(11.5)).foregroundStyle(pal.ink6).lineLimit(1)
            }
            .padding(.horizontal, 14).frame(height: 41)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("org.docRow.\(i)", text: r.title)
    }

    private func open(_ d: Attachment) {
        if d.source == .link, let u = d.url.flatMap(URL.init(string:)) { openURL(u); note = nil; return }
        note = t.t("doc.openFail")
    }
}

extension AppModel {
    /// Имя вида словарём; слова нет — код как есть (веб `docKindName`).
    func docKindName(_ k: DocKind) -> String {
        let s = lexicon.t("doc." + k.rawValue)
        return s == "doc." + k.rawValue ? k.rawValue : s
    }

    /// Справа в строке бумаги: у ссылки сайт, у файла вес (веб `docSize`: КБ до мегабайта).
    func docTrailing(_ d: Attachment) -> String {
        if d.source == .link { return DocLabel.host(d.url ?? "") }
        guard let b = d.size, b > 0 else { return "" }
        return b < 1_048_576 ? lexicon.t("doc.kb", ["n": String(max(1, Int((Double(b) / 1024).rounded())))])
                             : lexicon.t("doc.mb", ["n": String(format: "%.1f", Double(b) / 1_048_576)])
    }

    /// «Кому и когда» под строкой полки: организация → клиент → жанр, дата съёмки.
    func docOwnerLine(_ d: OrgBook.ShelfDoc) -> String {
        var parts: [String] = []
        let words = PlannerWords(lexicon: lexicon, orgs: orgs)
        if let sid = d.sessionId, let s = sessions.first(where: { $0.id == sid }) {
            if let id = s.orgId, let o = orgs.first(where: { $0.id == id }), !o.name.isEmpty { parts.append(o.name) }
            else { let c = words.clientName(s); parts.append(c.isEmpty ? words.typeName(s) : c) }
        } else if let id = d.orgId, let o = orgs.first(where: { $0.id == id }) {
            parts.append(orgTitle(o))
        }
        if let day = d.day {
            let facts = PlannerFacts(app: self, dark: true)
            parts.append(facts.dates.dMonYear(facts.date(day)))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
