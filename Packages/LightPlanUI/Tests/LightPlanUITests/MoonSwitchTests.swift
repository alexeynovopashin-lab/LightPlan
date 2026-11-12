import CoreGraphics
import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
import LightPlanData
@testable import LightPlanUI

/// 30г.6: переключатель «Луна» (`docs/30g2_modes_table.md` № 54, 65, 73, 92, 94, 102 (стрелка к луне), 103 (кнопка «Слои»),
/// 104, 145, 147, 165, 203 и § 2 «Луна»). Луна видна только в «Астро» с «Луной»; в «Просто», «Про» и в «Астро» без «Луны» её
/// нет нигде. Данные не меняются: пожелание «Луна» в съёмке, слой «Луна» карты и флаг слоя AR остаются, их только не показывают,
/// и в «Астро» с «Луной» всё снова видно. Под `swift test` словарь отдаёт ключи — сравнения через `lexicon.t` верны и там.
@MainActor
struct MoonSwitchTests {

    // MARK: - Подставные источники

    /// Небо суток одно на все часы: дождь (код 61, облачность 95) или ясно — как в `CardLightTests`.
    private struct SkySource: WeatherSource {
        let rain: Bool
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            var time: [String] = []
            let d0 = CivilDate(year: 2026, month: 9, day: 15)
            for k in 0..<21 {
                let d = d0.adding(days: k)
                for h in 0..<24 { time.append(String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, h)) }
            }
            let n = time.count
            return HourlyWeather(time: time, cloud: Array(repeating: rain ? 95 : 5, count: n),
                                 temperature: Array(repeating: 12, count: n), windSpeed: Array(repeating: 2, count: n),
                                 precipitation: Array(repeating: rain ? 3 : 0, count: n),
                                 weatherCode: Array(repeating: rain ? 61 : 0, count: n))
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
    private final class Disk: DraftStoring, @unchecked Sendable {
        var data: Data?
        func load() -> Data? { data }
        func save(_ data: Data?) { self.data = data }
    }

    /// Четыре положения, которые проверяет каждое место: «Просто», «Про», «Астро», «Астро» без «Луны».
    enum Look: CaseIterable, CustomStringConvertible {
        case simple, pro, astro, astroNoMoon
        var sees: Bool { self == .astro }
        /// «Астро» — значит, остальные переключатели (с 30г.7 «Звёзды» и «Млечный Путь») включены.
        var astroMode: Bool { self == .astro || self == .astroNoMoon }
        var description: String { "\(self == .simple ? "Просто" : self == .pro ? "Про" : self == .astro ? "Астро" : "Астро без Луны")" }
        func apply(_ s: inout AppSettings) {
            switch self {
            case .simple: s.mode = .simple; s.astro[.moon] = true
            case .pro: s.mode = .pro; s.astro[.moon] = true
            case .astro: s.mode = .astro; s.astro[.moon] = true
            case .astroNoMoon: s.mode = .astro; s.astro[.moon] = false
            }
        }
    }

