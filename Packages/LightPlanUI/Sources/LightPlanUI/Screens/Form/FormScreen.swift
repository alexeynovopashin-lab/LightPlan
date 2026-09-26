import SwiftUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Форма записи (`#formOverlay` веба, итерация 23): жанр, клиент / пара /
/// заказчик, время, заметки, заказ. Состав полей даёт `FormShape` по жанру и
/// режиму; всё, что про место, маршрут, деньги, сдачу и документы, — итерация 24.
/// Экран на всю высоту, поверх вкладок: веб сдвигает его снизу за 0,42 с.
struct FormScreen: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    /// Раскрыта одна из четырёх строк времени — по одной, как `ROWS` веба.
    @State private var picker: TimePicker? = Self.launchPicker
    @State private var orgSheet = false
    @State private var genreSheet = false
    /// Веер правила повтора раскрыт.
    @State private var repMenu = false
    @FocusState private var focus: Bool

    enum TimePicker: String { case startDate, startTime, endDate, endTime, repeatCount }

    /// Снимок сценария: `-LPShotPicker startTime` раскрывает строку сразу (только Debug).
    private static var launchPicker: TimePicker? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "LPShotPicker").flatMap(TimePicker.init(rawValue:))
        #else
        nil
        #endif
    }

    var body: some View {
        if let f = app.form {
            let pal = Palette(scheme)
            let t = app.lexicon
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    bar(pal, t).padding(.top, 46).padding(.bottom, 8)
                    title(f, pal, t)
                    if app.formIsDraft { draftStrip(pal, t) }
                    genreBlock(f, pal, t).padding(.top, 24)
                    whoBlock(f, pal, t)
                    timeBlock(f, pal, t)
                    notesBlock(f, pal, t)
                    if f.shows(.order) { orderBlock(f, pal, t) }
                    if !f.isNew { deleteButton(f, pal, t) }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(.container, edges: .top)
            .background(pal.surface.ignoresSafeArea())
            .overlayPreferenceValue(RepeatAnchorKey.self) { anchor in repFan(anchor, f, t) }
            .sheet(isPresented: $orgSheet) { OrgPickSheet(app: app) }
            .sheet(isPresented: $genreSheet) { GenreSheet(app: app) }
        }
    }

    // MARK: - Шапка

    private func bar(_ pal: Palette, _ t: Lexicon) -> some View {
        HStack {
            FormBarButton(node: "form.close", kind: .close, label: t.t("form.cancel")) { app.closeForm() }
            Spacer()
            FormBarButton(node: "form.save", kind: .save, label: t.t("form.save")) { app.saveForm() }
        }
    }

    private func title(_ f: EventForm, _ pal: Palette, _ t: Lexicon) -> some View {
        let name = f.mode == .meet ? (f.isNew ? t.t("form.newMeet") : t.t("plan.meet")) : (f.isNew ? t.t("plan.newShoot") : t.t("card.shootPoint"))
        return VStack(alignment: .leading, spacing: 0) {
            Text(name).font(webFont(30, 650)).tracking(-0.5).foregroundStyle(pal.ink).frame(maxWidth: .infinity, alignment: .leading).shotNode("form.title", text: name).padding(.top, 10)
            Text(subtitle(f, t)).font(.system(size: 14)).foregroundStyle(pal.ink4).frame(maxWidth: .infinity, alignment: .leading).shotNode("form.sub", text: subtitle(f, t)).padding(.top, 6)
            if let note = app.formNote {
                Text(note).font(.system(size: 13)).foregroundStyle(pal.ink4).padding(.top, 6)
            }
        }
    }

    /// Откуда взялось время (веб `formSub`): встреча — про разговор, свет — подсказал, окно — вот.
    private func subtitle(_ f: EventForm, _ t: Lexicon) -> String {
        if f.mode == .meet { return t.t("form.subMeet") }
        guard let w = app.formLight(on: f.day), !w.poor else { return t.t("form.subNoWindow") }
        let clock = clockText
        if f.timeFromLight || f.start == Int(w.start.rounded()) {
            return t.t("form.subFromLight", ["t": clock.fmt(Double(f.start))])
        }
        if f.start + f.duration == Int(w.end.rounded()) {
            return t.t("form.subLongerThanLight", ["tail": t.t("form.goldenAtEnd")])
        }
        return t.t("form.subWindow", ["range": clock.range(w.start, w.end)])
    }

    private func draftStrip(_ pal: Palette, _ t: Lexicon) -> some View {
        HStack {
            Text(t.t("form.draftRestored")).font(.system(size: 13)).foregroundStyle(pal.ink3)
            Spacer()
            Button(t.t("form.draftReset")) { app.resetDraft() }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(pal.brass)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 14)
    }

    // MARK: - Жанр

    private func genreBlock(_ f: EventForm, _ pal: Palette, _ t: Lexicon) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // `.g-label` с шестерёнкой «Мои жанры»: ряд по центру, шестерёнка (`.gear`: поле 8,
            // знак 21 линией 1,6, `--ink-4`) делает его высотой 37.
            HStack {
                Text(t.t("form.genre"))
                    .font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(pal.ink7)
                Spacer()
                Button { genreSheet = true } label: {
                    Icon("gear", size: 21, line: 1.6).foregroundStyle(pal.ink4).padding(8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.t("form.myGenres"))
                .shotNode("form.gear")
            }
            .padding(.top, 30).padding(.horizontal, 4).padding(.bottom, 9)
            FormGroup {
                GenreGrid(app: app, form: f)
                .shotNode("form.genre")
                .padding(.top, 13).padding(.horizontal, 15).padding(.bottom, 15)
            }
        }
    }

    // MARK: - Клиент, пара, заказчик

    @ViewBuilder
    private func whoBlock(_ f: EventForm, _ pal: Palette, _ t: Lexicon) -> some View {
        if f.shows(.who) {
            let group = f.genre.group.rawValue
            VStack(alignment: .leading, spacing: 0) {
                FormGroupLabel(text: t.t("who." + group))
                FormGroup(node: "form.who") {
                    if f.shows(.contactLine) {
                        FormTextField(placeholder: t.t("whoHint." + group), text: text(\.contact), kind: .name)
                        phoneRow(t.t("form.phone"), text: phone(\.clientPhone))
                    }
                    if f.shows(.breed) {
                        FormTextField(placeholder: t.t("form.breedPh"), text: text(\.breed))
                    }
                    ForEach(Array(f.genre.persons.enumerated()), id: \.offset) { i, role in
                        FormTextField(placeholder: t.t("form.namePh", ["role": t.t("person." + role.rawValue).lowercased()]),
                                      text: person(i, name: true), kind: .name)
                        phoneRow(t.t("form.phone"), text: person(i, name: false, phone: true))
                    }
                    if f.shows(.organization) { orgRow(f, pal, t, group: group) }
                    if f.shows(.orderContact) {
                        FormTextField(placeholder: t.t("form.person"), text: text(\.orderPerson), kind: .name)
                        phoneRow(t.t("form.phone"), text: phone(\.orderPhone))
                    }
                    if f.shows(.guests) { guestsRow(f, pal, t) }
                    if f.repeatOn { repToggle(.client, f, t) }
                }
            }
        }
    }

    private func phoneRow(_ placeholder: String, text: Binding<String>) -> some View {
        FormTextField(placeholder: placeholder, text: text, kind: .phone)
    }

    private func orgRow(_ f: EventForm, _ pal: Palette, _ t: Lexicon, group: String) -> some View {
        let org = f.orgId.flatMap { id in app.orgs.first { $0.id == id } }
        return Button { orgSheet = true } label: {
            HStack(spacing: 12) {
                Text(t.t("orgRole." + group)).font(.system(size: 16)).foregroundStyle(pal.ink)
                Spacer()
                Text(org?.name ?? t.t("form.pick")).font(.system(size: 16)).foregroundStyle(org == nil ? pal.ink6 : pal.ink)
                Icon("chevron", size: 16, line: 2).foregroundStyle(pal.ink6)
            }
            .padding(15).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func guestsRow(_ f: EventForm, _ pal: Palette, _ t: Lexicon) -> some View {
        HStack {
            Text(t.t("form.guestsAria")).font(.system(size: 15)).foregroundStyle(pal.ink)
            Spacer()
            FormStepper(value: f.guests, step: 10, range: 0...2000) { v in edit { $0.guests = v } }
        }
        .padding(.vertical, 13).padding(.horizontal, 15).frame(minHeight: 50)
    }

    // MARK: - Время

    private func timeBlock(_ f: EventForm, _ pal: Palette, _ t: Lexicon) -> some View {
        let dates = DateText(language: app.language)
        let clock = clockText
        let twelve = clock.is12
        return VStack(alignment: .leading, spacing: 0) {
            FormGroupLabel(text: t.t("form.time"))
            FormGroup {
                timeRow("form.start", t.t("form.start"), sub: startHint(f, t),
                        date: dates.dMonShortYear(carrier(f.day)), time: clock.fmt(Double(f.start)),
                        openDate: picker == .startDate, openTime: picker == .startTime,
                        pickDate: { toggle(.startDate) }, pickTime: { toggle(.startTime) }, pal)
                if picker == .startDate {
                    FormDateGrid(selected: f.day, dates: dates, date: carrier) { d in
                        edit { $0.setStart(day: d) }; picker = nil
                    }
                }
                if picker == .startTime {
                    FormTimeWheel(minute: f.start, step: app.settings.timeStep, twelveHour: twelve, language: app.language) { m in
                        edit { $0.setStart(minute: m) }
                    }
                    .padding(.horizontal, 10)
                }
                timeRow("form.end", t.t("form.end"), sub: durationText(f, t),
                        date: dates.dMonShortYear(carrier(f.endDay)), time: clock.fmt(Double(f.start + f.duration)),
                        openDate: picker == .endDate, openTime: picker == .endTime,
                        pickDate: { toggle(.endDate) }, pickTime: { toggle(.endTime) }, pal)
                if picker == .endDate {
                    FormDateGrid(selected: f.endDay, range: f.day.ordinal...(f.day.ordinal + EventForm.maxDuration / 1440),
                                 dates: dates, date: carrier) { d in
                        app.setFormEnd(dayOffset: d.days(since: f.day), minuteOfDay: f.endMinuteOfDay); picker = nil
                    }
                }
                if picker == .endTime {
                    FormTimeWheel(minute: f.endMinuteOfDay, step: app.settings.timeStep, twelveHour: twelve, language: app.language) { m in
                        app.setFormEnd(dayOffset: f.endDayOffset, minuteOfDay: m)
                    }
                    .padding(.horizontal, 10)
                }
                repeatRows(f, pal, t)
            }
        }
    }

    private func timeRow(_ node: String, _ label: String, sub: String?, date: String, time: String,
                         openDate: Bool, openTime: Bool, pickDate: @escaping () -> Void, pickTime: @escaping () -> Void,
                         _ pal: Palette) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 12) {
                Text(label).font(.system(size: 16)).foregroundStyle(pal.ink)
                Spacer()
                HStack(spacing: 6) {    // `.caps` веба: зазор 6
                    FormCapsule(node: node + "Date", text: date, open: openDate, action: pickDate)
                    FormCapsule(node: node + "Val", text: time, open: openTime, action: pickTime)
                }
            }
            if let sub { Text(sub).font(.system(size: 11)).foregroundStyle(pal.ink6).multilineTextAlignment(.trailing) }
        }
        .padding(.vertical, 14).padding(.horizontal, 15).frame(minHeight: 52)
    }

    private func startHint(_ f: EventForm, _ t: Lexicon) -> String? {
        guard f.mode != .meet else { return nil }
        guard let w = app.formLight(on: f.day), !w.poor else { return t.t("day.noWindow") }
        return t.t(w.dawn ? "win.dawn" : "win.sunset") + " " + clockText.range(w.start, w.end)
    }

    /// «1,5 часа» и слово про полночь: конец числом меньше начала без пояснения не читается.
    private func durationText(_ f: EventForm, _ t: Lexicon) -> String {
        let m = f.duration, h = m / 60, mm = m % 60
        var s: String
        if h == 0 { s = t.t("dur.minutes", ["m": "\(mm)"]) }
        else if mm == 0 { s = t.t("dur.hours", ["h": "\(h)", "hourWord": t.word("unit.hour", h)]) }
        else { s = t.t("dur.hoursMins", ["h": "\(h)", "m": "\(mm)"]) }
        let off = f.endDayOffset
        if off > 0 {
            s += " · " + (off == 1 ? t.t("blk.nextDay") : t.t("when.inDays", ["n": t.count("unit.day", off)]))
        }
        return s
    }

    // MARK: - Повтор

    /// Строки повтора в группе времени (веб `#fRepRow`, `#fRepNRow`, `#fRepSum`). У карточки
    /// из группы строка остаётся, но это сведения, а не выбор — без капсулы.
    @ViewBuilder
    private func repeatRows(_ f: EventForm, _ pal: Palette, _ t: Lexicon) -> some View {
        let info = app.formRepeatInfo(f)
        if f.repeatEditable || info != nil {
            HStack(spacing: 12) {
                Text(t.t("rep.label")).font(.system(size: 16)).foregroundStyle(pal.ink)
                Spacer()
                if f.repeatEditable {
                    FormCapsule(node: "form.repVal", text: t.t("rep." + (f.repeatRule?.rawValue ?? "never")), open: repMenu) {
                        focus = false
                        withAnimation(.snappy(duration: 0.22)) { repMenu.toggle() }
                    }
                    .anchorPreference(key: RepeatAnchorKey.self, value: .bounds) { $0 }
                } else if let info {
                    Text(info).font(.system(size: 15)).foregroundStyle(pal.ink4).shotNode("form.repInfo", text: info)
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 15).frame(minHeight: 52)
        }
        if f.repeatOn {
            HStack(spacing: 12) {
                Text(t.t("rep.count")).font(.system(size: 16)).foregroundStyle(pal.ink)
                Spacer()
                FormCapsule(node: "form.repN", text: t.count("unit.times", f.repeatCount), open: picker == .repeatCount) {
                    toggle(.repeatCount)
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 15).frame(minHeight: 52)
            if picker == .repeatCount {
                Picker("", selection: Binding(get: { f.repeatCount }, set: { app.setFormRepeatCount($0) })) {
                    ForEach(Repeats.minCount...Repeats.maxCount, id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 140)
                .padding(.horizontal, 10)
            }
            if let sum = app.formRepeatSummary(f) {
                // `.f-hint.rep-sum`: 12 `--ink-6`, поле 11 · 15 · 13, строка 1,45.
                Text(sum).font(.system(size: 12)).foregroundStyle(pal.ink6).lineSpacing(12 * 0.45 - 2)
                    .padding(.top, 11).padding(.horizontal, 15).padding(.bottom, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shotNode("form.repSum", text: sum)
            }
        }
    }

    /// Веер правила от капсулы: по её правому краю, под ней на 8; внизу экрана — над ней.
    @ViewBuilder
    private func repFan(_ anchor: Anchor<CGRect>?, _ f: EventForm, _ t: Lexicon) -> some View {
        if repMenu, let anchor {
            GeometryReader { geo in
                let r = geo[anchor]
                let h: CGFloat = 6 * 44 + 12
                let below = r.maxY + 8 + h <= geo.size.height - 12
                ZStack(alignment: .topTrailing) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { repMenu = false }
                    RepeatFan(lexicon: t, current: f.repeatRule) { rule in
                        repMenu = false
                        app.setFormRepeat(rule)
                    }
                    .padding(.trailing, max(12, geo.size.width - r.maxX))
                    .padding(.top, below ? r.maxY + 8 : max(12, r.minY - 8 - h))
                    .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
        }
    }

    private func toggle(_ p: TimePicker) {
        focus = false
        withAnimation(.easeOut(duration: 0.34)) { picker = picker == p ? nil : p }
    }

    // MARK: - Заметки и заказ

    private func notesBlock(_ f: EventForm, _ pal: Palette, _ t: Lexicon) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FormGroupLabel(text: t.t("card.notes"))
            FormGroup {
                TextField("", text: text(\.notes), prompt: Text(t.t("form.notesPh")).foregroundStyle(pal.ink8), axis: .vertical)
                    .font(.system(size: 16)).foregroundStyle(pal.ink).lineSpacing(3)
                    .lineLimit(2...12)
                    .padding(15).frame(minHeight: 92, alignment: .topLeading)
                if f.repeatOn { repToggle(.notes, f, t) }
            }
        }
    }

    private func orderBlock(_ f: EventForm, _ pal: Palette, _ t: Lexicon) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FormGroupLabel(text: t.t("form.order"))
            FormGroup {
                FormTextField(placeholder: t.t("form.briefPh"), text: text(\.brief))
                if f.shows(.models) { FormTextField(placeholder: t.t("form.modelsPh"), text: text(\.models)) }
                if f.repeatOn { repToggle(.brief, f, t) }
            }
        }
    }

    private func repToggle(_ b: RepeatBlock, _ f: EventForm, _ t: Lexicon) -> some View {
        FormToggleRow(node: "form.rep." + b.rawValue, label: t.t("rep." + b.rawValue), on: f.repeatBlocks.contains(b)) { v in
            app.setFormRepeat(block: b, on: v)
        }
    }

    /// «Удалить» (`.danger`): во всю ширину, отступ 26, поле 15, 15 `--terra-2`, без подложки.
    private func deleteButton(_ f: EventForm, _ pal: Palette, _ t: Lexicon) -> some View {
        Button { app.deleteFormRecord() } label: {
            Text(t.t("card.delShoot")).font(.system(size: 15)).foregroundStyle(pal.terra2)
                .frame(maxWidth: .infinity).padding(15).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 26)
        .shotNode("form.delete")
    }

    // MARK: - Связки

    private var clockText: ClockText {
        ClockText(language: app.language, preference: ClockPreference(rawValue: app.settings.clock.rawValue) ?? .auto)
    }

    /// День на местную полночь — словарю дат нужен момент.
    private func carrier(_ d: CivilDate) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (d.year, d.month, d.day, 12)
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }

    /// Правка формы: любое поле ведёт к черновику через 600 мс.
    private func edit(_ change: (inout EventForm) -> Void) {
        guard var f = app.form else { return }
        change(&f)
        app.form = f
        app.formChanged()
    }

    private func text(_ kp: WritableKeyPath<EventForm, String>) -> Binding<String> {
        Binding(get: { app.form?[keyPath: kp] ?? "" }, set: { v in edit { $0[keyPath: kp] = v } })
    }

    /// Телефон разбивается на разряды на ходу; вставка и автозаполнение узнаются по росту цифр.
    private func phone(_ kp: WritableKeyPath<EventForm, String>) -> Binding<String> {
        Binding(get: { app.form?[keyPath: kp] ?? "" }, set: { v in
            let old = (app.form?[keyPath: kp] ?? "").filter(\.isNumber).count
            let shown = TelFormat.typed(v, previousDigits: old, country: app.telCountry)
            edit { $0[keyPath: kp] = shown }
        })
    }

    private func person(_ i: Int, name: Bool, phone isPhone: Bool = false) -> Binding<String> {
        Binding(get: {
            guard let p = app.form?.persons, i < p.count else { return "" }
            return isPhone ? p[i].phone : p[i].name
        }, set: { v in
            edit { f in
                guard i < f.persons.count else { return }
                if isPhone {
                    let old = f.persons[i].phone.filter(\.isNumber).count
                    f.persons[i].phone = TelFormat.typed(v, previousDigits: old, country: app.telCountry)
                } else {
                    f.persons[i].name = v
                }
            }
        })
    }
}

