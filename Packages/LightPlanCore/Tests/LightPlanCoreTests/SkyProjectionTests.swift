import Testing
import Foundation
import LightPlanCore

/// Проекция «азимут, высота → точка экрана» для слоя AR (шаг 29.8в). Чистая математика, без устройства:
/// всё, что на телефоне зависит от формулы, ловится здесь. Допуск положения — 0,5 pt: градус азимута на
/// экране 393 × 852 — около 12 pt, то есть сдвиг цели на 1° этот допуск не пропускает (проверено порчей).
struct SkyProjectionTests {

    static let screen = ScreenViewport(width: 393, height: 852)
    static let optics = CameraOptics(longSideFOV: 65, aspect: 4.0 / 3.0)
    static let tol = 0.5

    static func point(_ az: Double, _ alt: Double, aim: CameraBasis, optics: CameraOptics = SkyProjectionTests.optics,
                      viewport: ScreenViewport = SkyProjectionTests.screen) -> ScreenPoint? {
        SkyProjection.project(azimuth: az, altitude: alt, basis: aim, optics: optics, viewport: viewport)
    }

    // MARK: - Центр, края

    @Test("цель на оси камеры — ровно в центре кадра, на любом курсе и наклоне")
    func centre() throws {
        for (az, alt) in [(0.0, 0.0), (90, 30), (213.4, -20), (359.9, 70), (180, 0)] {
            let p = try #require(Self.point(az, alt, aim: CameraBasis(azimuth: az, altitude: alt)))
            #expect(abs(p.x - 196.5) < 1e-6 && abs(p.y - 426) < 1e-6, "az \(az) alt \(alt): \(p)")
        }
    }

    @Test("край кадра: цель на половине поля зрения по горизонтали и по вертикали лежит на кромке окна")
    func edges() throws {
        let aim = CameraBasis(azimuth: 120, altitude: 0)
        let fov = SkyProjection.visibleFOV(optics: Self.optics, viewport: Self.screen)
        // Камера на горизонте, цель по горизонтали сдвинута вдоль плоскости, перпендикулярной оси:
        // край кадра по ширине — угол, у которого tan = (W/2)/f; по большому кругу это не «половина поля»,
        // поэтому цель строится вектором, а не сложением азимутов.
        let f = SkyProjection.focalLength(optics: Self.optics, viewport: Self.screen)
        let halfW = atan(196.5 / f), halfH = atan(426 / f)
        #expect(abs(fov.horizontal - 2 * halfW * 180 / .pi) < 1e-9)
        #expect(abs(fov.vertical - 2 * halfH * 180 / .pi) < 1e-9)
        // Верх и низ кадра — по высоте (камера на горизонте: вертикаль экрана = высота над горизонтом).
        let top = try #require(Self.point(120, halfH * 180 / .pi, aim: aim))
        let bottom = try #require(Self.point(120, -halfH * 180 / .pi, aim: aim))
        #expect(abs(top.y - 0) < 1e-6 && abs(bottom.y - 852) < 1e-6)
        #expect(abs(top.x - 196.5) < 1e-6)
        // Левый и правый край: направление «вправо на halfW» от оси на горизонте — азимут + atan(tan(halfW)).
        let right = try #require(Self.point(120 + halfW * 180 / .pi, 0, aim: aim))
        let left = try #require(Self.point(120 - halfW * 180 / .pi, 0, aim: aim))
        #expect(abs(right.x - 393) < 1e-6 && abs(left.x - 0) < 1e-6)
        #expect(abs(right.y - 426) < 1e-6)
    }

    @Test("кадр заполняет окно: на высоком экране длинная сторона кадра идёт по высоте и видна целиком")
    func tallScreenShowsFullLongSide() {
        let fov = SkyProjection.visibleFOV(optics: Self.optics, viewport: Self.screen)
        #expect(abs(fov.vertical - 65) < 1e-9)
        #expect(fov.horizontal < 65 && fov.horizontal > 30)
    }

    @Test("окно шире кадра по пропорции: заполнение идёт по ширине, поле по высоте срезается")
    func wideWindowCropsHeight() {
        let wide = ScreenViewport(width: 400, height: 400)   // квадрат: короткая сторона кадра = ширина
        let fov = SkyProjection.visibleFOV(optics: Self.optics, viewport: wide)
        #expect(fov.vertical < 65)
        #expect(abs(fov.horizontal - fov.vertical) < 1e-9)
    }

