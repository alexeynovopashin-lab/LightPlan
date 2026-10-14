import Testing
import Foundation
import LightPlanCore

/// Солнце слоя AR (шаг 29.8в): дуга суток, момент ↔ часы места, рефракция, устойчивость курса.
struct SunTrackTests {

    static let moscow = Place(latitude: 55.7558, longitude: 37.6173, zone: ZoneID("Europe/Moscow")!)
    static let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    static let day = CivilDate(year: 2026, month: 6, day: 21)

    // MARK: - Часы места

    @Test("момент → часы места → момент возвращается; Томск (+7) и Москва (+3) в один и тот же момент разошлись на 4 ч")
    func wallClockRoundTrip() {
        let m = SunTrack.moment(day: Self.day, minutes: 13 * 60 + 30, in: Self.moscow)
        let back = SunTrack.wallClock(of: m, in: Self.moscow)
        #expect(back.day == Self.day && abs(back.minutes - 810) < 1e-6)
        let tm = SunTrack.wallClock(of: m, in: Self.tomsk)
        #expect(tm.day == Self.day && abs(tm.minutes - (810 + 240)) < 1e-6)
    }

    @Test("за полночь по часам места день меняется, минуты — нет отрицательных")
    func midnight() {
        let m = SunTrack.moment(day: Self.day, minutes: 1440 + 5, in: Self.moscow)
        let w = SunTrack.wallClock(of: m, in: Self.moscow)
        #expect(w.day == CivilDate(year: 2026, month: 6, day: 22) && abs(w.minutes - 5) < 1e-6)
    }

    // MARK: - Дуга

    @Test("дуга суток: 145 точек через 10 минут от 0 до 1440, максимум совпадает с высотой полудня SolarDay")
    func arcShape() throws {
        let arc = SunTrack.arc(day: Self.day, in: Self.moscow)
        #expect(arc.count == 145)
        #expect(arc.first?.minutes == 0 && arc.last?.minutes == 1440)
        let solar = SolarDay(date: Self.day, place: Self.moscow)
        let top = try #require(arc.max { $0.altitude < $1.altitude })
        // Шаг 10 минут: ближайшая точка к полудню не дальше 5 минут → высота не ниже максимума на 0,05°.
        #expect(top.altitude <= solar.maxElevation + 1e-9)
        #expect(solar.maxElevation - top.altitude < 0.05)
        #expect(abs(top.minutes - solar.solarNoon) <= 5 + 1e-9)
    }

    @Test("высота и азимут в точке дуги — те же числа, что у SolarDay «Света» на ту же минуту")
    func sameNumbersAsSolarDay() {
        let solar = SolarDay(date: Self.day, place: Self.moscow)
        for s in SunTrack.arc(day: Self.day, in: Self.moscow) {
            #expect(s.altitude == solar.elevation(at: s.minutes))
            #expect(s.azimuth == solar.azimuth(at: s.minutes))
        }
    }

    @Test("порог: зимой в Москве видимая часть дуги — короче суток, точки ниже −6° отброшены")
    func threshold() {
        let winter = CivilDate(year: 2026, month: 12, day: 21)
        let arc = SunTrack.arc(day: winter, in: Self.moscow)
        let seen = SunTrack.visible(arc)
        #expect(seen.count < arc.count && seen.count > 40)
        #expect(seen.allSatisfy { $0.altitude >= -6 })
        #expect(arc.filter { $0.altitude < -6 }.count == arc.count - seen.count)
    }

    @Test("азимут: утром солнце на востоке, в полдень на юге, вечером на западе (северное полушарие, лето)")
    func compassSides() {
        let arc = SunTrack.arc(day: Self.day, in: Self.moscow)
        let solar = SolarDay(date: Self.day, place: Self.moscow)
        let morning = SunTrack.sample(day: Self.day, minutes: solar.solarNoon - 360, in: Self.moscow)
        let noon = SunTrack.sample(day: Self.day, minutes: solar.solarNoon, in: Self.moscow)
        let evening = SunTrack.sample(day: Self.day, minutes: solar.solarNoon + 360, in: Self.moscow)
        #expect(morning.azimuth > 60 && morning.azimuth < 120)
        #expect(abs(noon.azimuth - 180) < 1)
        #expect(evening.azimuth > 240 && evening.azimuth < 300)
        #expect(!arc.isEmpty)
    }

