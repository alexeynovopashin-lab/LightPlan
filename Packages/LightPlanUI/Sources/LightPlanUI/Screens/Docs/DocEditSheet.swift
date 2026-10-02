import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Лист бумаги: быстрое «+» и правка (итерация 28д, шаг 4; справка § 6.3)

/// Один лист на «+» и «Править»: вид (чипы), ссылка, название, день, привязка. Правится в заготовке
/// (`DocDraft`) и пишется только по «Добавить» / «Сохранить». Привязка — раскрывашка: «Мои», пять
/// последних съёмок, пять последних организаций и «Другая…» с полным списком и поиском. Название и день
/// за человека не подставляются.
struct DocEditSheet: View {
    @Bindable var app: AppModel
    let mode: DocSheet
    @State private var draft = DocDraft()
    @State private var loaded = false
    @State private var bindOpen = false
    @State private var page: Page = .form
    @State private var query = ""
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focus: Field?

    private enum Page { case form, sessions, orgs }
    private enum Field { case url, title }
    private var t: Lexicon { app.lexicon }
    private var editing: Bool { if case .edit = mode { true } else { false } }

    var body: some View {
        let pal = Palette(scheme)
        Group {
            switch page {
            case .form: form(pal)
            case .sessions: picker(pal, sessions: true)
            case .orgs: picker(pal, sessions: false)
            }
        }
        .background(pal.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let d = app.docDraft(for: mode) { draft = d }
        }
    }

    // MARK: форма

