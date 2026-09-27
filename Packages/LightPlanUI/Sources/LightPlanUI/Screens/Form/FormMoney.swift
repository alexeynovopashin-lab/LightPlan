import SwiftUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Блоки «Оплата» и «Сдать материал» формы (веб `#fPayGroup`, `#fDelvGroup`,
/// итерация 24, шаг 3). Счёт — `EventForm` (`FormMoney.swift` в Domain).
struct FormPayBlock: View {
    @Bindable var app: AppModel
    let form: EventForm
    @Binding var sheet: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let ctx = app.formMoney(form)
        VStack(alignment: .leading, spacing: 0) {
            // `.g-label` с шестерёнкой «Ставка и пакеты» — как у «Жанра».
            HStack {
                Text(t.t("form.pay"))
                    .font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(pal.ink7)
                Spacer()
                Button { sheet = true } label: {
                    Icon("gear", size: 21, line: 1.6).foregroundStyle(pal.ink4).padding(8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.t("form.ratePacks"))
                .shotNode("form.payGear")
            }
            .padding(.top, 30).padding(.horizontal, 4).padding(.bottom, 9)
            FormGroup(node: "form.pay") {
                fold(ctx, pal, t)
                if form.payOpen { rows(ctx, pal, t) }
            }
        }
    }

    // MARK: - Свёрнутая строка

    /// Сводка спойлера (`#fPayFold`): способ и итог одной строкой, стрелка вниз / вверх.
    private func fold(_ ctx: FormMoneyContext, _ pal: Palette, _ t: Lexicon) -> some View {
        Button { withAnimation(.easeOut(duration: 0.3)) { app.toggleFormPay() } } label: {
            HStack(spacing: 12) {
                (Text(t.t("pay." + form.pay.rawValue) + " · ").foregroundStyle(pal.ink)
                 + Text(money(form.summaryAmount(ctx))).fontWeight(.semibold).foregroundStyle(pal.brass))
                    .font(.system(size: 15).monospacedDigit())
                Spacer(minLength: 0)
                Icon("chevron", size: 16, line: 2.4).foregroundStyle(pal.ink4)
                    .rotationEffect(.degrees(form.payOpen ? -90 : 90))
            }
            .padding(.vertical, 14).padding(.horizontal, 15).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("form.payFold")
    }

    // MARK: - Раскрытая оплата

    @ViewBuilder
    private func rows(_ ctx: FormMoneyContext, _ pal: Palette, _ t: Lexicon) -> some View {
        let sign = NumberText(language: app.language).currencySign(form.currency.rawValue)
        let mech = form.pay.mechanic
        let compose = form.composesMonth
        VStack(alignment: .leading, spacing: 8) {
            FormChips(options: form.payKinds.map { (t.t("pay." + $0.rawValue), $0.rawValue) },
                      selected: form.pay.rawValue) { v in
                if let k = PayKind(rawValue: v) { app.setFormPay(k) }
            }
            .shotNode("form.payType")
            if form.pay == .pack {
                let packs = app.usablePacks(form.genre)
                FormChips(options: packs.indices.map { (packName(packs[$0], $0, t), String($0)) },
                          selected: packs.firstIndex(where: form.isChosen).map(String.init) ?? "") { v in
                    if let i = Int(v), packs.indices.contains(i) { app.chooseFormPack(packs[i]) }
                }
            }
        }
        .padding(.top, 13).padding(.horizontal, 15).padding(.bottom, 15)
        if form.monthGroup != nil {
            payRow(t.t("form.perMonth", ["sign": sign]), node: "form.monthSum") {
                FormMoneyField(value: FormMoneyField.rounded(form.monthSumTyped ?? form.monthSumWas(ctx))) { app.setFormMonthSum($0) }
            }
        }
        if !compose {
            payRow(rateLabel(mech, sign, t), node: "form.rate") {
                FormMoneyField(value: form.rate,
                               placeholder: mech == .monthly ? "\(NSDecimalNumber(decimal: form.ratePlaceholder(ctx)).intValue)" : "0") {
                    app.setFormRate($0)
                }
            }
        }
        if let hint = app.formMonthSumHint(form) { hintRow(hint, pal) }
        if compose {
            payRow(t.t("form.perMonth", ["sign": sign]), node: "form.monTotal") {
                FormMoneyField(value: FormMoneyField.rounded(form.repeatMonthly)) { app.setFormMonth(total: $0) }
            }
            payRow(t.t("form.perShoot", ["sign": sign]), node: "form.monShoot") {
                FormMoneyField(value: FormMoneyField.rounded(form.perShoot)) { app.setFormMonth(perShoot: $0) }
            }
            payRow(t.t("form.perHour", ["sign": sign]), node: "form.monHour") {
                FormMoneyField(value: FormMoneyField.rounded(form.duration > 0 ? form.perShoot / (Decimal(form.duration) / 60) : 0)) {
                    app.setFormMonth(perHour: $0)
                }
            }
            let n = form.firstMonthCount
            hintRow(t.t("rep.payFirst", ["n": t.count("unit.shoot", n), "k": String(n)]), pal)
        }
        if mech == .unit {
            payRow(t.t(form.pay.countsUnits ? "payUnit." + form.pay.rawValue : "form.qty"), node: "form.units") {
                FormUnitsStepper(value: form.units, set: { app.setFormUnits($0) }, step: { app.stepFormUnits($0) })
            }
        }
        if form.shows(.prepay) {
            payRow(capFirst(t.t("form.prepayLbl", ["word": prepayWord(t), "sign": sign])), node: "form.prepay") {
                FormMoneyField(value: form.prepay(ctx)) { app.setFormPrepay($0) }
            }
        }
        payRow(t.t("form.expenseLbl", ["sign": sign]), node: "form.expense") {
            FormMoneyField(value: form.expense) { app.setFormExpense($0) }
        }
        total(ctx, pal, t)
    }

    /// `.pay-row`: подпись 15 `--ink` слева, поле справа; поля 13 / 15, минимум 50.
    private func payRow<F: View>(_ label: String, node: String, @ViewBuilder field: () -> F) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 15)).foregroundStyle(Palette(scheme).ink).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            field()
        }
        .padding(.vertical, 13).padding(.horizontal, 15).frame(minHeight: 50)
        .shotNode(node)
    }

    /// `.f-hint.rep-sum`: 12 `--ink-6`, поля 11 / 15 / 13, строки 1,45.
    private func hintRow(_ s: String, _ pal: Palette) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(pal.ink6).lineSpacing(12 * 0.45 - 2)
            .padding(.top, 11).padding(.horizontal, 15).padding(.bottom, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Итог (`.pay-total`): доход, часы, расход, строка остатка; справа прибыль,
    /// латунью, а в минусе — терракотой.
    private func total(_ ctx: FormMoneyContext, _ pal: Palette, _ t: Lexicon) -> some View {
        let inc = form.income(ctx), net = form.net(ctx), pre = form.prepay(ctx)
        var lbl = t.t("form.incomeIs", ["sum": money(inc)])
        if form.pay.mechanic == .hourly { lbl += " · " + GenreSheet.durationLabel(form.duration, t) }
        if form.expense != 0 { lbl += " " + t.t("form.minusExp", ["sum": money(form.expense)]) }
        if pre != 0 {
            lbl += "\n" + t.t("pane.prepayRest", ["word": prepayWord(t), "prepay": money(pre), "rest": money(form.rest(ctx))])
        }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(lbl).font(.system(size: 13).monospacedDigit()).foregroundStyle(pal.ink4)
            Spacer(minLength: 0)
            Text(money(net)).font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(net < 0 ? pal.terra : pal.brass)
        }
        .padding(.vertical, 14).padding(.horizontal, 15)
        .shotNode("form.payTotal")
    }

    // MARK: - Слова

    private func rateLabel(_ m: PayMechanic, _ sign: String, _ t: Lexicon) -> String {
        switch m {
        case .hourly: t.t("form.rateHour", ["sign": sign])
        case .unit: t.t("form.priceEach", ["sign": sign])
        case .monthly: t.t("form.perShoot", ["sign": sign])
        case .flat: t.t("form.sumFlat", ["sign": sign])
        }
    }

    /// На чипсе пакета — только имя; безымянный старый пакет называется суммой.
    private func packName(_ p: Pack, _ i: Int, _ t: Lexicon) -> String {
        p.name.isEmpty ? money(p.price) : p.name
    }

    private func prepayWord(_ t: Lexicon) -> String { t.t("prepayW." + app.settings.practice.rawValue) }

    private func money(_ v: Decimal) -> String {
        NumberText(language: app.language).money(NSDecimalNumber(decimal: v).doubleValue, form.currency.rawValue)
    }
}