/// Выбор организации: существующие и «новая» строкой. Организация — отдельная
/// запись с постоянным ключом (`docs/12`), её карточка и правка — итерация 28.
struct OrgPickSheet: View {
    @Bindable var app: AppModel
    @State private var name = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        ScrollView {
            VStack(spacing: 10) {
                FormGroup {
                    ForEach(app.orgs) { o in
                        Button { choose(o) } label: {
                            HStack {
                                Text(o.name).font(.system(size: 16)).foregroundStyle(pal.ink)
                                Spacer()
                                if o.id == app.form?.orgId { Icon("check", size: 18, line: 2).foregroundStyle(pal.brass) }
                            }
                            .padding(15).frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        TextField("", text: $name, prompt: Text(t.t("form.clientName")).foregroundStyle(pal.ink8))
                            .font(.system(size: 16)).foregroundStyle(pal.ink)
                            .submitLabel(.done).onSubmit(addNew)
                        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button(action: addNew) { Icon("plus", size: 20, line: 2).foregroundStyle(pal.brass) }.buttonStyle(.plain)
                        }
                    }
                    .padding(15).frame(minHeight: 52)
                }
                if app.form?.orgId != nil {
                    Button(t.t("form.change")) { app.setFormOrg(nil); dismiss() }
                        .font(.system(size: 14)).foregroundStyle(pal.ink4)
                }
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
    }

    private func choose(_ o: Org) { app.setFormOrg(o); dismiss() }
    private func addNew() {
        let v = name.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        app.setFormOrg(app.addOrg(name: v)); dismiss()
    }
}
