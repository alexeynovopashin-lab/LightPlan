import SwiftUI
import LightPlanData
import LightPlanDomain

/// Корень настроек в стиле Telegram (30и.11, выбор Алексея 15.11: «вид настроек как в телеграм» — вариант B листа
/// `docs/30i11_settings_sketch.html`): плакат аккаунта, блоки со скруглением 20, рубрики над блоками.

/// Скругление блока рубрики (лист, вариант B).
enum SettingsRoot {
    static let radius: CGFloat = 20
    /// Прорезь начинается от текста: поле 16 + знак 17 + зазор 11.
    static let slitInset: CGFloat = 44
}

/// Блок рубрики: подложка `sheet`, скругление 20, между строками — прорезь (1 pt цвета страницы), не светлая линия.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme)
        let r = RoundedRectangle(cornerRadius: SettingsRoot.radius, style: .continuous)
        VStack(spacing: 0) {
            Group(subviews: content()) { subs in
                ForEach(Array(subs.enumerated()), id: \.offset) { i, v in
                    if i > 0 { Rectangle().fill(pal.surface).frame(height: 1).padding(.leading, SettingsRoot.slitInset) }
                    v
                }
            }
        }
        .background(pal.sheet, in: r)
        .clipShape(r)
        .plateStyle(pal, radius: SettingsRoot.radius)
        .padding(.horizontal, 16)
    }
}

/// Заголовок рубрики над блоком — та же подпись, что у глав, поле под блок 16.
struct RubricLabel: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
            .foregroundStyle(Palette(colorScheme).ink7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 7)
    }
}

/// Круг с инициалами вместо фото (аватар — отдельный шаг: выбор из «Фото» и хранение ещё не сделаны).
struct AvatarPlaceholder: View {
    let initials: String
    var size: CGFloat = 88
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let pal = Palette(colorScheme)
        ZStack {
            Circle().fill(LinearGradient(colors: pal.dark ? [Color(hex: 0x6F6A5F), Color(hex: 0x3D3A33)] : [Color(hex: 0x8D8D93), Color(hex: 0x5F5F66)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            if initials.isEmpty {
                Icon("aperture", size: size * 0.42, line: 1.6).foregroundStyle(.white)
            } else {
                Text(initials).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Плакат аккаунта: аватар 88 по центру, имя, «телефон · город», справа вверху «Изм.»; всё ведёт на страницу «Профиль».
struct AccountPoster: View {
    @Bindable var app: AppModel
    let open: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pal = Palette(colorScheme), t = app.lexicon
        let name = app.myName
        VStack(spacing: 0) {
            AvatarPlaceholder(initials: app.myInitials).shotNode("account.avatar")
            Text(name.isEmpty ? t.t("set.myNameNone") : name)
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(name.isEmpty ? pal.ink4 : pal.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.top, 10).shotNode("account.name", text: name)
            Text(line(t))
                .font(.system(size: 15)).foregroundStyle(pal.ink3).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.top, 2).shotNode("account.line", text: line(t))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .overlay(alignment: .topTrailing) {
            Button(action: open) {
                Text(t.t("set.accEdit")).font(.system(size: 15)).foregroundStyle(pal.ink)
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(pal.press, in: Capsule())
            }
            .buttonStyle(.plain).padding(.trailing, 16).padding(.top, 8)
            .shotNode("account.edit", text: t.t("set.accEdit"))
        }
        .shotNode("account")
    }

    private func line(_ t: Lexicon) -> String {
        let phone = app.myPhone, city = app.settings.home.isEmpty ? t.t("set.myCityNone") : app.settings.home.name
        return phone.isEmpty ? city : phone + " · " + city
    }
}

/// Блоки рубрик «Про» и «Астро»: из глав — в рубрики; «Контакты», «Мои места», «Мудборды», «Корзина» подняты на корень.
struct SettingsRubrics: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var colorScheme

    typealias Chapter = SettingsView.Chapter

    var body: some View {
        let t = app.lexicon
        VStack(spacing: 0) {
            RubricLabel(text: t.t("set.rubWork"))
            SettingsGroup {
                chapter(.shoots); chapter(.clients)
                layer("phone", "set.contacts", app.contactsValue, "contacts") { app.openContacts() }
                places
                layer("album", "set.moodboards", moodboards, "moodboards") { app.openMbGallery(backKey: "nav.settings") }
                chapter(.playlists)
            }
            RubricLabel(text: t.t("set.rubCal"))
            SettingsGroup { chapter(.calendar); chapter(.alerts) }
            RubricLabel(text: t.t("set.rubLook"))
            SettingsGroup {
                VStack(alignment: .leading, spacing: 0) {
                    WebSeg(options: [(t.t("set.themeDark"), AppSettings.Theme.dark), (t.t("set.themeLight"), .light), (t.t("set.themeAuto"), .auto)],
                           selection: Binding(get: { app.settings.theme }, set: { v in app.update { $0.theme = v } }),
                           track: Palette(colorScheme).field)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .shotNode("root.theme")
                chapter(.view); chapter(.locale)
            }
            RubricLabel(text: t.t("set.rubSystem"))
            SettingsGroup {
                chapter(.places); chapter(.network); chapter(.data)
                Button { app.binOpen = true } label: {
                    SetItemRow(icon: "trash", title: t.t("card.bin"), value: app.trashed.isEmpty ? t.t("bin.emptyShort") : String(app.trashed.count), grouped: true)
                }.buttonStyle(.plain).shotNode("root.bin")
            }
            RubricLabel(text: t.t("set.grpAbout"))
            SettingsGroup { chapter(.about) }
        }
        .padding(.bottom, 8)
        .shotNode("nav")
    }

    private var moodboards: String {
        let n = app.mbFolders(app.mbLibrary()).count
        return n == 0 ? app.lexicon.t("card.none") : String(n)
    }

    private var places: some View {
        Button { app.placeSheetStart = .addr; app.placeSheetOpen = true } label: {
            SetItemRow(icon: "pin", title: app.lexicon.t("loc.myPlaces"),
                       value: app.spotCount > 0 ? String(app.spotCount) : app.lexicon.t("card.none"), grouped: true)
        }.buttonStyle(.plain).shotNode("root.places")
    }

    private func layer(_ icon: String, _ key: String, _ value: String, _ node: String, _ go: @escaping () -> Void) -> some View {
        Button { withAnimation(overlaySlide) { go() } } label: {
            SetItemRow(icon: icon, title: app.lexicon.t(key), value: value, grouped: true)
        }.buttonStyle(.plain).shotNode("root." + node)
    }

    @ViewBuilder private func chapter(_ ch: Chapter) -> some View {
        let t = app.lexicon
        let v = SettingsView.value(of: ch, app: app)
        if ch.opensLayer {
            Button { withAnimation(overlaySlide) { app.openClients() } } label: {
                SetItemRow(icon: ch.icon, title: t.t(ch.titleKey), value: v, grouped: true)
            }.buttonStyle(.plain).shotNode("nav." + ch.rawValue, text: t.t(ch.titleKey) + v)
        } else {
            NavigationLink(value: ch) {
                SetItemRow(icon: ch.icon, title: t.t(ch.titleKey), value: v, grouped: true)
            }.buttonStyle(.plain).shotNode("nav." + ch.rawValue, text: t.t(ch.titleKey) + v)
        }
    }
}
