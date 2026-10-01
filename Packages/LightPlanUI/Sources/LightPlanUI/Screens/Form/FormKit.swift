import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Оборудование и документы заказа в форме (итерация 24, шаг 4а). Правила —
/// `EventForm` (`FormKit.swift` домена); файлы на Диск — итерация 31: без
/// облака «Файл» говорит то же, что веб без подключённого Диска.

// MARK: - Оборудование

/// Строка «Оборудование» (`#fKitRow`): `.row` — 16 `--ink`, справа «n из m»
/// `--ink-3` или «Пока пусто»; тап — лист со списком.
struct FormKitRow: View {
    @Bindable var app: AppModel
    let form: EventForm
    @Binding var sheet: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let list = app.equipment
        let value = list.isEmpty ? t.t("kit.empty")
            : t.t("kit.count", ["n": String(form.kitChecked(in: list)), "m": String(list.count)])
        Button { sheet = true } label: {
            HStack(spacing: 12) {
                Text(t.t("form.kit")).font(.system(size: 16)).foregroundStyle(pal.ink)
                Spacer(minLength: 0)
                Text(value).font(.system(size: 16)).monospacedDigit().foregroundStyle(pal.ink3)
                    .shotNode("form.kitSum", text: value)
            }
            .padding(.vertical, 14).padding(.horizontal, 15).frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.t("form.kitAria"))
        .accessibilityValue(value)
        .shotNode("form.kit")
    }
}

/// Лист «Оборудование» (`#kSheet`): свой список без каталога; у позиции —
/// тумблер «берём на эту съёмку» и крестик; внизу — новая позиция и «＋».
struct KitSheet: View {
    @Bindable var app: AppModel
    @State private var draft = ""
    @FocusState private var typing: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let list = app.equipment
        let gear = app.form?.gear ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(pal.edge).frame(width: 38, height: 4).frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 18)
                Text(t.t("form.kit")).font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
                    .shotNode("kit.title")
                Text(t.t("kit.sub")).font(.system(size: 13)).foregroundStyle(pal.ink4).padding(.top, 5)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    if list.isEmpty {
                        // `.kit-empty`: 12 `--ink-6`, поля 0 15 10.
                        Text(t.t("kit.empty")).font(.system(size: 12)).foregroundStyle(pal.ink6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 10)
                    } else {
                        ForEach(list.indices, id: \.self) { i in
                            // `.pack-item`: зазор 6, поля 0 15 10; имя 14 `--ink`; `.pk-x` 26, 15 `--ink-6`.
                            HStack(spacing: 6) {
                                Text(list[i]).font(.system(size: 14)).foregroundStyle(pal.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Toggle("", isOn: Binding(get: { gear.contains(list[i]) }, set: { _ in app.toggleFormGear(list[i]) }))
                                    .labelsHidden().tint(pal.brass)
                                Button { app.removeEquipment(at: i) } label: {
                                    Text("✕").font(.system(size: 15)).foregroundStyle(pal.ink6)
                                        .frame(width: 26, height: 26).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(t.t("kit.removeAria"))
                            }
                            .padding(.horizontal, 15).padding(.top, i == 0 ? 13 : 0).padding(.bottom, 10)
                            .shotNode("kit.item")
                        }
                    }
                    HStack(spacing: 6) {
                        TextField("", text: $draft, prompt: Text(t.t("kit.newPh")).foregroundStyle(pal.ink8))
                            .font(.system(size: 14)).foregroundStyle(pal.ink)
                            .focused($typing).submitLabel(.done)
                            .onSubmit(add)
                            .padding(10)
                            .background(pal.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button(action: add) {
                            Text(t.t("kit.add")).font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.brass)
                                .frame(width: 38, height: 38).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 15).padding(.top, 10).padding(.bottom, 10)
                    .overlay(alignment: .top) { Rectangle().fill(pal.surface).frame(height: 1) }
                    .shotNode("kit.new")
                }
                .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .shotNode("kit.sheet")
    }

    /// «＋» и «Ввод»: позиция в список и сразу на съёмку; поле остаётся в фокусе.
    private func add() {
        app.addEquipment(draft)
        draft = ""
        typing = true
    }
}

// MARK: - Документы заказа

