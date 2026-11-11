import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// 30г.8: настройки в «Просто» — один лист без глав (ответ 5 Алексея 05.11, рисунок `docs/30g2_prostoe_sketch.png`). Состав —
/// колонка «Просто» раздела А описи `docs/30g2_modes_table.md` (ветка `wt/30g-2-modes-recalc`), строки № 1–44. «Про» и
/// «Астро» — главы, как были. Значения от режима не зависят (ответ 2): лист и главы читают и пишут одни и те же поля.
@MainActor
struct SimpleSettingsSheetTests {

    // MARK: - Опись

    /// Колонка «Просто», строки № 1–44: «есть» или «следует за №…» (№ 16 идёт за № 15, его тумблер на листе).
    static let simpleRows: Set<Int> = [1, 2, 4, 7, 10, 15, 16, 20, 24, 29, 36, 37, 39, 40, 41, 42, 43, 44]
    /// Колонка «Просто»: «нет, фиксировано» (№ 3 — небо на «Астро», его держат `StarsMilkyWaySwitchTests`).
    static let hiddenRows: Set<Int> = [3, 5, 6, 8, 9, 11, 12, 13, 14, 17, 18, 19, 21, 22, 23, 25, 26, 27, 28,
                                       30, 31, 32, 33, 34, 35, 38]

    @Test func inventoryRowsOneToFortyFourAreAllAccountedFor() {
        #expect(Self.simpleRows.isDisjoint(with: Self.hiddenRows))
        #expect(Self.simpleRows.union(Self.hiddenRows) == Set(1...44))
    }

    @Test func theSheetHoldsExactlyTheSimpleColumn() {
        let rows = SimpleSheet.items.flatMap(\.inventoryRows)
        #expect(rows.count == Set(rows).count, "строка описи стоит в одном пункте листа")
        #expect(Set(rows).union(SimpleSheet.aboveRows) == Self.simpleRows)
        #expect(Set(rows).isDisjoint(with: Self.hiddenRows), "чего в колонке «Просто» нет, на листе нет")
        #expect(SimpleSheet.items.count == Set(SimpleSheet.items).count)
        #expect(Set(SimpleSheet.items) == Set(SimpleSheet.Item.allCases), "каждый пункт стоит на листе")
    }

