import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Карточка клиента (шаг К2, справка `docs/clients_reference.md` § 4.4)

/// Один прокручиваемый экран, правки пишутся сразу (как карточка организации). Сверху имя и вид «Пара | Семья | Персона»,
/// подсказка «этот номер есть у другого клиента — объединить?», люди (имя, телефон со звонком), свои ссылки клиента и
/// ссылки его съёмок, съёмки с суммами — они **считаются** из съёмок с этим клиентом, в клиенте не хранятся; внизу
/// «Объединить с другим клиентом» и «Удалить клиента». Мессенджеры людей, кнопка «написать» у телефона и «Пишем» —
/// шаг К4. Дни рождения людей, годовщина пары и «Поздравлять» — шаг К6 (`AppModel+Greetings`).
struct ClientCardScreen: View {
    @Bindable var app: AppModel
    let id: String
    let onBack: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var askingLink = false
    @State private var askingDelete = false
    /// Подсказка «объединить?» ждёт подтверждения: кого вливаем.
    @State private var askingMerge: ClientTwinRow?
    /// Открыт лист даты: чей день рождения или годовщина.
    @State private var dateAsk: DateAsk?

    private enum DateAsk: Identifiable, Hashable {
        case birthday(Int), anniversary
        var id: Self { self }
    }

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        let c = app.clientRecord(id) ?? Client(id: id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: t.t(app.org.clientBackKey), node: "clc.back", action: onBack)
                Text(app.clientTitle(c)).font(webFont(26, 700)).tracking(-0.5).foregroundStyle(pal.ink)
                    .lineLimit(2).padding(.top, 14).padding(.horizontal, 4)
                    .shotNode("clc.title", text: app.clientTitle(c))
                ClientsSeg(options: [(t.t("clc.kindCouple"), ClientKind.couple), (t.t("clc.kindFamily"), .family),
                                     (t.t("clc.kindPerson"), .person)],
                           selection: Binding(get: { app.clientRecord(id)?.kind ?? .person }, set: { app.setClientKind(id, $0) }),
                           stretch: true, node: "clc.kinds", itemNode: "clc.kind")
                    .padding(.top, 14)
                twins(pal)
                people(c, pal)
                greet(c, pal)
                FormGroupLabel(text: t.t("clc.links"))
                links(c, pal)
                FormGroupLabel(text: t.t("nav.shoots"))
                shoots(pal)
                actions(c, pal)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(pal.surface.ignoresSafeArea())
        .binSubject(app, "client." + id)
        .shotNode("clc.card", text: c.kind.rawValue)
        .sheet(isPresented: $askingLink) {
            AskLinkSheet(title: t.t("clc.linkAsk"), titleField: t.t("doc.titleOpt"), ok: t.t("ask.ok"), cancel: t.t("ask.cancel"),
                         dateWords: nil) { a in
                askingLink = false
                if let a { app.addClientLink(id, a.url, title: a.title) }
            }
        }
        .sheet(item: $dateAsk) { dateSheet($0) }
        .sheet(isPresented: $app.org.clientPick) {
            ClientMergePicker(app: app, targetId: id)
        }
        .alert(mergeQuestion(askingMerge), isPresented: Binding(get: { askingMerge != nil }, set: { if !$0 { askingMerge = nil } })) {
            Button(t.t("clc.mergeOk")) { if let m = askingMerge { app.mergeClient(m.clientId, into: id) }; askingMerge = nil }
            Button(t.t("ask.cancel"), role: .cancel) { askingMerge = nil }
        } message: {
            Text(mergeBody(askingMerge))
        }
    }

    private func mergeQuestion(_ m: ClientTwinRow?) -> String {
        guard let m, let c = app.clientRecord(id) else { return "" }
        return t.t("clc.mergeAsk", ["a": app.clientTitle(c), "b": m.title])
    }

    private func mergeBody(_ m: ClientTwinRow?) -> String {
        guard let m, let c = app.clientRecord(id) else { return "" }
        return t.t("clc.mergeBody", ["a": app.clientTitle(c), "b": m.title])
    }

    // MARK: «номер есть у другого клиента» (§ 3.4)

    @ViewBuilder private func twins(_ pal: Palette) -> some View {
        let list = app.clientTwins(id)
        if !list.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, tw in
                    HStack(alignment: .center, spacing: 12) {
                        Icon("couple", size: 17, line: 1.6).foregroundStyle(pal.brass)
                        Text(t.t("clc.twin", ["tel": tw.phone, "name": tw.title]))
                            .font(.system(size: 14)).foregroundStyle(pal.ink3).lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { askingMerge = tw } label: {
                            Text(t.t("clc.mergeOk")).font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.brass)
                                .padding(.horizontal, 12).frame(height: 34)
                                .background(pal.pressBrass, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .shotNode("clc.twinMerge.\(i)", text: tw.clientId)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shotNode("clc.twin.\(i)", text: tw.title)
                }
            }
            .padding(.top, 14)
        }
    }

    // MARK: люди

    /// Человек — группа «имя / телефон»; у телефона кнопка звонка. Подпись группы — «Человек», у пары и семьи — с номером.
    private func people(_ c: Client, _ pal: Palette) -> some View {
        let many = c.kind != .person || c.people.count > 1
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(c.people.indices), id: \.self) { i in
                HStack(spacing: 0) {
                    FormGroupLabel(text: many ? t.t("clc.personN", ["n": "\(i + 1)"]) : t.t("clc.person"))
                    if c.people.count > 1 {
                        Button { app.removeClientPerson(id, at: i) } label: {
                            Icon("close", size: 14, line: 2).foregroundStyle(pal.ink5)
                                .frame(width: 32, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).padding(.top, 21)
                        .accessibilityLabel(t.t("clc.removePerson"))
                        .shotNode("clc.removePerson.\(i)")
                    }
                }
                FormGroup(node: "clc.person.\(i)") {
                    FormTextField(placeholder: t.t("clc.namePh"),
                                  text: Binding(get: { app.clientRecord(id)?.people[safe: i]?.name ?? "" },
                                                set: { app.setClientPersonName(id, at: i, $0) }), kind: .name)
                    HStack(spacing: 0) {
                        FormTextField(placeholder: t.t("form.phone"),
                                      text: Binding(get: { app.clientRecord(id)?.people[safe: i]?.phone ?? "" },
                                                    set: { app.setClientPersonPhone(id, at: i, $0) }), kind: .phone)
                        callButton(c.people[i].phone, i, pal)
                        reachButton(c, i, pal)
                    }
                    birthdayRow(c.people[i], i, pal)
                    ForEach(c.people[i].messengers.compactMap { MessengerKind(rawValue: $0.kind) }, id: \.self) { k in
                        messengerRow(c.people[i], i, k, pal)
                    }
                    addMessenger(c.people[i], i, pal)
                }
            }
            writeTo(c)
            if ClientBook.canAddPerson(c) {
                Button { app.addClientPerson(id) } label: {
                    Text(t.t("clc.addPerson")).font(.system(size: 15)).foregroundStyle(pal.brass)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).frame(height: 44)
                        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.top, 8)
                .shotNode("clc.addPerson", text: t.t("clc.addPerson"))
            }
        }
    }

    /// Звонок: номер настоящий (пять цифр и больше) — кнопка с трубкой; набирается международный номер.
    @ViewBuilder private func callButton(_ phone: String, _ i: Int, _ pal: Palette) -> some View {
        if TelFormat.isReal(phone, country: app.telCountry) {
            let e = TelFormat.e164(phone, country: app.telCountry)
            let dial = e.isEmpty ? phone.filter { $0.isNumber || $0 == "+" } : e
            Button { if let u = URL(string: "tel:" + dial) { openURL(u) } } label: {
                Icon("phone", size: 17).foregroundStyle(pal.brass).frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(PressFade())
            .accessibilityLabel(t.t("clc.call"))
            .shotNode("clc.call.\(i)")
        }
    }

    // MARK: праздники (К6, § 6)

    private var facts: PlannerFacts { PlannerFacts(app: app, dark: true) }

    /// «2 ноября» без года, «2 ноября 1990» с годом.
    private func dayText(year: Int?, month: Int, day: Int) -> String {
        let f = facts
        let d = f.date(CivilDate(year: year ?? 2000, month: month, day: day))
        return year == nil ? f.dates.dMon(d) : f.dates.dMonYear(d)
    }

    /// «День рождения»: дата справа, под подписью — сколько лет, если год известен. Нет даты — латунное «Добавить».
    private func birthdayRow(_ p: ClientPerson, _ i: Int, _ pal: Palette) -> some View {
        let b = Birthday(p.birthday)
        let age = b?.age(on: app.today).map { t.count("clc.age", $0) }
        return Button { dateAsk = .birthday(i) } label: {
            FormSubRow(node: "clc.bday.\(i)", label: t.t("clc.bday"), sub: age) {
                Text(b.map { dayText(year: $0.year, month: $0.month, day: $0.day) } ?? t.t("clc.dateAdd"))
                    .font(.system(size: 16)).foregroundStyle(b == nil ? pal.brass : pal.ink3)
                    .shotNode("clc.bdayValue.\(i)", text: p.birthday ?? "")
            }
        }
        .buttonStyle(.plain)
    }

    /// Годовщина пары (у пары), «Поздравлять» и строка о том, что будет: в 10:00 в день праздника. Уведомления запрещены
    /// в настройках iPhone — строка ведёт туда.
    private func greet(_ c: Client, _ pal: Palette) -> some View {
        let denied = app.greetNeedsSettings(c)
        let ask = app.greetNeedsAsk(c)
        return VStack(alignment: .leading, spacing: 0) {
            FormGroupLabel(text: t.t("clc.greetSec"))
            FormGroup(node: "clc.greetGroup") {
                if c.kind == .couple {
                    let a = app.clientAnniversary(c)
                    Button { dateAsk = .anniversary } label: {
                        FormSubRow(node: "clc.anniv", label: t.t("clc.anniv"),
                                   sub: app.clientAnniversaryFromWedding(c) ? t.t("clc.annivWedding") : nil) {
                            Text(a.map { dayText(year: $0.year, month: $0.month, day: $0.day) } ?? t.t("clc.dateAdd"))
                                .font(.system(size: 16)).foregroundStyle(a == nil ? pal.brass : pal.ink3)
                                .shotNode("clc.annivValue", text: a?.snapshotString ?? "")
                        }
                    }
                    .buttonStyle(.plain)
                }
                FormToggleRow(node: "clc.greet", label: t.t("clc.greet"), on: c.greet) { app.setClientGreet(id, $0) }
            }
            Button {
                if ask { app.askGreetPermission() }
                #if os(iOS)
                if denied, let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                #endif
            } label: {
                Text(t.t(denied ? "clc.greetDenied" : ask ? "clc.greetAsk" : "clc.greetNote")).font(.system(size: 13))
                    .foregroundStyle(denied || ask ? pal.brass : pal.ink4).lineSpacing(4).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4).padding(.top, 8)
            }
            .buttonStyle(.plain)
            .disabled(!denied && !ask)
            .shotNode("clc.greetNote", text: denied ? "denied" : ask ? "ask" : "note")
        }
    }

    @ViewBuilder private func dateSheet(_ ask: DateAsk) -> some View {
        let c = app.clientRecord(id) ?? Client(id: id)
        let today = app.today
        let f = facts
        let words = { (title: String) in
            ClientDateSheet.Words(title: title, noYear: t.t("clc.noYear"), ok: t.t("clc.dateOk"), cancel: t.t("ask.cancel"),
                                  clear: t.t("clc.dateClear"))
        }
        let month = { (m: Int) in f.dates.monthTitle(f.date(CivilDate(year: 2000, month: m, day: 1))) }
        switch ask {
        case .birthday(let i):
            let b = Birthday(c.people[safe: i]?.birthday)
            ClientDateSheet(words: words(t.t("clc.bday")), yearOptional: true, canClear: b != nil, thisYear: today.year,
                            initial: b.map { ($0.year, $0.month, $0.day) } ?? (nil, today.month, today.day),
                            monthName: month) { a in
                dateAsk = nil
                switch a {
                case .set(let y, let m, let d): app.setClientBirthday(id, at: i, Birthday(year: y, month: m, day: d))
                case .clear: app.setClientBirthday(id, at: i, nil)
                case .cancel: break
                }
            }
        case .anniversary:
            let a = app.clientAnniversary(c)
            ClientDateSheet(words: words(t.t("clc.anniv")), yearOptional: false, canClear: a != nil, thisYear: today.year,
                            initial: a.map { ($0.year, $0.month, $0.day) } ?? (today.year, today.month, today.day),
                            monthName: month) { ans in
                dateAsk = nil
                switch ans {
                case .set(let y, let m, let d):
                    app.setClientAnniversary(id, CivilDate(year: y ?? today.year, month: m, day: d))
                case .clear: app.setClientAnniversary(id, nil)
                case .cancel: break
                }
            }
        }
    }

    // MARK: мессенджеры (К4, § 7.1)

    /// Кнопка мессенджера у телефона: основной способ этого человека (звёздочка, иначе первый мессенджер, иначе SMS),
    /// долгое нажатие — все его способы.
    @ViewBuilder private func reachButton(_ c: Client, _ i: Int, _ pal: Palette) -> some View {
        if let plan = app.personReach(c.people[i]) {
            ReachButton(plan: plan, pal: pal, titled: false, node: "clc.reach.\(i)", write: { t.t("reach.write", ["way": $0]) })
        }
    }

    /// Строка мессенджера: название, поле (вставленная ссылка профиля становится именем), звёздочка «основной», ✕.
    private func messengerRow(_ p: ClientPerson, _ i: Int, _ k: MessengerKind, _ pal: Palette) -> some View {
        let main = ClientReach.primary(of: p, country: app.telCountry)?.way == .messenger(k)
        return HStack(spacing: 0) {
            Text(k.title).font(.system(size: 15)).foregroundStyle(pal.ink3)
                .frame(width: 92, alignment: .leading).padding(.leading, 15)
            TextField("", text: Binding(get: { app.clientRecord(id)?.people[safe: i]?.messengers.first { $0.kind == k.rawValue }?.value ?? "" },
                                        set: { app.setClientMessenger(id, at: i, k, $0) }),
                      prompt: Text(placeholder(k, p)).foregroundStyle(pal.ink8))
                .font(.system(size: 16)).foregroundStyle(pal.ink)
                #if os(iOS)
                .textInputAutocapitalization(.never).keyboardType(k == .whatsapp ? .phonePad : .URL)
                #endif
                .autocorrectionDisabled()
                .frame(height: 48)
            Button { app.setClientPreferred(id, at: i, k) } label: {
                Icon("star", size: 16, line: 1.6).foregroundStyle(main ? pal.brass : pal.ink7)
                    .frame(width: 40, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.t("clc.msgMain"))
            .accessibilityAddTraits(main ? .isSelected : [])
            .shotNode("clc.msgMain.\(i).\(k.rawValue)", text: main ? "on" : "off")
            Button { app.removeClientMessenger(id, at: i, k) } label: {
                Icon("close", size: 13, line: 2).foregroundStyle(pal.ink5).frame(width: 36, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.t("clc.msgRemove"))
        }
        .shotNode("clc.msg.\(i).\(k.rawValue)", text: k.rawValue)
    }

    /// Подсказка поля: что вписать. У Telegram и WhatsApp пустое поле значит «по номеру телефона».
    private func placeholder(_ k: MessengerKind, _ p: ClientPerson) -> String {
        let tel = TelFormat.isReal(p.phone, country: app.telCountry)
        switch k {
        case .telegram: return t.t(tel ? "clc.msgPhTgTel" : "clc.msgPhTg")
        case .vk: return t.t("clc.msgPhVk")
        case .instagram: return t.t("clc.msgPhIg")
        case .whatsapp: return t.t(tel ? "clc.msgPhWaTel" : "clc.msgPhWa")
        case .max: return t.t("clc.msgPhMax")
        }
    }

    /// «+ мессенджер»: меню тех, каких у человека ещё нет.
    @ViewBuilder private func addMessenger(_ p: ClientPerson, _ i: Int, _ pal: Palette) -> some View {
        let left = ClientReach.missing(in: p)
        if !left.isEmpty {
            Menu {
                ForEach(left, id: \.self) { k in Button(k.title) { app.addClientMessenger(id, at: i, k) } }
            } label: {
                Text(t.t("clc.addMessenger")).font(.system(size: 15)).foregroundStyle(pal.brass)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).frame(height: 44)
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .shotNode("clc.addMsg.\(i)", text: t.t("clc.addMessenger"))
        }
    }

    /// «Пишем»: кому из людей пишет кнопка в шапке съёмки. Только когда связаться можно больше чем с одним.
    @ViewBuilder private func writeTo(_ c: Client) -> some View {
        let options = app.clientWriters(c)
        if options.count > 1 {
            FormGroupLabel(text: t.t("clc.writeTo"))
            ClientsSeg(options: options,
                       selection: Binding(get: { app.clientRecord(id).flatMap { ClientReach.writer(of: $0, country: app.telCountry) } ?? 0 },
                                          set: { app.setClientMain(id, $0) }),
                       stretch: true, node: "clc.writeTo", itemNode: "clc.writer")
        }
    }

    // MARK: ссылки

    /// Свои ссылки клиента (с ✕) и ссылки его съёмок — те живут в съёмках, здесь только видны (с датой съёмки).
    private func links(_ c: Client, _ pal: Palette) -> some View {
        let shootLinks = ClientBook.shootLinks(of: id, in: app.sessions)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(c.links.enumerated()), id: \.element.id) { i, d in
                linkRow(d, day: nil, node: "clc.link.\(i)", pal) { app.removeClientLink(id, linkId: d.id) }
            }
            Button { askingLink = true } label: {
                HStack(spacing: 7) {
                    LinkGlyph().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 17, height: 17)
                    Text(t.t("clc.addLink")).font(.system(size: 15))
                }
                .foregroundStyle(pal.brass)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).frame(height: 44)
                .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shotNode("clc.addLink", text: t.t("clc.addLink"))
            ForEach(Array(shootLinks.enumerated()), id: \.offset) { i, l in
                linkRow(l.doc, day: l.day, node: "clc.shootLink.\(i)", pal, remove: nil)
            }
            if c.links.isEmpty && shootLinks.isEmpty {
                Text(t.t("clc.linksEmpty")).font(.system(size: 13)).foregroundStyle(pal.ink4).lineSpacing(4)
                    .padding(.horizontal, 4).padding(.top, 2)
                    .shotNode("clc.linksEmpty")
            }
        }
    }

    /// Строка ссылки 41 pt как бумага организации: слева хозяин адреса латунью, название, справа ✕ у своих.
    private func linkRow(_ d: Attachment, day: CivilDate?, node: String, _ pal: Palette, remove: (() -> Void)?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Button { if let u = d.url.flatMap(URL.init(string:)) { openURL(u) } } label: {
                    HStack(spacing: 11) {
                        Text(DocLabel.host(d.url ?? "", linkWord: t.t("ref.link"))).font(webFont(11)).tracking(0.2)
                            .foregroundStyle(pal.brass).lineLimit(1).frame(minWidth: 56, alignment: .leading)
                        Text(DocLabel.sub(d, anyWord: t.t("doc.any"))).font(webFont(14)).foregroundStyle(pal.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let remove {
                    Button(action: remove) {
                        Text("✕").font(.system(size: 13)).foregroundStyle(pal.ink4).frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain).shotNode(node + ".del")
                }
            }
            .padding(.horizontal, 14).frame(height: 41)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
            .shotNode(node)
            if let day {
                let f = PlannerFacts(app: app, dark: true)
                Text(t.t("org.fromShoot") + " " + f.dates.dMon(f.date(day))).font(webFont(13)).foregroundStyle(pal.ink6)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 2)
            }
        }
    }

    // MARK: съёмки (вычисляются)

    private func shoots(_ pal: Palette) -> some View {
        let list = ClientBook.shoots(of: id, in: app.sessions)
        let words = PlannerWords(lexicon: t, orgs: app.orgs)
        let f = PlannerFacts(app: app, dark: true)
        return VStack(alignment: .leading, spacing: 10) {
            Text(app.clientLine(id)).font(webFont(13)).foregroundStyle(pal.ink4)
                .padding(.horizontal, 4)
                .shotNode("clc.total", text: app.clientLine(id))
            ForEach(Array(list.enumerated()), id: \.element.id) { si, s in
                Button { withAnimation(overlaySlide) { app.openClientShoot(s.id) } } label: {
                    HStack(spacing: 14) {
                        Group {
                            if let n = words.iconName(s) { Icon(n, size: 18, line: 1.6) } else { Icon(genre: s.genre?.rawValue ?? "", size: 18, line: 1.6) }
                        }
                        .foregroundStyle(pal.ink4)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(pal.press))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(words.typeName(s) + " · " + f.dates.dMonYear(f.date(s.day))).font(webFont(15)).foregroundStyle(pal.ink).lineLimit(1)
                            Text(app.orgShootMoney(s)).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Icon("chevron", size: 16, line: 2.4).foregroundStyle(pal.ink6)
                    }
                    .padding(14).frame(height: 64)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .shotNode("clc.shoot.\(si)", text: s.id)
            }
        }
    }

    // MARK: объединить, удалить

    private func actions(_ c: Client, _ pal: Palette) -> some View {
        VStack(spacing: 10) {
            if !app.clientMergeCandidates(id).isEmpty && app.clients.contains(where: { $0.id == id }) {
                Button { app.org.clientPick = true } label: {
                    Text(t.t("clc.merge")).font(.system(size: 15)).foregroundStyle(pal.ink3)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .shotNode("clc.merge", text: t.t("clc.merge"))
            }
            Button {
                if app.clientShootCount(id) > 0 { askingDelete = true } else { erase() }
            } label: {
                Text(t.t("clc.del")).font(.system(size: 15)).foregroundStyle(Color(hex: pal.dark ? 0xB9603D : 0x9E4722))
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shotNode("clc.delete", text: t.t("clc.del"))
            .alert(t.t("clc.delAsk", ["n": t.count("unit.shoot", app.clientShootCount(id))]), isPresented: $askingDelete) {
                Button(t.t("ask.del"), role: .destructive) { erase() }
                Button(t.t("ask.cancel"), role: .cancel) {}
            }
        }
        .padding(.top, 28)
    }

    /// Клиент стирается насовсем (без «Вернуть»), с тем же полётом и звуком, что организация.
    private func erase() {
        let id = id
        app.flyToBin(["client." + id]) {
            let open = app.org.clientCardId == id
            app.deleteClient(id)
            if open { onBack() }
        }
    }
}

/// Лист «С кем объединить»: все остальные клиенты строками списка «Частные»; нажатие спрашивает подтверждение.
struct ClientMergePicker: View {
    @Bindable var app: AppModel
    let targetId: String
    @Environment(\.colorScheme) private var scheme
    @State private var asking: ClientTwinRow?

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        let target = app.clientRecord(targetId).map(app.clientTitle) ?? ""
        let list = app.clientMergeCandidates(targetId)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(t.t("clc.pickTitle", ["name": target])).font(webFont(19, 600)).foregroundStyle(pal.ink)
                    .padding(.top, 22).padding(.horizontal, 4)
                    .shotNode("clc.pickTitle")
                Text(t.t("clc.pickHint")).font(.system(size: 13)).foregroundStyle(pal.ink4).lineSpacing(4)
                    .padding(.horizontal, 4).padding(.bottom, 4)
                ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                    Button { asking = ClientTwinRow(clientId: c.id, title: app.clientTitle(c), phone: "") } label: {
                        HStack(spacing: 14) {
                            Icon(AppModel.clientIcon(c.kind), size: 18, line: 1.6).foregroundStyle(pal.ink4)
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(pal.press))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.clientTitle(c)).font(webFont(15)).foregroundStyle(pal.ink).lineLimit(1)
                                Text(app.clientLine(c.id)).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14).frame(height: 64)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .shotNode("clc.pick.\(i)", text: app.clientTitle(c))
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
        .background(pal.surface.ignoresSafeArea())
        .shotNode("clc.picker", text: "\(list.count)")
        .presentationDetents([.large])
        .alert(asking.map { t.t("clc.mergeAsk", ["a": target, "b": $0.title]) } ?? "",
               isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            Button(t.t("clc.mergeOk")) { if let a = asking { app.mergeClient(a.clientId, into: targetId) }; asking = nil }
            Button(t.t("ask.cancel"), role: .cancel) { asking = nil }
        } message: {
            Text(asking.map { t.t("clc.mergeBody", ["a": target, "b": $0.title]) } ?? "")
        }
    }
}