    // MARK: - За камерой

    @Test("цель за спиной и сбоку у плоскости камеры — не рисуется")
    func behindCamera() {
        let aim = CameraBasis(azimuth: 90, altitude: 10)
        #expect(Self.point(270, -10, aim: aim) == nil)        // ровно позади
        #expect(Self.point(90 + 100, 10, aim: aim) == nil)    // 100° от оси
        #expect(Self.point(90 + 89, 10, aim: aim) == nil)     // глубже порога
        #expect(Self.point(90 + 60, 10, aim: aim) != nil)     // 60° от оси — перед камерой
    }

    @Test("взгляд в зенит: цель у горизонта позади, сам зенит — в центре")
    func zenith() throws {
        let aim = CameraBasis(azimuth: 0, altitude: 90)
        let z = try #require(Self.point(0, 90, aim: aim))
        #expect(abs(z.x - 196.5) < 1e-6 && abs(z.y - 426) < 1e-6)
        #expect(Self.point(0, -10, aim: aim) == nil)
    }

    // MARK: - Поле зрения

    @Test("поле зрения уже — та же цель дальше от центра; шире — ближе")
    func fieldOfView() throws {
        let aim = CameraBasis(azimuth: 0, altitude: 0)
        let wide = CameraOptics(longSideFOV: 80, aspect: 4.0 / 3.0)
        let narrow = CameraOptics(longSideFOV: 40, aspect: 4.0 / 3.0)
        let a = try #require(Self.point(10, 0, aim: aim, optics: wide))
        let b = try #require(Self.point(10, 0, aim: aim, optics: narrow))
        #expect(abs(b.x - 196.5) > abs(a.x - 196.5))
        // Ровно: смещение = f·tan(10°), f по формуле.
        for o in [wide, narrow] {
            let f = SkyProjection.focalLength(optics: o, viewport: Self.screen)
            let p = try #require(Self.point(10, 0, aim: aim, optics: o))
            #expect(abs(p.x - (196.5 + f * tan(10 * .pi / 180))) < 1e-6)
        }
        // Вертикаль экрана видит ровно longSideFOV.
        let f = SkyProjection.focalLength(optics: narrow, viewport: Self.screen)
        #expect(abs(2 * atan(426 / f) * 180 / .pi - 40) < 1e-9)
    }

    // MARK: - Поворот на 360°

    @Test("курс 0°, 360° и 720° дают одну картинку; через север цель в 20° от оси остаётся в 20° от оси")
    func fullTurn() throws {
        let base = try #require(Self.point(30, 15, aim: CameraBasis(azimuth: 10, altitude: 5)))
        for turn in [-360.0, 360, 720] {
            let p = try #require(Self.point(30 + turn, 15, aim: CameraBasis(azimuth: 10 + turn, altitude: 5)))
            #expect(abs(p.x - base.x) < 1e-6 && abs(p.y - base.y) < 1e-6)
        }
        // Камера на 350°, цель на 10°: 20° через север, вправо от оси.
        let across = try #require(Self.point(10, 0, aim: CameraBasis(azimuth: 350, altitude: 0)))
        let direct = try #require(Self.point(30, 0, aim: CameraBasis(azimuth: 10, altitude: 0)))
        #expect(abs(across.x - direct.x) < 1e-6 && abs(across.y - direct.y) < 1e-6)
        #expect(across.x > 196.5)
    }

    @Test("пока камеру ведут по кругу, цель на востоке обходит экран слева направо и пропадает за спиной")
    func sweep() {
        var seen: [Double] = []
        for heading in stride(from: 0.0, through: 360, by: 15) {
            if let p = Self.point(90, 0, aim: CameraBasis(azimuth: heading, altitude: 0)) { seen.append(p.x) }
        }
        // Камера поворачивается вправо: цель сдвигается влево, значит x убывает по мере поворота к востоку.
        let sorted = seen.sorted(by: >)
        #expect(!seen.isEmpty && seen.count < 25)
        #expect(sorted.first! > 196.5 && sorted.last! < 196.5)
    }