    // MARK: - Рефракция

    @Test("рефракция: на горизонте ≈ 0,48°, на 10° ≈ 0,09°, на 45° ≈ 0,017°; растёт к горизонту, ниже −1° не растёт")
    func refraction() {
        func add(_ h: Double) -> Double { SunTrack.apparent(altitude: h) - h }
        #expect(abs(add(0) - 0.483) < 0.01)
        #expect(abs(add(10) - 0.090) < 0.005)
        #expect(abs(add(45) - 0.017) < 0.003)
        #expect(add(0) > add(5) && add(5) > add(20) && add(20) > add(60))
        #expect(abs(add(-1) - add(-6)) < 1e-12)
        #expect(add(-0.833) > 0.55 && add(-0.833) < 0.65)   // восход по меркам приложения: верхний край у горизонта
    }

    @Test("в момент «восхода» приложения (−0,833°) верхний край диска, с рефракцией, лежит около горизонта")
    func sunriseUpperLimb() {
        // Видимый центр −0,833 + 0,62 = −0,21°; радиус диска 0,267° → верхний край +0,05°.
        let centre = SunTrack.apparent(altitude: -0.833)
        #expect(abs((centre + 0.267) - 0.05) < 0.03)
    }

    // MARK: - Устойчивость курса

    @Test("курс прыгает при неподвижном телефоне: разброс 7° за 0,5 с — предупреждение")
    func jitterIsUnsteady() {
        var g = HeadingSteadiness()
        var t = 0.0
        for i in 0..<20 {
            g.add(time: t, heading: i % 2 == 0 ? 100 : 107, rate: 1)
            t += 0.05
        }
        #expect(g.isUnsteady)
        #expect((g.excess ?? 0) > 5)
    }

    @Test("курс стоит: ±1° — нет предупреждения; меньше пяти отсчётов — не судим")
    func steady() {
        var g = HeadingSteadiness()
        for i in 0..<4 { g.add(time: Double(i) * 0.05, heading: 100, rate: 0) }
        #expect(g.excess == nil && !g.isUnsteady)
        for i in 4..<20 { g.add(time: Double(i) * 0.05, heading: i % 2 == 0 ? 100 : 101, rate: 0) }
        #expect(!g.isUnsteady)
    }

    @Test("телефон поворачивают за солнцем со скоростью 40°/с: разброс 20°, но гироскоп его объясняет — тихо")
    func panningIsNotNoise() {
        var g = HeadingSteadiness()
        for i in 0..<30 { g.add(time: Double(i) * 0.05, heading: 100 + 40 * Double(i) * 0.05, rate: 40) }
        #expect(!g.isUnsteady)
        #expect((g.excess ?? 99) < 1)
    }

    @Test("у севера: 359° и 1° — это 2°, а не 358°")
    func wraps() {
        #expect(abs(HeadingSteadiness.circularSpread([359, 0, 1, 358.5]) - 2.5) < 1e-9)
        var g = HeadingSteadiness()
        for i in 0..<20 { g.add(time: Double(i) * 0.05, heading: i % 2 == 0 ? 359.5 : 0.5, rate: 0) }
        #expect(!g.isUnsteady)
    }

    @Test("предупреждение держится 1,5 с после последнего скачка и гаснет")
    func holdsThenClears() {
        var g = HeadingSteadiness()
        var t = 0.0
        for i in 0..<20 { g.add(time: t, heading: i % 2 == 0 ? 100 : 108, rate: 0); t += 0.05 }
        #expect(g.isUnsteady)
        // Курс встал. Через секунду — всё ещё держится.
        for _ in 0..<18 { g.add(time: t, heading: 104, rate: 0); t += 0.05 }
        #expect(g.isUnsteady)
        // Скачков нет уже больше двух секунд (окно 0,5 с + выдержка 1,5 с) — погасло.
        for _ in 0..<30 { g.add(time: t, heading: 104, rate: 0); t += 0.05 }
        #expect(!g.isUnsteady)
    }
}