/// Заглавная буква — свойство места, а не слова (веб `capFirst`).
func capFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

/// Чипсы `.chips`: 13, поля 10 / 15, `--press`; выбранный — латунь на `--press-brass`, 600.
struct FormChips: View {
    let options: [(String, String)]
    let selected: String
    let pick: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        FlowLayout(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].1 == selected
                Button { pick(options[i].1) } label: {
                    Text(options[i].0)
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? pal.brass : pal.ink3)
                        .padding(.vertical, 10).padding(.horizontal, 15)
                        .background(on ? pal.pressBrass : pal.press, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Поле суммы `.pay-in`: обведено, потому что правится; справа, цифрами одной
/// ширины, тянется за числом от четырёх цифр; в фокусе — латунь.
struct FormMoneyField: View {
    let value: Decimal?
    var placeholder = "0"
    let change: (Decimal?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        field(pal)
            .font(.system(size: 16).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .foregroundStyle(focused ? pal.brass : pal.ink)
            .focused($focused)
            .fixedSize()
            // Высота поля веба — 30 (строка 18 и поля по 6), строка оплаты — 56 (пары 24 шаг 3).
            .frame(minWidth: 4 * 9.6, minHeight: 18, maxHeight: 18)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(focused ? Color(hex: 0xE2A44C, alpha: 0.16) : pal.field,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .onAppear { text = Self.show(value) }
            .onChange(of: value) { _, v in if !focused { text = Self.show(v) } }
            .onChange(of: text) { _, s in if focused { change(Self.parse(s)) } }
            .onChange(of: focused) { _, on in if !on { text = Self.show(value) } }
    }

    @ViewBuilder
    private func field(_ pal: Palette) -> some View {
        let f = TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(pal.ink7))
        #if os(iOS)
        f.keyboardType(.decimalPad)
        #else
        f
        #endif
    }

    /// Ноль в поле не пишется — пустое поле с подсказкой «0» (веб `fRate || ""`).
    static func show(_ v: Decimal?) -> String {
        guard let v, v != 0 else { return "" }
        return NSDecimalNumber(decimal: v).stringValue
    }

    /// Разбор как у веба: цифры, точка и запятая; запятая — дробная.
    static func parse(_ s: String) -> Decimal? {
        let kept = s.filter { $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }.replacingOccurrences(of: ",", with: ".")
        guard !kept.isEmpty else { return nil }
        let head = kept.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        return Decimal(string: head.count > 1 ? head[0] + "." + head[1].filter(\.isNumber) : String(head[0])) ?? 0
    }

    /// Поля «в месяц» показывают целые (веб `monShow`: `Math.round`).
    static func rounded(_ v: Decimal) -> Decimal { EventForm.roundMoney(v) }
}

/// Количество (`.stepper`): кнопки 38 × 34 и поле 58, в которое можно вписать «50».
struct FormUnitsStepper: View {
    let value: Int
    let set: (Int) -> Void
    let step: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        HStack(spacing: 2) {
            button("−", pal) { step(-1) }
            TextField("", text: $text)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .focused($focused)
                .multilineTextAlignment(.center)
                .font(.system(size: 16).monospacedDigit()).foregroundStyle(focused ? pal.brass : pal.ink)
                .frame(width: 54, height: 22).padding(.vertical, 6).padding(.horizontal, 2)
                .background(focused ? Color(hex: 0xE2A44C, alpha: 0.16) : pal.field,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            button("+", pal) { step(1) }
        }
        .onAppear { text = String(value) }
        .onChange(of: value) { _, v in if !focused { text = String(v) } }
        .onChange(of: text) { _, s in
            let d = String(s.filter(\.isNumber).prefix(4))
            if d != s { text = d }
            if focused, let n = Int(d) { set(n) }
        }
        // Пустое поле — незаконченный ввод, а не ноль предметов: на выходе — единица.
        .onChange(of: focused) { _, on in if !on { if Int(text) == nil { set(1) }; text = String(value) } }
    }
    private func button(_ s: String, _ pal: Palette, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(s).font(.system(size: 19)).foregroundStyle(pal.ink3)
                .frame(width: 38, height: 34)
                .background(pal.press, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Сдать материал

/// «Сдать материал» (`#fDelvGroup`): шкала срока, подсказка с датой, «Материал сдан».
struct FormDeliveryBlock: View {
    @Bindable var app: AppModel
    let form: EventForm
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        VStack(alignment: .leading, spacing: 0) {
            FormGroupLabel(text: t.t("form.deliver"))
            FormGroup(node: "form.delv") {
                VStack(alignment: .leading, spacing: 0) {
                    DeadlineDial(stop: form.deadlineStop, labels: labels(t)) { app.setFormDeadline(stop: $0) }
                        .shotNode("form.delvDial")
                    Text(hint(t)).font(.system(size: 12)).foregroundStyle(pal.ink6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .shotNode("form.delvHint")
                        .padding(.top, 8)
                }
                .padding(.top, 13).padding(.horizontal, 15).padding(.bottom, 15)
                // «Материал сдан» — только у сохранённой записи: новую ещё не снимали (веб L30550).
                if !form.isNew {
                    FormToggleRow(node: "form.done", label: t.t("form.delivered"), on: form.delivered) { app.setFormDelivered($0) }
                }
                if form.repeatOn {
                    FormToggleRow(node: "form.rep.delivery", label: t.t("rep.delivery"), on: form.repeatBlocks.contains(.delivery)) {
                        app.setFormRepeat(block: .delivery, on: $0)
                    }
                }
            }
        }
    }

    /// Подписи под рисками — короткие: «жанр», «3 дн», «нед» (веб `DELV_OPTS`).
    private func labels(_ t: Lexicon) -> [String] {
        ["delv.byGenreShort", "delv.d3", "delv.w1", "delv.w2", "delv.m1", "delv.m3", "delv.never"].map { t.t($0) }
    }

    /// Первое деление — автомат: подсказка объясняет, что решил жанр.
    private func hint(_ t: Lexicon) -> String {
        guard let d = app.formDeadline(form) else { return t.t("delv.untracked") }
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (d.year, d.month, d.day, 12)
        let at = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        let until = t.t("delv.until", ["d": DateText(language: app.language).dMon(at)])
        return form.deadline == .auto ? t.t("delv.byGenre") + " · " + until : until
    }
}

/// Шкала срока (`.dial`): дорожка 3 `--rail`, риски 1 × 6 `--rail-5`, бегунок
/// 11 × 24 `--knob` с краем 2 `--knob-edge`; подписи 9,5 под рисками, текущая —
/// латунью. Отпущенный палец встаёт на ближайшее деление, щелчок — на каждом.
struct DeadlineDial: View {
    let stop: Int
    let labels: [String]
    let pick: (Int) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        GeometryReader { geo in
            let w = geo.size.width, n = labels.count
            let x = { (i: Int) -> CGFloat in 5.5 + CGFloat(i) / CGFloat(max(1, n - 1)) * (w - 11) }
            ZStack(alignment: .topLeading) {
                Capsule().fill(pal.rail).frame(width: w, height: 3).offset(y: 2 + 16 - 1.5)
                ForEach(0..<n, id: \.self) { i in
                    Rectangle().fill(pal.rail5).frame(width: 1, height: 6).offset(x: x(i) - 0.5, y: 24)
                    Text(labels[i])
                        .font(.system(size: 9.5, weight: i == stop ? .semibold : .regular).monospacedDigit())
                        .tracking(0.3).foregroundStyle(i == stop ? pal.brass : pal.ink7)
                        .fixedSize()
                        .frame(width: 60).offset(x: x(i) - 30, y: 33)
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(pal.knob)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(pal.knobEdge, lineWidth: 2))
                    .frame(width: 11, height: 24)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
                    .offset(x: x(stop) - 5.5, y: 2 + 16 - 12)
                    .animation(.easeOut(duration: 0.15), value: stop)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let i = Int(((g.location.x - 5.5) / max(1, w - 11) * CGFloat(n - 1)).rounded())
                let c = min(max(i, 0), n - 1)
                if c != stop { pick(c) }
            })
        }
        .frame(height: 54)
        .sensoryFeedback(.selection, trigger: stop)
        .accessibilityElement()
        .accessibilityValue(labels.indices.contains(stop) ? labels[stop] : "")
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: if stop < labels.count - 1 { pick(stop + 1) }
            case .decrement: if stop > 0 { pick(stop - 1) }
            @unknown default: break
            }
        }
    }
}

// MARK: - Лист «Ставка и пакеты»

/// Лист шестерёнки оплаты (веб `#paySheet`): валюта сделки, ставка часа жанра,
/// доля предоплаты и пакеты. Всё, кроме валюты, принадлежит открытому жанру —
/// подпись называет его вслух.
struct PaySheet: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let g = app.form?.genre ?? .portrait
        let mark = "· " + t.t("genre." + g.rawValue).lowercased()
        let byHour = GenreProfile(g).spec.pay.contains { $0.mechanic == .hourly }
        let nt = NumberText(language: app.language)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(pal.edge).frame(width: 38, height: 4).frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 18)
                Text(t.t("form.ratePacks")).font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
                    .shotNode("pay.title")
                Text(t.t("gen.paySub")).font(.system(size: 13)).foregroundStyle(pal.ink4).padding(.top, 5)
                FormGroup(node: "pay.group") {
                    FormChips(options: Currency.allCases.map { (nt.currencySign($0.rawValue) + " " + $0.rawValue, $0.rawValue) },
                              selected: app.form?.currency.rawValue ?? "") { v in
                        if let c = Currency(rawValue: v) { app.setFormCurrency(c) }
                    }
                    .padding(.top, 13).padding(.horizontal, 15)
                    .shotNode("pay.cur")
                    if byHour {
                        HStack(spacing: 12) {
                            Text(t.t("gen.rateLbl", ["genre": t.t("genre." + g.rawValue).lowercased(),
                                                     "sign": nt.currencySign(app.settings.currency.rawValue)]))
                                .font(.system(size: 15)).foregroundStyle(pal.ink).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            FormMoneyField(value: app.genreRate(g)) { app.setGenreRate(g, $0) }
                        }
                        .padding(.vertical, 13).padding(.horizontal, 15).frame(minHeight: 50)
                        .shotNode("pay.rate")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        head(capFirst(t.t("prepayW." + app.settings.practice.rawValue)), mark, pal)
                        FormChips(options: EventForm.prepayShares.map { ($0 == 0 ? t.t("gen.preNone") : "\($0)%", String($0)) },
                                  selected: String(app.genrePrepayShare(g))) { v in
                            app.setGenrePrepayShare(g, Int(v) ?? 0)
                        }
                        .padding(.horizontal, 15).padding(.bottom, 15)
                    }
                    .shotNode("pay.pre")
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            (Text(t.t("gen.packs")) + Text(" " + mark).foregroundStyle(pal.ink4))
                                .font(.system(size: 15)).foregroundStyle(pal.ink)
                            Spacer()
                            Button { addPack(g) } label: {
                                Text(t.t("gen.packAdd")).font(.system(size: 13, weight: .semibold)).foregroundStyle(pal.brass)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .disabled(app.genrePacks(g).count >= Pack.limit)
                        }
                        .padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 9)
                        PackEditor(app: app, genre: g)
                    }
                    .shotNode("pay.packs")
                }
                .padding(.top, 18)
                Button { dismiss() } label: {
                    Text(t.t("pick.done")).font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.onBrass)
                        .frame(maxWidth: .infinity).padding(16)
                        .background(pal.brass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            }
            .padding(.horizontal, 24).padding(.bottom, 34)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    /// `.pack-head`: 15 `--ink`, имя жанра `--ink-4` без прописных.
    private func head(_ s: String, _ mark: String, _ pal: Palette) -> some View {
        (Text(s) + Text(" " + mark).foregroundStyle(pal.ink4))
            .font(.system(size: 15)).foregroundStyle(pal.ink)
            .padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 9)
    }

    private func addPack(_ g: Genre) {
        var list = app.genrePacks(g)
        guard list.count < Pack.limit else { return }
        list.append(Pack(name: "", price: 0))
        app.setGenrePacks(g, list)
    }
}