    /// Москва, «сейчас» — 20.09 12:00; съёмка 21.09 18:00–20:00 с местом.
    private static func shoot(_ id: String, wishes: [Wish]) -> Session {
        var s = Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 9, day: 21),
                        start: 1080, end: 1200, duration: 120, genre: .portrait)
        s.wishes = wishes
        s.latitude = 55.75; s.longitude = 37.62
        return s
    }

    private func model(_ sessions: [Session] = [], rain: Bool = false, look: Look = .astro,
                       at iso: String = "2026-09-20T12:00:00+03:00") -> AppModel {
        var snap = Snapshot()
        snap.sessions = sessions
        let now = ISO8601DateFormatter().date(from: iso)!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: SkySource(rain: rain), now: { now })
        app.draftStore = Disk()
        app.update { look.apply(&$0) }
        return app
    }

    private func open(_ app: AppModel, _ id: String) async -> Session {
        app.openCard(id: id)
        await app.pointWeather.settled()
        return app.sessions.first { $0.id == id }!
    }

    // MARK: - Небо на нажатии «Астро»

    /// 30г.10 (DECISIONS 07.11): в небе, которое идёт 2,4 с по нажатию «Астро» (опись № 3), луна стоит только с «Луной».
    /// Само небо включают «Звёзды», поэтому «Астро» без «Луны» — это созвездия без луны; созвездия при этом те же.
    /// Час берётся тот, где луна над горизонтом: иначе её нет в сцене и без правила, и тест ничего бы не доказал.
    @Test func astroButtonSkyShowsTheMoonOnlyWithTheSwitch() throws {
        let hours = (0..<24).map { String(format: "2026-09-20T%02d:00:00+03:00", $0) }
        let up = try #require(hours.first { model(look: .astro, at: $0).astroSkyScene().moon != nil },
                              "за сутки луна ни разу не над горизонтом — тесту не на чем стоять")
        let with = model(look: .astro, at: up).astroSkyScene()
        let without = model(look: .astroNoMoon, at: up).astroSkyScene()
        #expect(with.moon != nil)
        #expect(without.moon == nil, "«Астро» без «Луны»: луны в небе на кнопке быть не должно")
        #expect(without.constellations == with.constellations && without.stars.count == with.stars.count
                && without.lines.count == with.lines.count, "созвездия от «Луны» не зависят")
        for look in [Look.simple, .pro] {
            #expect(model(look: look, at: up).astroSkyScene().moon == nil, "\(look)")
        }
    }

    // MARK: - Правило и настройки

    /// Переключатель больше не приглушён; правило одно — `sees(.moon)`, его копия на экране «Света» — `light.moon`.
    @Test func ruleReachesTheScreensInEveryLook() {
        #expect(AstroSwitchRows.working.contains(.moon))
        let app = model()
        for look in Look.allCases {
            app.update { look.apply(&$0) }
            #expect(app.settings.sees(.moon) == look.sees, "\(look)")
            #expect(app.light.moon == look.sees, "\(look)")
            #expect(app.seesMoon == look.sees, "\(look)")
        }
    }

    // MARK: - «Свет»: купол, лента, «Подробно» (№ 54, 65, § 2 лента)

    /// Луна на куполе — только в «Астро» с «Луной»; выбор кнопки помнится и возвращается вместе с переключателем.
    /// `timebar.showMoon` читают купол, «Подробно» и знаки фазы на ленте (`RibbonView`).
    @Test func domeMoonModeOnlyWithTheSwitchAndRemembered() throws {
        let app = model()
        app.light.moonMode = true
        #expect(app.light.timebar.showMoon)
        #expect(app.light.telemetry.proGroups.first?.title == app.lexicon.t("pro.moonNow"))
        #expect(app.light.telemetry.readout == nil)
        for look in [Look.simple, .pro, .astroNoMoon] {
            app.update { look.apply(&$0) }
            #expect(!app.light.moonMode && !app.light.timebar.showMoon, "\(look)")
            #expect(!app.light.telemetry.proGroups.contains { $0.title == app.lexicon.t("pro.moonNow") }, "\(look)")
            #expect(app.light.telemetry.readout != nil, "\(look)")
            // Кнопки на куполе нет, но если бы её нажали — луна всё равно не появится.
            app.light.moonMode = true
            #expect(!app.light.timebar.showMoon, "\(look)")
        }
        app.update { Look.astro.apply(&$0) }
        #expect(app.light.moonMode && app.light.timebar.showMoon)
        app.light.moonMode = false
        app.update { Look.pro.apply(&$0) }
        app.update { Look.astro.apply(&$0) }
        #expect(!app.light.moonMode)
    }

    // MARK: - «Карта»: слой, свод, затмения (№ 73, 92, 94)

    /// Слой «Луна»: рисуется и стоит в меню только в «Астро» с «Луной»; включённый в файле слой не выключается.
    @Test func mapMoonLayerOnlyWithTheSwitchAndStaysInTheFile() {
        let app = model()
        #expect(app.mapLayers.moon)
        for look in Look.allCases {
            app.update { look.apply(&$0) }
            #expect(app.mapLayersShown.moon == look.sees, "\(look)")
            #expect(app.mapLayerKeys.contains(.moon) == look.sees, "\(look)")
            // Без «Астро» уходит и «Млечный Путь» (30г.7): 3 пункта; в «Астро» без «Луны» — 4.
            #expect(app.mapLayerKeys.count == (look.sees ? 5 : look.astroMode ? 4 : 3), "\(look)")
            #expect(app.mapLayers.moon, "\(look): слой в файле выключился")
            #expect(app.snapshot.mapLayers?["moon"] != false, "\(look)")
            // Остальные слои — как в меню; «Млечный Путь» — со своим переключателем (30г.7; первый вход в «Астро» его
            // включил, 30г.7а).
            #expect(app.mapLayersShown.sun == app.mapLayers.sun
                    && app.mapLayersShown.mw == (app.mapLayers.mw && look.astroMode), "\(look)")
        }
    }

    /// Прибор по слоям, которые видны: без «Луны» ни пути, ни точки луны (её тап и чип ползунка тоже молчат).
    @Test func mapInstrumentDrawsTheMoonOnlyWhenShown() {
        let app = model()
        let date = CivilDate(year: 2026, month: 9, day: 23)
        let place = Place(latitude: 53.3481, longitude: 83.7798, zone: ZoneID(fixedOffsetHours: 7))
        let sun = SolarDay(date: date, place: place)
        // Луна над горизонтом: ищем минуту суток, где её точка есть с «Луной».
        func scene(_ minute: Minutes) -> MapInstrument.Scene {
            let input = MapInstrument.Input(date: date, minute: minute, solar: sun, place: place, layers: app.mapLayersShown,
                                            pro: true, azimuths: true, lightTheme: false, chip: .drag,
                                            clock: { "\($0)" }, cardinals: ["С", "В", "Ю", "З"])
            return MapInstrument.scene(input, day: MapInstrument.Day(date: date, place: place, solar: sun))
        }
        let minute = stride(from: 0.0, to: 1440, by: 30).first { scene($0).marks.moon != nil }
        #expect(minute != nil)
        guard let minute else { return }
        for look in Look.allCases {
            app.update { look.apply(&$0) }
            let s = scene(minute)
            #expect((s.marks.moon != nil) == look.sees, "\(look)")
            #expect((s.moonAt != nil) == look.sees, "\(look)")
        }
    }

    /// Решение Алексея 11.11 (30г.10): луна в строках Млечного Пути — причина, по которой он виден или нет, а не светило.
    /// Поэтому «Луна для звёзд: засветит · диск N %» в своде «Карты» и «Луна сейчас» в группе «Млечный Путь» остаются и
    /// при выключенной «Луне» (Барнаул, 23.09.2026 23:00: диск 91 %, строка есть). Своя строка луны при этом уходит.
    @Test func milkyWayMoonLinesStayWithoutTheMoonSwitch() throws {
        let lexicon = Lexicon("ru"), clock = ClockText(language: "ru", preference: .h24)
        let date = CivilDate(year: 2026, month: 9, day: 23)
        let place = Place(latitude: 53.3481, longitude: 83.7798, zone: ZoneID(fixedOffsetHours: 7))
        let sun = SolarDay(date: date, place: place)
        func build(_ moon: Bool) -> MapSummary {
            MapSummary.build(date: date, t: 1380, sun: sun, place: place, utcOffset: 7, pro: true, moon: moon, glow: nil,
                             mw: MapSummary.MilkyWayInput(window: MilkyWayWindow(date: date, place: place),
                                                          moon: MoonVsStars(date: date, place: place), sky: nil, nextDark: { nil }),
                             dateShort: { "\($0.day).\($0.month)" }, lexicon: lexicon, clock: clock)
        }
        let on = build(true), off = build(false)
        let glare = try #require(on.rows.first { $0.label == "map.moonGlare" }, "в эту ночь строки о луне для звёзд нет — тесту не на чем стоять")
        #expect(off.rows.first { $0.label == "map.moonGlare" }?.text == glare.text, "без «Луны» строка «Луна для звёзд» пропала")
        #expect(!off.rows.contains { $0.label == "map.moon" }, "своя строка луны без «Луны» осталась")
        let group = { (s: MapSummary) in s.pro.first { $0.title == lexicon.t("mpro.mw") }?.rows.map(\.label) }
        let rows = try #require(group(on))
        #expect(rows.contains(lexicon.t("mpro.moonNow")))
        #expect(group(off) == rows, "группа «Млечный Путь» в «Подробно» от «Луны» зависеть не должна")
    }

    /// Свод: строки «Луна» и «Затмение», группа «Ближайшее затмение» в «Подробно» — только с «Луной». Прочее не меняется.
    @Test func mapSummaryHidesMoonAndEclipses() throws {
        let lexicon = Lexicon("ru"), clock = ClockText(language: "ru", preference: .h24)
        let place = Place(latitude: 53.3481, longitude: 83.7798, zone: ZoneID(fixedOffsetHours: 7))
        // День затмения из таблицы — чтобы строка «Затмение» в своде была.
        let ecl = try #require(EclipseTable.all.first { $0.date.ordinal >= CivilDate(year: 2026, month: 1, day: 1).ordinal })
        let date = ecl.date
        let sun = SolarDay(date: date, place: place)
        func build(_ moon: Bool) -> MapSummary {
            MapSummary.build(date: date, t: 720, sun: sun, place: place, utcOffset: 7, pro: true, moon: moon, glow: nil, mw: nil,
                             dateShort: { "\($0.day).\($0.month)" }, lexicon: lexicon, clock: clock)
        }
        let on = build(true), off = build(false)
        #expect(on.rows.contains { $0.label == "map.moon" } && on.rows.contains { $0.label == "map.eclipse" })
        #expect(off.rows.map(\.label) == on.rows.map(\.label).filter { $0 != "map.moon" && $0 != "map.eclipse" })
        #expect(on.pro.last?.title == lexicon.t("mpro.nextEcl"))
        #expect(off.pro.map(\.title) == on.pro.map(\.title).filter { $0 != lexicon.t("mpro.nextEcl") })
    }

    // MARK: - AR: слой, стрелка, кнопка «Слои» (№ 102, 103, 104)

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }
    private func ar(_ defaults: UserDefaults, allowed: Set<SunARSkyLayer>) -> SunARModel {
        SunARModel(target: SunARTarget(place: tomsk, moment: Moment(ISO8601DateFormatter().date(from: "2026-10-20T14:00:00Z")!)),
                   source: nil, camera: nil, calibrationFlag: MemoryFlag(), bodies: DeviceBodiesSettings(defaults: defaults),
                   allowed: allowed)
    }

    /// Слои AR, которые разрешает приложение: луна — по «Луне», остальные — по «Звёздам» и «Млечному Пути» (30г.7).
    @Test func arLayersFollowTheSwitch() {
        let app = model()
        for look in Look.allCases {
            app.update { look.apply(&$0) }
            #expect(app.arSkyLayers.contains(.moon) == look.sees, "\(look)")
            #expect(app.arSkyLayers.isSuperset(of: [.milkyWay, .stars, .constellations, .planets]) == look.astroMode, "\(look)")
        }
    }

    /// Без «Луны» включённый слой луны не рисуется: ни диска, ни дуги, ни стрелки за краем кадра (её строит `night.picked`);
    /// строки в «Слоях» и точки на кнопке нет. Флаг устройства не трогается — с «Луной» луна снова на месте.
    @Test func arMoonLayerHiddenButItsFlagKept() {
        let defaults = UserDefaults(suiteName: "moon-switch-\(UUID().uuidString)")!
        let all = Set(SunARSkyLayer.allCases)
        let first = ar(defaults, allowed: all)
        first.set(.moon, on: true)
        let viewport = ScreenViewport(width: 393, height: 852), basis = CameraBasis(azimuth: 183, altitude: 18)
        #expect(first.moonShown && first.layersOn == [.moon])
        #expect(first.nightScene(basis: basis, optics: .typical, viewport: viewport).picked != nil)

        let hidden = ar(defaults, allowed: all.subtracting([.moon]))
        #expect(hidden.moonOn && !hidden.moonShown)
        #expect(hidden.layersOn.isEmpty)
        #expect(!hidden.layersListed.contains(.moon) && hidden.layersListed.count == 4)
        let night = hidden.nightScene(basis: basis, optics: .typical, viewport: viewport)
        #expect(night.picked == nil && night.now == nil)
        #expect(defaults.bool(forKey: "lightplan.native.sunar.moon"), "флаг слоя выключился")

        let back = ar(defaults, allowed: all)
        #expect(back.moonShown && back.layersOn == [.moon])
    }

    /// Кнопка «Слои» — пока разрешён хотя бы один её слой; без единого её нет.
    @Test func arLayersButtonOnlyWithSomeLayerAllowed() {
        let defaults = UserDefaults(suiteName: "moon-switch-\(UUID().uuidString)")!
        #expect(ar(defaults, allowed: Set(SunARSkyLayer.allCases)).layersButtonShown)
        #expect(ar(defaults, allowed: [.moon]).layersButtonShown)
        #expect(!ar(defaults, allowed: []).layersButtonShown)
        // С 30г.7 в «Просто» и «Про» кнопки нет; в «Астро» без «Луны» она есть — остались звёзды и Млечный Путь.
        let app = model()
        for look in Look.allCases {
            app.update { look.apply(&$0) }
            #expect(ar(defaults, allowed: app.arSkyLayers).layersButtonShown == look.astroMode, "\(look)")
        }
    }

    // MARK: - Карточка: строки луны, «Ожидалась луна» (№ 145, 147)

    /// Строка луны в блоке «Свет» — только с «Луной»; пожелание в записи остаётся и с «Луной» строка возвращается.
    @Test func cardMoonLineOnlyWithTheSwitch() async {
        let app = model([Self.shoot("a", wishes: [.moon])])
        let s = await open(app, "a")
        for look in Look.allCases {
            app.update { look.apply(&$0) }
            #expect(app.cardSays(s, phase: .before).contains { $0.kind == .moon } == look.sees, "\(look)")
            #expect((app.cardMoon(s, phase: .before) != nil) == look.sees, "\(look)")
            #expect(app.sessions.first { $0.id == "a" }?.wishes == [.moon], "\(look): пожелание пропало")
            #expect(app.snapshot.sessions.first { $0.id == "a" }?.wishes == [.moon], "\(look)")
        }
    }

    /// «Ожидалась луна. Прогноз … — дождь» — только с «Луной»; закат рядом с ней говорится всегда.
    @Test func cardWishMissedSaysMoonOnlyWithTheSwitch() async {
        let app = model([Self.shoot("m", wishes: [.moon]), Self.shoot("ms", wishes: [.moon, .sunset])], rain: true)
        let m = await open(app, "m")
        let ms = await open(app, "ms")
        app.update { Look.astro.apply(&$0) }
        let moonOnly = app.cardWishMissed(m, phase: .before)
        let both = app.cardWishMissed(ms, phase: .before)
        #expect(moonOnly != nil && both != nil && both != moonOnly)
        for look in [Look.simple, .pro, .astroNoMoon] {
            app.update { look.apply(&$0) }
            #expect(app.cardWishMissed(m, phase: .before) == nil, "\(look)")
            let sunset = app.cardWishMissed(Self.shoot("s", wishes: [.sunset]), phase: .before)
            #expect(sunset != nil && app.cardWishMissed(ms, phase: .before) == sunset, "\(look)")
        }
        app.update { Look.astro.apply(&$0) }
        #expect(app.cardWishMissed(m, phase: .before) == moonOnly)
    }

    // MARK: - Форма: плитка «Луна», «замысел против прогноза» (№ 165, 203)

    /// Новолуние 09.11.2026: с пожеланием «Луна» плашка говорит «новолуние».
    private let newMoon = CivilDate(year: 2026, month: 11, day: 9)

    /// Плиток девять только с «Луной»; без неё восемь, «Луны» среди них нет, порядок остальных тот же.
    @Test func formWishTilesEightWithoutTheMoon() {
        let app = model()
        for look in Look.allCases {
            app.update { look.apply(&$0) }
            // Вне «Астро» уходят и «Звёзды» (30г.7): семь.
            #expect(app.wishTiles.count == (look.sees ? 9 : look.astroMode ? 8 : 7), "\(look)")
            #expect(app.wishTiles.contains(.moon) == look.sees, "\(look)")
            #expect(app.wishTiles == Wish.allCases.filter { ($0 != .moon || look.sees) && ($0 != .stars || look.astroMode) },
                    "\(look)")
        }
    }

    /// Плашка «замысел против прогноза» о луне молчит без «Луны», а сама «Луна» остаётся в форме.
    @Test func formWishWarningSilentAboutHiddenMoon() throws {
        let app = model()
        app.openForm(day: newMoon)
        app.toggleFormWish(.moon)
        let form = try #require(app.form)
        let warn = try #require(app.formWishWarning(form))
        #expect(warn.title == app.lexicon.t("wc.newMoonT"))
        for look in [Look.simple, .pro, .astroNoMoon] {
            app.update { look.apply(&$0) }
            #expect(app.formWishWarning(form) == nil, "\(look)")
            #expect(app.form?.wishes == [.moon], "\(look)")
        }
        app.update { Look.astro.apply(&$0) }
        #expect(app.formWishWarning(form) == warn)
    }

    /// Сохранённая съёмка с «Луной», правка в «Про»: «Неважно» горит (видимых пожеланий нет) и стирает только видимые;
    /// после «Сохранить» пожелание «Луна» в файле, а в «Астро» с «Луной» плитка снова горит.
    @Test func hiddenMoonWishSurvivesAnEditInPro() throws {
        let app = model([Self.shoot("a", wishes: [.moon])], look: .pro)
        app.openForm(editing: "a")
        #expect(app.form?.wishes == [.moon])
        let shown = app.shownWishes(app.form?.wishes ?? [])
        #expect(shown.isEmpty)
        app.toggleFormWish(.sunset)
        #expect(app.form?.wishes == [.moon, .sunset])
        app.toggleFormWish(.any)
        #expect(app.form?.wishes == [.moon], "«Неважно» стёрло скрытую «Луну»")
        _ = try #require(app.saveForm())
        #expect(app.sessions.first { $0.id == "a" }?.wishes == [.moon])
        #expect(app.snapshot.sessions.first { $0.id == "a" }?.wishes == [.moon])
        app.update { Look.astro.apply(&$0) }
        app.openForm(editing: "a")
        #expect(app.form?.wishOn(.moon) == true)
        #expect(app.wishTiles.contains(.moon))
        // С «Луной» «Неважно» стирает и её — как всегда.
        app.toggleFormWish(.any)
        #expect(app.form?.wishes == [])
    }
}

