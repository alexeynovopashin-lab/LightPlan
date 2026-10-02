import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Экран «Документы» (итерация 28д, шаг 3а; справка `docs_reference.md` § 3 и 6.2)

/// Верхний уровень: восемь разделов строками, как папки Finder; тап — раздел (`DocsSectionView`).
/// Каркас как у «Организаций»: поля 24, сверху 14, снизу 34, фон `surface`. Поле поиска — под заголовком
/// (шаг 3б): пока в нём есть слова, вместо разделов — результаты по всей полке. Тап по бумаге —
/// экран бумаги (`DocPaperScreen`) поверх корня и раздела. «+» — в шапке, лист `DocEditSheet` (шаг 4).
struct DocsScreen: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        ZStack {
            if let s = app.docsNav.section {
                DocsSectionView(app: app, section: s)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            } else {
                root(pal).transition(.opacity)
            }
            if let d = app.docsNav.paper {
                DocPaperScreen(app: app, doc: d, backTitle: backTitle)
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }
        }
        .background(pal.surface.ignoresSafeArea())
        .animation(overlaySlide, value: app.docsNav.section)
        .sheet(item: $app.docsNav.sheet) { DocEditSheet(app: app, mode: $0) }
    }

    /// «Назад» экрана бумаги ведёт туда, откуда пришли: в раздел или в «Документы».
    private var backTitle: String {
        app.docsNav.section.map(app.docSectionTitle) ?? app.lexicon.t("doc.stripTitle")
    }

    private func root(_ pal: Palette) -> some View {
        let t = app.lexicon
        let counts = app.docCounts()
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: t.t("nav.shoots"), node: "docs.back") {
                    withAnimation(overlaySlide) { app.closeDocs() }
                }
                HStack(spacing: 12) {
                    Text(t.t("doc.stripTitle")).font(webFont(26, 650)).tracking(-0.4).foregroundStyle(pal.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    DocPlusButton(app: app)
                }
                .padding(.top, 10)
                DocsSearchField(app: app).padding(.top, 14)
                if app.docSearching {
                    DocsResults(app: app)
                } else {
                    VStack(spacing: 8) {
                        ForEach(DocSection.allCases, id: \.self) { s in row(s, counts.count(of: s), pal) }
                    }
                    .padding(.top, 14)
                }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .shotNode("docs.root", text: "\(counts.total)")
    }

    /// Строка раздела: высота 46, радиус 14, `sheet`; знак 18, название 14,5/500, число 12 `ink6`
    /// (нулевое не рисуется), шеврон 13. «Требуют внимания» — с янтарным числом.
    private func row(_ s: DocSection, _ n: Int, _ pal: Palette) -> some View {
        let amber = s == .attention
        return Button { app.openDocSection(s) } label: {
            HStack(spacing: 12) {
                Icon(AppModel.docSectionIcon(s), size: 18, line: 1.6).foregroundStyle(amber && n > 0 ? pal.brassDeep : pal.ink4)
                    .frame(width: 22)
                Text(app.docSectionTitle(s)).font(webFont(14.5, 500)).foregroundStyle(pal.ink).lineLimit(1)
                Spacer(minLength: 0)
                if n > 0 {
                    Text("\(n)").font(webFont(12)).foregroundStyle(amber ? pal.brassDeep : pal.ink6)
                }
                Icon("chevron", size: 13, line: 2.4).foregroundStyle(pal.ink4)
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("docs.sec." + s.rawValue, text: "\(n)")
    }
}
