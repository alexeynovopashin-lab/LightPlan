import SwiftUI
import LightPlanData

/// «Мой город»: поле и подсказки справочника (`cityHints` веба). Набранное
/// руками — уже ответ: имя пишется сразу, свет не двигается. Выбор подсказки
/// пишет имя, точку и страну — и «Свет» переезжает туда же.
struct CitySearchField: View {
    @Bindable var app: AppModel
    @State private var text = ""
    @State private var hits: [CityHit] = []
    /// Последнее имя, выбранное в подсказке: пока поле ему равно, справочник
    /// не спрашиваем — иначе выбор тут же вызвал бы второй поиск того же города.
    @State private var picked: String?

    var body: some View {
        TextField(app.lexicon.t("start.cityPh"), text: $text)
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
        ForEach(hits, id: \.self) { h in
            Button {
                picked = h.name
                text = h.name
                hits = []
                app.takeCity(h)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.name).foregroundStyle(.primary)
                    if !h.area.isEmpty { Text(h.area).font(.footnote).foregroundStyle(.secondary) }
                }
            }
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

    var body: some View {
        let t = app.lexicon
        Section {
            Picker(t.t("fb.title"), selection: $kind) {
                Text(t.t("fb.idea")).tag("idea")
                Text(t.t("fb.bug")).tag("bug")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField(t.t("fb.textPh"), text: $text, axis: .vertical)
                .lineLimit(3...8)
            ShareLink(item: message) {
                Text(t.t("fb.send"))
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Link(t.t("fb.telegram"), destination: Self.telegram)
        } header: {
            Text(t.t("fb.title"))
        } footer: {
            Text(t.t("fb.note"))
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
/// человека на пороге. Номер телефона веба сюда не перенесён — поля профиля
/// с номером нет ни в одной итерации плана (DECISIONS).
struct StartSheet: View {
    @Bindable var app: AppModel

    var body: some View {
        let t = app.lexicon
        NavigationStack {
            List {
                Section {
                    CitySearchField(app: app)
                } header: {
                    // `start.sub` веба говорит и о номере, которого здесь нет, —
                    // берём подпись «Моего города», она о том же без номера.
                    Text(t.t("set.myCityNote"))
                        .textCase(nil)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
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