/// Сцена AR: что нарисовано и где (шаг 29.8в).
struct SunARSceneTests {
    static let place = SunTrackTests.moscow
    static let day = CivilDate(year: 2026, month: 6, day: 21)
    static let screen = ScreenViewport(width: 393, height: 852)
    static let optics = CameraOptics.typical

    static func scene(az: Double, alt: Double, roll: Double = 0, minutes: Double = 13 * 60 + 11) -> SunARScene {
        SunARScene.make(basis: CameraBasis(azimuth: az, altitude: alt, roll: roll), optics: optics, viewport: screen,
                        arc: SunTrack.arc(day: day, in: place),
                        sun: SunTrack.sample(day: day, minutes: minutes, in: place))
    }

    @Test("камера на солнце: маркер в центре кадра с допуском на рефракцию (0,02° ≈ 0,3 pt)")
    func markerAtCentre() throws {
        let sun = SunTrack.sample(day: day(), minutes: 15 * 60, in: Self.place)
        let s = SunARScene.make(basis: CameraBasis(azimuth: sun.azimuth, altitude: sun.apparentAltitude),
                                optics: Self.optics, viewport: Self.screen,
                                arc: SunTrack.arc(day: day(), in: Self.place), sun: sun)
        let m = try #require(s.marker)
        #expect(abs(m.x - 196.5) < 1e-6 && abs(m.y - 426) < 1e-6)
        #expect(!s.markerGhost)
    }

    func day() -> CivilDate { Self.day }

    @Test("дуга летнего дня в Москве: один отрезок (солнце не заходит глубже −6° дольше полуночи нет) и подписи часов с 2 до 22")
    func summerArcHours() {
        // Широта 55,76°, 21 июня: ниже −6° солнце не уходит вовсе (белые ночи), дуга — одна замкнутая линия.
        let arc = SunTrack.arc(day: Self.day, in: Self.place)
        #expect(arc.allSatisfy { $0.altitude >= -12 })
        let s = Self.scene(az: 180, alt: 20)
        #expect(!s.arc.isEmpty)
        // Подписи — только полные часы, по одной на час, часы возрастают.
        let hs = s.hours.map(\.hour)
        #expect(hs == hs.sorted() && Set(hs).count == hs.count)
        #expect(hs.allSatisfy { (0..<24).contains($0) })
    }

    @Test("за камерой дуга рвётся: взгляд на юг — северная половина дуги не рисуется; на север — южная")
    func arcBreaksBehindCamera() {
        let south = Self.scene(az: 180, alt: 10)
        let north = Self.scene(az: 0, alt: 10)
        let southCount = south.arc.reduce(0) { $0 + $1.count }
        let northCount = north.arc.reduce(0) { $0 + $1.count }
        let all = SunTrack.arc(day: Self.day, in: Self.place).filter { $0.altitude >= SunTrack.arcFrom }.count
        #expect(southCount < all && northCount < all)
        #expect(southCount > 0)
    }

    @Test("поворот на 360° ничего не меняет в сцене")
    func fullTurn() {
        let a = Self.scene(az: 170, alt: 12)
        let b = Self.scene(az: 170 + 360, alt: 12)
        let ma = try! #require(a.marker), mb = try! #require(b.marker)
        #expect(abs(ma.x - mb.x) < 1e-6 && abs(ma.y - mb.y) < 1e-6)
        #expect(a.hours.count == b.hours.count)
        let pa: [ScreenPoint] = a.arc.flatMap { $0.map(\.point) }
        let pb: [ScreenPoint] = b.arc.flatMap { $0.map(\.point) }
        #expect(pa.count == pb.count)
        var worst = 0.0
        for (p, q) in zip(pa, pb) { worst = max(worst, abs(p.x - q.x), abs(p.y - q.y)) }
        #expect(worst < 1e-6)
    }

    @Test("солнце ниже порога — маркер призрак, но не пропадает, пока он перед камерой")
    func ghostMarker() throws {
        // Московская полночь 21 июня: солнце на ≈ −10…−11° — ниже порога −6°.
        let s = Self.scene(az: 0, alt: -10, minutes: 60)
        #expect(s.markerGhost)
        #expect(s.marker != nil)
    }

