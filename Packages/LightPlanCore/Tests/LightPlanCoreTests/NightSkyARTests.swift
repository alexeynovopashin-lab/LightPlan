import Testing
import Foundation
import LightPlanCore

/// Луна и Млечный Путь слоя AR (шаг 29.8в.4): дуга луны, форма освещённой части, наклон кромки, полоса, стрелка.
struct NightSkyARTests {

    static let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    static let viewport = ScreenViewport(width: 393, height: 852)
    static let box = ScreenBox(minX: 16, minY: 120, maxX: 377, maxY: 640)

    // MARK: - Луна: дуга

    @Test("дуга луны: 145 точек через 10 минут; точка в полдень — то же число, что у MoonSample на ту же минуту")
    func moonArcMatchesCore() {
        let day = CivilDate(year: 2026, month: 10, day: 14)
        let arc = MoonTrack.arc(day: day, in: Self.tomsk)
        #expect(arc.count == 145)
        #expect(arc.first?.minutes == 0 && arc.last?.minutes == 1440)
        let noon = MoonSample(date: day, minutes: 720, place: Self.tomsk)
        #expect(arc[72].azimuth == noon.azimuth && arc[72].altitude == noon.altitude)
        // Выборка в одну минуту — тот же путь, что точка дуги.
        let one = MoonTrack.sample(day: day, minutes: 720, in: Self.tomsk)
        #expect(one == arc[72])
    }

    @Test("фаза метки — фаза ядра: доля и цикл те же, что у MoonPhase на ту же минуту")
    func phaseIsCores() {
        let day = CivilDate(year: 2026, month: 10, day: 14)
        let s = MoonTrack.sample(day: day, minutes: 1200, in: Self.tomsk)
        let core = MoonPhase(date: day, minutes: 1200, zone: Self.tomsk.zone)
        #expect(s.phase.fraction == core.fraction && s.phase.cycle == core.cycle)
    }

    // MARK: - Луна: форма диска

    private func area(_ pts: [ScreenPoint]) -> Double {
        guard pts.count > 2 else { return 0 }
        var a = 0.0
        for i in 0..<pts.count {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            a += p.x * q.y - q.x * p.y
        }
        return abs(a) / 2
    }

