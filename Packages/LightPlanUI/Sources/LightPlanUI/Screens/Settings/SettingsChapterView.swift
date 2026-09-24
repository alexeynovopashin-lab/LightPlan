import SwiftUI
import LightPlanData
import LightPlanDomain
import LightPlanMapCanvas
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
        ChapterPage(title: t.t(chapter.titleKey)) {
            switch chapter {
            case .profile: profile
            case .view: view
            case .shoots: shoots
            case .alerts: foreign("set.feedback"); foreign("set.notify")
            case .places: places
            case .store: foreign("set.moodboards"); foreign("set.orgsDocs"); foreign("card.bin")
            case .data: foreign("set.data"); foreign("set.icsImport"); foreign("cloud.title")
            case .locale: locale
            case .about: about
            }
        }
    }

    // MARK: - Профиль

    @ViewBuilder private var profile: some View {
        SecLabel(text: t.t("set.myCity"), first: true)
        CitySearchField(app: app, style: .web)
        SetNote(text: t.t("set.myCityNote"))
        // Номер, ID приложения и контакты — профиль для Event OS; ни одна
        // итерация плана их пока не назначает (записано в DECISIONS).
        foreign("set.myPhone")
        foreign("set.appId")
        foreign("set.contacts")
    }

    // MARK: - Вид

    /// Порядок и узлы — как `#setOvView` веба: лента суток, прорезь с
    /// образцом барабана, тема.
    @ViewBuilder private var view: some View {
        // Лента суток и прорезь — только в астро: в «Просто» самой ленты нет,
        // выбор вида был бы настройкой без предмета (`renderRibbonSeg`).
        let slotShown = s.pro && s.ribbonMode == .drum && colorScheme == .light
        if s.pro {
            segment("set.ribbon", \.ribbonMode, [(.drum, "set.ribbonDrum"), (.lane, "set.ribbonLane")],
                    note: t.t(s.ribbonMode == .drum ? "set.ribbonNoteDrum" : "set.ribbonNoteLane"), first: true, index: 0)
        }
        // Прорезь видна только у барабана и только в светлой теме: в тёмной
        // три вида сходятся в один (`renderDrumSlotSeg`).
        if slotShown {
            segment("set.drumSlot", \.drumSlot,
                    [(.paper, "set.drumPaper"), (.graphite, "set.drumGraphite"), (.window, "set.drumWindow")],
                    note: t.t("set.drumNote" + s.drumSlot.rawValue.prefix(1).uppercased() + s.drumSlot.rawValue.dropFirst()),
                    index: 1)
            // `.drum-preview`: тот же барабан, что на «Свете», без касаний.
            RibbonView(state: app.light.timebar, preview: true)
                .environment(\.drumSlot, s.drumSlot)
                .allowsHitTesting(false)
                .shotNode("preview.0")
                .padding(.horizontal, 24)
                .padding(.top, 10)
        }
        segment("set.theme", \.theme, [(.dark, "set.themeDark"), (.light, "set.themeLight"), (.auto, "set.themeAuto")],
                // Подпись «Тема» у веба — не первая в разметке главы даже в
                // «Просто» (лента и прорезь скрыты, но стоят раньше), поле 30.
                note: t.t("set.themeNote"), index: s.pro ? (slotShown ? 2 : 1) : 0)
    }

    // MARK: - Карта и места

    /// `#setOvPlaces`: «Карта» — тумблер названий улиц с пояснением; под ним
    /// выбор холста (docs/17 § 10 — только натив, у веба холст один, и слов
    /// для строки в словаре нет: варианты названы именами поставщиков). На Mac
    /// MapLibre нет — выбирать не из чего. «Места» — счёт точек; лист точек
    /// открывается с карты.
    @ViewBuilder private var places: some View {
        let pal = Palette(colorScheme)
        SecLabel(text: t.t("nav.map"), first: true, node: "sec.0")
        HStack(spacing: 12) {
            Text(t.t("set.streetNames")).font(.system(size: 15)).foregroundStyle(pal.ink)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { app.mapLabels }, set: { app.setMapLabels($0) }))
                .labelsHidden().tint(pal.brass)
                // Переключатель iOS 26 — 28 pt, у веба `.toggle` 31: строка
                // держит высоту веба (замер пары 20б).
                .frame(height: 31)
                .shotNode("labels.toggle", text: app.mapLabels ? "on" : "off")
        }
        // `.item` веба: поля 15, переключатель 31 и волосок 1 снизу — 62.
        .padding(.horizontal, 24)
        .padding(.top, 15)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
        // Узлы по порядку, как `shot.js` нумерует главы веба: строка — `item.N`,
        // пояснение — `note.N`. У выбора холста пары нет: у веба холст один.
        .shotNode("item.0", text: t.t("set.streetNames"))
        SetNote(text: t.t("set.streetNote"), node: "note.0")
        #if os(iOS)
        WebSeg(options: [("OpenStreetMap", MapCanvasSource.mapLibre), ("Apple", .mapKit)],
               selection: Binding(get: { app.mapSource }, set: { app.setMapSource($0) }))
            .shotNode("canvas")
            .padding(.horizontal, 24).padding(.top, 16)
        #endif
        SecLabel(text: t.t("set.places"), node: "sec.1")
        SetItemRow(icon: "pin", title: t.t("loc.myPlaces"),
                   value: app.spotCount > 0 ? String(app.spotCount) : t.t("card.none"), chevron: false)
            .shotNode("item.1", text: t.t("loc.myPlaces"))
    }

    // MARK: - Съёмки

    @ViewBuilder private var shoots: some View {
        foreign("set.calendar")
        foreign("card.delivery")
        segment("set.step", \.timeStep, AppSettings.steps.map { ($0, "set.step\($0)") },
                note: s.timeStep == 30 ? t.t("set.stepNote30")
                    : t.t("set.stepNoteN", ["n": t.count("unit.min", s.timeStep)]))
        SecLabel(text: t.t("set.travel"))
        WebSeg(options: AppSettings.travelChoices.map { (String($0), $0) }, selection: binding(\.travelMin))
            .padding(.horizontal, 24).padding(.top, 12)
        SetNote(text: t.t("set.travelNote", ["n": t.count("unit.min", s.travelMin)]))
        foreign("set.music")
        foreign("set.playlists")
        foreign("set.finish")
    }

    // MARK: - Язык и регион

    /// Узлы — как `#setOvLocale`: язык (у веба — фишки, здесь строка в
    /// настройки iPhone, решение 21 сентября), часы, единицы, валюта, практика.
    @ViewBuilder private var locale: some View {
        SecLabel(text: t.t("set.language"), first: true, node: "sec.0")
        Button { openLanguageSettings() } label: {
            SetItemRow(icon: nil, title: SettingsText.languageName(app.language), value: "")
        }
        .buttonStyle(.plain)
        .shotNode("item.0")
        SetNote(text: t.t(Lexicon.has(app.language) ? "set.langNote" : "set.langStub"), node: "note.0")

        segment("set.clock", \.clock, [(.auto, "set.clockAuto"), (.h24, "set.clock24"), (.h12, "set.clock12")],
                note: t.t(s.clock == .auto ? "set.clockNoteAuto" : "set.clockNote",
                          ["sample": ClockText(language: app.language, preference: AppModel.clock(s.clock)).fmt(19 * 60 + 52)]),
                index: 1, segIndex: 0, segTop: 4)

        SecLabel(text: t.t("set.units"), node: "sec.2")
        WebSeg(options: [("°C", AppSettings.TempUnit.c), ("°F", AppSettings.TempUnit.f)], selection: binding(\.tempUnit))
            .shotNode("seg.1")
            .padding(.horizontal, 24).padding(.top, 4)
        SetNote(text: t.t(s.tempUnit == .f ? "set.unitNoteF" : "set.unitNoteC"), node: "note.2")

        let num = NumberText(language: app.language)
        SecLabel(text: t.t("set.currency"), node: "sec.3")
        Chips(options: Currency.allCases.map { (num.currencySign($0.rawValue) + " " + $0.rawValue, $0) },
              selection: binding(\.currency), node: "chips.1")
        SetNote(text: t.t("set.curNote", ["sample": num.money(14000, s.currency.rawValue)]), node: "note.3")

        SecLabel(text: t.t("set.practice"), node: "sec.4")
        Chips(options: AppSettings.Practice.allCases.map { (t.t("practice." + $0.rawValue), $0) },
              selection: Binding(get: { s.practice }, set: { p in app.update { $0.practice = p; $0.practicePicked = true } }),
              node: "chips.2")
        SetNote(text: t.t("practice.note." + s.practice.rawValue), node: "note.4")
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
        SetNote(text: t.t("set.privacy"))
        SetNote(text: t.t("set.tagline") + "\n" + t.t("set.build", ["stamp": SettingsText.buildStamp(app.language, clock: AppModel.clock(s.clock))]))
            .monospacedDigit()
    }

    // MARK: - Общие куски

    /// Подпись, сегмент и пояснение — `.sec-label` + `.seg` + `.seg-note`
    /// веба. `index` — номер подписи и пояснения в главе для пары снимков,
    /// `segIndex` — номер сегмента, если они расходятся.
    private func segment<V: Hashable>(_ titleKey: String, _ key: WritableKeyPath<AppSettings, V>,
                                      _ options: [(V, String)], note: String, first: Bool = false,
                                      index: Int? = nil, segIndex: Int? = nil, segTop: CGFloat = 12) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SecLabel(text: t.t(titleKey), first: first, node: index.map { "sec.\($0)" })
            WebSeg(options: options.map { (t.t($0.1), $0.0) }, selection: binding(key))
                .shotNode((segIndex ?? index).map { "seg.\($0)" } ?? "")
                .padding(.horizontal, 24).padding(.top, segTop)
            SetNote(text: note, node: index.map { "note.\($0)" })
        }
    }

    /// Раздел чужой итерации: имя на месте приглушённой строкой, содержимого
    /// пока нет.
    private func foreign(_ titleKey: String) -> some View {
        SetItemRow(icon: nil, title: t.t(titleKey), value: "", chevron: false, dim: true)
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
