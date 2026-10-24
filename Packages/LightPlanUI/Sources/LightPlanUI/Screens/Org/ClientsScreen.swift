import SwiftUI
import LightPlanCore
import LightPlanData
import LightPlanDomain
#if os(iOS)
import UIKit
#endif

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
    @Environment(\.openURL) private var openURL

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
        // Первое открытие «Клиентов» — момент спросить доступ к Контактам и о прошлых клиентах (К7, § 5).
        .task { app.contactsOpened() }
        .confirmationDialog(t.t("clk.removeAsk", ["n": t.count("clk.contacts", app.contactsOwnCount)]),
                            isPresented: $app.contactsRemoveAsk, titleVisibility: .visible) {
            Button(t.t("clk.removeYes"), role: .destructive) { app.removeAppContacts() }
            Button(t.t("ask.cancel"), role: .cancel) {}
        } message: {
            Text(t.t("clk.removeNote"))
        }
    }

    // MARK: Частные

    @ViewBuilder private func privates(_ pal: Palette) -> some View {
        let rows = app.clientRows()
        ClientFilterChips(options: ClientBook.Filter.allCases.map { (t.t(Self.filterKey($0)), $0) },
                          selection: $app.org.clientsFilter)
            .padding(.top, 14)
        if let n = app.contactsPastAsk { pastPlate(n, pal).padding(.top, 14) }
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
        contactsPart(pal)
    }

    // MARK: Контакты iPhone (К7, § 5)

    /// Под списком: тумблер «Сохранять клиентов в Контакты iPhone» (по умолчанию вкл), подпись — почему так, строка
    /// «спросить снова» о прошлых клиентах и «Убрать из Контактов всё, что записало приложение». В тестовой сборке
    /// тумблера нет — она в книгу не пишет никогда (защита 1); остаётся подпись, почему.
    @ViewBuilder private func contactsPart(_ pal: Palette) -> some View {
        if app.contactsAvailable {
            VStack(alignment: .leading, spacing: 8) {
                if app.contactsWrites {
                    HStack(spacing: 12) {
                        Text(t.t("clk.toggle")).font(.system(size: 15)).foregroundStyle(pal.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Toggle("", isOn: Binding(
                            get: { app.contactsOn },
                            set: { on in
                                // Отказали или открыли часть книги — спросить снова нельзя: ведём в настройки iPhone.
                                if on, app.contactsNeedsSettings { openSystemSettings() } else { app.setContactsWanted(on) }
                            }))
                            .labelsHidden().tint(pal.brass)
                            .shotNode("clk.toggle", text: app.contactsOn ? "on" : "off")
                    }
                    .padding(.horizontal, 15).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
                    contactsNote(contactsNoteText, pal, node: "clk.note")
                    if app.contactsOn, app.contactsPastAnswer == false, app.contactsPastWaiting > 0, app.contactsPastAsk == nil {
                        contactsLine(t.t("clk.pastAgain", ["n": "\(app.contactsPastWaiting)"]), ink: pal.brass, pal, node: "clk.pastAgain") {
                            app.askPastClientsAgain()
                        }
                    }
                    if app.contactsOwnCount > 0 {
                        contactsLine(t.t("clk.remove"), ink: pal.ink3, pal, node: "clk.remove") { app.contactsRemoveAsk = true }
                    }
                    if let n = app.contactsRemoved {
                        contactsNote(t.t("clk.removed", ["n": "\(n)"]), pal, node: "clk.removed")
                    }
                } else {
                    contactsNote(t.t("clk.testBuild"), pal, node: "clk.testBuild")
                }
            }
            .padding(.top, 22)
            .shotNode("clk.part")
        }
    }

    private var contactsNoteText: String {
        if app.contactsAuth == .denied { return t.t("clk.denied") }
        if app.contactsAuth == .limited { return t.t("clk.limited") }
        if !app.contactsOn { return t.t("clk.noteOff") }
        if app.contactsFailed { return t.t("clk.failed") }
        return t.t("clk.noteOn")
    }

    private func contactsNote(_ text: String, _ pal: Palette, node: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(pal.ink5).lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
            .shotNode(node, text: text)
    }

    private func contactsLine(_ title: String, ink: Color, _ pal: Palette, node: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15)).foregroundStyle(ink).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode(node, text: title)
    }

    /// «Сохранить в Контакты N клиентов из прошлых съёмок?» — «Да» / «Нет» (защита 2). Плашка над списком: её видно
    /// сразу, как открыли «Клиенты».
    private func pastPlate(_ n: Int, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Icon("partner", size: 17, line: 1.6).foregroundStyle(pal.brass).padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.t("clk.pastAsk", ["n": t.count("clk.clients", n)])).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(pal.ink).lineSpacing(3)
                        .shotNode("clk.pastText", text: "\(n)")
                    Text(t.t("clk.pastNote")).font(.system(size: 13)).foregroundStyle(pal.ink5).lineSpacing(3)
                        .shotNode("clk.pastNote", text: t.t("clk.pastNote"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                pastButton(t.t("clf.yes"), ink: pal.brass, back: pal.pressBrass, node: "clk.pastYes") { app.answerPastClients(true) }
                pastButton(t.t("studio.askNo"), ink: pal.ink3, back: pal.press, node: "clk.pastNo") { app.answerPastClients(false) }
            }
            .padding(.leading, 29)
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
        .shotNode("clk.past", text: "\(n)")
    }

    private func pastButton(_ title: String, ink: Color, back: Color, node: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                .padding(.horizontal, 14).frame(height: 32)
                .background(back, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .shotNode(node)
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
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
