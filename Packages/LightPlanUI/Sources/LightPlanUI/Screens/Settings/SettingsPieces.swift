import SwiftUI
import LightPlanDomain
import LightPlanData

/// «Мой город»: поле и подсказки справочника (`cityHints` веба). Набранное
/// руками — уже ответ: имя пишется сразу, свет не двигается. Выбор подсказки
/// пишет имя, точку и страну — и «Свет» переезжает туда же.
struct CitySearchField: View {
    @Bindable var app: AppModel
    /// `.list` — строки системного списка (лист первого запуска), `.web` —
    /// поле `.set-in` и подсказки строками `.item` (глава «Профиль», 19б).
    enum Style { case list, web }
    var style: Style = .list
    @State private var text = ""
    @State private var hits: [CityHit] = []
    /// Последнее имя, выбранное в подсказке: пока поле ему равно, справочник
    /// не спрашиваем — иначе выбор тут же вызвал бы второй поиск того же города.
    @State private var picked: String?

    var body: some View {
        switch style {
        case .list: fieldAndHits
        case .web: VStack(alignment: .leading, spacing: 0) { fieldAndHits }
        }
    }

    @ViewBuilder private var fieldAndHits: some View {
        let field = TextField(app.lexicon.t("start.cityPh"), text: $text)
            .autocorrectionDisabled()
            .onAppear { picked = app.settings.home.name; text = app.settings.home.name }
            .onChange(of: text) { _, v in
                if v != picked { app.typeCity(v.trimmingCharacters(in: .whitespaces)) }
            }
            .task(id: text) {
                let q = text.trimmingCharacters(in: .whitespaces)
                guard q != picked, q.count >= 3 else { hits = []; return }
                // Пауза веба — 450 мс: спрашиваем, когда перестали набирать.
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                hits = (try? await app.cityLookup.cities(matching: q)) ?? []
            }
        if style == .web { field.modifier(SetInputStyle()) } else { field }
        ForEach(hits, id: \.self) { h in
            Button {
                picked = h.name
                text = h.name
                hits = []
                app.takeCity(h)
            } label: {
                if style == .web {
                    SetItemRow(icon: "pin", title: h.name, value: h.area, chevron: false)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.name).foregroundStyle(.primary)
                        if !h.area.isEmpty { Text(h.area).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// «Обратная связь»: отзыв или баг, текст, системная отправка (`fbSend`).
/// Сервера нет — текст уходит туда, куда человек выберет сам. В хвосте —
/// диагностика без съёмок и клиентских данных: канал, сборка, язык, практика.
struct FeedbackSection: View {
    @Bindable var app: AppModel
    @State private var kind = "idea"
    @State private var text = ""

    private static let telegram = URL(string: "https://t.me/lightplan_app")!

    @Environment(\.colorScheme) private var colorScheme

    /// Вид `#setOvAbout` веба: подпись, сегмент «идея / ошибка», поле
    /// (`.field textarea`: `--sheet`, 16/24, поле 14 · 15, скругление 12),
    /// кнопка отправки (`.data-btn`), ссылка на канал и пояснение.
    var body: some View {
        let t = app.lexicon, pal = Palette(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            SecLabel(text: t.t("fb.title"))
            WebSeg(options: [(t.t("fb.idea"), "idea"), (t.t("fb.bug"), "bug")], selection: $kind)
                .padding(.horizontal, 24).padding(.top, 12)
            TextField(t.t("fb.textPh"), text: $text, axis: .vertical)
                .lineLimit(2...8)
                .lineSpacing(24 - 19.1)
                .modifier(SetInputStyle())
                .padding(.top, 2)
            ShareLink(item: message) {
                Text(t.t("fb.send"))
            }
            .buttonStyle(DataButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Link(destination: Self.telegram) {
                Text(t.t("fb.telegram")).font(.system(size: 14)).foregroundStyle(pal.brassInk)
            }
            .padding(.horizontal, 24).padding(.top, 12)
            SetNote(text: t.t("fb.note"))
        }
    }

    private var message: String {
        let t = app.lexicon
        let title = t.t(kind == "bug" ? "fb.bugTitle" : "fb.ideaTitle")
        // Канал «native»: у веба здесь beta или main, у приложения — своя ветка.
        let diag = ["native", SettingsText.buildStamp(app.language), app.language, app.settings.practice.rawValue]
            .joined(separator: " · ")
        return title + "\n" + text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n—\n" + diag
    }
}

/// Лист «Откуда вы работаете» — первый запуск (`startSheet` веба). «Готово»
/// закрывает лист, а не подтверждает ответ: пустое поле не повод держать
/// человека на пороге. Только город: «Свету» номер не нужен, его спросит лист «Ваш номер»
/// на входе в планировщик (Алексей 05.11, шаг 30ж.1).
struct StartSheet: View {
    @Bindable var app: AppModel
    /// 30и.6: сколько раз выбран город из подсказки — каждый выбор рисует линию города заново (`CityOutlineView`).
    @State private var cityPicks = 0

    var body: some View {
        let t = app.lexicon
        NavigationStack {
            List {
                // 30и.6: линия крыш города одной линией над полем: общий силуэт, для Москвы, Петербурга, Новосибирска и Томска — своя.
                Section {
                    CityOutlineView(outline: CityOutline.of(city: app.settings.home.name), drawn: cityPicks)
                        .padding(.vertical, 6)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                Section {
                    CitySearchField(app: app)
                } header: {
                    Text(t.t("start.sub"))
                        .textCase(nil)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            }
            .onChange(of: app.settings.home.name) { _, _ in
                // Выбор из подсказки приносит координаты; набранное руками имя их сбрасывает — тогда линия не рисуется заново.
                if app.settings.home.coordinate != nil { cityPicks += 1 }
            }
            .navigationTitle(t.t("start.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.t("pick.done")) { app.finishStart() }
                }
            }
        }
    }
}

/// Лист «Ваш номер» (Алексей 05.11, шаг 30ж.1): вход в планировщик и любой другой путь к съёмке, пока
/// номера нет. Поле то же, что в «Профиле»; «Готово» работает только с номером, крестик возвращает на
/// прежний экран и ничего не записывает. Кода подтверждения нет.
struct PhoneSheet: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    var body: some View {
        let t = app.lexicon, pal = Palette(scheme)
        NavigationStack {
            List {
                Section {
                    MyPhoneField(app: app, focused: $focused)
                        .shotNode("phone.field")
                    MyPhoneCountryAsk(app: app, hint: true)
                } footer: {
                    Text(t.t("phone.why"))
                        .shotNode("phone.why", text: t.t("phone.why"))
                }
            }
            .navigationTitle(t.t("phone.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { app.cancelPhoneAsk() } label: { Icon("close", size: 16, line: 2).foregroundStyle(pal.ink) }
                        .accessibilityLabel(t.t("card.close"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { app.confirmPhoneAsk() } label: {
                        Text(t.t("pick.done")).shotNode(app.hasPlannerPhone ? "phone.done.on" : "phone.done.off")
                    }
                    .disabled(!app.hasPlannerPhone)
                }
            }
        }
        .onAppear { focused = true }
    }
}
