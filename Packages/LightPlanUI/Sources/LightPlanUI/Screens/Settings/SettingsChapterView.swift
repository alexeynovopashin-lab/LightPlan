import SwiftUI
import LightPlanData
import LightPlanDomain
#if os(iOS)
import UIKit
#endif

/// Страница одной главы настроек. Свои разделы итерации 19а работают;
/// разделы, содержимое которых делает другая итерация (корзина — 22, карта —
/// 20, мудборды и организации — 28, знакомство — 29, уведомления — 30,
/// копия и облако — 31), стоят на своём месте в главе приглушённой строкой:
/// свою работу они добавят сами.
struct SettingsChapterView: View {
    @Bindable var app: AppModel
    let chapter: SettingsView.Chapter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    private var t: Lexicon { app.lexicon }
    private var s: AppSettings { app.settings }

    var body: some View {
        List {
            switch chapter {
            case .profile: profile
            case .view: view
            case .shoots: shoots
            case .alerts: foreign("set.feedback"); foreign("set.notify")
            case .places: foreign("nav.map"); foreign("set.places")
            case .store: foreign("set.moodboards"); foreign("set.orgsDocs"); foreign("card.bin")
            case .data: foreign("set.data"); foreign("set.icsImport"); foreign("cloud.title")
            case .locale: locale
            case .about: about
            }
        }
    }

    // MARK: - Профиль

    @ViewBuilder private var profile: some View {
        Section {
            CitySearchField(app: app)
        } header: {
            Text(t.t("set.myCity"))
        } footer: {
            Text(t.t("set.myCityNote"))
        }
        // Номер, ID приложения и контакты — профиль для Event OS; ни одна
        // итерация плана их пока не назначает (записано в DECISIONS).
        foreign("set.myPhone")
        foreign("set.appId")
        foreign("set.contacts")
    }

    // MARK: - Вид

    @ViewBuilder private var view: some View {
        // Лента суток и прорезь — только в астро: в «Просто» самой ленты нет,
        // выбор вида был бы настройкой без предмета (`renderRibbonSeg`).
        if s.pro {
            segment("set.ribbon", \.ribbonMode, [(.drum, "set.ribbonDrum"), (.lane, "set.ribbonLane")],
                    note: t.t(s.ribbonMode == .drum ? "set.ribbonNoteDrum" : "set.ribbonNoteLane"))
        }
        // Прорезь видна только у барабана и только в светлой теме: в тёмной
        // три вида сходятся в один (`renderDrumSlotSeg`).
        if s.pro, s.ribbonMode == .drum, colorScheme == .light {
            segment("set.drumSlot", \.drumSlot,
                    [(.paper, "set.drumPaper"), (.graphite, "set.drumGraphite"), (.window, "set.drumWindow")],
                    note: t.t("set.drumNote" + s.drumSlot.rawValue.prefix(1).uppercased() + s.drumSlot.rawValue.dropFirst()))
        }
        segment("set.theme", \.theme, [(.dark, "set.themeDark"), (.light, "set.themeLight"), (.auto, "set.themeAuto")],
                note: t.t("set.themeNote"))
    }

    // MARK: - Съёмки

