import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Строки полки «Документов»: общие для разделов и результатов поиска (итерация 28д, шаги 3а–3б)

/// Переключатель видов, как в Finder: три сегмента со знаками; выбранный на `--press`. Вид один
/// на все разделы и запоминается (`DocsPrefs.layout`).
struct DocLayoutSwitch: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
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
                .accessibilityLabel(app.lexicon.t(key))
                .shotNode("docs.layout." + lay.rawValue, text: on ? "on" : "off")
            }
        }
    }
}

/// Заголовки колонок списка: «Название» и «Дата» сортируют, тот же тап меняет направление. У
/// «Недавних» и у результатов поиска порядок задан не колонкой — заголовки подписи без тапа.
struct DocColumnHeads: View {
    @Bindable var app: AppModel
    let sortable: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        HStack(spacing: 10) {
            Text(app.lexicon.t("doc.colKind")).font(webFont(11)).foregroundStyle(pal.ink6).frame(width: 72, alignment: .leading)
            head(.title, "doc.title", pal)
            Spacer(minLength: 0)
            head(.date, "doc.colDate", pal)
        }
        .padding(.horizontal, 14)
    }

    private func head(_ key: DocSortKey, _ word: String, _ pal: Palette) -> some View {
        let on = sortable && app.org.docs.sortKey == key
        return Button { app.editDocsPrefs { $0.tapColumn(key) } } label: {
            Text(app.lexicon.t(word) + (on ? (app.org.docs.ascending ? " ↑" : " ↓") : ""))
                .font(webFont(11, on ? 500 : 400)).foregroundStyle(on ? pal.ink3 : pal.ink6)
                .frame(minHeight: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!sortable)
        .shotNode("docs.sort." + key.rawValue, text: on ? (app.org.docs.ascending ? "asc" : "desc") : "")
    }
}

/// Строка бумаги от 41 pt высотой: вид · название · дата; вид и название переносятся на вторую
/// строку. Тап открывает экран бумаги.
struct DocRow: View {
    @Bindable var app: AppModel
    let row: DocShelf.Row
    let index: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        Button { withAnimation(overlaySlide) { app.openDocPaper(row.shelf) } } label: {
            HStack(spacing: 10) {
                Text(row.kindLabel).font(webFont(11)).tracking(0.2)
                    .foregroundStyle(pal.brass).fixedSize(horizontal: false, vertical: true).frame(width: 72, alignment: .leading)
                Text(row.title).font(webFont(14)).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(row.dateText ?? "—").font(webFont(11.5)).foregroundStyle(pal.ink6).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 7).frame(minHeight: 41)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("docs.row.\(index)", text: row.title)
    }
}

/// Вид Б — таблица. Колонки на узком экране: «Вид» 54, «Организация» 76, «Дата» 58; «Название»
/// берёт остаток.
struct DocTable: View {
    @Bindable var app: AppModel
    let rows: [DocShelf.Row]
    let sortable: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                head(.kind, "doc.colKind", pal).frame(width: 54, alignment: .leading)
                head(.title, "doc.title", pal).frame(maxWidth: .infinity, alignment: .leading)
                head(.org, "org.one", pal).frame(width: 76, alignment: .leading)
                head(.date, "doc.colDate", pal).frame(width: 58, alignment: .leading)
            }
            .padding(.horizontal, 12)
            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in rowView(r, i, pal) }
            }
            .padding(.top, 4)
        }
    }

    private func head(_ key: DocSortKey, _ word: String, _ pal: Palette) -> some View {
        let on = sortable && app.org.docs.sortKey == key
        return Button { app.editDocsPrefs { $0.tapColumn(key) } } label: {
            Text(app.lexicon.t(word) + (on ? (app.org.docs.ascending ? " ↑" : " ↓") : ""))
                .font(webFont(11, on ? 500 : 400)).foregroundStyle(on ? pal.ink3 : pal.ink6)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(minHeight: 30, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!sortable)
        .shotNode("docs.tsort." + key.rawValue, text: on ? (app.org.docs.ascending ? "asc" : "desc") : "")
    }

    private func rowView(_ r: DocShelf.Row, _ i: Int, _ pal: Palette) -> some View {
        Button { withAnimation(overlaySlide) { app.openDocPaper(r.shelf) } } label: {
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
}

/// Вид В — месяц: заголовок «Месяц · N бумаг» и строки под ним.
struct DocMonth: View {
    @Bindable var app: AppModel
    let group: DocShelf.Group
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.label).font(webFont(15, 500)).foregroundStyle(pal.ink).lineLimit(1)
                Text("· " + app.lexicon.count("unit.doc", group.rows.count)).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 30)
            .shotNode("docs.month." + group.id, text: String(group.rows.count))
            ForEach(Array(group.rows.enumerated()), id: \.offset) { i, r in DocRow(app: app, row: r, index: i) }
        }
    }
}