    // MARK: - Матрица поворота телефона

    /// Три оси устройства (вправо по экрану, вверх по экрану, из экрана к лицу) в системе отсчёта
    /// `xTrueNorthZVertical`: X — север, Y — запад, Z — вверх. Строки матрицы — оси устройства.
    static func rotation(x: (Double, Double, Double), y: (Double, Double, Double), z: (Double, Double, Double)) -> DeviceRotation {
        DeviceRotation(m11: x.0, m12: x.1, m13: x.2, m21: y.0, m22: y.1, m23: y.2, m31: z.0, m32: z.1, m33: z.2)
    }

    @Test("телефон лежит экраном вверх, верх экрана на север: камера смотрит вниз, право — восток, верх кадра — север")
    func flatOnTable() {
        let r = Self.rotation(x: (0, -1, 0), y: (1, 0, 0), z: (0, 0, 1))
        let b = CameraBasis(rotation: r)
        #expect(abs(b.aim.altitude + 90) < 1e-9)
        #expect(abs(b.right.east - 1) < 1e-12)
        #expect(abs(b.up.north - 1) < 1e-12)
    }

    @Test("телефон в портрете, камера на север / на восток / вверх на 30°: матрица даёт те же оси, что азимут и высота")
    func uprightPoses() {
        // На север: ось к лицу (z) смотрит на юг.
        let north = CameraBasis(rotation: Self.rotation(x: (0, -1, 0), y: (0, 0, 1), z: (-1, 0, 0)))
        #expect(abs(north.aim.azimuth - 0) < 1e-9 || abs(north.aim.azimuth - 360) < 1e-9)
        #expect(abs(north.aim.altitude) < 1e-9)
        // На восток: z — на запад, право экрана — юг.
        let east = CameraBasis(rotation: Self.rotation(x: (-1, 0, 0), y: (0, 0, 1), z: (0, 1, 0)))
        #expect(abs(east.aim.azimuth - 90) < 1e-9 && abs(east.aim.altitude) < 1e-9)
        #expect(abs(east.right.north + 1) < 1e-12)
        // Вверх на 30° на север: верх телефона откинут назад.
        let c = cos(30 * Double.pi / 180), s = sin(30 * Double.pi / 180)
        let tilted = CameraBasis(rotation: Self.rotation(x: (0, -1, 0), y: (-s, 0, c), z: (-c, 0, -s)))
        #expect(abs(tilted.aim.altitude - 30) < 1e-9)
        let direct = CameraBasis(azimuth: 0, altitude: 30)
        #expect(abs(tilted.right.east - direct.right.east) < 1e-12)
        #expect(abs(tilted.up.up - direct.up.up) < 1e-12 && abs(tilted.up.north - direct.up.north) < 1e-12)
    }

    @Test("крен: кадр по часовой на 90° — верх кадра смотрит вправо, мир поворачивается против часовой: цель над осью уезжает влево")
    func roll() throws {
        let level = CameraBasis(azimuth: 0, altitude: 0)
        let rolled = CameraBasis(azimuth: 0, altitude: 0, roll: 90)
        let before = try #require(Self.point(0, 10, aim: level))
        let after = try #require(Self.point(0, 10, aim: rolled))
        #expect(before.y < 426 && abs(before.x - 196.5) < 1e-6)
        #expect(after.x < 196.5 && abs(after.y - 426) < 1e-6)
        // Горизонт при крене в 90° — вертикальная линия: точки с высотой 0 по бокам оси остаются в одной колонке.
        let left = try #require(Self.point(-10, 0, aim: rolled))
        let right = try #require(Self.point(10, 0, aim: rolled))
        #expect(abs(left.x - right.x) < 1e-6 && left.y != right.y)
    }

    // MARK: - Порча

    @Test("порча: сдвиг азимута цели на 1° заметен — больше допуска положения")
    func oneDegreeIsVisible() throws {
        let aim = CameraBasis(azimuth: 200, altitude: 15)
        let truth = try #require(Self.point(210, 15, aim: aim))
        let shifted = try #require(Self.point(211, 15, aim: aim))
        let d = hypot(truth.x - shifted.x, truth.y - shifted.y)
        #expect(d > Self.tol, "1° = \(d) pt")
    }
}