    private func form(_ pal: Palette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(pal.edge).frame(width: 38, height: 4).frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 18)
                Text(t.t(editing ? "doc.editTitle" : "doc.addTitle")).font(.system(size: 19, weight: .semibold)).tracking(-0.2)
                    .foregroundStyle(pal.ink).accessibilityAddTraits(.isHeader)
                    .shotNode("doc.sheet.title", text: editing ? "edit" : "add")
                label(t.t("doc.addKind"), pal).padding(.top, 16)
                kinds(pal)
                if draft.linkEditable {
                    label(t.t("doc.linkOpt"), pal).padding(.top, 14)
                    linkField(pal)
                }
                label(t.t("doc.titleOpt"), pal).padding(.top, 14)
                field($draft.title, .title, pal).shotNode("doc.sheet.name")
                if !draft.owner.isSession { dateRow(pal).padding(.top, 10) }
                label(t.t("doc.addBind"), pal).padding(.top, 14)
                bindBlock(pal)
                Button(action: submit) {
                    Text(t.t(editing ? "doc.save" : "ask.ok")).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(pal.onBrass).frame(maxWidth: .infinity).padding(16)
                        .background(pal.brass.opacity(draft.canSave ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain).disabled(!draft.canSave)
                .padding(.top, 18).shotNode("doc.sheet.ok", text: draft.canSave ? "on" : "off")
                Button { app.closeDocSheet() } label: {
                    Text(t.t("ask.cancel")).font(.system(size: 15)).foregroundStyle(pal.ink3)
                        .frame(maxWidth: .infinity).padding(.vertical, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.top, 6).shotNode("doc.sheet.cancel")
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        .shotNode("doc.sheet", text: editing ? "edit" : "add")
    }

    private func label(_ s: String, _ pal: Palette) -> some View {
        Text(s).font(webFont(11)).tracking(0.2).foregroundStyle(pal.ink6).padding(.bottom, 7)
    }

    // MARK: вид

    /// Чипы как у видов полки (34 pt, радиус 11, 13 pt) + «Без вида».
    private func kinds(_ pal: Palette) -> some View {
        FlowLayout(spacing: 7) {
            chip(t.t("doc.noKind"), on: draft.kind == nil, id: "none", pal) { draft.pickKind(nil) }
            ForEach(app.docKinds, id: \.self) { k in
                chip(app.docKindName(k), on: draft.kind == k, id: k.rawValue, pal) { draft.pickKind(k) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ title: String, on: Bool, id: String, _ pal: Palette, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title).font(webFont(13)).foregroundStyle(on ? pal.onBrass : pal.ink3)
                .padding(.horizontal, 13).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? pal.brass : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? pal.brass : pal.press, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .shotNode("doc.sheet.kind." + id, text: on ? "on" : "off")
    }

    // MARK: поля

    private func linkField(_ pal: Palette) -> some View {
        HStack(spacing: 6) {
            TextField("", text: Binding(get: { draft.url }, set: { draft.setURL($0) }), prompt: Text("https://").foregroundColor(pal.ink6))
                .font(.system(size: 16)).foregroundStyle(pal.ink).focused($focus, equals: .url)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled(true)
                .submitLabel(.next).onSubmit { focus = .title }
                .shotNode("doc.sheet.url", text: draft.url)
            Button {
                if let s = UIPasteboard.general.string { draft.setURL(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
            } label: {
                Text(t.t("doc.paste")).font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.brass)
                    .padding(.horizontal, 8).frame(minHeight: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain).shotNode("doc.sheet.paste")
        }
        .padding(.vertical, 7).padding(.leading, 15).padding(.trailing, 7)
        .background(focus == .url ? pal.press : pal.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func field(_ text: Binding<String>, _ f: Field, _ pal: Palette) -> some View {
        TextField("", text: text, prompt: Text(t.t("doc.titleOpt")).foregroundColor(pal.ink6))
            .font(.system(size: 16)).foregroundStyle(pal.ink).focused($focus, equals: f)
            .textInputAutocapitalization(.sentences).submitLabel(.done).onSubmit { focus = nil }
            .padding(.vertical, 14).padding(.horizontal, 15)
            .background(focus == f ? pal.press : pal.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// «Дата — Без даты»: тап ставит сегодня и открывает выбор, крестик снимает (как в 12б). Сама не ставится.
    private func dateRow(_ pal: Palette) -> some View {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let binding = Binding<Date>(
            get: { let d = draft.date ?? app.today; return utc.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: 12)) ?? Date() },
            set: { let c = utc.dateComponents([.year, .month, .day], from: $0)
                   if let y = c.year, let m = c.month, let d = c.day { draft.date = CivilDate(year: y, month: m, day: d) } })
        return HStack(spacing: 10) {
            Text(t.t("doc.colDate")).font(.system(size: 16)).foregroundStyle(pal.ink3)
            Spacer(minLength: 0)
            if draft.date == nil {
                Button { draft.date = app.today; focus = nil } label: {
                    Text(t.t("doc.noDate")).font(.system(size: 16)).foregroundStyle(pal.ink6).contentShape(Rectangle())
                }
                .buttonStyle(.plain).shotNode("doc.sheet.dateNone", text: t.t("doc.noDate"))
            } else {
                DatePicker("", selection: binding, displayedComponents: .date)
                    .labelsHidden().environment(\.timeZone, TimeZone(identifier: "UTC")!)
                    .shotNode("doc.sheet.date", text: draft.date.map { String(format: "%04d-%02d-%02d", $0.year, $0.month, $0.day) } ?? "")
                Button { draft.date = nil } label: {
                    Icon("close", size: 14, line: 2).foregroundStyle(pal.ink4).frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(t.t("doc.dateClear")).shotNode("doc.sheet.dateClear")
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 15).frame(minHeight: 50)
        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: привязка

    private func bindBlock(_ pal: Palette) -> some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.18)) { bindOpen.toggle() } } label: {
                HStack(spacing: 10) {
                    Text(app.docOwnerText(draft.owner)).font(.system(size: 16)).foregroundStyle(pal.ink)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Icon("chevron", size: 13, line: 2.4).foregroundStyle(pal.ink4).rotationEffect(.degrees(bindOpen ? 90 : 0))
                }
                .padding(.horizontal, 15).frame(minHeight: 50).contentShape(Rectangle())
            }
            .buttonStyle(.plain).shotNode("doc.sheet.bind", text: app.docOwnerText(draft.owner))
            if bindOpen {
                VStack(alignment: .leading, spacing: 0) {
                    option(t.t("doc.addMine"), on: draft.owner == .mine, id: "mine", pal) { draft.owner = .mine; bindOpen = false }
                    header(t.t("doc.addRecentSessions"), pal)
                    ForEach(app.docRecentSessions(), id: \.id) { s in sessionOption(s, pal) }
                    option(t.t("doc.addOtherSession"), on: false, id: "otherSession", pal, accent: true) { query = ""; page = .sessions }
                    header(t.t("doc.addRecentOrgs"), pal)
                    ForEach(app.docRecentOrgs(), id: \.id) { o in orgOption(o, pal) }
                    option(t.t("doc.addOtherOrg"), on: false, id: "otherOrg", pal, accent: true) { query = ""; page = .orgs }
                }
                .padding(.bottom, 6)
            }
        }
        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func header(_ s: String, _ pal: Palette) -> some View {
        Text(s).font(webFont(11)).tracking(0.2).foregroundStyle(pal.ink6).padding(.horizontal, 15).padding(.top, 12).padding(.bottom, 4)
    }

    private func option(_ title: String, on: Bool, id: String, _ pal: Palette, accent: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 14.5)).foregroundStyle(accent ? pal.brass : pal.ink)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                if on { Icon("check", size: 15, line: 2).foregroundStyle(pal.brass) }
            }
            .padding(.horizontal, 15).padding(.vertical, 8).frame(minHeight: 38).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("doc.sheet.opt." + id, text: on ? "on" : "off")
    }

    private func sessionOption(_ s: Session, _ pal: Palette) -> some View {
        option(app.docSessionTitle(s), on: draft.owner == .session(s.id), id: "s." + s.id, pal) {
            draft.owner = .session(s.id); draft.date = nil; bindOpen = false
        }
    }

    private func orgOption(_ o: Org, _ pal: Palette) -> some View {
        option(app.orgTitle(o), on: draft.owner == .org(o.id), id: "o." + o.id, pal) { draft.owner = .org(o.id); bindOpen = false }
    }

    // MARK: полные списки

    /// «Другая съёмка…» / «Другая организация…»: поле поиска и весь список; выбор возвращает на форму.
    private func picker(_ pal: Palette, sessions: Bool) -> some View {
        let q = query
        return VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(pal.edge).frame(width: 38, height: 4).frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 14)
            HStack {
                Button { page = .form } label: {
                    Icon("chevron", size: 14, line: 2.4).foregroundStyle(pal.ink4).rotationEffect(.degrees(180))
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(t.t("ask.cancel")).shotNode("doc.pick.back")
                Text(t.t(sessions ? "doc.pickSession" : "doc.pickOrg")).font(.system(size: 19, weight: .semibold)).tracking(-0.2)
                    .foregroundStyle(pal.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            TextField("", text: $query, prompt: Text(t.t("doc.pickSearch")).foregroundColor(pal.ink6))
                .font(.system(size: 14)).foregroundStyle(pal.ink).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 14).frame(height: 39)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.sheet))
                .padding(.top, 8).shotNode("doc.pick.search", text: query)
            ScrollView {
                VStack(spacing: 6) {
                    if sessions {
                        let list = app.docSessionChoices(matching: q)
                        ForEach(list, id: \.id) { s in pickRow(app.docSessionTitle(s), "s." + s.id, pal) { draft.owner = .session(s.id); draft.date = nil; page = .form } }
                        if list.isEmpty { none(q, pal) }
                    } else {
                        let list = app.docOrgChoices(matching: q)
                        ForEach(list, id: \.id) { o in pickRow(app.orgTitle(o), "o." + o.id, pal) { draft.owner = .org(o.id); page = .form } }
                        if list.isEmpty { none(q, pal) }
                    }
                }
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
        .shotNode("doc.pick", text: sessions ? "sessions" : "orgs")
    }

    private func pickRow(_ title: String, _ id: String, _ pal: Palette, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title).font(webFont(14)).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 7).frame(minHeight: 41)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).shotNode("doc.pick.row." + id, text: title)
    }

    private func none(_ q: String, _ pal: Palette) -> some View {
        Text(t.t("doc.searchNone", ["q": q])).font(.system(size: 14)).foregroundStyle(pal.ink3)
            .frame(maxWidth: .infinity).padding(.vertical, 20).shotNode("doc.pick.none")
    }

    private func submit() {
        switch mode {
        case .add: app.addDoc(draft)
        case .edit(let id): app.saveDoc(id, draft)
        }
    }
}