// MARK: - «Луна» в форме по времени съёмки (30г.12, вариант А)

extension MoonSwitchTests {
    /// Съёмка в Петербурге: оценка пояса по долготе там даёт настоящие +3, ответ не зависит от сети.
    private static func spb(_ id: String, _ day: CivilDate, start: Int) -> Session {
        var s = Session(id: id, kind: .shoot, day: day, start: start, end: start + 60, duration: 60, genre: .portrait)
        s.wishes = [.moon]
        s.latitude = 59.9343; s.longitude = 30.3351
        return s
    }

    private func formWarning(_ s: Session, at iso: String) throws -> (AppModel, WishWarning?) {
        let app = model([s], at: iso)
        app.openForm(editing: s.id)
        let f = try #require(app.form)
        return (app, app.formWishWarning(f))
    }

    /// Белая ночь, полнолуние 18.06.2027, съёмка 21:00–22:00: луна взойдёт только в 23:12 (`MoonDay`, 30г.12). Раньше форма
    /// молчала (фаза 100 % в 22:00), теперь говорит словами строки карточки, и слова те же, что у карточки.
    @Test func formSaysTheMoonIsNotUpDuringTheShoot() throws {
        let s = Self.spb("w", CivilDate(year: 2027, month: 6, day: 18), start: 1260)
        let (app, warn) = try formWarning(s, at: "2027-06-10T12:00:00+03:00")
        let w = try #require(warn, "луна под горизонтом всю съёмку — плашка должна быть")
        #expect(w.title == app.lexicon.t("wc.moonAwayT"))
        let card = try #require(app.moonAnswer(app.sessions.first { $0.id == "w" }!))
        guard case .moonNear(_, let arc, _) = card else { Issue.record("ждали moonNear, а не \(card)"); return }
        #expect(arc.lowerBound == 23 * 60 + 12, "восход 23:12, как в 30g12_moon_white_night.md")
        #expect(w.message == app.moonWords(card), "форма говорит словами строки карточки")
        for look in [Look.simple, .pro, .astroNoMoon] {
            app.update { look.apply(&$0) }
            #expect(app.formWishWarning(try #require(app.form)) == nil, "\(look): без «Луны» плашка о ней молчит")
        }
    }

    /// Молодой месяц 13.11.2026 (18 % в 22:00): в 16:40 — сумерки, месяц на небе (14:14–18:09) — плашки нет; в 17:45 —
    /// ночь (солнце ниже −6° с 17:22), месяц ещё на небе — «почти новая — света не даст», как прежде.
    @Test func thinCrescentIsASubjectByDayAndAWarningAtNight() throws {
        let day = CivilDate(year: 2026, month: 11, day: 13)
        let (_, dusk) = try formWarning(Self.spb("d", day, start: 16 * 60 + 40), at: "2026-11-12T12:00:00+03:00")
        #expect(dusk == nil, "месяц в сумерках — объект съёмки")
        let (app, night) = try formWarning(Self.spb("n", day, start: 17 * 60 + 45), at: "2026-11-12T12:00:00+03:00")
        let w = try #require(night)
        #expect(w.title == app.lexicon.t("wc.newMoonT"))
        #expect(w.message.contains("18%") || w.message.contains("17%"), "процент — в минуту съёмки: \(w.message)")
    }
}
