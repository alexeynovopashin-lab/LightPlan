import CoreGraphics
import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
import LightPlanData
@testable import LightPlanUI

/// 30г.7: переключатели «Звёзды» и «Млечный Путь» (`docs/30g2_modes_table.md` § 2). «Звёзды» — № 3 (небо на «Астро»),
/// 103 (кнопка «Слои»), 106 (слои звёзд, созвездий, планет в AR), 146 (окно Млечного Пути в карточке, с ним «…ниже −18°»),
/// 147 («Ожидались звёзды»), 166 (плитка), 200 (всплывашка), звёздная часть 203; «Млечный Путь» — № 74 (слой «Карты»),
/// 96 (группа «Подробно»), 103, 105 (слой AR и «Как в тёмном месте»). Каждое место проверяется в «Просто», «Про», «Астро»
/// и в «Астро» с каждым из пяти выключенным: видно только в «Астро» со своим переключателем, чужой ничего не меняет.
/// Данные не меняются: пожелание «Звёзды», слой «Млечный Путь» карты и флаги слоёв AR остаются.
@MainActor
struct StarsMilkyWaySwitchTests {

    // MARK: - Подставные источники

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

    /// Восемь положений: три режима и «Астро» с каждым выключенным переключателем.
    struct Look: CustomStringConvertible {
        let mode: AppMode
        let off: AstroSwitch?
        static let all: [Look] = [Look(mode: .simple, off: nil), Look(mode: .pro, off: nil), Look(mode: .astro, off: nil)]
            + AstroSwitch.allCases.map { Look(mode: .astro, off: $0) }
        static let astro = Look(mode: .astro, off: nil)
        static let pro = Look(mode: .pro, off: nil)
        func sees(_ s: AstroSwitch) -> Bool { mode == .astro && off != s }
        var stars: Bool { sees(.stars) }
        var milkyWay: Bool { sees(.milkyWay) }
        var description: String { mode.rawValue + (off.map { "~" + $0.rawValue } ?? "") }
        func apply(_ s: inout AppSettings) {
            s.mode = mode
            for sw in AstroSwitch.allCases { s.astro[sw] = sw != off }
        }
    }

    /// Москва, «сейчас» — 20.09.2026 12:00; съёмка 21.09 22:00–01:00 с местом (ночь с ядром над горизонтом и луной).
    private static func shoot(_ id: String, wishes: [Wish], day: CivilDate = CivilDate(year: 2026, month: 9, day: 21),
                              start: Int = 1320, end: Int = 1500) -> Session {
        var s = Session(id: id, kind: .shoot, day: day, start: start, end: end, duration: end - start, genre: .landscape)
        s.wishes = wishes
        s.latitude = 55.75; s.longitude = 37.62
        return s
    }

