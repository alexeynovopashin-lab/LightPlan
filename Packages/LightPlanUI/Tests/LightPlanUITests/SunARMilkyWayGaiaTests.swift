import Testing
import Foundation
import simd
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
#if os(iOS)
import UIKit
import Darwin
#endif

/// Млечный Путь из Gaia DR3 (шаг 29.8в.19; слово Алексея 20.10: «россыпь звезд и систем с реальными координатами…
/// Млечный путь — это не рисунок, это галактика»). Проверки шага числами: (а) звёзды Gaia ложатся туда же, куда слой
/// «Звёзды» кладёт звёзды каталога; (б) свечение лежит на месте — центр тяжести яркости кадра у ядра = центр тяжести
/// самой карты; (в) кадр 90° × 60° похож на образцы `Tools/milkyway_gaia/previews`; (г) «Как в тёмном месте» —
/// полная яркость; (д) на кадре не больше 80 тысяч звёзд; (е) данные читаются один раз; (ж) без данных — запасная
/// полоса. Числа печатаются строкой `GAIA …` — их берёт отчёт шага.
@MainActor
struct SunARMilkyWayGaiaTests {

    private let sochi = Place(latitude: 43.585, longitude: 39.723, zone: ZoneID("Europe/Moscow")!)
    private let sydney = Place(latitude: -33.87, longitude: 151.21, zone: ZoneID("Australia/Sydney")!)
    private let aug15 = CivilDate(year: 2026, month: 8, day: 15)
    private let jan15 = CivilDate(year: 2026, month: 1, day: 15)
    private let jun15 = CivilDate(year: 2026, month: 6, day: 15)
    private let phone = ScreenViewport(width: 440, height: 956)

    // MARK: - Независимые от приложения формулы (судья)

    /// ICRS → галактические: матрица A_G каталога Hipparcos (ESA 1997, т. 1, § 1.5.3) — не `MilkyWay.equatorial`.
    private static func galactic(raHours: Double, dec: Double) -> (l: Double, b: Double) {
        let a = raHours * 15 * .pi / 180, d = dec * .pi / 180
        let e = SIMD3(cos(d) * cos(a), cos(d) * sin(a), sin(d))
        let g = SIMD3(-0.0548755604 * e.x - 0.8734370902 * e.y - 0.4838350155 * e.z,
                      0.4941094279 * e.x - 0.4448296300 * e.y + 0.7469822445 * e.z,
                      -0.8676661490 * e.x - 0.1980763734 * e.y + 0.4559837762 * e.z)
        let l = atan2(g.y, g.x) * 180 / .pi
        return ((l + 360).truncatingRemainder(dividingBy: 360), asin(g.z) * 180 / .pi)
    }

    private func look(day: CivilDate, minutes: Minutes, place: Place, basis: CameraBasis,
                      optics: CameraOptics = .typical, viewport: ScreenViewport? = nil,
                      visibility: Double = 1, dark: Bool = false) -> MilkyWayGaiaLook {
        let f = MilkyWayLook.frame(day: day, minutes: minutes, in: place)
        return MilkyWayGaiaLook(pixelToSky: MilkyWayLook.pixelToSky(basis: basis, optics: optics, viewport: viewport ?? phone),
                                axes: [f.x, f.y, f.z].map { SIMD3($0.east, $0.north, $0.up) },
                                visibility: visibility, dark: dark)
    }

    private static func sky(_ v: SIMD3<Double>) -> SkyVector { SkyVector(east: v.x, north: v.y, up: v.z) }

    /// Точка середины полосы (l, b = 0) в осях горизонта.
    private static func along(_ f: MilkyWayLook.Frame, _ l: Double) -> SkyVector {
        let c = cos(l * .pi / 180), s = sin(l * .pi / 180)
        return SkyVector(east: f.x.east * c + f.y.east * s, north: f.x.north * c + f.y.north * s, up: f.x.up * c + f.y.up * s)
    }

