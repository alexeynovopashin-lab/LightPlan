import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Контакты (`#phoneOverlay`, итерация 28, шаг 7)

/// Все номера из съёмок и организаций одним списком. Номер сверху, под ним карточки, где он встретился;
/// связка (номер в двух карточках) выделена латунью — ради неё список и заведён. Считается на лету
/// (`AppModel.contacts`), нигде не хранится. Строка записи открывает карточку записи, строка организации —
/// её карточку. Прежний номер — тише и без кнопки звонка, но узнаётся.
struct ContactsScreen: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        let list = app.contacts
        let links = PhoneBook.linkCount(list)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: t.t("nav.back"), node: "contacts.back") {
                    withAnimation(overlaySlide) { app.closeContacts() }
                }
                header(links, pal)
                if list.isEmpty {
                    Text(t.t("ph.empty")).font(.system(size: 13)).lineSpacing(5).foregroundStyle(pal.ink7)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14).padding(.horizontal, 2)
                        .shotNode("contacts.empty")
                }
                ForEach(Array(list.enumerated()), id: \.element.key) { gi, g in group(g, gi, pal) }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(pal.surface.ignoresSafeArea())
        .shotNode("contacts.list", text: "\(list.count)")
    }

    /// `.g-label` «Контакты» слева и «N связок» справа.
    private func header(_ links: Int, _ pal: Palette) -> some View {
        HStack {
            Text(t.t("set.contacts")).shotNode("contacts.title", text: t.t("set.contacts"))
            Spacer(minLength: 0)
            if links > 0 { Text(t.count("unit.link", links)).shotNode("contacts.count", text: "\(links)") }
        }
        .font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
        .foregroundStyle(pal.ink7)
        .padding(.top, 30).padding(.horizontal, 4).padding(.bottom, 0)
    }

    // MARK: группа-номер

    /// `.ph-row`: радиус 16, поля 13/14/8; сверху номер 16 pt, метки и звонок, ниже — «где встречается».
    private func group(_ g: PhoneBook.Group, _ gi: Int, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(TelFormat.format(g.phone, country: app.telCountry, pasted: true))
                    .font(.system(size: 16).monospacedDigit()).tracking(0.2)
                    .foregroundStyle(g.live ? pal.ink : pal.ink5).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if g.mine { tag(t.t("ph.mine"), pal.green) }
                if g.isLink { tag(t.t("ph.link"), pal.brass) }
                if !g.live { tag(t.t("ph.past"), pal.ink7, line: pal.hair2) }
                if g.live { call(g, gi, pal) }
            }
            VStack(spacing: 0) {
                ForEach(Array(g.rows.enumerated()), id: \.offset) { i, r in row(r, gi: gi, i: i, pal) }
            }
            .padding(.top, 6)
        }
        .padding(.top, 13).padding(.horizontal, 14).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
        .shotNode("contacts.group.\(gi)", text: g.key)
        .padding(.top, 12)
    }

    /// `.ph-tag`: 10 pt, прописные, разрядка 0,6, рамка 1, радиус 6, поле 3/6.
    private func tag(_ s: String, _ ink: Color, line: Color? = nil) -> some View {
        Text(s).font(.system(size: 10)).tracking(0.6).textCase(.uppercase).foregroundStyle(ink)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(line ?? ink, lineWidth: 1))
            .fixedSize()
    }

    /// `.ph-call`: 32×32, знак 18, `tel:` с международным номером.
    private func call(_ g: PhoneBook.Group, _ gi: Int, _ pal: Palette) -> some View {
        Button {
            if let u = URL(string: "tel:" + TelFormat.e164(g.phone, country: app.telCountry)) { openURL(u) }
        } label: {
            Icon("call", size: 18, line: 1.6).foregroundStyle(pal.ink5).frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("contacts.call.\(gi)")
        .accessibilityLabel(TelFormat.format(g.phone, country: app.telCountry, pasted: true))
    }

    /// `.ph-card`: знак жанра или города 15, заголовок 13, справа «роль · имя» 11; строки разделены линией.
    private func row(_ r: PhoneBook.Row, gi: Int, i: Int, _ pal: Palette) -> some View {
        Button { withAnimation(overlaySlide) { app.openContact(r) } } label: {
            HStack(spacing: 9) {
                sign(r, pal)
                Text(app.contactTitle(r)).font(.system(size: 13)).foregroundStyle(r.past ? pal.ink7 : pal.ink4).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(app.contactWho(r)).font(.system(size: 11)).foregroundStyle(pal.ink7).lineLimit(1).fixedSize()
            }
            .padding(.vertical, 8).frame(height: 32)
            .overlay(alignment: .top) { if i != 0 { Rectangle().fill(pal.surface).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("contacts.row.\(gi).\(i)", text: app.contactTitle(r) + "|" + app.contactWho(r))
    }

    @ViewBuilder private func sign(_ r: PhoneBook.Row, _ pal: Palette) -> some View {
        let ink = r.past ? pal.ink8 : pal.ink6
        switch r.card {
        case .org: Icon("city", size: 15, line: 1.6).foregroundStyle(ink)
        case .shoot(let id):
            let s = app.sessions.first { $0.id == id }
            let w = PlannerWords(lexicon: t, orgs: app.orgs)
            if let s, let n = w.iconName(s) { Icon(n, size: 15, line: 1.6).foregroundStyle(ink) }
            else { Icon(genre: s?.genre?.rawValue ?? "", size: 15, line: 1.6).foregroundStyle(ink) }
        }
    }
}