    @Test("порча: сдвиг азимута солнца на 1° сдвигает маркер больше допуска")
    func oneDegreeShiftsMarker() throws {
        let sun = SunTrack.sample(day: Self.day, minutes: 14 * 60, in: Self.place)
        let shifted = SunSample(minutes: sun.minutes, azimuth: sun.azimuth + 1, altitude: sun.altitude)
        let basis = CameraBasis(azimuth: sun.azimuth - 15, altitude: 20)
        func marker(_ s: SunSample) throws -> ScreenPoint {
            try #require(SunARScene.make(basis: basis, optics: Self.optics, viewport: Self.screen, arc: [], sun: s).marker)
        }
        let a = try marker(sun), b = try marker(shifted)
        #expect(hypot(a.x - b.x, a.y - b.y) > 5)
    }

    @Test("земля: в кадре на уровне горизонта лежит ниже линии; при взгляде вверх она уходит за нижний край, вниз — весь экран")
    func ground() throws {
        let level = Self.scene(az: 90, alt: 0)
        let g = try #require(level.ground)
        #expect(g.count == 4)
        // Нижняя левая и нижняя правая вершины ниже центра экрана.
        #expect(g[2].y > 426 && g[3].y > 426 && g[0].y < 1000)
        // Взгляд почти в зенит: горизонт далеко внизу за краем окна — земля есть, но на экран не попадает.
        let up = Self.scene(az: 90, alt: 85).ground ?? []
        #expect(up.allSatisfy { $0.y > 852 })
        let down = try #require(Self.scene(az: 90, alt: -88).ground)
        #expect(down.count == 4 && down[0] == ScreenPoint(x: 0, y: 0))
    }

    @Test("горизонт: у ровной камеры — одна прямая на высоте центра; стороны света в кадре отмечены")
    func horizonLine() throws {
        let s = Self.scene(az: 90, alt: 0)
        let run = try #require(s.horizon.max { $0.count < $1.count })
        #expect(run.allSatisfy { abs($0.y - 426) < 1e-6 })
        let east = try #require(s.cardinals.first { $0.index == 2 })
        #expect(abs(east.point.x - 196.5) < 1e-6)
        #expect(s.cardinals.first { $0.index == 6 } == nil)    // запад позади
    }

    // MARK: - Два маркера: «сейчас» и выбранный момент (29.8в.2)

    private func twoMarkers(picked: SunSample, now: SunSample?, pickedIsNow: Bool = false,
                            basis: CameraBasis = CameraBasis(azimuth: 190, altitude: 30)) -> SunARScene {
        SunARScene.make(basis: basis, optics: Self.optics, viewport: Self.screen, arc: [], sun: picked,
                        now: now, pickedIsNow: pickedIsNow)
    }

    @Test("выбранный момент = сейчас: маркер один (он же «сейчас»), второго нет")
    func pickedIsNowMerges() throws {
        let sun = SunTrack.sample(day: Self.day, minutes: 14 * 60, in: Self.place)
        let s = twoMarkers(picked: sun, now: sun, pickedIsNow: true)
        #expect(s.markerIsNow)
        #expect(s.marker != nil)
        #expect(s.nowMarker == nil)
    }