    #if os(iOS)
    private func gpu() throws -> MilkyWayGaiaGPU { try #require(MilkyWayGaiaGPU.shared, "данные Gaia не прочитались") }

    /// Яркость пикселя кадра 0…1 (BGRA, предумноженный свет без подложки).
    private static func lum(_ px: [UInt8], _ i: Int) -> Double {
        (0.0722 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.2126 * Double(px[i + 2])) / 255
    }
    #endif

    // MARK: - (а) положение

    @Test("(а) десять ярких звёзд (Вега, Капелла, Арктур, Ригель, Бетельгейзе, Денеб, Альтаир, Процион, Регул, Спика) по цепочке Gaia ложатся на точки слоя «Звёзды» не дальше 0,1°: три места и даты, все часы, когда звезда над горизонтом, крен 15°")
    func namedStarsMatchStarLayer() throws {
        let catalog = StarCatalogAR.current
        let keys = ["star.vega", "star.capella", "star.arcturus", "star.rigel", "star.betelgeuse", "star.deneb",
                    "star.altair", "star.procyon", "star.regulus", "star.spica"]
        var worst = 0.0, worstAt = "", checks = 0, lowest = 90.0
        for key in keys {
            let i = try #require(catalog.stars.firstIndex { $0.nameKey == key }, "\(key) нет в каталоге")
            let s = catalog.stars[i]
            let g = Self.galactic(raHours: s.ra, dec: s.dec)
            var seen = 0
            for (day, place) in [(aug15, sochi), (jan15, sochi), (jun15, sydney)] {
                for minutes in stride(from: 0.0, to: 1440, by: 120) {
                    let positions = StarSkyAR.horizontals(catalog: catalog, day: day, minutes: minutes, in: place)
                    let hp = positions[i]
                    guard hp.altitude > 1 else { continue }
                    let basis = CameraBasis(azimuth: hp.azimuth + 9, altitude: min(hp.altitude + 6, 80), roll: 15)
                    let scene = StarSkyAR.make(catalog: catalog, positions: positions, sunAltitude: -30, basis: basis,
                                               optics: .typical, viewport: phone, stars: true, constellations: false)
                    guard let dot = scene.dots.first(where: { $0.index == i }) else { continue }
                    let lk = look(day: day, minutes: minutes, place: place, basis: basis)
                    let p = try #require(lk.screen(l: g.l, b: g.b))
                    let deg = hypot(p.x - dot.point.x, p.y - dot.point.y) / lk.focal * 180 / .pi
                    checks += 1; seen += 1
                    lowest = min(lowest, hp.altitude)
                    if deg > worst { worst = deg; worstAt = "\(key) \(day.month).\(day.day) \(Int(minutes)) мин, высота \(Int(hp.altitude))°" }
                }
            }
            #expect(seen > 0, "\(key): ни разу не над горизонтом")
        }
        print(String(format: "GAIA a.named checks=%d worst=%.4f° at %@ lowestAlt=%.1f°", checks, worst, worstAt, lowest))
        #expect(worst <= 0.1, "хуже всего \(worst)° — \(worstAt)")
    }

    @Test("(а) звёзды каталога слоя 3,5…5ᵐ есть в файле Gaia на тех же местах: ближайшая запись G ≤ 7 не дальше 0,1° у 90 % и больше")
    func catalogStarsInGaiaFile() throws {
        let data = try #require(MilkyWayGaia.shared)
        let end = data.prefix[70]
        var units: [SIMD3<Double>] = []
        units.reserveCapacity(end)
        for k in 0..<end { let s = data.star(k); units.append(MilkyWayGaiaLook.unit(l: s.l, b: s.b)) }
        var dists: [Double] = []
        for s in StarCatalogAR.current.stars where s.magnitude >= 3.5 && s.magnitude <= 5 {
            let g = Self.galactic(raHours: s.ra, dec: s.dec)
            let u = MilkyWayGaiaLook.unit(l: g.l, b: g.b)
            let best = units.reduce(-1.0) { max($0, simd_dot($1, u)) }
            dists.append(acos(min(best, 1)) * 180 / .pi)
        }
        dists.sort()
        let within = dists.filter { $0 <= 0.1 }.count
        let share = Double(within) / Double(max(dists.count, 1))
        print(String(format: "GAIA a.catalog stars=%d within0.1=%d share=%.3f median=%.4f° p90=%.4f°", dists.count, within, share,
                     dists[dists.count / 2], dists[dists.count * 9 / 10]))
        #expect(dists.count >= 30, "звёзд каталога 3,5…5ᵐ: \(dists.count)")
        #expect(share >= 0.9)
    }

    #if os(iOS)
    @Test("(а) видеокарта кладёт звезду Gaia туда же, куда CPU (`screen`, с рефракцией): уединённые звёзды 3,5…6ᵐ, центр тяжести пятна не дальше 0,1° и 1 pt; у горизонта тоже")
    func gpuStarsWhereCPUSays() throws {
        let gpu = try gpu()
        let data = gpu.data
        let scale: CGFloat = 2
        var worst = 0.0, n = 0, lowAlt = 90.0
        // Ночь Сочи на Лебедя (высоко) и на северо-запад у самого горизонта (там звёзд реже) (камера на 6°: рефракция до 0,4°).
        for (minutes, basis) in [(1350.0, CameraBasis(azimuth: Self.along(MilkyWayLook.frame(day: aug15, minutes: 1350, in: sochi), 80)
                                                         .horizontal.azimuth, altitude: 45)),
                                 (1290.0, CameraBasis(azimuth: 330, altitude: 6))] {
            let lk = look(day: aug15, minutes: minutes, place: sochi, basis: basis)
            let size = CGSize(width: phone.width, height: phone.height)
            let r = try #require(gpu.render(lk, size: size, scale: scale, glow: false))
            // Всё до G 9 в кадре — чтобы проверить, что у звезды нет соседей ближе 6 pt.
            var placed: [(p: CGPoint, g: Double, alt: Double)] = []
            for k in data.start..<data.prefix[90] {
                let s = data.star(k)
                guard let p = lk.screen(l: s.l, b: s.b), p.x > -8, p.y > -8, p.x < size.width + 8, p.y < size.height + 8 else { continue }
                let alt = asin(MilkyWayGaiaLook.apparent(lk.horizon(l: s.l, b: s.b)).z) * 180 / .pi
                placed.append((p, s.g, alt))
            }
            for (i, s) in placed.enumerated() where s.g <= 6 && s.alt > 1.5 {
                guard s.p.x > 10, s.p.y > 10, s.p.x < size.width - 10, s.p.y < size.height - 10 else { continue }
                let crowded = placed.enumerated().contains { j, o in j != i && hypot(o.p.x - s.p.x, o.p.y - s.p.y) < 6 }
                guard !crowded else { continue }
                var sw = 0.0, sx = 0.0, sy = 0.0
                let cx = Int(s.p.x * scale), cy = Int(s.p.y * scale)
                for y in (cy - 8)...(cy + 8) {
                    for x in (cx - 8)...(cx + 8) {
                        let w = Self.lum(r.pixels, (y * r.width + x) * 4)
                        sw += w; sx += w * (Double(x) + 0.5); sy += w * (Double(y) + 0.5)
                    }
                }
                guard sw > 0.05 else { continue }
                let dx = sx / sw / scale - s.p.x, dy = sy / sw / scale - s.p.y
                let pt = hypot(dx, dy)
                worst = max(worst, pt / lk.focal * 180 / .pi)
                #expect(pt <= 1, "звезда G \(s.g) на высоте \(s.alt)°: пятно в \(pt) pt от расчёта")
                n += 1
                lowAlt = min(lowAlt, s.alt)
            }
        }
        print(String(format: "GAIA a.gpu stars=%d worst=%.4f° lowestAlt=%.1f°", n, worst, lowAlt))
        #expect(n >= 20)
        #expect(worst <= 0.1)
    }

    // MARK: - (б) ядро

    @Test("(б) свечение на месте: центр тяжести яркости кадра в круге 3° у ядра не дальше 1° от corePosition (задание) и в кругах 3° и 10° — не дальше 0,2° от центра тяжести самой карты; в круге 10° до ядра ≈ 1,2°: облако Стрельца южнее плоскости")
    func coreCentroid() throws {
        let gpu = try gpu()
        let data = gpu.data
        let scale: CGFloat = 2
        // Сидней, 15.06, 22:00: ядро почти в зените — дымка у горизонта ни при чём.
        let minutes = 1320.0
        let core = MilkyWay.corePosition(date: jun15, minutes: minutes, place: sydney, time: .iau)
        let coreSeen = SkyVector(azimuth: core.azimuth, altitude: SunTrack.apparent(altitude: core.altitude))
        let basis = CameraBasis(azimuth: core.azimuth, altitude: SunTrack.apparent(altitude: core.altitude))
        let lk = look(day: jun15, minutes: minutes, place: sydney, basis: basis)
        let size = CGSize(width: phone.width, height: phone.height)
        let r = try #require(gpu.render(lk, size: size, scale: scale, stars: false))
        let fw = SIMD3(basis.forward.east, basis.forward.north, basis.forward.up)
        let c0 = SIMD3(coreSeen.east, coreSeen.north, coreSeen.up)
        for radius in [3.0, 10.0] {
            let cutoff = cos(radius * Double.pi / 180)
            var acc = SIMD3<Double>(0, 0, 0)
            for y in 0..<r.height {
                for x in 0..<r.width {
                    let s = MilkyWayLook.sky(at: ScreenPoint(x: (Double(x) + 0.5) / scale, y: (Double(y) + 0.5) / scale),
                                             matrix: lk.pixelToSky)
                    let e = SIMD3(s.east, s.north, s.up)
                    guard simd_dot(e, c0) >= cutoff else { continue }
                    let cosT = simd_dot(e, fw)
                    acc += Self.lum(r.pixels, (y * r.width + x) * 4) * cosT * cosT * cosT * e
                }
            }
            let frameC = simd_normalize(acc)
            // Та же сумма по самой карте (тон k·Y^γ, площадь ячейки ∝ cos b): галактическое → горизонт → видимая высота.
            var gal = SIMD3<Double>(0, 0, 0)
            let w = data.glowWidth, h = data.glowHeight
            for j in 0..<h {
                let b = 90 - (Double(j) + 0.5) * 180 / Double(h)
                guard abs(b) <= radius + 1 else { continue }
                for i in 0..<w {
                    var l = 180 - (Double(i) + 0.5) * 360 / Double(w)
                    if l < 0 { l += 360 }
                    let u = MilkyWayGaiaLook.unit(l: l, b: b)
                    guard u.x >= cutoff else { continue }
                    let o = (j * w + i) * 4
                    let y = (0.2126 * Double(data.glow[o]) + 0.7152 * Double(data.glow[o + 1]) + 0.0722 * Double(data.glow[o + 2])) / 65535
                    let t = min(MilkyWayGaiaLook.toneK * pow(max(y, 1e-12), MilkyWayGaiaLook.toneGamma), 1)
                    gal += t * cos(b * .pi / 180) * u
                }
            }
            let g = simd_normalize(gal)
            let mapC = MilkyWayGaiaLook.apparent(lk.axes[0] * g.x + lk.axes[1] * g.y + lk.axes[2] * g.z)
            let toMap = acos(min(simd_dot(frameC, mapC), 1)) * 180 / .pi
            let toCore = acos(min(simd_dot(frameC, c0), 1)) * 180 / .pi
            let mapL = atan2(g.y, g.x) * 180 / .pi, mapB = asin(g.z) * 180 / .pi
            print(String(format: "GAIA b.core radius=%.0f° frameToMap=%.3f° frameToCore=%.3f° mapCentroid l=%.2f° b=%.2f°", radius,
                         toMap, toCore, mapL, mapB))
            #expect(toMap <= 0.2, "круг \(radius)°: центр тяжести кадра в \(toMap)° от центра тяжести карты")
            if radius <= 3 { #expect(toCore <= 1, "круг \(radius)°: до corePosition \(toCore)°") }
        }
    }

    // MARK: - (в) сходство с образцами

    /// Прямолинейная проекция 90° × 60°, центр (l0, 0), верх кадра — галактический север, как `preview.py`. Небо
    /// поставлено так, что центр кадра в зените (всё поле выше 38°): дымка и горизонт ни при чём.
    private func previewLook(l0: Double) -> (MilkyWayGaiaLook, CGSize) {
        let lr = l0 * Double.pi / 180
        let f = SIMD3(cos(lr), sin(lr), 0)
        let r = simd_normalize(simd_cross(f, SIMD3(0, 0, 1)))
        let u = simd_cross(r, f)
        // Поворот галактика → «восток, север, вверх»: f → вверх, r → восток, u → юг (тройки одной руки).
        let to = simd_double3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1)))
        let from = simd_double3x3(columns: (r, u, f))
        let m = to * from.transpose
        let axes = [m * SIMD3(1, 0, 0), m * SIMD3(0, 1, 0), m * SIMD3(0, 0, 1)]
        let size = CGSize(width: 900, height: 900 * tan(Double.pi / 6))
        let focal = size.width / 2
        let basis = CameraBasis(forward: SkyVector(east: 0, north: 0, up: 1), right: SkyVector(east: 1, north: 0, up: 0),
                                up: SkyVector(east: 0, north: -1, up: 0))
        let cx = size.width / 2, cy = size.height / 2
        func row(_ k: KeyPath<SkyVector, Double>) -> [Double] {
            [basis.right[keyPath: k] / focal, -basis.up[keyPath: k] / focal,
             basis.forward[keyPath: k] - cx / focal * basis.right[keyPath: k] + cy / focal * basis.up[keyPath: k]]
        }
        return (MilkyWayGaiaLook(pixelToSky: row(\.east) + row(\.north) + row(\.up), axes: axes, visibility: 1, dark: false), size)
    }

    private static func previews() -> URL {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        return u.appending(path: "Tools/milkyway_gaia/previews")
    }

    /// Яркость → блоки 6 × 6 → Гаусс σ = 1 блок: одно сглаживание для обеих картинок.
    private static func smoothed(_ lum: [Double], w: Int, h: Int) -> [Double] {
        let bw = w / 6, bh = h / 6
        var a = [Double](repeating: 0, count: bw * bh)
        for y in 0..<(bh * 6) { for x in 0..<(bw * 6) { a[(y / 6) * bw + x / 6] += lum[y * w + x] / 36 } }
        let k = (-3...3).map { exp(-Double($0 * $0) / 2) }
        let ks = k.reduce(0, +)
        func pass(_ src: [Double], dx: Int, dy: Int) -> [Double] {
            var out = src
            for y in 0..<bh {
                for x in 0..<bw {
                    var s = 0.0
                    for (t, kv) in k.enumerated() {
                        let xx = min(max(x + (t - 3) * dx, 0), bw - 1), yy = min(max(y + (t - 3) * dy, 0), bh - 1)
                        s += kv * src[yy * bw + xx]
                    }
                    out[y * bw + x] = s / ks
                }
            }
            return out
        }
        return pass(pass(a, dx: 1, dy: 0), dx: 0, dy: 1)
    }

    private static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count), ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var sab = 0.0, saa = 0.0, sbb = 0.0
        for i in a.indices { let x = a[i] - ma, y = b[i] - mb; sab += x * y; saa += x * x; sbb += y * y }
        return sab / (saa * sbb).squareRoot()
    }

    @Test("(в) кадр приложения 90° × 60° на ядро, Лебедя (l = 80°) и Южный Крест (l = 303°) похож на образец: нормированная корреляция яркости после одного сглаживания ≥ 0,9", arguments: [
        ("view_core_l0.jpg", 0.0), ("view_cygnus_l80.jpg", 80.0), ("view_crux_l303.jpg", 303.0)])
    func matchesPreview(name: String, l0: Double) throws {
        let gpu = try gpu()
        let (lk, size) = previewLook(l0: l0)
        let url = Self.previews().appending(path: name)
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "нет \(url.path)")
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let w = img.width, h = img.height
        var ref = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(CGContext(data: &ref, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: img.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let r = try #require(gpu.render(lk, size: size, scale: CGFloat(w) / size.width))
        #expect(r.width == w && abs(r.height - h) <= 1, "кадр \(r.width)×\(r.height), образец \(w)×\(h)")
        let hh = min(h, r.height)
        var a = [Double](repeating: 0, count: w * hh), b = a
        for y in 0..<hh {
            for x in 0..<w {
                let o = (y * w + x) * 4
                a[y * w + x] = (0.2126 * Double(ref[o]) + 0.7152 * Double(ref[o + 1]) + 0.0722 * Double(ref[o + 2])) / 255
                b[y * w + x] = Self.lum(r.pixels, (y * r.width + x) * 4)
            }
        }
        let corr = Self.pearson(Self.smoothed(a, w: w, h: hh), Self.smoothed(b, w: w, h: hh))
        let raw = Self.pearson(a, b)
        let meanA = a.reduce(0, +) / Double(a.count), meanB = b.reduce(0, +) / Double(b.count)
        print(String(format: "GAIA c.%@ corr=%.4f raw=%.4f meanRef=%.4f meanApp=%.4f stars=%d", name, corr, raw, meanA, meanB, r.drawn))
        #expect(corr >= 0.9, "\(name): корреляция \(corr)")
    }

    // MARK: - (г) «Как в тёмном месте» и пол планирования

    @Test("(г) «Как в тёмном месте»: днём (видимость 0) яркость у ядра не ниже 90 % ночной; без флага днём — пол планирования, не ноль")
    func darkSiteFullBrightness() throws {
        let gpu = try gpu()
        let minutes = 1320.0
        let core = MilkyWay.corePosition(date: jun15, minutes: minutes, place: sydney, time: .iau)
        let basis = CameraBasis(azimuth: core.azimuth, altitude: core.altitude)
        let size = CGSize(width: phone.width, height: phone.height)
        func coreSum(visibility: Double, dark: Bool) throws -> Double {
            let lk = look(day: jun15, minutes: minutes, place: sydney, basis: basis, visibility: visibility, dark: dark)
            let r = try #require(gpu.render(lk, size: size, scale: 1))
            var s = 0.0
            for y in (r.height / 2 - 80)..<(r.height / 2 + 80) {
                for x in (r.width / 2 - 80)..<(r.width / 2 + 80) { s += Self.lum(r.pixels, (y * r.width + x) * 4) }
            }
            return s
        }
        let night = try coreSum(visibility: 1, dark: false)
        let dayDark = try coreSum(visibility: 0, dark: true)
        let dayPlan = try coreSum(visibility: 0, dark: false)
        print(String(format: "GAIA d.dark night=%.1f dayDark=%.1f (%.3f) dayPlan=%.1f (%.3f)", night, dayDark, dayDark / night,
                     dayPlan, dayPlan / night))
        #expect(dayDark >= 0.9 * night)
        #expect(dayPlan >= 0.3 * night, "днём без флага полоса гаснет ниже пола: \(dayPlan / night)")
        #expect(dayPlan < 0.9 * night, "без флага днём не тусклее ночи: \(dayPlan / night)")
    }

    @Test("(г) тон «скромно»: k·Y^0,7, ядро карты (99,9-й перцентиль в |l|, |b| ≤ 10°) ≈ 0,6; контраст полосы к соседнему небу (b 20…30°) у ядра не выше 6 : 1")
    func modestTone() throws {
        let data = try #require(MilkyWayGaia.shared)
        let w = data.glowWidth, h = data.glowHeight
        func toned(_ i: Int, _ j: Int) -> Double {
            let o = (j * w + ((i % w) + w) % w) * 4
            let y = (0.2126 * Double(data.glow[o]) + 0.7152 * Double(data.glow[o + 1]) + 0.0722 * Double(data.glow[o + 2])) / 65535
            return min(MilkyWayGaiaLook.toneK * pow(max(y, 1e-12), MilkyWayGaiaLook.toneGamma), 1)
        }
        func col(_ l: Double) -> Int { Int(((0.5 - l / 360).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * Double(w)) }
        func row(_ b: Double) -> Int { min(h - 1, Int((0.5 - b / 180) * Double(h))) }
        var core: [Double] = []
        for j in row(10)...row(-10) { for l in stride(from: -10.0, through: 10, by: 0.25) { core.append(toned(col(l), j)) } }
        core.sort()
        let p999 = core[Int(Double(core.count - 1) * 0.999)]
        // Контраст по столбцам |l| ≤ 5°: полоса |b| < 3° против неба 20…30° по обе стороны.
        var band = 0.0, nb = 0.0, side = 0.0, ns = 0.0
        for l in stride(from: -5.0, through: 5, by: 0.25) {
            let i = col(l)
            for j in row(3)...row(-3) { band += toned(i, j); nb += 1 }
            for j in row(30)...row(20) { side += toned(i, j); ns += 1 }
            for j in row(-20)...row(-30) { side += toned(i, j); ns += 1 }
        }
        let contrast = (band / nb) / (side / ns)
        print(String(format: "GAIA d.tone core999=%.3f contrast=%.2f", p999, contrast))
        #expect(abs(p999 - 0.6) <= 0.08, "ядро \(p999)")
        #expect(contrast <= 6, "контраст полосы \(contrast)")
    }

    // MARK: - (д) бюджет звёзд

    @Test("(д) на кадре не больше 80 тысяч звёзд: 12 направлений вдоль полосы в Сочи и ядро в зените Сиднея, экраны 17 Pro Max и SE; широкий кадр 120° режет слабейшие")
    func starBudget() throws {
        let data = try #require(MilkyWayGaia.shared)
        var units: [SIMD3<Double>] = []
        units.reserveCapacity(data.count)
        for k in 0..<data.count { let s = data.star(k); units.append(MilkyWayGaiaLook.unit(l: s.l, b: s.b)) }
        func exact(_ lk: MilkyWayGaiaLook, _ size: CGSize, end: Int) -> Int {
            let m = lk.galacticToScreen
            var n = 0
            for k in data.start..<end {
                let q = m * units[k]
                guard q.z > 1e-6 else { continue }
                let x = q.x / q.z, y = q.y / q.z
                guard x >= 0, y >= 0, x <= size.width, y <= size.height else { continue }
                if simd_dot(lk.axes[0] * units[k].x + lk.axes[1] * units[k].y + lk.axes[2] * units[k].z, SIMD3(0, 0, 1)) > 0 { n += 1 }
            }
            return n
        }
        var worst = 0, worstEstimate = 0, wideLimit = 99.0, wideCount = 0
        let screens = [ScreenViewport(width: 440, height: 956), ScreenViewport(width: 375, height: 667)]
        for vp in screens {
            for l in stride(from: 0.0, to: 360, by: 30) {
                let f = MilkyWayLook.frame(day: aug15, minutes: 1350, in: sochi)
                let hz = Self.along(f, l).horizontal
                let basis = CameraBasis(azimuth: hz.azimuth, altitude: max(hz.altitude, 10))
                let lk = look(day: aug15, minutes: 1350, place: sochi, basis: basis, viewport: vp)
                let size = CGSize(width: vp.width, height: vp.height)
                let range = data.drawRange(lk, size: size)
                let n = exact(lk, size, end: range.end)
                worst = max(worst, n); worstEstimate = max(worstEstimate, range.visible)
            }
            let core = MilkyWay.corePosition(date: jun15, minutes: 1320, place: sydney, time: .iau)
            let lk = look(day: jun15, minutes: 1320, place: sydney, basis: CameraBasis(azimuth: core.azimuth, altitude: core.altitude),
                          viewport: vp)
            let size = CGSize(width: vp.width, height: vp.height)
            let range = data.drawRange(lk, size: size)
            worst = max(worst, exact(lk, size, end: range.end)); worstEstimate = max(worstEstimate, range.visible)
            // Широкий кадр 120° на ядро: бюджет режет слабейшие.
            let wide = look(day: jun15, minutes: 1320, place: sydney, basis: CameraBasis(azimuth: core.azimuth, altitude: core.altitude),
                            optics: CameraOptics(longSideFOV: 120, aspect: 4.0 / 3.0), viewport: vp)
            let wr = data.drawRange(wide, size: size)
            let wn = exact(wide, size, end: wr.end)
            wideLimit = min(wideLimit, wr.gLimit); wideCount = max(wideCount, wn)
            #expect(wn <= MilkyWayGaia.budget, "широкий кадр: \(wn)")
        }
        print("GAIA e.budget phoneWorst=\(worst) estimateWorst=\(worstEstimate) wideWorst=\(wideCount) wideGLimit=\(wideLimit)")
        #expect(worst <= MilkyWayGaia.budget)
        #expect(wideLimit < 10, "широкий кадр не урезан: предел G \(wideLimit)")
    }

    // MARK: - (е) память

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    @Test("(е) данные и видеокарта собираются один раз; 40 входов и выходов холста Gaia (окно с холстом создаётся, рисует кадр и уходит) не копят память больше 8 МБ")
    func loadedOnceNoLeak() throws {
        let gpu = try gpu()
        let minutes = 1350.0
        let basis = CameraBasis(azimuth: 180, altitude: 25)
        let lk = look(day: aug15, minutes: minutes, place: sochi, basis: basis)
        func cycle() {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: phone.width, height: phone.height))
            let host = UIHostingController(rootView: SunARGaiaSkyView(gpu: gpu, look: lk).frame(width: phone.width, height: phone.height))
            window.rootViewController = host
            window.isHidden = false
            host.view.layoutIfNeeded()
            window.isHidden = true
            window.rootViewController = nil
        }
        for _ in 0..<5 { autoreleasepool { cycle() } }
        gpu.queue.makeCommandBuffer().map { $0.commit(); $0.waitUntilCompleted() }
        let before = Self.footprintMB()
        for _ in 0..<40 { autoreleasepool { cycle() } }
        gpu.queue.makeCommandBuffer().map { $0.commit(); $0.waitUntilCompleted() }
        let after = Self.footprintMB()
        _ = MilkyWayGaia.shared; _ = MilkyWayGaiaGPU.shared
        print(String(format: "GAIA f.memory loads=%d builds=%d before=%.1fMB after=%.1fMB delta=%.1fMB", MilkyWayGaia.loads,
                     MilkyWayGaiaGPU.builds, before, after, after - before))
        #expect(MilkyWayGaia.loads == 1)
        #expect(MilkyWayGaiaGPU.builds == 1)
        #expect(after - before <= 8, "память выросла на \(after - before) МБ за 40 входов")
    }
    #endif

    // MARK: - (ж) без данных

    @Test("(ж) нет файлов или они испорчены — данных нет (`nil`), слой рисует запасную полосу формулы; строки «Слоёв» говорят «по формуле» без кредита")
    func fallbackWithoutData() throws {
        let fm = FileManager.default
        let src = try #require(Bundle.module.url(forResource: "MilkyWayData", withExtension: nil, subdirectory: nil)
                                ?? MilkyWayGaiaTestsBundle.dataDirectory, "нет MilkyWayData в пакете")
        let root = fm.temporaryDirectory.appending(path: "gaia-fallback-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func copy(_ name: String) throws -> URL {
            let d = root.appending(path: name)
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            for f in ["stars_gaia.bin", "milkyway_glow_gaia.png", "spec.json"] {
                try fm.copyItem(at: src.appending(path: f), to: d.appending(path: f))
            }
            return d
        }
        #expect(MilkyWayGaia.load(directory: try copy("whole")) != nil, "целая копия читается")
        let empty = root.appending(path: "empty")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(MilkyWayGaia.load(directory: empty) == nil, "пустая папка")
        let noPNG = try copy("noPNG")
        try fm.removeItem(at: noPNG.appending(path: "milkyway_glow_gaia.png"))
        #expect(MilkyWayGaia.load(directory: noPNG) == nil, "без карты")
        let cut = try copy("cut")
        let bin = cut.appending(path: "stars_gaia.bin")
        try Data(try Data(contentsOf: bin).prefix(1000)).write(to: bin)
        #expect(MilkyWayGaia.load(directory: cut) == nil, "обрезанный файл звёзд")
        let magic = try copy("magic")
        var d = try Data(contentsOf: magic.appending(path: "stars_gaia.bin"))
        d[0] = UInt8(ascii: "X")
        try d.write(to: magic.appending(path: "stars_gaia.bin"))
        #expect(MilkyWayGaia.load(directory: magic) == nil, "чужой файл")

        // Запасной вариант на экране: источник «формула» → строки «Слоёв» без Gaia.
        let lex = Lexicon("ru")
        let plan = MilkyWayPlan(day: aug15, place: sochi)
        let eye = MilkyWayLook.eyeNote(sunAltitude: -30, moonAltitude: -10, moonFraction: 0, glow: 0, coreAltitude: 20)
        let clock = ClockText(language: "ru", preference: .h24)
        let formula = SunARMilkyWayNotes.lines(plan: plan, eye: eye, clock: clock, lexicon: lex, gaia: false)
        let gaia = SunARMilkyWayNotes.lines(plan: plan, eye: eye, clock: clock, lexicon: lex, gaia: true)
        #expect(formula.last == lex.t("ar.mwFormula"))
        #expect(!formula.joined().contains("ESA"))
        #expect(gaia.contains(lex.t("ar.mwGaia")) && gaia.joined().contains("ESA, Gaia DPAC"))
    }
}

/// Папка данных рядом с исходниками (на случай, если пакет тестов не видит ресурсов модуля).
enum MilkyWayGaiaTestsBundle {
    static var dataDirectory: URL? {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { u.deleteLastPathComponent() }
        let d = u.appending(path: "Sources/LightPlanUI/MilkyWayData")
        return FileManager.default.fileExists(atPath: d.path) ? d : nil
    }
}
