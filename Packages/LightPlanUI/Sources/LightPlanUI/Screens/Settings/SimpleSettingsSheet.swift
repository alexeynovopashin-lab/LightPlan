import SwiftUI
import LightPlanData
import LightPlanDomain
#if os(iOS)
import UIKit
#endif

/// Настройки в «Просто» (30г.8): один лист без глав — ответ 5 Алексея 05.11, рисунок `docs/30g2_prostoe_sketch.png`
/// (ветка описи `wt/30g-2-modes-recalc`), состав — колонка «Просто» раздела А описи `docs/30g2_modes_table.md` (№ 1–44).
///
/// Сверху, как во всех режимах, выбор режима и пояснение (№ 1, 2). Дальше прямо на листе: город, тема, напоминание,
/// Календарь iPhone, единицы, валюта; ниже пять строк, которые открывают свой экран. Чего в колонке «Просто» нет, на листе
/// нет. Значения — те же поля, что у глав «Про» и «Астро» (ответ 2): смена режима ничего не сдвигает, лист только
/// раскладывает их по-другому.
enum SimpleSheet {

    enum Item: String, CaseIterable {
        case city, theme, lightView, remind, calendar, units, clock, currency
        case clients, contacts, playlists, bin, about

        /// Строки описи (раздел А), которые стоят в этом пункте.
        var inventoryRows: [Int] {
            switch self {
            case .city: [4]
            case .theme: [10]
            case .lightView: []              // 30з.2а: нет в описи, решение оркестратора — оба вида «Света» проверяются во всех режимах
            case .remind: [24]
            case .calendar: [15, 16]          // «Куда класть» идёт вслед за тумблером
            case .units: [36]
            case .clock: [34]                // 30з.4 (слово Алексея 13.11: «в режиме просто нет переключателя 24|AMPM»): строка описи № 34 из «нет» в «есть»
            case .currency: [37]
            case .clients: [20]
            case .contacts: [7]
            case .playlists: [39, 40]         // ответ 1: плеер и библиотека остаются
            case .bin: [29]
            case .about: [41, 42, 43, 44]
            }
        }

        /// Строка с шевроном: открывает свой экран, а не меняется на месте.
        var opensScreen: Bool {
            switch self {
            case .clients, .contacts, .playlists, .bin, .about: true
            case .city, .theme, .lightView, .remind, .calendar, .units, .clock, .currency: false
            }
        }
    }

    /// Порядок листа — как на рисунке.
    static let items: [Item] = [.city, .theme, .lightView, .remind, .calendar, .units, .clock, .currency,
                                .clients, .contacts, .playlists, .bin, .about]

    /// Строки описи над листом во всех режимах: выбор режима и пояснение под ним.
    static let aboveRows: Set<Int> = [1, 2]

    /// Как стоит секция Календаря iPhone на листе: тумблер и «Куда класть», без «Других календарей».
    static let calendarLook: CalendarMirrorSection.Look = .sheet

    /// Глава, которую открывает строка листа (остальные строки открывают слой поверх вкладок или корзину).
    static func chapter(of item: Item) -> SettingsView.Chapter? {
        switch item {
        case .playlists: .playlists
        case .about: .about
        default: nil
        }
    }

    /// Что показывает пункт сейчас: ровно те поля, что читают главы «Про» и «Астро». Это же — текст узла снимка.
    @MainActor static func state(_ item: Item, app: AppModel) -> String {
        let s = app.settings, t = app.lexicon
        switch item {
        case .city: return s.home.isEmpty ? "" : s.home.name
        case .theme: return s.theme.rawValue
        case .lightView: return s.lightBlocks ? "blocks" : "flat"
        case .remind: return String(app.remindMinutes)
        case .calendar: return app.calendarMirrorOn ? "on" : "off"
        case .units: return s.tempUnit.rawValue
        case .clock: return s.clock.rawValue
        case .currency: return s.currency.rawValue
        case .clients: return app.clientsValue
        case .contacts: return app.contactsValue
        case .playlists: return SettingsView.value(of: .playlists, app: app)
        case .bin: return app.trashed.isEmpty ? t.t("bin.emptyShort") : String(app.trashed.count)
        case .about: return ""
        }
    }

    /// Настройка листа пишет в то же поле, что и глава (ответ 2).
    @MainActor static func binding<V>(_ app: AppModel, _ key: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { app.settings[keyPath: key] }, set: { v in app.update { $0[keyPath: key] = v } })
    }

    /// «Напоминать о съёмке»: то же `notif.remind`, что в главе «Оповещения».
    @MainActor static func remind(_ app: AppModel) -> Binding<Int> {
        Binding(get: { app.remindMinutes }, set: { app.setRemindMinutes($0) })
    }
}