    private func model(_ sessions: [Session] = [], rain: Bool = false, look: Look = .astro) -> AppModel {
        var snap = Snapshot()
        snap.sessions = sessions
        let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00+03:00")!
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

    // MARK: - Правило и настройки (№ 3)

    /// Все пять работают; правило одно — `sees`, экраны читают `seesStars` / `seesMilkyWay`. Небо на нажатии «Астро» и звёзды
    /// на кнопке (`SettingsView`: `sky:` и `showSky`) идут по `seesStars`: со «Звёздами» — да, без них и вне «Астро» — нет.
    @Test func ruleReachesTheScreensInEveryLook() {
        #expect(AstroSwitchRows.working == Set(AstroSwitch.allCases))
        let app = model()
        for look in Look.all {
            app.update { look.apply(&$0) }
            #expect(app.settings.sees(.stars) == look.stars, "\(look)")
            #expect(app.seesStars == look.stars, "\(look)")
            #expect(app.settings.sees(.milkyWay) == look.milkyWay, "\(look)")
            #expect(app.seesMilkyWay == look.milkyWay, "\(look)")
        }
    }

    /// Строки «Пока работают …» под переключателями больше нет (рисунок описи: за пятью строками сразу главы) — ни ключа
    /// в каталоге, ни слов ни на одном языке.
    @Test(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
    func waitingNoteIsGone() {
        for lang in ["ru", "en", "en-US", "es", "ja", "zh"] {
            #expect(Lexicon(lang).t("set.astro.waiting") == "set.astro.waiting", "\(lang)")
        }
    }

    // MARK: - «Карта»: слой и «Подробно» (№ 74, 96)

    /// Слой «Млечный Путь»: включённый в меню, рисуется и стоит в меню только в «Астро» с «Млечным Путём»; в файле
    /// остаётся включённым. Вместе со слоем уходит ночной холст светлой темы (`lightCanvas`).
    @Test func mapMilkyWayLayerOnlyWithTheSwitchAndStaysInTheFile() {
        let app = model()
        app.setMapLayer(.mw, true)
        for look in Look.all {
            app.update { look.apply(&$0) }
            #expect(app.mapLayersShown.mw == look.milkyWay, "\(look)")
            #expect(app.mapLayerKeys.contains(.mw) == look.milkyWay, "\(look)")
            #expect(app.mapLayers.mw, "\(look): слой в файле выключился")
            #expect(app.snapshot.mapLayers?["mw"] == true, "\(look)")
            #expect(MapInstrument.lightCanvas(lightTheme: true, layers: app.mapLayersShown) == !look.milkyWay, "\(look)")
            // Луна — по своему переключателю, прочие слои — как в меню.
            #expect(app.mapLayersShown.moon == look.sees(.moon) && app.mapLayersShown.sun && app.mapLayersShown.spots, "\(look)")
        }
    }

    /// Прибор по слоям, которые видны: без «Млечного Пути» ни пыли, ни полосы, ни ядра.
    @Test func mapInstrumentDrawsTheMilkyWayOnlyWhenShown() {
        let app = model()
        app.setMapLayer(.mw, true)
        let date = CivilDate(year: 2026, month: 9, day: 23)
        let place = Place(latitude: 53.3481, longitude: 83.7798, zone: ZoneID(fixedOffsetHours: 7))
        let sun = SolarDay(date: date, place: place)
        for look in Look.all {
            app.update { look.apply(&$0) }
            let input = MapInstrument.Input(date: date, minute: 1380, solar: sun, place: place, layers: app.mapLayersShown,
                                            pro: true, azimuths: true, lightTheme: false, chip: .drag,
                                            clock: { "\($0)" }, cardinals: ["С", "В", "Ю", "З"])
            let s = MapInstrument.scene(input, day: MapInstrument.Day(date: date, place: place, solar: sun))
            #expect(s.marks.dust.contains { $0 > 0 } == look.milkyWay, "\(look)")
            #expect((s.marks.core != nil) == look.milkyWay, "\(look)")
        }
    }

    /// «Подробно» и свод «Карты»: группа «Млечный Путь» идёт за слоем, который виден (`MapScreenView.summary` берёт
    /// `mapLayersShown.mw`). Без него уходит вся группа, с ней — высоты ядра и «Луна сейчас», и строки свода (ночь, вердикт,
    /// луна для звёзд).
    @Test func mapSummaryMilkyWayGroupGoesWithTheLayer() {
        let lexicon = Lexicon("ru"), clock = ClockText(language: "ru", preference: .h24)
        let date = CivilDate(year: 2026, month: 9, day: 23)
        let place = Place(latitude: 53.3481, longitude: 83.7798, zone: ZoneID(fixedOffsetHours: 7))
        let sun = SolarDay(date: date, place: place)
        let app = model()
        app.setMapLayer(.mw, true)
        for look in Look.all {
            app.update { look.apply(&$0) }
            let mw: MapSummary.MilkyWayInput? = app.mapLayersShown.mw
                ? MapSummary.MilkyWayInput(window: MilkyWayWindow(date: date, place: place), moon: MoonVsStars(date: date, place: place),
                                           sky: nil, nextDark: { nil })
                : nil
            let s = MapSummary.build(date: date, t: 1380, sun: sun, place: place, utcOffset: 7, pro: true,
                                     terms: app.light.terms, azimuths: app.light.azimuths, moon: app.light.moon,
                                     glow: nil, mw: mw, dateShort: { "\($0.day).\($0.month)" }, lexicon: lexicon, clock: clock)
            let group = s.pro.first { $0.title == lexicon.t("mpro.mw") }
            #expect((group != nil) == look.milkyWay, "\(look)")
            #expect(s.rows.contains { $0.label == "map.verdict" } == look.milkyWay, "\(look)")
            #expect(s.rows.contains { $0.label == "map.night" } == look.milkyWay, "\(look)")
            if let group {
                let labels = group.rows.map(\.label)
                #expect(labels.contains(lexicon.t("mpro.moonNow")) && labels.contains(lexicon.t("mpro.maxDay")), "\(look)")
            }
        }
    }

    // MARK: - AR: кнопка «Слои» и слои (№ 103, 105, 106)

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }
    /// 20.10.2026 03:00 по Томску: ночь, ядро и звёзды над горизонтом.
    private func ar(_ defaults: UserDefaults, allowed: Set<SunARSkyLayer>, at iso: String = "2026-10-19T20:00:00Z") -> SunARModel {
        SunARModel(target: SunARTarget(place: tomsk, moment: Moment(ISO8601DateFormatter().date(from: iso)!)),
                   source: nil, camera: nil, calibrationFlag: MemoryFlag(), bodies: DeviceBodiesSettings(defaults: defaults),
                   allowed: allowed)
    }

    /// Каждый слой AR — по своему переключателю; планеты и созвездия — под «Звёздами». Кнопка «Слои» — пока разрешён
    /// хоть один из трёх: «Луна», «Звёзды», «Млечный Путь»; в «Просто» и «Про» её нет, в «Астро» без всех трёх — тоже.
    @Test func arLayersAndTheLayersButtonFollowTheSwitches() {
        let defaults = UserDefaults(suiteName: "stars-switch-\(UUID().uuidString)")!
        let app = model()
        for look in Look.all {
            app.update { look.apply(&$0) }
            let allowed = app.arSkyLayers
            #expect(allowed.contains(.milkyWay) == look.milkyWay, "\(look)")
            for l in [SunARSkyLayer.stars, .constellations, .planets] { #expect(allowed.contains(l) == look.stars, "\(look) \(l)") }
            #expect(allowed.contains(.moon) == look.sees(.moon), "\(look)")
            let button = look.sees(.moon) || look.stars || look.milkyWay
            #expect(ar(defaults, allowed: allowed).layersButtonShown == button, "\(look)")
        }
        app.update { s in s.mode = .astro; s.astro[.moon] = false; s.astro[.stars] = false; s.astro[.milkyWay] = false }
        #expect(app.arSkyLayers.isEmpty)
        #expect(!ar(defaults, allowed: app.arSkyLayers).layersButtonShown)
        app.update { $0.astro[.milkyWay] = true }
        #expect(ar(defaults, allowed: app.arSkyLayers).layersButtonShown)
    }

    /// Без «Млечного Пути» включённый слой не рисуется: ни полосы, ни ядра (его стрелки и «ядро восходит» строит та же
    /// сцена), строки «Млечный Путь» с «Как в тёмном месте» в «Слоях» нет, маска не темнит. Флаг устройства цел.
    @Test func arMilkyWayHiddenButItsFlagKept() {
        let defaults = UserDefaults(suiteName: "mw-switch-\(UUID().uuidString)")!
        let all = Set(SunARSkyLayer.allCases)
        let viewport = ScreenViewport(width: 393, height: 852), basis = CameraBasis(azimuth: 200, altitude: 20)
        let first = ar(defaults, allowed: all)
        first.set(.milkyWay, on: true)
        #expect(first.milkyWayShown && first.layersOn == [.milkyWay] && first.skyLayerOn)
        #expect(first.nightScene(basis: basis, optics: .typical, viewport: viewport).milkyWayOn)

        let hidden = ar(defaults, allowed: all.subtracting([.milkyWay]))
        #expect(hidden.milkyWayOn && !hidden.milkyWayShown)
        #expect(hidden.layersOn.isEmpty && !hidden.layersListed.contains(.milkyWay))
        #expect(!hidden.nightScene(basis: basis, optics: .typical, viewport: viewport).milkyWayOn)
        #expect(!hidden.skyLayerOn && hidden.maskOpacity == 0)
        #expect(defaults.bool(forKey: "lightplan.native.sunar.milkyWay"), "флаг слоя выключился")

        #expect(ar(defaults, allowed: all).milkyWayShown)
    }

    /// Без «Звёзд» включённые звёзды, созвездия и планеты не считаются и не рисуются, их строк в «Слоях» нет, маска
    /// не темнит; флаги устройства целы и со «Звёздами» всё на месте.
    @Test func arStarsConstellationsPlanetsHiddenButFlagsKept() {
        let defaults = UserDefaults(suiteName: "stars-switch-\(UUID().uuidString)")!
        let all = Set(SunARSkyLayer.allCases)
        let viewport = ScreenViewport(width: 393, height: 852), basis = CameraBasis(azimuth: 200, altitude: 30)
        let first = ar(defaults, allowed: all)
        for l in [SunARSkyLayer.stars, .constellations, .planets] { first.set(l, on: true) }
        #expect(first.layersOn == [.stars, .constellations, .planets] && first.skyLayerOn)
        #expect(first.starScene(basis: basis, optics: .typical, viewport: viewport) != nil)
        #expect(first.planetScene(basis: basis, optics: .typical, viewport: viewport) != nil)

        let hidden = ar(defaults, allowed: all.subtracting([.stars, .constellations, .planets]))
        #expect(hidden.starsOn && hidden.constellationsOn && hidden.planetsOn)
        #expect(!hidden.starsShown && !hidden.constellationsShown && !hidden.planetsShown)
        #expect(hidden.layersOn.isEmpty && hidden.layersListed == [.moon, .milkyWay])
        #expect(hidden.starScene(basis: basis, optics: .typical, viewport: viewport) == nil)
        #expect(hidden.planetScene(basis: basis, optics: .typical, viewport: viewport) == nil)
        #expect(!hidden.skyLayerOn && hidden.maskOpacity == 0)
        for k in ["stars", "constellations", "planets"] {
            #expect(defaults.bool(forKey: "lightplan.native.sunar." + k), "флаг \(k) выключился")
        }
        let back = ar(defaults, allowed: all)
        #expect(back.starsShown && back.constellationsShown && back.planetsShown)
    }

    // MARK: - Карточка: окно Млечного Пути, «−18°», «Ожидались звёзды» (№ 146, 147)

    /// Строка звёзд в блоке «Свет» — только со «Звёздами»; «Млечный Путь» и прочие её не трогают; пожелание в записи.
    @Test func cardStarsLineOnlyWithTheSwitch() async {
        let app = model([Self.shoot("a", wishes: [.stars])])
        let s = await open(app, "a")
        for look in Look.all {
            app.update { look.apply(&$0) }
            #expect(app.cardSays(s, phase: .before).contains { $0.kind == .stars } == look.stars, "\(look)")
            #expect((app.cardStars(s, phase: .before) != nil) == look.stars, "\(look)")
            #expect(app.snapshot.sessions.first { $0.id == "a" }?.wishes == [.stars], "\(look): пожелание пропало")
        }
    }

    /// «Млечного Пути в эту ночь не будет: небо не темнеет, солнце не уходит ниже −18°» (белая ночь, Москва 21.06.2027):
    /// в «Астро» со «Звёздами» текст прежний — и без «Терминов» тоже (простых слов Алексей ещё не выбрал); в «Просто»,
    /// «Про» и без «Звёзд» строки нет.
    @Test func cardMinus18PhraseOnlyWithStarsAndUnchanged() async {
        let june = CivilDate(year: 2027, month: 6, day: 21)
        let app = model([Self.shoot("w", wishes: [.stars], day: june)])
        let s = await open(app, "w")
        let phrase = app.lexicon.t("light.starsNoDark")
        for look in Look.all {
            app.update { look.apply(&$0) }
            let line = app.cardSays(s, phase: .before).first { $0.kind == .stars }?.text
            #expect(line == (look.stars ? phrase : nil), "\(look)")
        }
    }

    /// «Ожидались звёзды. Прогноз … — дождь» — только со «Звёздами»; закат рядом с ними говорится всегда.
    @Test func cardWishMissedSaysStarsOnlyWithTheSwitch() async {
        let app = model([Self.shoot("st", wishes: [.stars]), Self.shoot("ss", wishes: [.stars, .sunset])], rain: true)
        let st = await open(app, "st")
        let ss = await open(app, "ss")
        let sunsetOnly = Self.shoot("s", wishes: [.sunset])
        for look in Look.all {
            app.update { look.apply(&$0) }
            let stars = app.cardWishMissed(st, phase: .before)
            #expect((stars != nil) == look.stars, "\(look)")
            let sunset = app.cardWishMissed(sunsetOnly, phase: .before)
            #expect(sunset != nil, "\(look)")
            #expect((app.cardWishMissed(ss, phase: .before) == sunset) == !look.stars, "\(look)")
        }
    }

    // MARK: - Форма: плитка, всплывашка, «замысел против прогноза» (№ 166, 200, 203)

    /// Плитка «Звёзды» — только со «Звёздами»; порядок остальных тот же.
    @Test func formStarsTileOnlyWithTheSwitch() {
        let app = model()
        for look in Look.all {
            app.update { look.apply(&$0) }
            #expect(app.wishTiles.contains(.stars) == look.stars, "\(look)")
            #expect(app.wishTiles == Wish.allCases.filter { ($0 != .stars || look.stars) && ($0 != .moon || look.sees(.moon)) },
                    "\(look)")
        }
    }

    /// 14:00 и «Звёзды»: со «Звёздами» — всплывашка «Звёзды …, сдвинуть?»; без них не спрашивает и время не двигает,
    /// хотя пожелание в форме есть.
    @Test func formStarsAskOnlyWithTheSwitch() {
        for look in Look.all {
            let app = model(look: look)
            app.openForm(day: CivilDate(year: 2026, month: 9, day: 21), start: 840, fromLight: false)
            app.toggleFormWish(.stars)
            #expect(app.form?.wishes.contains(.stars) == true, "\(look)")
            if look.stars {
                #expect(app.formTimeAsk?.kind == .light(.stars), "\(look)")
            } else {
                #expect(app.formTimeAsk == nil, "\(look)")
                #expect(app.form?.start == 840 && app.form?.timeShifted == false, "\(look)")
            }
        }
    }

    /// Плашка «замысел против прогноза» о звёздах молчит без «Звёзд» (город, дождь), а сами «Звёзды» остаются в форме.
    @Test func formWishWarningSilentAboutHiddenStars() throws {
        let app = model(rain: true)
        app.openForm(day: CivilDate(year: 2026, month: 9, day: 21))
        app.toggleFormWish(.stars)
        let form = try #require(app.form)
        let warn = app.formWishWarning(form)
        #expect(warn != nil)
        for look in Look.all {
            app.update { look.apply(&$0) }
            #expect((app.formWishWarning(form) == warn) == look.stars, "\(look)")
            #expect((app.formWishWarning(form) == nil) == !look.stars, "\(look)")
            #expect(app.form?.wishes == [.stars], "\(look)")
        }
    }

    /// Сохранённая съёмка со «Звёздами», правка в «Про»: «Неважно» стирает только видимые; после «Сохранить» «Звёзды»
    /// в файле, а в «Астро» плитка снова горит.
    @Test func hiddenStarsWishSurvivesAnEditInPro() throws {
        let app = model([Self.shoot("a", wishes: [.stars])], look: .pro)
        app.openForm(editing: "a")
        #expect(app.form?.wishes == [.stars])
        let shown = app.shownWishes(app.form?.wishes ?? [])
        #expect(shown.isEmpty)
        app.toggleFormWish(.sunset)
        app.toggleFormWish(.any)
        #expect(app.form?.wishes == [.stars], "«Неважно» стёрло скрытые «Звёзды»")
        _ = try #require(app.saveForm())
        #expect(app.snapshot.sessions.first { $0.id == "a" }?.wishes == [.stars])
        app.update { Look.astro.apply(&$0) }
        app.openForm(editing: "a")
        #expect(app.form?.wishOn(.stars) == true && app.wishTiles.contains(.stars))
    }
}