    @Test("пять фаз — пять разных форм: новая пуста, молодая — серп, четверть — половина, полная — весь диск, убывающая — своя; площадь = доле диска")
    func fiveShapes() {
        let shapes: [(String, Double)] = [("новая", 0.0), ("молодая", 0.12), ("первая четверть", 0.5),
                                          ("полная", 1.0), ("убывающая", 0.78)]
        let outlines = shapes.map { MoonDisc.litOutline(fraction: $0.1) }
        #expect(outlines[0].isEmpty)
        for (i, o) in outlines.enumerated() where i > 0 {
            #expect(abs(area(o) / Double.pi - shapes[i].1) < 0.02, "\(shapes[i].0): площадь \(area(o) / Double.pi)")
        }
        // Все формы попарно разные.
        for i in 0..<outlines.count {
            for j in (i + 1)..<outlines.count { #expect(outlines[i] != outlines[j], "\(shapes[i].0) = \(shapes[j].0)") }
        }
        // Четверть — терминатор прямой по центру (x = 0).
        let quarter = outlines[2]
        let half = quarter.count / 2
        #expect(quarter[half...].allSatisfy { abs($0.x) < 1e-9 })
        // Полная — терминатор лёг на левую кромку: левее центра есть точки у x = −1.
        #expect(outlines[3].contains { $0.x < -0.99 })
    }

    @Test("реальные сутки: доля освещённой части из ядра даёт форму той же площади; цикл от новой к полной — доля растёт")
    func realPhases() {
        var fractions: [Double] = []
        for d in 0..<30 {
            let day = CivilDate(year: 2026, month: 10, day: 1 + d % 30)
            let s = MoonTrack.sample(day: day, minutes: 720, in: Self.tomsk)
            fractions.append(s.phase.fraction)
            let o = MoonDisc.litOutline(fraction: s.phase.fraction)
            if s.phase.fraction >= 0.01 { #expect(abs(area(o) / Double.pi - s.phase.fraction) < 0.02) }
        }
        #expect(fractions.min()! < 0.1 && fractions.max()! > 0.9)
    }

    // MARK: - Луна: наклон кромки

    private func angle(moon: HorizontalPoint, sun: HorizontalPoint, aimAz: Double, aimAlt: Double) -> Double? {
        let basis = CameraBasis(azimuth: aimAz, altitude: aimAlt)
        return MoonLimb.brightLimbAngle(moon: moon, sun: sun, basis: basis, optics: .typical, viewport: Self.viewport)
    }

    @Test("светлая кромка смотрит на солнце: справа от луны — вправо, над ней — вверх, слева — влево")
    func limbPointsAtSun() throws {
        let moon = HorizontalPoint(altitude: 30, azimuth: 180)
        let right = try #require(angle(moon: moon, sun: HorizontalPoint(altitude: 30, azimuth: 200), aimAz: 180, aimAlt: 30))
        let up = try #require(angle(moon: moon, sun: HorizontalPoint(altitude: 55, azimuth: 180), aimAz: 180, aimAlt: 30))
        let left = try #require(angle(moon: moon, sun: HorizontalPoint(altitude: 30, azimuth: 160), aimAz: 180, aimAlt: 30))
        let deg = 180 / Double.pi
        #expect(abs(right * deg) < 8, "вправо: \(right * deg)")
        #expect(abs(up * deg - 90) < 3, "вверх: \(up * deg)")
        #expect(abs(abs(left * deg) - 180) < 8, "влево: \(left * deg)")
    }

    @Test("телефон наклонён на 30° по часовой: направление на солнце на экране поворачивается ровно на столько")
    func limbFollowsRoll() throws {
        let moon = HorizontalPoint(altitude: 20, azimuth: 180)
        let sun = HorizontalPoint(altitude: 20, azimuth: 195)
        let level = CameraBasis(azimuth: 180, altitude: 20)
        let rolled = CameraBasis(azimuth: 180, altitude: 20, roll: 30)
        let a0 = try #require(MoonLimb.brightLimbAngle(moon: moon, sun: sun, basis: level, optics: .typical, viewport: Self.viewport))
        let a1 = try #require(MoonLimb.brightLimbAngle(moon: moon, sun: sun, basis: rolled, optics: .typical, viewport: Self.viewport))
        // Наклон кадра по часовой — всё на экране поворачивается против: угол в оси «вверх» растёт на крен.
        var diff = (a1 - a0) * 180 / Double.pi
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        #expect(abs(abs(diff) - 30) < 1.5, "поворот \(diff)")
    }

    @Test("солнце и луна в одной точке — направления нет")
    func limbUndefinedWhenCoincide() {
        let p = HorizontalPoint(altitude: 10, azimuth: 90)
        #expect(angle(moon: p, sun: p, aimAz: 90, aimAlt: 10) == nil)
    }

    // MARK: - Млечный Путь

    @Test("ядро — MilkyWay.corePosition: тот же расчёт, второго нет; полоса — 121 точка ядра")
    func coreIsCores() {
        let day = CivilDate(year: 2026, month: 7, day: 20)
        let a = MilkyWayAR.core(day: day, minutes: 23 * 60, in: Self.tomsk)
        let b = MilkyWay.corePosition(date: day, minutes: 23 * 60, place: Self.tomsk)
        #expect(a == b)
        let band = MilkyWayAR.band(day: day, minutes: 23 * 60, in: Self.tomsk)
        #expect(band.count == MilkyWay.band.count && band.count == 121)
        // Края полосы — по разные стороны от оси: в точке ядра они не совпадают.
        #expect(band[0].left != band[0].right)
    }

    @Test("призрак днём: солнце выше −6° — 0,25; тёмное небо — полная")
    func ghostByDay() {
        #expect(MilkyWayAR.isGhost(sunAltitude: 20))
        #expect(MilkyWayAR.isGhost(sunAltitude: -5.9))
        #expect(!MilkyWayAR.isGhost(sunAltitude: -6.1))
        #expect(!MilkyWayAR.isGhost(sunAltitude: -30))
        #expect(MilkyWayAR.ghostOpacity == 0.25)
    }

    @Test("камера на ядро: ядро в центре кадра, полоса — многоугольник через весь экран; без Млечного Пути сцена пуста")
    func bandOnScreen() throws {
        let day = CivilDate(year: 2026, month: 7, day: 20)
        let core = MilkyWayAR.core(day: day, minutes: 23 * 60, in: Self.tomsk)
        let basis = CameraBasis(azimuth: core.azimuth, altitude: max(core.altitude, 5))
        let band = MilkyWayAR.band(day: day, minutes: 23 * 60, in: Self.tomsk)
        let scene = NightSkyARScene.make(basis: basis, optics: .typical, viewport: Self.viewport, moon: nil,
                                         milkyWay: .init(band: band, core: core, sunAltitude: -20))
        #expect(scene.milkyWayOn && !scene.skyGhost)
        #expect(!scene.band.isEmpty && scene.band.allSatisfy { $0.count >= 4 })
        let c = try #require(scene.core)
        if core.altitude >= 5 {
            #expect(abs(c.x - Self.viewport.width / 2) < 2 && abs(c.y - Self.viewport.height / 2) < 2)
        }
        let off = NightSkyARScene.make(basis: basis, optics: .typical, viewport: Self.viewport, moon: nil, milkyWay: nil)
        #expect(!off.milkyWayOn && off.band.isEmpty && off.core == nil && off.picked == nil && off.arc.isEmpty)
    }

    // MARK: - Сцена луны

    @Test("луна включена: метка и дуга есть, фаза метки — фаза ядра, призрак под горизонтом")
    func moonScene() throws {
        let day = CivilDate(year: 2026, month: 10, day: 14)
        let picked = MoonTrack.sample(day: day, minutes: 21 * 60, in: Self.tomsk)
        let sun = SunTrack.sample(day: day, minutes: 21 * 60, in: Self.tomsk)
        let basis = CameraBasis(azimuth: picked.azimuth, altitude: max(picked.apparentAltitude, 0))
        let scene = NightSkyARScene.make(
            basis: basis, optics: .typical, viewport: Self.viewport,
            moon: .init(arc: MoonTrack.arc(day: day, in: Self.tomsk), picked: picked, now: nil,
                        sunAtPicked: HorizontalPoint(altitude: sun.apparentAltitude, azimuth: sun.azimuth), sunAtNow: nil),
            milkyWay: nil)
        let mark = try #require(scene.picked)
        #expect(mark.illuminated == picked.phase.fraction)
        #expect(mark.waxing == (picked.phase.cycle < 0.5))
        #expect(mark.ghost == (picked.altitude < 0))
        #expect(mark.limbAngle != nil)
        #expect(scene.now == nil && !scene.arc.isEmpty)
    }

    // MARK: - Стрелка за краем

    @Test("светило в рамке — стрелки нет")
    func noPointerInside() {
        let b = CameraBasis(azimuth: 180, altitude: 30)
        // В центре и немного в стороне от него — оба в рамке.
        #expect(EdgePointing.pointer(azimuth: 180, altitude: 30, basis: b, optics: .typical, viewport: Self.viewport,
                                     box: Self.box) == nil)
        #expect(EdgePointing.pointer(azimuth: 190, altitude: 36, basis: b, optics: .typical, viewport: Self.viewport,
                                     box: Self.box) == nil)
    }

    @Test("светило справа за кадром — значок на правом краю рамки, стрелка вправо; слева — на левом")
    func pointerSides() throws {
        let b = CameraBasis(azimuth: 180, altitude: 30)
        // Камера смотрит на юг: право кадра — запад (270°).
        let r = try #require(EdgePointing.pointer(azimuth: 250, altitude: 30, basis: b, optics: .typical,
                                                  viewport: Self.viewport, box: Self.box))
        #expect(abs(r.point.x - Self.box.maxX) < 1e-6)
        #expect(abs(r.angle) < 0.6)
        let l = try #require(EdgePointing.pointer(azimuth: 110, altitude: 30, basis: b, optics: .typical,
                                                  viewport: Self.viewport, box: Self.box))
        #expect(abs(l.point.x - Self.box.minX) < 1e-6)
        #expect(abs(abs(l.angle) - Double.pi) < 0.6)
    }

    @Test("светило выше кадра — значок на верхнем краю, стрелка вверх; за спиной — стрелка есть и стоит на рамке")
    func pointerAboveAndBehind() throws {
        let b = CameraBasis(azimuth: 180, altitude: 10)
        let up = try #require(EdgePointing.pointer(azimuth: 180, altitude: 80, basis: b, optics: .typical,
                                                   viewport: Self.viewport, box: Self.box))
        #expect(abs(up.point.y - Self.box.minY) < 1e-6)
        #expect(abs(up.angle + Double.pi / 2) < 0.3)
        let behind = try #require(EdgePointing.pointer(azimuth: 0, altitude: 10, basis: b, optics: .typical,
                                                       viewport: Self.viewport, box: Self.box))
        let onEdge = abs(behind.point.x - Self.box.minX) < 1e-6 || abs(behind.point.x - Self.box.maxX) < 1e-6
            || abs(behind.point.y - Self.box.minY) < 1e-6 || abs(behind.point.y - Self.box.maxY) < 1e-6
        #expect(onEdge && Self.box.contains(behind.point))
    }
}