/// Лист «Просто». Куски — те же, что в главах: подпись, сегмент, фишки, строка, секция Календаря и напоминания. Обычных
/// пояснений под настройками нет, как на рисунке; пояснение, которое просит действия (разрешить уведомления, доступ к
/// календарю), остаётся.
struct SimpleSettingsSheet: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SimpleSheet.items, id: \.self) { item in
                piece(item)
                    .shotNode("simple." + item.rawValue, text: SimpleSheet.state(item, app: app))
            }
        }
        .padding(.top, 2)
        .shotNode("simple")
    }

    @ViewBuilder private func piece(_ item: SimpleSheet.Item) -> some View {
        let t = app.lexicon
        switch item {
        case .city:
            VStack(alignment: .leading, spacing: 0) {
                SecLabel(text: t.t("set.myCity"), first: true)
                CitySearchField(app: app, style: .web)
            }
        case .theme:
            VStack(alignment: .leading, spacing: 0) {
                SecLabel(text: t.t("set.theme"))
                WebSeg(options: [(t.t("set.themeDark"), AppSettings.Theme.dark), (t.t("set.themeLight"), .light),
                                 (t.t("set.themeAuto"), .auto)],
                       selection: SimpleSheet.binding(app, \.theme))
                    .padding(.horizontal, 24).padding(.top, 12)
            }
        case .lightView:
            VStack(alignment: .leading, spacing: 0) {
                SecLabel(text: t.t("set.lightView"))
                WebSeg(options: [(t.t("set.lightViewBlocks"), true), (t.t("set.lightViewFlat"), false)],
                       selection: SimpleSheet.binding(app, \.lightBlocks))
                    .padding(.horizontal, 24).padding(.top, 12)
            }
        case .remind:
            ShootReminderSection(app: app, quiet: true)
        case .calendar:
            CalendarMirrorSection(app: app, look: SimpleSheet.calendarLook)
                .padding(.top, 14)
        case .units:
            VStack(alignment: .leading, spacing: 0) {
                SecLabel(text: t.t("set.units"))
                WebSeg(options: [("°C", AppSettings.TempUnit.c), ("°F", AppSettings.TempUnit.f)],
                       selection: SimpleSheet.binding(app, \.tempUnit))
                    .padding(.horizontal, 24).padding(.top, 12)
            }
        case .clock:
            // Часы — тот же `settings.clock` и те же три выбора и слова, что в главе «Язык и регион» (`set.clock*`); пояснения под ним, как у остальных пунктов листа, нет.
            VStack(alignment: .leading, spacing: 0) {
                SecLabel(text: t.t("set.clock"))
                WebSeg(options: [(t.t("set.clockAuto"), AppSettings.Clock.auto), (t.t("set.clock24"), .h24), (t.t("set.clock12"), .h12)],
                       selection: SimpleSheet.binding(app, \.clock))
                    .padding(.horizontal, 24).padding(.top, 12)
            }
        case .currency:
            let num = NumberText(language: app.language)
            VStack(alignment: .leading, spacing: 0) {
                SecLabel(text: t.t("set.currency"))
                Chips(options: Currency.allCases.map { (num.currencySign($0.rawValue) + " " + $0.rawValue, $0) },
                      selection: SimpleSheet.binding(app, \.currency))
            }
            .padding(.bottom, 14)
        case .clients:
            Button { withAnimation(overlaySlide) { app.openClients() } } label: { row(item, icon: "heart", key: "set.clients") }
                .buttonStyle(.plain)
        case .contacts:
            Button { withAnimation(overlaySlide) { app.openContacts() } } label: { row(item, icon: "phone", key: "set.contacts") }
                .buttonStyle(.plain)
        case .playlists, .about:
            if let ch = SimpleSheet.chapter(of: item) {
                NavigationLink(value: ch) { row(item, icon: ch.icon, key: ch.titleKey) }
                    .buttonStyle(.plain)
            }
        case .bin:
            Button { app.binOpen = true } label: { row(item, icon: "trash", key: "card.bin") }
                .buttonStyle(.plain)
        }
    }

    private func row(_ item: SimpleSheet.Item, icon: String, key: String) -> some View {
        SetItemRow(icon: icon, title: app.lexicon.t(key), value: SimpleSheet.state(item, app: app))
    }
}

/// «Напоминать о съёмке» (шаг «Напоминание-1»): `notif.remind`, минуты до начала съёмки или встречи. Выбор не «выкл»
/// спрашивает у системы право уведомлять, если ещё не спрашивали; отказ — пояснение ведёт в настройки iPhone. Одна и та же
/// секция в главе «Оповещения» и на листе «Просто» (30г.8: `quiet` — без обычного пояснения, просьба и отказ видны; минуты
/// числами без «мин», как на рисунке).
struct ShootReminderSection: View {
    @Bindable var app: AppModel
    var quiet = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let t = app.lexicon
        let on = app.remindMinutes > 0
        let ask = on && app.alertAuth == .notDetermined
        let denied = on && app.alertAuth == .denied
        VStack(alignment: .leading, spacing: 0) {
            SecLabel(text: t.t("set.remind"), node: "sec.remind")
            // На листе — голые числа, как на рисунке: «10 мин» в шести ячейках обрезается до «10 м…» (замер 30г.8).
            WebSeg(options: ReminderSchedule.choices.map { ($0 == 0 ? t.t("set.off") : quiet ? String($0) : t.count("unit.minute", $0), $0) },
                   selection: SimpleSheet.remind(app))
                .shotNode("remind.seg", text: "\(app.remindMinutes)")
                .padding(.horizontal, 24).padding(.top, 12)
            if ask || denied || !quiet {
                SetNote(text: t.t(ask ? "set.remindAsk" : denied ? "set.remindDenied" : "set.remindNote"), node: "remind.note")
            }
            if ask {
                Button { app.setRemindMinutes(app.remindMinutes) } label: { Text(t.t("set.wxAlertAllow")) }
                    .buttonStyle(DataButtonStyle())
                    .shotNode("remind.allow", text: t.t("set.wxAlertAllow"))
            } else if denied {
                Button { openSystemSettings() } label: { Text(t.t("set.remindSettings")) }
                    .buttonStyle(DataButtonStyle())
            }
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }
}