    @ViewBuilder private var shoots: some View {
        foreign("set.calendar")
        foreign("card.delivery")
        segment("set.step", \.timeStep, AppSettings.steps.map { ($0, "set.step\($0)") },
                note: s.timeStep == 30 ? t.t("set.stepNote30")
                    : t.t("set.stepNoteN", ["n": t.count("unit.min", s.timeStep)]))
        Section {
            Picker(t.t("set.travel"), selection: binding(\.travelMin)) {
                ForEach(AppSettings.travelChoices, id: \.self) { Text(String($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text(t.t("set.travel"))
        } footer: {
            Text(t.t("set.travelNote", ["n": t.count("unit.min", s.travelMin)]))
        }
        foreign("set.music")
        foreign("set.playlists")
        foreign("set.finish")
    }

    // MARK: - Язык и регион

    @ViewBuilder private var locale: some View {
        Section {
            Button {
                openLanguageSettings()
            } label: {
                HStack {
                    Text(t.t("set.language")).foregroundStyle(.primary)
                    Spacer()
                    Text(SettingsText.languageName(app.language)).foregroundStyle(.secondary)
                    #if os(iOS)
                    Icon("chevron", size: 12, line: 1.8).foregroundStyle(.tertiary)
                    #endif
                }
            }
            .tint(.primary)
        } footer: {
            Text(t.t(Lexicon.has(app.language) ? "set.langNote" : "set.langStub"))
        }

        segment("set.clock", \.clock, [(.auto, "set.clockAuto"), (.h24, "set.clock24"), (.h12, "set.clock12")],
                note: t.t(s.clock == .auto ? "set.clockNoteAuto" : "set.clockNote",
                          ["sample": ClockText(language: app.language, preference: AppModel.clock(s.clock)).fmt(19 * 60 + 52)]))

        Section {
            Picker(t.t("set.units"), selection: binding(\.tempUnit)) {
                Text("°C").tag(AppSettings.TempUnit.c)
                Text("°F").tag(AppSettings.TempUnit.f)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text(t.t("set.units"))
        } footer: {
            Text(t.t(s.tempUnit == .f ? "set.unitNoteF" : "set.unitNoteC"))
        }

        let num = NumberText(language: app.language)
        Section {
            Picker(t.t("set.currency"), selection: binding(\.currency)) {
                ForEach(Currency.allCases, id: \.self) { c in
                    Text(num.currencySign(c.rawValue) + " " + c.rawValue).tag(c)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(t.t("set.currency"))
        } footer: {
            Text(t.t("set.curNote", ["sample": num.money(14000, s.currency.rawValue)]))
        }

        Section {
            Picker(t.t("set.practice"), selection: Binding(
                get: { s.practice },
                set: { p in app.update { $0.practice = p; $0.practicePicked = true } })) {
                ForEach(AppSettings.Practice.allCases, id: \.self) { p in
                    Text(t.t("practice." + p.rawValue)).tag(p)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(t.t("set.practice"))
        } footer: {
            Text(t.t("practice.note." + s.practice.rawValue))
        }
    }

    /// Своего выбора языка нет: строка ведёт на страницу приложения в
    /// настройках iPhone. iOS после смены языка перезапускает приложение —
    /// поэтому отложенная запись снимка дописывается до ухода.
    private func openLanguageSettings() {
        #if os(iOS)
        Task {
            await app.flush()
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
        #endif
    }

    // MARK: - О приложении

    @ViewBuilder private var about: some View {
        foreign("tour.row")
        FeedbackSection(app: app)
        foreign("set.legal")
        Section {
            EmptyView()
        } footer: {
            VStack(alignment: .leading, spacing: 12) {
                Text(t.t("set.privacy"))
                Text(t.t("set.tagline") + "\n" + t.t("set.build", ["stamp": SettingsText.buildStamp(app.language, clock: AppModel.clock(s.clock))]))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Общие куски

    /// Сегмент с подписью и примечанием — `.seg` + `.seg-note` веба.
    private func segment<V: Hashable>(_ titleKey: String, _ key: WritableKeyPath<AppSettings, V>,
                                      _ options: [(V, String)], note: String) -> some View {
        Section {
            Picker(t.t(titleKey), selection: binding(key)) {
                ForEach(options, id: \.0) { v, k in Text(t.t(k)).tag(v) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text(t.t(titleKey))
        } footer: {
            Text(note)
        }
    }

    /// Раздел чужой итерации: имя на месте, содержимого пока нет.
    private func foreign(_ titleKey: String) -> some View {
        Section {
            Text(t.t(titleKey)).foregroundStyle(.tertiary)
        }
    }

    private func binding<V>(_ key: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { app.settings[keyPath: key] },
                set: { v in app.update { $0[keyPath: key] = v } })
    }
}

extension SettingsText {
    /// Штамп сборки — дата и время файла программы, как веб берёт
    /// `document.lastModified` (`renderBuildInfo`): без ручного счётчика.
    static func buildStamp(_ language: String, clock: ClockPreference = .auto) -> String {
        guard let url = Bundle.main.executableURL,
              let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return "—" }
        let dt = DateText(language: language)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.hour, .minute], from: d)
        return dt.dNum(d) + " " + ClockText(language: language, preference: clock).fmt(Double(c.hour! * 60 + c.minute!))
    }
}