    @Test("тот же день, другой час: два маркера в разных местах; «сейчас» от выбранного не зависит")
    func differentHourTwoMarkers() throws {
        let picked = SunTrack.sample(day: Self.day, minutes: 17 * 60, in: Self.place)
        let now = SunTrack.sample(day: Self.day, minutes: 12 * 60, in: Self.place)
        let s = twoMarkers(picked: picked, now: now)
        let a = try #require(s.marker), b = try #require(s.nowMarker)
        #expect(!s.markerIsNow)
        #expect(hypot(a.x - b.x, a.y - b.y) > 30)
        // «Сейчас» стоит там, где его сосчитал независимый вызов проекции.
        let q = try #require(SkyProjection.project(azimuth: now.azimuth, altitude: now.apparentAltitude,
                                                   basis: CameraBasis(azimuth: 190, altitude: 30),
                                                   optics: Self.optics, viewport: Self.screen))
        #expect(abs(b.x - q.x) < 1e-6 && abs(b.y - q.y) < 1e-6)
    }

    @Test("тот же час другого дня: маркеры не совпадают (солнце в июне и в декабре стоит по-разному)")
    func differentDayTwoMarkers() throws {
        let june = SunTrack.sample(day: Self.day, minutes: 12 * 60, in: Self.place)
        let dec = SunTrack.sample(day: CivilDate(year: 2026, month: 12, day: 21), minutes: 12 * 60, in: Self.place)
        let s = twoMarkers(picked: dec, now: june)
        let a = try #require(s.marker), b = try #require(s.nowMarker)
        #expect(abs(a.y - b.y) > 100, "в декабре солнце в полдень много ниже: \(a) против \(b)")
    }

    @Test("«сейчас» за камерой — метки нет, выбранный маркер на месте; «сейчас» ниже порога — призрак")
    func nowBehindAndGhost() throws {
        let picked = SunTrack.sample(day: Self.day, minutes: 13 * 60, in: Self.place)
        let behind = SunSample(minutes: 0, azimuth: 10, altitude: 20)
        let s = twoMarkers(picked: picked, now: behind, basis: CameraBasis(azimuth: 190, altitude: 30))
        #expect(s.marker != nil)
        #expect(s.nowMarker == nil)

        let night = SunSample(minutes: 0, azimuth: 190, altitude: -20)
        let g = twoMarkers(picked: picked, now: night, basis: CameraBasis(azimuth: 190, altitude: 0))
        #expect(g.nowMarker != nil)
        #expect(g.nowGhost)
        #expect(!g.markerGhost)
    }
}

/// Вид AR по замечаниям Алексея (шаг 29.8в.3): свет вдоль дуги, пунктир под горизонтом, восход и закат на
/// горизонте, восемь сторон света, пороги отдачи, строка «до заката».
struct SunARLightTests {
    static let moscow = SunTrackTests.moscow
    static let screen = ScreenViewport(width: 393, height: 852)
    static let optics = CameraOptics.typical
    static let equinox = CivilDate(year: 2026, month: 3, day: 20)
    /// Мурманск (68,97° с. ш.): полярный день с конца мая — по нему ищется пограничный день.
    static let murmansk = Place(latitude: 68.9733, longitude: 33.0855, zone: ZoneID("Europe/Moscow")!)

    static func scene(day: CivilDate, place: Place, az: Double = 180, alt: Double = 0, minutes: Double = 12 * 60) -> SunARScene {
        let solar = SolarDay(date: day, place: place)
        return SunARScene.make(basis: CameraBasis(azimuth: az, altitude: alt), optics: optics, viewport: screen,
                               arc: SunTrack.arc(day: day, in: place),
                               sun: SunTrack.sample(day: day, minutes: minutes, in: place), solar: solar)
    }

    // MARK: - Дуга цветом света

    @Test("каждая точка дуги несёт состояние света своей высоты — тот же LightState, что у таймбара")
    func arcPointsCarryLightState() {
        let day = Self.equinox
        let solar = SolarDay(date: day, place: Self.moscow)
        // Камера смотрит на юг и чуть вниз: в кадре и дневная часть дуги, и сумеречная.
        let s = Self.scene(day: day, place: Self.moscow, az: 180, alt: 5)
        let pts = s.arc.flatMap { $0 }
        #expect(!pts.isEmpty)
        for p in pts {
            let want = LightState(elevation: p.altitude, morning: p.minutes < solar.solarNoon).code
            #expect(p.state == want, "минута \(p.minutes): \(p.state) вместо \(want)")
        }
        // Полдень равноденствия в Москве (≈ 34°): «день»; у горизонта над ним — «золотой час».
        let states = Set(pts.map(\.state))
        #expect(states.contains(.golden) || states.contains(.evening) || states.contains(.morningWarm))
        #expect(pts.contains { $0.state == .day || $0.state == .morning })
    }