/// Документы заказа в группе «Заказ» (`#docKinds`, `#docGrid`, `.ref-add`, `#docNote`).
/// Виды чипсами — и фильтр, и метка новым; карточки по три в ряд; «Файл» и «Ссылка».
struct FormDocs: View {
    @Bindable var app: AppModel
    let form: EventForm
    @State private var kind: DocKind?
    @State private var note: String?
    @State private var asking = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        VStack(alignment: .leading, spacing: 0) {
            kinds(pal, t).shotNode("form.docKinds")
            let shown = form.docsShown(kind: kind)
            if !shown.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(shown, id: \.index) { p in card(p.index, p.doc, pal, t) }
                }
                .padding(.horizontal, 15).padding(.top, 12)
                .shotNode("form.docGrid")
            }
            HStack(spacing: 8) {
                addButton(t.t("doc.fileBtn"), icon: "doc", pal) { note = t.t("ref.noDiskDoc") }
                    .shotNode("form.docFile")
                addButton(t.t("ref.link"), icon: nil, pal) { asking = true }
                    .shotNode("form.docLink")
            }
            .padding(12).padding(.horizontal, 3)
            .overlay(alignment: .top) { Rectangle().fill(pal.surface).frame(height: 1) }
            if let note {
                // `.ref-note`: 12 `--ink-4`, межстрочие 1,45, поля 0 15 12.
                Text(note).font(.system(size: 12)).foregroundStyle(pal.ink4).lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15).padding(.bottom, 12)
                    .shotNode("form.docNote")
            }
        }
        .sheet(isPresented: $asking) {
            AskLinkSheet(title: t.t("doc.linkAsk"), titleField: t.t("doc.titleOpt"), ok: t.t("ask.ok"), cancel: t.t("ask.cancel")) { a in
                asking = false
                if let a { app.addFormDocLink(a.url, kind: kind, title: a.title) }
            }
        }
    }

    /// `.rf-tags.wrap`: чипсы в перенос, зазор 7, поля 12 13 6; `.rf-tag` — 13 `--ink-3`,
    /// край 1 `--press`, скругление 11; выбранный — латунь, текст `--sheet`; счётчик `--ink-6`.
    private func kinds(_ pal: Palette, _ t: Lexicon) -> some View {
        FlowLayout(spacing: 7) {
            ForEach(app.docKinds, id: \.self) { k in
                let on = kind == k
                let n = form.docCount(k)
                Button { kind = on ? nil : k } label: {
                    (Text(kindName(k, t)) + (n > 0 ? Text("  \(n)").foregroundStyle(on ? Color(hex: 0x17150F, alpha: 0.6) : pal.ink6) : Text("")))
                        .font(.system(size: 13)).monospacedDigit()
                        .foregroundStyle(on ? pal.sheet : pal.ink3)
                        .frame(minHeight: 18)   // строка 13 px у веба — 18, чипс 34 с краем
                        .padding(.vertical, 8).padding(.horizontal, 13)
                        .background(on ? pal.brass : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? pal.brass : pal.press, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13).padding(.top, 12).padding(.bottom, 6)
    }

    /// `.ref-card.link`: квадрат, подложка `--sheet-4`, скругление 10, поля 10;
    /// сверху 9,5 прописными латунью (700), под ним 11 `--ink-4` до четырёх строк; крестик 22.
    private func card(_ i: Int, _ d: Attachment, _ pal: Palette, _ t: Lexicon) -> some View {
        let top = DocLabel.top(d, kindName: { kindName($0, t) }, fileWord: t.t("doc.file"), linkWord: t.t("ref.link"))
        let sub = DocLabel.sub(d, anyWord: t.t("doc.any"))
        return Button { open(d, t) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(top).font(.system(size: 9.5, weight: .bold)).tracking(0.4).textCase(.uppercase)
                    .foregroundStyle(pal.brass).lineLimit(1).padding(.trailing, 22)
                Text(sub).font(.system(size: 11)).foregroundStyle(pal.ink4).lineSpacing(3).lineLimit(4)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(10)
            .aspectRatio(1, contentMode: .fit)
            .background(pal.sheet4, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button { app.removeFormDoc(at: i) } label: {
                Text("✕").font(.system(size: 13)).foregroundStyle(pal.ink)
                    .frame(width: 22, height: 22).background(pal.fillA, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
        }
        .shotNode("form.docCard")
    }

    /// `.ref-btn`: во всю долю, подложка `--sheet`, скругление 10, поле 11, 14 `--ink-3`, знак 17.
    private func addButton(_ title: String, icon: String?, _ pal: Palette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Icon(icon, size: 17, line: 1.6) } else { LinkGlyph().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 17, height: 17) }
                Text(title).font(.system(size: 14))
            }
            .frame(minHeight: 20)   // строка 14 px у веба — 20: кнопка 42
            .foregroundStyle(pal.ink3)
            .frame(maxWidth: .infinity).padding(11)
            .background(pal.sheet, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Ссылка открывается в браузере; файл живёт на Диске — без облака (итерация 31)
    /// веб говорит «нет связи с Диском», так же и здесь.
    private func open(_ d: Attachment, _ t: Lexicon) {
        if d.source == .link, let u = d.url.flatMap(URL.init(string:)) { openURL(u); return }
        if d.path != nil { note = t.t("doc.openFail") }
    }

    /// Имя вида словарём; незнакомого слова нет — код как есть (веб `docKindName`).
    private func kindName(_ k: DocKind, _ t: Lexicon) -> String {
        let s = t.t("doc." + k.rawValue)
        return s == "doc." + k.rawValue ? k.rawValue : s
    }
}

/// Знак ссылки веба (`#docLink`): два звена цепи, вид 24. Дуги SVG (`a4 4 0 0 0`)
/// строятся по центру и углам — так звенья те же, что у веба, а не на глаз.
struct LinkGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let k = r.width / 24
        var p = Path()
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        /// Дуга радиуса 4 с флагами 0 0 из `a` в `b` (единицы вида 24).
        func arc(_ a: (Double, Double), _ b: (Double, Double)) {
            let (mx, my) = ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
            let (dx, dy) = (b.0 - a.0, b.1 - a.1)
            let half = hypot(dx, dy) / 2
            let rad = max(4, half)
            let h = sqrt(max(0, rad * rad - half * half))
            // Флаг хода 0 — против часовой на экране: центр слева от хода a→b.
            let (cx, cy) = (mx + h * dy / (2 * half), my - h * dx / (2 * half))
            let a0 = atan2(a.1 - cy, a.0 - cx), a1 = atan2(b.1 - cy, b.0 - cx)
            var sweep = a1 - a0
            if sweep > 0 { sweep -= 2 * .pi }
            let n = 8
            for s in 1...n {
                let t = a0 + sweep * Double(s) / Double(n)
                p.addLine(to: pt(cx + rad * cos(t), cy + rad * sin(t)))
            }
        }
        // M10 13.5a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1.6 1.6
        p.move(to: pt(10, 13.5)); arc((10, 13.5), (15.7, 13.5))
        p.addLine(to: pt(18.7, 10.5)); arc((18.7, 10.5), (13, 4.8))
        p.addLine(to: pt(11.4, 6.4))
        // M14 10.5a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1.6-1.6
        p.move(to: pt(14, 10.5)); arc((14, 10.5), (8.3, 10.5))
        p.addLine(to: pt(5.3, 13.5)); arc((5.3, 13.5), (11, 19.2))
        p.addLine(to: pt(12.6, 17.6))
        return p
    }
}

/// Лист «ссылка на документ» с двумя полями: ссылка и необязательное «Название» (итерация 28,
/// шаг 12а). Пустая ссылка — как «Отмена»; пустое название — имя соберётся по умолчанию.
struct AskLinkSheet: View {
    let title: String
    let titleField: String
    let ok: String
    let cancel: String
    let answer: ((url: String, title: String)?) -> Void
    @State private var url = ""
    @State private var name = ""
    @FocusState private var focus: Field?
    @Environment(\.colorScheme) private var scheme
    private enum Field { case url, name }

    var body: some View {
        let pal = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(pal.edge).frame(width: 38, height: 4).frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 18)
            Text(title).font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
                .fixedSize(horizontal: false, vertical: true)
            field($url, .url, placeholder: "", pal).padding(.top, 16)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled(true)
                .shotNode("ask.link.url")
            field($name, .name, placeholder: titleField, pal).padding(.top, 10)
                .keyboardType(.default).textInputAutocapitalization(.sentences)
                .shotNode("ask.link.title")
            Button { finish() } label: {
                Text(ok).font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.onBrass)
                    .frame(maxWidth: .infinity).padding(16)
                    .background(pal.brass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            Button { answer(nil) } label: {
                Text(cancel).font(.system(size: 15)).foregroundStyle(pal.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.hidden)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { focus = .url } }
    }

    private func field(_ text: Binding<String>, _ f: Field, placeholder: String, _ pal: Palette) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(pal.ink6))
            .font(.system(size: 16)).foregroundStyle(pal.ink)
            .focused($focus, equals: f).submitLabel(f == .url ? .next : .done)
            .onSubmit { if f == .url { focus = .name } else { finish() } }
            .padding(.vertical, 14).padding(.horizontal, 15)
            .background(focus == f ? pal.press : pal.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func finish() {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        answer(u.isEmpty ? nil : (u, name))
    }
}

/// Лист «спросить строку» (веб `#askSheet`, `askText`/`askUrl`): заголовок, поле
/// с клавиатурой адреса, «Добавить» латунью и «Отмена». Пустое — как «Отмена».
struct AskTextSheet: View {
    let title: String
    let ok: String
    let cancel: String
    /// Клавиатура: адрес для ссылки, обычная для имён (мудборд, 28).
    var keyboard: UIKeyboardType = .URL
    var initial = ""
    /// Пустое имя — тоже ответ (переименование снимает имя); по умолчанию пустое = «Отмена».
    var allowEmpty = false
    let answer: (String?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(pal.edge).frame(width: 38, height: 4).frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 18)
            Text(title).font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
                .fixedSize(horizontal: false, vertical: true)
            TextField("", text: $text)
                .font(.system(size: 16)).foregroundStyle(pal.ink)
                .keyboardType(keyboard).textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .URL)
                .focused($focused).submitLabel(.done).onSubmit { finish() }
                .padding(.vertical, 14).padding(.horizontal, 15)
                .background(focused ? pal.press : pal.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 16)
                .shotNode("ask.input")
            Button { finish() } label: {
                Text(ok).font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.onBrass)
                    .frame(maxWidth: .infinity).padding(16)
                    .background(pal.brass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            Button { answer(nil) } label: {
                Text(cancel).font(.system(size: 15)).foregroundStyle(pal.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            text = initial
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { focused = true }
        }
    }

    private func finish() {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        answer(v.isEmpty && !allowEmpty ? nil : v)
    }
}
