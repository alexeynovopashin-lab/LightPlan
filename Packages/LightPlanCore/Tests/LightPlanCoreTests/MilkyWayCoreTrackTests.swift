import Testing
import Foundation
import LightPlanCore

/// Траектория ядра Млечного Пути (шаг 29.8в.17б): восход и заход против astropy, окно съёмки против
/// `MilkyWayWindow`, справка о видимости глазом, честные строки для широт без восхода и без захода.
/// Эталон — `Fixtures/mw_core_astropy.json`, собирается `python3 Tools/mw_core_ref.py` (astropy, рефракция ERFA).
struct MilkyWayCoreTrackTests {

    struct Reference: Decodable {
        struct Event: Decodable { let kind: String; let minutes: Double; let azimuth: Double }
        struct Sample: Decodable { let minutes: Int; let azimuth: Double; let altitude: Double }
        struct Case: Decodable {
            let place: String
            let lat, lon: Double
            let zone: String
            let date: String
            let state: String
            let events: [Event]
            let samples: [Sample]
        }
        let cases: [Case]
    }

    static let loaded: Result<Reference, Error> = Result { try ParityFixtures.load("mw_core_astropy.json", as: Reference.self) }

    static func place(_ c: Reference.Case) -> Place? {
        ZoneID(c.zone).map { Place(latitude: c.lat, longitude: c.lon, zone: $0) }
    }

    static func day(_ iso: String) -> CivilDate {
        let p = iso.split(separator: "-").map { Int($0)! }
        return CivilDate(year: p[0], month: p[1], day: p[2])
    }

    /// Разница азимутов по кругу.
    static func azDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    // MARK: - Против astropy

    @Test("восход и заход ядра: Томск, Сидней, Москва, пять дат — время ≤ 2 минут, азимут ≤ 0,5° от astropy")
    func riseAndSetAgainstAstropy() throws {
        let ref = try Self.loaded.get()
        var checked = 0
        var worstMinutes = 0.0, worstAzimuth = 0.0
        for c in ref.cases where ["tomsk", "sydney", "moscow"].contains(c.place) {
            let place = try #require(Self.place(c), "нет зоны \(c.zone)")
            let passage = MilkyWayCoreTrack.passage(day: Self.day(c.date), in: place)
            #expect(passage.events.count == c.events.count, "\(c.place) \(c.date): событий \(passage.events.count), эталон \(c.events.count)")
            for e in c.events {
                let mine = passage.events.first { ($0.kind == .rise ? "rise" : "set") == e.kind }
                let m = try #require(mine, "\(c.place) \(c.date): нет события \(e.kind)")
                let dm = abs(m.minutes - e.minutes), da = Self.azDiff(m.azimuth, e.azimuth)
                worstMinutes = max(worstMinutes, dm); worstAzimuth = max(worstAzimuth, da)
                #expect(dm <= 2, "\(c.place) \(c.date) \(e.kind): \(m.minutes) против \(e.minutes) мин")
                #expect(da <= 0.5, "\(c.place) \(c.date) \(e.kind): азимут \(m.azimuth) против \(e.azimuth)")
                checked += 1
            }
        }
        #expect(checked == 30, "сверено событий: \(checked)")
        print("MW-CORE worst rise/set: \(worstMinutes) мин, \(worstAzimuth)°")
    }

    @Test("широта 70°: ядро не восходит ни в одну из пяти дат; широта −70°: не заходит")
    func polarLatitudesAreHonest() throws {
        let ref = try Self.loaded.get()
        var n = 0
        for c in ref.cases where c.place == "lat70" || c.place == "lat_m70" {
            let place = try #require(Self.place(c), "нет зоны \(c.zone)")
            let passage = MilkyWayCoreTrack.passage(day: Self.day(c.date), in: place)
            #expect(passage == (c.place == "lat70" ? .neverRises : .neverSets), "\(c.place) \(c.date): \(passage)")
            n += 1
        }
        #expect(n == 10)
    }

