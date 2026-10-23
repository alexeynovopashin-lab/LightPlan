import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Клиенты (шаг К1, справка `docs/clients_reference.md` § 4.2–4.3)

/// Экран «Клиенты» из настроек: слой поверх вкладок. В шапке «Назад» слева и переключатель «Частные | Компании» справа.
/// «Частные» — клиенты, собранные из съёмок по номеру телефона, с фильтром «Все · Пары · Семьи · Персоны»; свежие
/// сверху. «Компании» — нынешние организации один в один (`OrgListScreen`), их карточка не менялась.
///
/// Строка ведёт в карточку клиента (шаг К2, `ClientCardScreen`); «+ Клиент» заводит клиента руками — черновиком, который
/// встаёт в данные, когда в нём вписано слово. Обычно клиент заводится сам, когда сохраняют съёмку.
struct ClientsScreen: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    OverlayBack(title: t.t(app.org.backKey), node: "org.back") {
                        withAnimation(overlaySlide) { app.closeOrgs() }
                    }
                    Spacer(minLength: 8)
                    ClientsSeg(options: [(t.t("cl.tabPrivate"), ClientsTab.privates), (t.t("cl.tabCompanies"), .companies)],
                               selection: $app.org.clientsTab)
                }
                switch app.org.clientsTab {
                case .privates: privates(pal)
                case .companies: OrgListScreen(app: app)
                }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(pal.surface.ignoresSafeArea())
        // «Компании» держат прежний узел `org.list` на весь экран — пара с вебом остаётся как была.
        .shotNode(app.org.clientsTab == .privates ? "cl.screen" : "org.list",
                  text: "\(app.org.clientsTab == .privates ? app.clients.count : app.orgs.count)")
    }

    // MARK: Частные

    @ViewBuilder private func privates(_ pal: Palette) -> some View {
        let rows = app.clientRows()
        ClientFilterChips(options: ClientBook.Filter.allCases.map { (t.t(Self.filterKey($0)), $0) },
                          selection: $app.org.clientsFilter)
            .padding(.top, 14)
        VStack(spacing: 10) {
            if app.clients.isEmpty {
                emptyPlate(pal)
            } else if rows.isEmpty {
                Text(t.t("cl.emptyKind")).font(.system(size: 14)).foregroundStyle(pal.ink4).lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                    .shotNode("cl.emptyKind")
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in row(r, i, pal) }
        }
        .padding(.top, 14)
        .shotNode("cl.list", text: "\(rows.count)")
        // Как «+ Организация» на «Компаниях»: тихая строка под списком.
        Button { withAnimation(overlaySlide) { app.newClient() } } label: {
            Text(t.t("cl.add")).font(webFont(14.5)).foregroundStyle(pal.ink4)
                .frame(maxWidth: .infinity).frame(height: 31).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("cl.add", text: t.t("cl.add"))
        .padding(.top, 12)
    }

    static func filterKey(_ f: ClientBook.Filter) -> String {
        switch f {
        case .all: "cl.fAll"
        case .couples: "cl.fCouples"
        case .families: "cl.fFamilies"
        case .persons: "cl.fPersons"
        }
    }

    /// Пусто от рождения — плашка со знаком и словом, как в «Документах»: не одинокая строка.
    private func emptyPlate(_ pal: Palette) -> some View {
        VStack(spacing: 12) {
            Icon("couple", size: 24, line: 1.6).foregroundStyle(pal.ink5)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.press))
            (Text(t.t("cl.emptyHead")).foregroundStyle(pal.ink3) + Text(" " + t.t("cl.empty")).foregroundStyle(pal.ink4))
                .font(.system(size: 14)).lineSpacing(5).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
        .shotNode("cl.empty")
    }

    /// Строка как у организации: плитка знака 34, имя 15, подпись 12, шеврон; 392×64.
    private func row(_ r: ClientRow, _ i: Int, _ pal: Palette) -> some View {
        Button { withAnimation(overlaySlide) { app.openClient(r) } } label: {
            HStack(spacing: 14) {
                Icon(r.icon, size: 18, line: 1.6).foregroundStyle(pal.ink4)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(pal.press))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(webFont(15)).foregroundStyle(pal.ink).lineLimit(1)
                    Text(r.subtitle).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1)
                }
                Spacer(minLength: 0)
                Icon("chevron", size: 16, line: 2.4).foregroundStyle(pal.ink6)
            }
            .padding(14).frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("cl.row.\(i)", text: r.title)
    }
}

/// Переключатель «Частные | Компании» в шапке: тот же вид, что `.seg` настроек (подложка `--sheet`, выбранная — `--seg-on`),
/// ниже ростом — он делит строку с «Назад».
struct ClientsSeg<V: Hashable>: View {
    let options: [(label: String, value: V)]
    @Binding var selection: V
    /// Во всю ширину (вид клиента в карточке, К2): варианты делят строку поровну.
    var stretch = false
    var node = "cl.tabs"
    var itemNode = "cl.tab"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].value == selection
                Button {
                    Haptics.play(.segment)
                    withAnimation(.easeInOut(duration: 0.25)) { selection = options[i].value }
                } label: {
                    Text(options[i].label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(on ? pal.ink : pal.ink4)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.vertical, 7).padding(.horizontal, 12)
                        .frame(maxWidth: stretch ? .infinity : nil)
                        .background(on ? pal.segOn : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .shotNode("\(itemNode).\(i)", text: options[i].label)
            }
        }
        .padding(3)
        .frame(maxWidth: stretch ? .infinity : nil)
        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shotNode(node)
    }
}

/// Фишки «Все · Пары · Семьи · Персоны»: вид `.chips` настроек (выбранная — латунью, прочие — `--ink-3` на `--press`).
struct ClientFilterChips<V: Hashable>: View {
    let options: [(label: String, value: V)]
    @Binding var selection: V
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        FlowLayout(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].value == selection
                Button { selection = options[i].value } label: {
                    Text(options[i].label)
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? pal.brass : pal.ink3)
                        .padding(.vertical, 9).padding(.horizontal, 14)
                        .background(on ? pal.pressBrass : pal.press, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .shotNode("cl.chip.\(i)", text: options[i].label)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shotNode("cl.chips")
    }
}
