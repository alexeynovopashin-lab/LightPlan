import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Карточка организации (`#orgCard`, итерация 28, шаг 6)

/// Один прокручиваемый экран, правки пишутся сразу (кнопки «Сохранить» нет — иначе её
/// забудут нажать ровно тогда, когда реквизиты нужны). Блоки: «Организация» (название, лицо,
/// телефон), «Реквизиты» (текст; «Файл» и «Снимок» приглушены до облака — слово Алексея 6-1),
/// «Документы организации» (свои и бумаги её съёмок), «Съёмки» (архив взаимодействия),
/// «Удалить организацию». Тот же экран открывается слоем поверх вкладок и листом из формы.
struct OrgCardScreen: View {
    @Bindable var app: AppModel
    let id: String
    let backTitle: String
    /// Из формы съёмки переход в чужую карточку съёмки закрыт: форма ещё открыта.
    var canOpenShoot = true
    let onBack: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var askingLink = false
    @State private var askingDelete = false
    @State private var reqNote: String?
    @State private var docNote: String?

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        let o = app.orgRecord(id) ?? Org(id: id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: backTitle, node: "orgc.back", action: onBack)
                label(t.t("org.one"), pal).shotNode("orgc.label")
                FormGroup(node: "orgc.group") {
                    FormTextField(placeholder: t.t("org.namePh"), text: text(\.name), kind: .text)
                }
                label(t.t("org.people"), pal)
                people(o, pal)
                label(t.t("doc.req"), pal)
                requisites(o, pal)
                label(t.t("org.docs"), pal)
                documents(o, pal)
                label(t.t("nav.shoots"), pal)
                shoots(o, pal)
                delete(o, pal)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(pal.surface.ignoresSafeArea())
        .shotNode("org.card", text: o.name)
        .sheet(isPresented: $askingLink) {
            AskTextSheet(title: t.t("org.docLinkAsk"), ok: t.t("ask.ok"), cancel: t.t("ask.cancel")) { url in
                askingLink = false
                if let url { app.addOrgDocLink(id, url) }
            }
        }
    }

    // MARK: связки с данными

    private func text(_ key: WritableKeyPath<Org, String>) -> Binding<String> {
        Binding(get: { app.orgRecord(id)?[keyPath: key] ?? "" },
                set: { v in app.editOrg(id) { $0[keyPath: key] = v } })
    }

    private func phone(_ o: Org) -> Binding<String> {
        Binding(get: { app.orgRecord(id)?.phone ?? "" }, set: { app.setOrgPhone(id, $0) })
    }

    // MARK: люди (Директор, Контактное лицо, «+ Добавить»; слово Алексея 01.10 — отход от беты)

    /// Строка: слева роль словом, справа имя и телефон. Директор и контактное лицо — постоянные; остальные
    /// добавляются «+ Добавить» с ролью, которую фотограф набирает сам, и убираются крестиком.
    private func people(_ o: Org, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FormGroup(node: "orgc.people") {
                fixedPerson(t.t("org.director"), name: text(\.director), phone: Binding(
                    get: { app.orgRecord(id)?.directorPhone ?? "" }, set: { app.setDirectorPhone(id, $0) }), pal)
                fixedPerson(t.t("form.person"), name: text(\.person), phone: phone(o), pal)
                ForEach(Array(o.staff.indices), id: \.self) { i in staffPerson(i, pal) }
            }
            Button { app.addOrgPerson(id) } label: {
                Text(t.t("org.addPerson")).font(.system(size: 15)).foregroundStyle(pal.brass)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).frame(height: 44)
                    .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shotNode("orgc.addPerson", text: t.t("org.addPerson"))
        }
    }

    private func fixedPerson(_ role: String, name: Binding<String>, phone: Binding<String>, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(role).font(.system(size: 12)).foregroundStyle(pal.ink4).padding(.horizontal, 15).padding(.top, 10)
            FormTextField(placeholder: t.t("org.personName"), text: name, kind: .name)
            FormTextField(placeholder: t.t("form.phone"), text: phone, kind: .phone)
        }
    }

    private func staffPerson(_ i: Int, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                FormTextField(placeholder: t.t("org.rolePh"), text: staffText(i, \.role), kind: .text)
                Button { app.removeOrgPerson(id, at: i) } label: {
                    Icon("close", size: 16, line: 2).foregroundStyle(pal.ink4).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.t("org.removePerson"))
            }
            FormTextField(placeholder: t.t("org.personName"), text: staffText(i, \.name), kind: .name)
            FormTextField(placeholder: t.t("form.phone"),
                          text: Binding(get: { app.orgRecord(id)?.staff[safe: i]?.phone ?? "" },
                                        set: { app.setOrgPersonPhone(id, at: i, $0) }), kind: .phone)
        }
    }

    private func staffText(_ i: Int, _ key: WritableKeyPath<OrgPerson, String>) -> Binding<String> {
        Binding(get: { app.orgRecord(id)?.staff[safe: i]?[keyPath: key] ?? "" },
                set: { v in app.editOrgPerson(id, at: i) { $0[keyPath: key] = v } })
    }

    /// `.g-label`: 10 / 600, прописные, разрядка 1,2 — над группой, у края 4.
    private func label(_ s: String, _ pal: Palette) -> some View { FormGroupLabel(text: s) }

    // MARK: реквизиты

    /// `#oReq` 392×190, 15 pt; под ним «Файл» и «Снимок» — приглушены: файлов до облака нет.
    private func requisites(_ o: Org, _ pal: Palette) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: text(\.requisites))
                    .font(.system(size: 15)).foregroundStyle(pal.ink).scrollContentBackground(.hidden)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                if o.requisites.isEmpty {
                    Text(t.t("org.reqPh")).font(.system(size: 15)).foregroundStyle(pal.ink8)
                        .padding(.horizontal, 15).padding(.vertical, 16).allowsHitTesting(false)
                }
            }
            .frame(height: 190)
            HStack(spacing: 8) {
                stub(t.t("doc.fileBtn"), icon: "doc", note: t.t("org.noDiskReq"), into: $reqNote, pal, node: "orgc.reqFile")
                stub(t.t("org.shotBtn"), icon: "album", note: t.t("org.noDiskReq"), into: $reqNote, pal, node: "orgc.reqShot")
            }
            .padding(12).padding(.horizontal, 3)
            .overlay(alignment: .top) { Rectangle().fill(pal.surface).frame(height: 1) }
            if let reqNote { noteText(reqNote, pal) }
        }
        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shotNode("orgc.req")
    }

    /// Кнопка, у которой нет дела до облака: приглушена и честно говорит почему, а не молчит.
    private func stub(_ title: String, icon: String, note: String, into target: Binding<String?>,
                      _ pal: Palette, node: String) -> some View {
        Button { target.wrappedValue = note } label: { buttonFace(title, icon: icon, pal) }
            .buttonStyle(.plain).opacity(0.4)
            .shotNode(node, text: title)
    }

    private func buttonFace(_ title: String, icon: String?, _ pal: Palette) -> some View {
        HStack(spacing: 7) {
            if let icon { Icon(icon, size: 17, line: 1.6) } else {
                LinkGlyph().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 17, height: 17)
            }
            Text(title).font(.system(size: 14))
        }
        .frame(minHeight: 20).foregroundStyle(pal.ink3)
        .frame(maxWidth: .infinity).padding(11)
        .background(pal.sheet4, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    private func noteText(_ s: String, _ pal: Palette) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(pal.ink4).lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15).padding(.bottom, 12)
    }

    // MARK: документы

    private func documents(_ o: Org, _ pal: Palette) -> some View {
        let list = OrgBook.docs(of: o, in: app.sessions, kind: app.org.docKind)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                FlowLayout(spacing: 7) {
                    ForEach(app.docKinds, id: \.self) { k in kindChip(k, OrgBook.docCount(of: o, in: app.sessions, kind: k), pal) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13).padding(.top, 12).padding(.bottom, 6)
                .shotNode("orgc.docKinds")
                HStack(spacing: 8) {
                    stub(t.t("doc.fileBtn"), icon: "doc", note: t.t("ref.noDiskDoc"), into: $docNote, pal, node: "orgc.docFile")
                    Button { askingLink = true } label: { buttonFace(t.t("ref.link"), icon: nil, pal) }
                        .buttonStyle(.plain).shotNode("orgc.docLink", text: t.t("ref.link"))
                }
                .padding(12).padding(.horizontal, 3)
                .overlay(alignment: .top) { Rectangle().fill(pal.surface).frame(height: 1) }
                if let docNote { noteText(docNote, pal) }
            }
            .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if list.isEmpty {
                (Text(t.t("org.docsEmptyHead")).foregroundStyle(pal.ink3) + Text(" " + t.t("org.docsEmptyTail")).foregroundStyle(pal.ink4))
                    .font(.system(size: 13)).lineSpacing(4).padding(.top, 12).padding(.horizontal, 4)
                    .shotNode("orgc.docsEmpty")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, d in docRow(d, i, pal) }
                }
                .padding(.top, 8)
            }
        }
    }

    /// Чип вида: выбранный и фильтрует список, и ставит вид новой бумаге (`#oDocKinds`).
    private func kindChip(_ k: DocKind, _ n: Int, _ pal: Palette) -> some View {
        let on = app.org.docKind == k
        return Button { app.org.docKind = on ? nil : k } label: {
            HStack(spacing: 5) {
                Text(app.docKindName(k)).font(webFont(13)).foregroundStyle(on ? pal.onBrass : pal.ink3)
                if n > 0 { Text("\(n)").font(webFont(13)).foregroundStyle(on ? pal.onBrass.opacity(0.6) : pal.ink6) }
            }
            .padding(.horizontal, 13).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? pal.brass : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? pal.brass : pal.press, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .shotNode("orgc.kind." + k.rawValue, text: "\(n)")
    }

    /// Строка бумаги 392×41: свои — с ✕, бумаги съёмок — с пометкой «съёмка {дата}» и без него.
    private func docRow(_ d: OrgBook.OrgDoc, _ n: Int, _ pal: Palette) -> some View {
        let kind = OrgBook.kind(of: d.doc)
        let top = kind.map(app.docKindName)
            ?? (d.doc.source == .link ? DocLabel.host(d.doc.url ?? "", linkWord: t.t("ref.link")) : (DocLabel.ext(d.doc.name ?? "") ?? t.t("doc.file")))
        let row = HStack(spacing: 11) {
            Button { open(d.doc) } label: {
                HStack(spacing: 11) {
                    Text(top).font(webFont(11)).tracking(0.2)
                        .foregroundStyle(pal.brass).lineLimit(1).frame(minWidth: 56, alignment: .leading)
                    Text(DocLabel.sub(d.doc, anyWord: t.t("doc.any"))).font(webFont(14)).foregroundStyle(pal.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(app.docTrailing(d.doc))
                        .font(webFont(11.5)).foregroundStyle(pal.ink6).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let i = d.index {
                Button { app.removeOrgDoc(id, at: i) } label: {
                    Text("✕").font(.system(size: 13)).foregroundStyle(pal.ink4).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).shotNode("orgc.docDel.\(n)")
            }
        }
        .padding(.horizontal, 14).frame(height: 41)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
        .shotNode("orgc.docRow.\(n)")
        // Бумага съёмки: дата отдельной строкой под рядом, без года (веб `.org-empty` под `.doc-row`).
        return VStack(spacing: 0) {
            row
            if let day = d.day {
                let f = PlannerFacts(app: app, dark: true)
                Text(t.t("org.fromShoot") + " " + f.dates.dMon(f.date(day))).font(webFont(13)).foregroundStyle(pal.ink6)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 2)
            }
        }
    }

    private func open(_ d: Attachment) {
        if d.source == .link, let u = d.url.flatMap(URL.init(string:)) { openURL(u); docNote = nil; return }
        docNote = t.t("doc.openFail")
    }

    private func dayText(_ d: CivilDate) -> String {
        let f = PlannerFacts(app: app, dark: true)
        return f.dates.dMonYear(f.date(d))
    }

    // MARK: съёмки организации

    private func shoots(_ o: Org, _ pal: Palette) -> some View {
        let list = OrgBook.shoots(of: o.id, in: app.sessions)
        let words = PlannerWords(lexicon: t, orgs: app.orgs)
        return VStack(spacing: 10) {
            if list.isEmpty {
                Text(t.t("org.noShoots")).font(.system(size: 14)).foregroundStyle(pal.ink4)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).padding(.horizontal, 4)
                    .shotNode("orgc.noShoots")
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { si, s in
                Button { if canOpenShoot { withAnimation(overlaySlide) { app.openOrgShoot(s.id) } } } label: {
                    HStack(spacing: 14) {
                        Group {
                            if let n = words.iconName(s) { Icon(n, size: 18, line: 1.6) } else { Icon(genre: s.genre?.rawValue ?? "", size: 18, line: 1.6) }
                        }
                        .foregroundStyle(pal.ink4)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(pal.press))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(words.typeName(s) + " · " + dayText(s.day)).font(webFont(15)).foregroundStyle(pal.ink).lineLimit(1)
                            Text(app.orgShootMoney(s)).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if canOpenShoot { Icon("chevron", size: 16, line: 2.4).foregroundStyle(pal.ink6) }
                    }
                    .padding(14).frame(height: 64)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheet))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .shotNode("orgc.shoot.\(si)", text: s.id)
            }
        }
    }

    // MARK: удаление

    private func delete(_ o: Org, _ pal: Palette) -> some View {
        Button {
            if app.orgShootCount(id) > 0 { askingDelete = true } else { app.deleteOrg(id); onBack() }
        } label: {
            Text(t.t("org.del")).font(.system(size: 15)).foregroundStyle(Color(hex: pal.dark ? 0xB9603D : 0x9E4722))
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.top, 28)
        .shotNode("orgc.delete", text: t.t("org.del"))
        .alert(t.t("org.delAsk", ["n": t.count("unit.shoot", app.orgShootCount(id))]), isPresented: $askingDelete) {
            Button(t.t("ask.del"), role: .destructive) { app.deleteOrg(id); onBack() }
            Button(t.t("ask.cancel"), role: .cancel) {}
        }
    }
}

extension AppModel {
    /// Вторая строка съёмки в архиве: сумма и «внесено N» (предоплата, если меньше суммы); суммы нет — «сумма не задана».
    func orgShootMoney(_ s: Session) -> String {
        let income = Money.income(of: s, among: sessions)
        guard income > 0 else { return lexicon.t("org.noSum") }
        let nt = NumberText(language: language)
        let cur = Money.currency(of: s, home: settings.currency).rawValue
        func m(_ v: Decimal) -> String { nt.money(NSDecimalNumber(decimal: v).doubleValue, cur) }
        return s.prepay > 0 && s.prepay < income ? m(income) + " · " + lexicon.t("org.paidIn", ["sum": m(s.prepay)]) : m(income)
    }
}