    @Test("дуга идёт ниже горизонта до −18° пунктиром: точки с видимой высотой < 0 помечены, глубже −18° дуги нет")
    func arcContinuesBelowHorizon() {
        // Взгляд на север-вниз и на юг-вниз: ночная часть дуги в кадре.
        var below = 0, above = 0, deepest = 0.0
        for az in [0.0, 180] {
            let s = Self.scene(day: Self.equinox, place: Self.moscow, az: az, alt: -25)
            for p in s.arc.flatMap({ $0 }) {
                if p.isBelowHorizon { below += 1 } else { above += 1 }
                deepest = min(deepest, p.altitude)
                #expect(p.altitude >= SunTrack.arcFrom)
                #expect(p.isBelowHorizon == (SunTrack.apparent(altitude: p.altitude) < 0))
            }
        }
        #expect(below > 0, "под горизонтом точек нет")
        #expect(deepest < -6, "дуга оборвана на прежнем пороге −6°: самая глубокая точка \(deepest)°")
        _ = above
    }

    @Test("состояния под горизонтом идут по порядку закат → сумерки → синий час → астро")
    func belowHorizonStatesInOrder() {
        // Вечерняя половина дуги равноденствия, минуты по возрастанию: закат, затем всё темнее.
        let day = Self.equinox
        let solar = SolarDay(date: day, place: Self.moscow)
        let evening = SunTrack.arc(day: day, in: Self.moscow).filter { $0.minutes > solar.solarNoon && $0.altitude < -0.833 && $0.altitude >= SunTrack.arcFrom }
        let codes = evening.map { LightState(elevation: $0.altitude, morning: false).code }
        let order: [LightCode] = [.sunset, .dusk, .blue, .deepDusk, .astroDusk]
        var last = 0
        for c in codes {
            let i = order.firstIndex(of: c)
            #expect(i != nil, "неожиданное состояние \(c)")
            if let i { #expect(i >= last); last = i }
        }
        #expect(Set(codes).count >= 4)
    }

    // MARK: - Восход и закат на горизонте

    @Test("обычный день: восход и закат на линии горизонта, минуты и азимуты — те же, что у SolarDay")
    func eventsOnHorizon() throws {
        let day = Self.equinox
        let solar = SolarDay(date: day, place: Self.moscow)
        let s = Self.scene(day: day, place: Self.moscow, az: 270, alt: 0)
        let set = try #require(s.events.first { $0.kind == .sunset })
        #expect(abs(set.minutes - (try #require(solar.set))) < 1e-9)
        #expect(abs(set.azimuth - solar.azimuth(at: set.minutes)) < 1e-9)
        // Камера смотрит на запад ровно на горизонт: метка заката в центре кадра по горизонтали и на линии.
        let p = try #require(set.point)
        #expect(abs(p.y - 426) < 1e-6)
        #expect(abs(p.x - 196.5) < 40, "закат на \(set.azimuth)°, камера на 270°: x = \(p.x)")
        let rise = try #require(s.events.first { $0.kind == .sunrise })
        #expect(rise.point == nil, "восток за спиной у камеры, метки на экране быть не должно")
    }

    @Test("полярный день: ни восхода, ни заката — событий нет; полярная ночь — тоже")
    func noEventsInPolarDay() {
        let june = CivilDate(year: 2026, month: 6, day: 21)
        let s = Self.scene(day: june, place: Self.murmansk)
        #expect(SolarDay(date: june, place: Self.murmansk).polar == .day)
        #expect(s.events.isEmpty)
        let dec = CivilDate(year: 2026, month: 12, day: 21)
        #expect(SolarDay(date: dec, place: Self.murmansk).polar == .night)
        #expect(Self.scene(day: dec, place: Self.murmansk).events.isEmpty)
    }

    @Test("пограничный день: метка заката есть в точности в те сутки, где у SolarDay есть закат; граница найдена")
    func sunsetEventAtPolarBoundary() {
        var withSet = 0, without = 0
        var lastWith: CivilDate?, firstWithout: CivilDate?
        var d = CivilDate(year: 2026, month: 5, day: 1)
        for _ in 0..<60 {
            let solar = SolarDay(date: d, place: Self.murmansk)
            let s = Self.scene(day: d, place: Self.murmansk, az: 0, alt: 0)
            let has = s.events.contains { $0.kind == .sunset }
            #expect(has == (solar.set != nil), "\(d): закат у SolarDay \(String(describing: solar.set)), метка \(has)")
            let hasRise = s.events.contains { $0.kind == .sunrise }
            #expect(hasRise == (solar.rise != nil), "\(d): восход")
            if solar.set != nil { withSet += 1; lastWith = d } else { without += 1; if firstWithout == nil { firstWithout = d } }
            d = d.adding(days: 1)
        }
        #expect(withSet > 0 && without > 0, "граница полярного дня за май–июнь не найдена: с закатом \(withSet), без \(without)")
        #expect(lastWith != nil && firstWithout != nil)
    }

    // MARK: - Стороны света

    @Test("восемь сторон света через 45°; основные (С, В, Ю, З) — чётные индексы")
    func eightCardinals() throws {
        // Широкий кадр не нужен: проверяем по индексам, считая проекцию на каждый из восьми азимутов отдельно.
        var seen = Set<Int>()
        for az in stride(from: 0.0, to: 360, by: 45) {
            let s = Self.scene(day: Self.equinox, place: Self.moscow, az: az, alt: 0)
            let c = try #require(s.cardinals.first { $0.index == Int(az / 45) }, "азимут \(az)° не в кадре")
            #expect(abs(c.point.x - 196.5) < 1e-6)
            #expect(c.isMain == (Int(az) % 90 == 0))
            seen.insert(c.index)
        }
        #expect(seen == Set(0..<8))
    }

    // MARK: - Пороги отдачи

    @Test("пороги: +6,05° (золотой час), −0,833° (закат), −4° и −6° (синий час); в обе стороны")
    func thresholds() {
        #expect(SunTrack.lightThresholds == [6.05, -0.833, -4, -6])
        #expect(SunTrack.thresholdsCrossed(from: 10, to: -8) == 4)
        #expect(SunTrack.thresholdsCrossed(from: -8, to: 10) == 4)
        #expect(SunTrack.thresholdsCrossed(from: 7, to: 5) == 1)          // начало золотого часа
        #expect(SunTrack.thresholdsCrossed(from: 5, to: 3) == 0)          // внутри золотого часа
        #expect(SunTrack.thresholdsCrossed(from: 0.5, to: -1.5) == 1)     // закат
        #expect(SunTrack.thresholdsCrossed(from: -3, to: -5) == 1)        // синий час начался
        #expect(SunTrack.thresholdsCrossed(from: 40, to: 20) == 0)        // в полдень порогов нет
        // Отсчёт ровно на пороге: щелчок один — на одном из двух шагов, не ноль и не два (ревью GPT к 5e03f85).
        #expect(SunTrack.thresholdsCrossed(from: 7, to: 6.05) + SunTrack.thresholdsCrossed(from: 6.05, to: 5) == 1)
        #expect(SunTrack.thresholdsCrossed(from: 5, to: 6.05) + SunTrack.thresholdsCrossed(from: 6.05, to: 7) == 1)
        #expect(SunTrack.thresholdsCrossed(from: -4, to: -4) == 0)
    }

    // MARK: - Строка «до заката»

    @Test("строка под временем: до рассвета → до заката → после заката; полярные сутки — без события")
    func eventNote() throws {
        let solar = SolarDay(date: Self.equinox, place: Self.moscow)
        let rise = try #require(solar.rise), set = try #require(solar.set)
        #expect(SunTrack.note(at: rise - 30, solar: solar) == .untilSunrise(30))
        #expect(SunTrack.note(at: set - 87, solar: solar) == .untilSunset(87))
        #expect(SunTrack.note(at: set + 12, solar: solar) == .afterSunset(12))
        #expect(SunTrack.note(at: set, solar: solar) == .afterSunset(0))
        let polar = SolarDay(date: CivilDate(year: 2026, month: 6, day: 21), place: Self.murmansk)
        #expect(SunTrack.note(at: 600, solar: polar) == .polarDay)
        let night = SolarDay(date: CivilDate(year: 2026, month: 12, day: 21), place: Self.murmansk)
        #expect(SunTrack.note(at: 600, solar: night) == .polarNight)
    }
}