    @Test("положение ядра в пяти отсчётах суток — против astropy: высота ≤ 0,5°, азимут ≤ 0,5° (азимут — на высотах 5–60°, у зенита он неустойчив)")
    func positionAgainstAstropy() throws {
        let ref = try Self.loaded.get()
        var worst = 0.0
        for c in ref.cases where ["tomsk", "sydney", "moscow"].contains(c.place) {
            let place = try #require(Self.place(c))
            for s in c.samples {
                let mine = MilkyWayCoreTrack.sample(day: Self.day(c.date), minutes: Double(s.minutes), in: place)
                // astropy даёт геометрическую высоту (без рефракции): сравнивается с геометрической высотой приложения.
                let da = abs(mine.altitude - s.altitude)
                worst = max(worst, da)
                #expect(da <= 0.5, "\(c.place) \(c.date) \(s.minutes): высота \(mine.altitude) против \(s.altitude)")
                if s.altitude > 5 && s.altitude < 60 { #expect(Self.azDiff(mine.azimuth, s.azimuth) <= 0.5, "\(c.place) \(c.date) \(s.minutes) азимут") }
            }
        }
        print("MW-CORE worst altitude: \(worst)°")
    }

    // MARK: - Дуга

    @Test("дуга ядра: 145 точек через 10 минут, точка в полдень — то же, что corePosition")
    func arcIsCorePosition() {
        let place = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
        let day = CivilDate(year: 2026, month: 8, day: 30)
        let arc = MilkyWayCoreTrack.arc(day: day, in: place)
        #expect(arc.count == 145 && arc.first?.minutes == 0 && arc.last?.minutes == 1440)
        let p = MilkyWay.corePosition(date: day, minutes: 720, place: place)
        #expect(arc[72].azimuth == p.azimuth && arc[72].altitude == p.altitude)
    }

    @Test("событие лежит на линии горизонта: видимая высота в минуту события ≈ 0")
    func eventSitsOnHorizon() throws {
        let place = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
        let passage = MilkyWayCoreTrack.passage(day: CivilDate(year: 2026, month: 8, day: 30), in: place)
        #expect(passage.events.count == 2)
        for e in passage.events {
            let s = MilkyWayCoreTrack.sample(day: CivilDate(year: 2026, month: 8, day: 30), minutes: e.minutes, in: place)
            #expect(abs(s.apparentAltitude) < 0.01, "\(e): \(s.apparentAltitude)")
        }
    }

    // MARK: - Окно

    @Test("окно съёмки в плане — то же, что MilkyWayWindow; оно лежит внутри «ядро над горизонтом» (10° выше, чем 0°)")
    func planWindowIsMilkyWayWindow() throws {
        let ref = try Self.loaded.get()
        var withWindow = 0
        for c in ref.cases where ["tomsk", "sydney", "moscow"].contains(c.place) {
            let place = try #require(Self.place(c))
            let day = Self.day(c.date)
            let plan = MilkyWayPlan(day: day, place: place)
            #expect(plan.window == MilkyWayWindow(date: day, place: place))
            guard !plan.window.spans.isEmpty else { continue }
            withWindow += 1
            // Окно считается по солнечным суткам (от солнечной полуночи), минуты могут выходить за 0…1440 — так и берём.
            // Каждый отрезок окна: ядро над горизонтом (и выше рабочей высоты) на всём протяжении, по шагу 5 минут.
            for span in plan.window.spans {
                var x = span.from
                while x <= span.to {
                    let s = MilkyWayCoreTrack.sample(day: day, minutes: x, in: place)
                    #expect(s.altitude >= MilkyWay.workLow && s.apparentAltitude > 0, "\(c.place) \(c.date): в \(x) мин ядро \(s.altitude)°")
                    x += 5
                }
            }
        }
        #expect(withWindow > 0)
    }

    @Test("отрезки окна, сросшиеся на стыке солнечных суток, склеены: Сидней в июне — один отрезок через полночь, а не два у краёв")
    func shootingJoinsSeam() throws {
        let sydney = Place(latitude: -33.8688, longitude: 151.2093, zone: ZoneID("Australia/Sydney")!)
        let plan = MilkyWayPlan(day: CivilDate(year: 2026, month: 6, day: 15), place: sydney)
        #expect(plan.window.spans.count == 2, "окно считается по солнечным суткам: два отрезка у краёв")
        #expect(plan.shooting.count == 1)
        let s = try #require(plan.shooting.first)
        #expect(s.to > 1440 && s.to - s.from > 600, "ночь через полночь: \(s)")
        // Склейка ничего не добавляет: сумма длин та же (отрезки внахлёст не считаются).
        let total = plan.window.spans.reduce(0) { $0 + ($1.to - $1.from) }
        #expect(abs((s.to - s.from) - total) <= 5)
        // Не сросшиеся отрезки остаются как есть: Томск в июле, окно у одного края.
        let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
        let t = MilkyWayPlan(day: CivilDate(year: 2026, month: 10, day: 10), place: tomsk)
        #expect(t.shooting == t.window.spans || t.window.spans.count >= 2)
    }

    @Test("темно: вечернее время — astroB солнца; на широте 62° в июне темноты нет")
    func darkLine() {
        let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
        let winter = MilkyWayPlan(day: CivilDate(year: 2026, month: 1, day: 15), place: tomsk)
        if case .from(let t) = winter.dark {
            let sun = SolarDay(date: CivilDate(year: 2026, month: 1, day: 15), place: tomsk)
            #expect(abs(t - (sun.astroB ?? -1)) < 1e-9)
        } else { Issue.record("зимой в Томске темнеет: \(winter.dark)") }
        let north = Place(latitude: 62, longitude: 30, zone: ZoneID("Europe/Moscow")!)
        #expect(MilkyWayPlan(day: CivilDate(year: 2026, month: 6, day: 21), place: north).dark == .never)
    }

    // MARK: - Справка о видимости глазом

    @Test("видимость глазом: город с засветкой 12 — 8 %; днём — солнце, 0; яркая Луна — причина Луна")
    func eyeNote() {
        // Ночь, ядро высоко, засветка 12: 1 / (1 + 12) = 7,7 % → 8.
        let city = MilkyWayLook.eyeNote(sunAltitude: -30, moonAltitude: -20, moonFraction: 0.5, glow: 12, coreAltitude: 30)
        #expect(city.percent == 8)
        #expect(city.causes == [.glow(.city, value: 12)])
        let day = MilkyWayLook.eyeNote(sunAltitude: 20, moonAltitude: -20, moonFraction: 0.5, glow: 0.3, coreAltitude: 30)
        #expect(day.percent == 0 && day.causes == [.daylight(sun: 20)])
        let moon = MilkyWayLook.eyeNote(sunAltitude: -30, moonAltitude: 25, moonFraction: 0.62, glow: 0.3, coreAltitude: 30)
        #expect(moon.percent == 0 && moon.causes == [.moon(percent: 62)])
        // Луна над горизонтом, но освещена на 40 % и меньше — не мешает (правило окна).
        let thin = MilkyWayLook.eyeNote(sunAltitude: -30, moonAltitude: 25, moonFraction: 0.3, glow: 0, coreAltitude: 30)
        #expect(thin.percent == 100)
        // Засветка выше 27 — «дальше пусто».
        let none = MilkyWayLook.eyeNote(sunAltitude: -30, moonAltitude: -20, moonFraction: 0.1, glow: 40, coreAltitude: 30)
        #expect(none.percent == 0 && none.causes == [.glow(.none, value: 40)])
        // Ядро у горизонта: дымка; под горизонтом — свой вывод.
        let low = MilkyWayLook.eyeNote(sunAltitude: -30, moonAltitude: -20, moonFraction: 0.1, glow: 0.3, coreAltitude: 4)
        #expect(low.percent > 0 && low.percent < 100 && low.causes.contains(.haze))
        let under = MilkyWayLook.eyeNote(sunAltitude: -30, moonAltitude: -20, moonFraction: 0.1, glow: 0.3, coreAltitude: -5)
        #expect(under.percent == 0 && under.causes.contains(.belowHorizon))
        // Сумерки: между −6° и −18° — доля.
        let dusk = MilkyWayLook.eyeNote(sunAltitude: -12, moonAltitude: -20, moonFraction: 0.1, glow: 0, coreAltitude: 30)
        #expect(dusk.percent == 50 && dusk.causes.contains(.twilight(sun: -12)))
    }

    @Test("число справки — то же, что множитель картины: eyeNote и visibility совпадают там, где ядро высоко")
    func eyeNoteMatchesVisibility() {
        for sun in [-4.0, -9.0, -15.0, -25.0] {
            for glow in [nil, 0.4, 3, 12, 30] as [Double?] {
                let v = MilkyWayLook.visibility(sunAltitude: sun, moonAltitude: -20, moonFraction: 0.1, glow: glow)
                let n = MilkyWayLook.eyeNote(sunAltitude: sun, moonAltitude: -20, moonFraction: 0.1, glow: glow, coreAltitude: 45)
                #expect(n.percent == Int((v.factor * 100).rounded()), "sun \(sun) glow \(String(describing: glow))")
            }
        }
    }

    // MARK: - Сцена

    @Test("траектория на экране: дуга с пунктиром под горизонтом, часы подписаны, события на линии горизонта")
    func trackOnScreen() throws {
        let place = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
        let day = CivilDate(year: 2026, month: 8, day: 30)
        let arc = MilkyWayCoreTrack.arc(day: day, in: place)
        let passage = MilkyWayCoreTrack.passage(day: day, in: place)
        let core = MilkyWay.corePosition(date: day, minutes: 1200, place: place)
        // Камера смотрит на юг, на 20° над горизонтом.
        let basis = CameraBasis(azimuth: 180, altitude: 20)
        let scene = NightSkyARScene.make(
            basis: basis, optics: CameraOptics.typical, viewport: ScreenViewport(width: 393, height: 852), moon: nil,
            milkyWay: .init(band: [], core: core, sunAltitude: -30,
                            track: .init(arc: arc, passage: passage)))
        let track = try #require(scene.coreTrack)
        #expect(!track.arc.isEmpty)
        let flat = track.arc.flatMap { $0 }
        #expect(flat.contains { $0.isBelowHorizon } && flat.contains { !$0.isBelowHorizon })
        #expect(flat.allSatisfy { $0.altitude >= MilkyWayCoreTrack.arcFrom })
        #expect(track.hours.allSatisfy { $0.altitude >= SunTrack.visibleFrom })
        #expect(track.events.count == 2)
        #expect(NightSkyARScene.make(basis: basis, optics: CameraOptics.typical, viewport: ScreenViewport(width: 393, height: 852),
                                     moon: nil, milkyWay: nil).coreTrack == nil)
    }
}