/// Редактор пакетов (`#packList`): имя · часы · цена · убрать; пусто — пример жанра.
struct PackEditor: View {
    @Bindable var app: AppModel
    let genre: Genre
    @Environment(\.colorScheme) private var scheme

    /// Жанры, у которых есть свой пример имени (веб `PACK_HINT`).
    static let hinted: Set<Genre> = [.wedding, .party, .lovestory, .family, .portrait, .animals,
                                     .product, .ad, .architecture, .report, .landscape, .street]

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let packs = app.genrePacks(genre)
        let hint = t.t(Self.hinted.contains(genre) ? "packHint." + genre.rawValue : "packHint.any")
        if packs.isEmpty {
            let sum = NumberText(language: app.language).money(14000, app.settings.currency.rawValue)
            Text(t.t("gen.packExample", ["name": hint, "sum": sum]))
                .font(.system(size: 12)).foregroundStyle(pal.ink6)
                .padding(.horizontal, 15).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 10) {
                ForEach(packs.indices, id: \.self) { i in row(i, packs, hint, pal, t) }
            }
            .padding(.horizontal, 15).padding(.bottom, 10)
        }
    }

    private func row(_ i: Int, _ packs: [Pack], _ hint: String, _ pal: Palette, _ t: Lexicon) -> some View {
        let nt = NumberText(language: app.language)
        let p = packs[i]
        return HStack(spacing: 6) {
            PackCell(text: p.name, prompt: hint) { v in edit(i) { $0.name = v } }
            PackCell(text: p.hours.map { nt.num($0) } ?? "", prompt: t.t("gen.hoursShort"), align: .center, numeric: true) { v in
                edit(i) { $0.hours = FormMoneyField.parse(v).map { NSDecimalNumber(decimal: $0).doubleValue }.flatMap { $0 > 0 ? $0 : nil } }
            }
            .frame(width: 46)
            PackCell(text: FormMoneyField.show(p.price), prompt: nt.currencySign(app.settings.currency.rawValue),
                     align: .trailing, numeric: true) { v in edit(i) { $0.price = FormMoneyField.parse(v) ?? 0 } }
            .frame(width: 82)
            Button {
                var list = app.genrePacks(genre)
                list.remove(at: i)
                app.setGenrePacks(genre, list)
            } label: {
                Text("✕").font(.system(size: 15)).foregroundStyle(pal.ink6).frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.t("gen.removeAria"))
        }
        // Удалили строку выше — ячейки ниже пересоздаются со своими числами.
        .id("\(i)-\(packs.count)")
    }

    private func edit(_ i: Int, _ change: (inout Pack) -> Void) {
        var list = app.genrePacks(genre)
        guard list.indices.contains(i) else { return }
        change(&list[i])
        app.setGenrePacks(genre, list)
    }
}

/// Поле пакета (`.pack-item input`): 14, поля 10, радиус 10. Текст держит само,
/// чтобы «1,» не терялось, пока дробь не дописана.
struct PackCell: View {
    let text: String
    let prompt: String
    var align: TextAlignment = .leading
    var numeric = false
    let commit: (String) -> Void
    @State private var value = ""
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        TextField("", text: $value, prompt: Text(prompt).foregroundStyle(pal.ink8))
            #if os(iOS)
            .keyboardType(numeric ? .decimalPad : .default)
            #endif
            .multilineTextAlignment(align)
            .font(.system(size: 14).monospacedDigit()).foregroundStyle(pal.ink)
            .padding(10)
            // Веб красит поля пакета в `--sheet` — цвет самой группы, и поле не видно; здесь `--field`.
            .background(pal.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onAppear { value = text }
            .onChange(of: value) { _, v in if v != text { commit(v) } }
    }
}
