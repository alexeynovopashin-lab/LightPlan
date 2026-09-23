import SwiftUI
import LightPlanData

/// Экран «Настройки» — порт `#s-set` веба (итерация 19а).
///
/// Корень: переключатель Просто/Астро и девять глав в порядке веба
/// (Профиль, Вид, Съёмки, Оповещения, Карта и места, Хранилище, Данные и
/// облако, Язык и регион, О приложении). План называл семь глав — это слепок
/// 26 августа; веб с тех пор разделил «Хранилище» и «Данные», вынес
/// «Оповещения», и сверяемся с ним, а не со слепком.
///
/// Справа у строки — состояние, а не подпись «что внутри» (`renderSetNav`):
/// с этим вопросом в настройки и приходят. Раскладка — системный список:
/// стекло и контролы в нативе системные (DECISIONS, «Стекло в нативе —
/// системное»).
public struct SettingsView: View {
    @Bindable var app: AppModel

    public init(app: AppModel) { self.app = app }

    enum Chapter: String, CaseIterable, Hashable {
        case profile, view, shoots, alerts, places, store, data, locale, about

        var icon: String {
            switch self {
            case .profile: "phone"
            case .view: "sun_moon"
            case .shoots: "camera"
            case .alerts: "alarm"
            case .places: "pin"
            case .store: "briefcase"
            case .data: "cloud"
            case .locale: "chat"
            case .about: "aperture"
            }
        }

        var titleKey: String {
            switch self {
            case .profile: "set.grpProfile"
            case .view: "set.grpView"
            case .shoots: "set.grpShoots"
            case .alerts: "set.grpAlerts"
            case .places: "set.grpPlaces"
            case .store: "set.storage"
            case .data: "set.grpData"
            case .locale: "set.grpLocale"
            case .about: "set.grpAbout"
            }
        }
    }

    public var body: some View {
        let t = app.lexicon
        NavigationStack {
            List {
                Section {
                    Picker(t.t("set.mode"), selection: binding(\.pro)) {
                        Text(t.t("set.modeSimple")).tag(false)
                        Text(t.t("set.modePro")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } footer: {
                    Text(t.t("set.modeNote"))
                }

                Section {
                    ForEach(Chapter.allCases, id: \.self) { ch in
                        NavigationLink(value: ch) {
                            HStack(spacing: 12) {
                                Icon(ch.icon, size: 20, line: 1.6).foregroundStyle(.secondary)
                                Text(t.t(ch.titleKey))
                                Spacer(minLength: 8)
                                Text(value(of: ch)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle(t.t("nav.settings"))
            .navigationDestination(for: Chapter.self) { ch in
                SettingsChapterView(app: app, chapter: ch)
                    .navigationTitle(t.t(ch.titleKey))
            }
        }
    }

    /// Порт `renderSetNav`. Чужие главы (оповещения, хранилище) до своих
    /// итераций молчат: сказать о них пока нечего.
    private func value(of ch: Chapter) -> String {
        let t = app.lexicon, s = app.settings
        switch ch {
        case .profile:
            // Номер телефона ещё не перенесён — строка отвечает городом.
            return s.home.isEmpty ? t.t("set.myCityNone") : s.home.name
        case .view:
            return t.t(s.theme == .light ? "set.themeLight" : s.theme == .auto ? "set.themeAuto" : "set.themeDark")
        case .shoots:
            return t.t("set.step\(s.timeStep)")
        case .places:
            return app.spotCount > 0 ? String(app.spotCount) : t.t("card.none")
        case .data:
            return t.t("set.off")      // облака ещё нет (итерация 31) — честно «выкл»
        case .locale:
            return SettingsText.languageName(app.language) + " · "
                + NumberText(language: app.language).currencySign(s.currency.rawValue)
        case .alerts, .store, .about:
            return ""
        }
    }

    private func binding<V>(_ key: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { app.settings[keyPath: key] },
                set: { v in app.update { $0[keyPath: key] = v } })
    }
}

/// Имена и образцы, которые собирает код, а не словарь.
enum SettingsText {
    /// Языки названы на себе самих (`LANG_NAMES`): их узнают, не умея читать
    /// текущий язык интерфейса.
    static func languageName(_ code: String) -> String {
        ["ru": "Русский", "en-GB": "English (UK)", "en-US": "English (US)",
         "es": "Español", "ja": "日本語", "zh": "中文"][code] ?? code
    }
}

#Preview {
    @Previewable @State var app: AppModel?
    Group {
        if let app { SettingsView(app: app) } else { Color.clear }
    }
    .task { app = await AppModel.live() }
}
