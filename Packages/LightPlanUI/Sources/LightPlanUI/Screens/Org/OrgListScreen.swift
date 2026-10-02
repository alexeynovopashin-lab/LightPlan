import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Организации (`#orgOverlay`, итерация 28, шаг 6)

/// Список организаций со строкой 392×64 и «+ Организация». Порядок — как заведены, поиска нет (эталон
/// заморожен, ошибка веба 27). «+ Организация» открывает карточку-черновик: пустая запись в данные не
/// ложится. Бумаги ушли отсюда в «Документы» под мудбордом (28д, шаг 3а).
struct OrgListScreen: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: t.t(app.org.backKey), node: "org.back") {
                    withAnimation(overlaySlide) { app.closeOrgs() }
                }
                orgs(pal)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(pal.surface.ignoresSafeArea())
        .shotNode("org.list", text: "\(app.orgs.count)")
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