    @Test func theSheetFollowsTheSketchSixSettingsInPlaceThenFiveRows() {
        #expect(SimpleSheet.items == [.city, .theme, .remind, .calendar, .units, .currency,
                                      .clients, .contacts, .playlists, .bin, .about])
        #expect(SimpleSheet.items.map(\.opensScreen) == Array(repeating: false, count: 6) + Array(repeating: true, count: 5))
    }

    @Test func modeChoiceStandsAboveTheSheetInEveryMode() {
        // № 1 (выбор режима) и № 2 (пояснение) — над листом и над главами, не пункты листа.
        #expect(SimpleSheet.aboveRows == [1, 2])
        #expect(!SimpleSheet.items.flatMap(\.inventoryRows).contains(1))
        #expect(!SimpleSheet.items.flatMap(\.inventoryRows).contains(2))
    }

    @Test func calendarOnTheSheetIsTheMirrorWithoutOtherCalendars() {
        // № 15–16 на листе, № 17–18 («Другие календари», галочки) — нет; в главе — всё, как было.
        #expect(SimpleSheet.Item.calendar.inventoryRows == [15, 16])
        #expect(SimpleSheet.calendarLook == .sheet)
        #expect(!SimpleSheet.calendarLook.ghosts)
        #expect(CalendarMirrorSection.Look.chapter.ghosts && CalendarMirrorSection.Look.chapter.label
                && CalendarMirrorSection.Look.chapter.plainNote)
    }

    @Test func playlistsAndAboutOpenTheirChapters() {
        #expect(SimpleSheet.chapter(of: .playlists) == .playlists)
        #expect(SimpleSheet.chapter(of: .about) == .about)
        for item in SimpleSheet.items where item != .playlists && item != .about {
            #expect(SimpleSheet.chapter(of: item) == nil, "\(item)")
        }
    }

    // MARK: - Режимы

    @Test func simpleIsOneSheetProAndAstroKeepTheirChapters() {
        #expect(SettingsView.root(.simple) == .sheet)
        #expect(SettingsView.root(.pro) == .chapters(astroSwitches: false))
        #expect(SettingsView.root(.astro) == .chapters(astroSwitches: true))
        // Главы «Про» и «Астро» — те же 13, в том же порядке, что до 30г.8.
        #expect(SettingsView.Chapter.allCases.map(\.rawValue) == ["profile", "view", "shoots", "calendar", "clients", "alerts",
                                                                  "places", "store", "data", "network", "locale", "playlists", "about"])
    }

    @Test func theLastRowScrollsAboveTheTabBar() {
        // Замер 30г.8: прокрутка корня кончалась у полосы «домой» (34), панель вкладок 84 закрывала последние 50 pt —
        // «О приложении» листа «Просто» и глав «Астро». Запас — ровно эти 50; дошла бы панель до прокрутки — 0.
        #expect(SettingsView.tabBarReserve(bottomSafe: 34) == 50)
        #expect(SettingsView.tabBarReserve(bottomSafe: 0) == TabBarView.height)
        #expect(SettingsView.tabBarReserve(bottomSafe: TabBarView.height) == 0)
        #expect(SettingsView.tabBarReserve(bottomSafe: 120) == 0)
    }

    // MARK: - Значения не зависят от режима (ответ 2)

    private struct DryWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func model(mode: AppMode) -> AppModel {
        let now = ISO8601DateFormatter().date(from: "2026-11-07T10:00:00+07:00")!
        let app = AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: DryWeather(), now: { now })
        app.update { $0.mode = mode }
        return app
    }

    @Test func aValueChangedInProShowsOnTheSimpleSheet() {
        let app = model(mode: .pro)
        app.update {
            $0.theme = .light; $0.tempUnit = .f; $0.currency = .usd
            $0.home = HomeCity(name: "Томск")
        }
        app.setRemindMinutes(30)
        app.update { $0.mode = .simple }
        #expect(SettingsView.root(app.settings.mode) == .sheet)
        #expect(SimpleSheet.state(.theme, app: app) == "light")
        #expect(SimpleSheet.state(.units, app: app) == "f")
        #expect(SimpleSheet.state(.currency, app: app) == "USD")
        #expect(SimpleSheet.state(.city, app: app) == "Томск")
        #expect(SimpleSheet.state(.remind, app: app) == "30")
        // Сегменты листа стоят на тех же значениях.
        #expect(SimpleSheet.binding(app, \.theme).wrappedValue == .light)
        #expect(SimpleSheet.binding(app, \.tempUnit).wrappedValue == .f)
        #expect(SimpleSheet.binding(app, \.currency).wrappedValue == .usd)
        #expect(SimpleSheet.remind(app).wrappedValue == 30)
    }

    @Test func aValueChangedOnTheSimpleSheetShowsInPro() {
        let app = model(mode: .simple)
        SimpleSheet.binding(app, \.theme).wrappedValue = .auto
        SimpleSheet.binding(app, \.tempUnit).wrappedValue = .f
        SimpleSheet.binding(app, \.currency).wrappedValue = .eur
        SimpleSheet.binding(app, \.home).wrappedValue = HomeCity(name: "Барнаул")
        SimpleSheet.remind(app).wrappedValue = 60
        app.update { $0.mode = .pro }
        let t = app.lexicon
        #expect(SettingsView.value(of: .view, app: app) == t.t("set.themeAuto"))
        #expect(SettingsView.value(of: .profile, app: app) == "Барнаул")
        #expect(SettingsView.value(of: .locale, app: app).hasSuffix(NumberText(language: "ru").currencySign("EUR")))
        #expect(app.settings.tempUnit == .f)
        #expect(app.remindMinutes == 60)
        // И обратно на лист: ничего не сдвинулось.
        app.update { $0.mode = .simple }
        #expect(SimpleSheet.state(.theme, app: app) == "auto")
        #expect(SimpleSheet.state(.remind, app: app) == "60")
    }

    @Test func hiddenSettingsKeepWorkingInSimpleAndSwitchingModesMovesNothing() {
        // Ответ 2: часы 12, неделя с воскресенья, шаг 10 минут из «Про» действуют и в «Просто»; смена режима ничего не сдвигает.
        let app = model(mode: .pro)
        app.update {
            $0.clock = .h12; $0.weekStart = .sun; $0.timeStep = 10; $0.travelMin = 90; $0.manualEnd = true
            $0.ribbonMode = .lane; $0.drumSlot = .window; $0.practice = .us; $0.practicePicked = true; $0.musicApp = .spotify
        }
        app.setRemindMinutes(5)
        var before = app.settings
        for mode in [AppMode.simple, .astro, .pro, .simple, .astro, .simple] {
            app.update { $0.mode = mode }
            var now = app.settings
            now.mode = before.mode
            now.astro = before.astro
            #expect(now == before, "\(mode)")
            #expect(app.remindMinutes == 5, "\(mode)")
            before = app.settings
        }
        #expect(app.settings.mode == .simple && app.weekStart == .sunday)
    }

    @Test func rowsOnTheSheetShowTheSameStateAsTheChapters() {
        let app = model(mode: .simple)
        let t = app.lexicon
        #expect(SimpleSheet.state(.clients, app: app) == app.clientsValue)
        #expect(SimpleSheet.state(.contacts, app: app) == app.contactsValue)
        #expect(SimpleSheet.state(.playlists, app: app) == SettingsView.value(of: .playlists, app: app))
        #expect(SimpleSheet.state(.playlists, app: app) == t.t("set.musicOff"))
        #expect(SimpleSheet.state(.bin, app: app) == t.t("bin.emptyShort"))
        app.update { $0.musicApp = .yandex }
        #expect(SimpleSheet.state(.playlists, app: app) == SettingsView.value(of: .playlists, app: app))
        #expect(SimpleSheet.state(.playlists, app: app) != t.t("set.musicOff"))
    }

    @Test func calendarMirrorTurnedOnOnTheSheetStaysOnInPro() async {
        let store = InMemoryCalendarStore(authorization: .notDetermined)
        let app = model(mode: .simple)
        app.attachCalendar(store: store, memory: InMemoryCalendarMemory())
        await app.calendarChain?.value
        #expect(SimpleSheet.state(.calendar, app: app) == "off")
        app.setCalendarMirror(true)
        await app.calendarChain?.value
        #expect(SimpleSheet.state(.calendar, app: app) == "on")
        app.update { $0.mode = .pro }
        #expect(app.calendarMirrorOn)
        app.update { $0.mode = .simple }
        #expect(SimpleSheet.state(.calendar, app: app) == "on")
    }
}
