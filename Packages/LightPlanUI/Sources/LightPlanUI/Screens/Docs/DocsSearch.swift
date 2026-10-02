import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Поиск по «Документам» (итерация 28д, шаг 3б; справка § 5)

/// Поле поиска над списком разделов и внутри раздела: высота 39, радиус 12, фон `sheet`, текст 14.
/// Знака лупы в библиотеке нет, новых не рисуем — поле узнаётся по подсказке; справа — «×», пока
/// есть запрос. Запрос один на корень и разделы (`DocsNav.query`).
struct DocsSearchField: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        HStack(spacing: 6) {
            TextField("", text: $app.docsNav.query, prompt: Text(app.lexicon.t("doc.searchHint")).foregroundStyle(pal.ink8))
                .font(.system(size: 14)).foregroundStyle(pal.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(app.lexicon.t("doc.searchHint"))
                .shotNode("docs.search", text: app.docsNav.query)
            if !app.docsNav.query.isEmpty {
                Button { app.docsNav.query = "" } label: {
                    Icon("close", size: 14, line: 2).foregroundStyle(pal.ink4).frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.lexicon.t("doc.searchReset"))
                .shotNode("docs.search.clear")
            }
        }
        .padding(.leading, 14).padding(.trailing, 4).frame(height: 39)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet))
    }
}

/// Результат поиска вместо содержимого корня или раздела: бумаги одним плоским списком (сначала
/// совпавшие в названии, потом по дате от новых), три вида действуют, групп раздела нет. Нет
/// совпадений — плашка «Ничего не найдено по «…»» и «Сбросить».
struct DocsResults: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let rows = app.docSearchRows()
        if rows.isEmpty {
            none(pal)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(app.lexicon.count("unit.doc", rows.count)).font(webFont(12)).foregroundStyle(pal.ink6)
                    .padding(.top, 14).shotNode("docs.results", text: String(rows.count))
                DocLayoutSwitch(app: app).padding(.top, 8)
                switch app.org.docs.layout {
                case .list:
                    DocColumnHeads(app: app, sortable: false).padding(.top, 10)
                    VStack(spacing: 6) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in DocRow(app: app, row: r, index: i) }
                    }
                    .padding(.top, 6)
                case .table:
                    DocTable(app: app, rows: app.docSearchTableRows(), sortable: false).padding(.top, 14)
                case .months:
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(app.docSearchMonths(), id: \.id) { g in DocMonth(app: app, group: g) }
                    }
                    .padding(.top, 16)
                }
            }
        }
    }

    private func none(_ pal: Palette) -> some View {
        let q = app.docsNav.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: 12) {
            Text(app.lexicon.t("doc.searchNone", ["q": q])).font(.system(size: 14)).foregroundStyle(pal.ink3)
                .lineSpacing(5).multilineTextAlignment(.center)
            Button { app.docsNav.query = "" } label: {
                Text(app.lexicon.t("doc.searchReset")).font(webFont(13.5, 500)).foregroundStyle(pal.brassDeep)
                    .padding(.horizontal, 16).frame(height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shotNode("docs.search.reset")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
        .padding(.top, 18)
        .shotNode("docs.search.none", text: q)
    }
}
