import Testing
import Foundation
import ImageIO
import simd
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
#if os(iOS)
import UIKit
import Darwin
#endif

/// Млечный Путь панорамой на всю сферу (шаг 29.8в.20): панорамы Алексея `MW` / `MW2` в `MilkyWayData/pano_*.png`
/// (в репозиторий не кладутся — проверки по картинке пропускаются, если файла нет). Проверки числами:
/// (а) проекция: галактический центр и Денеб падают в те же азимут и высоту, что у дуги ядра и слоя «Звёзды»;
/// (б) картинка: ядро на центральном столбце, Большое Магелланово Облако справа от него (l растёт влево);
/// (в) кадр видеокарты совпадает с процессорным расчётом по той же картинке; (г) нет горизонта — под ним тоже светится;
/// (д) «Как в тёмном месте» и пол планирования; (е) память и время кадра. Числа печатаются строкой `PANO …`.
@MainActor
struct SunARMilkyWayPanoTests {

    private let sochi = Place(latitude: 43.585, longitude: 39.723, zone: ZoneID("Europe/Moscow")!)
    private let sydney = Place(latitude: -33.87, longitude: 151.21, zone: ZoneID("Australia/Sydney")!)
    private let aug15 = CivilDate(year: 2026, month: 8, day: 15)
    private let jun15 = CivilDate(year: 2026, month: 6, day: 15)
    private let phone = ScreenViewport(width: 440, height: 956)

    /// ICRS → галактические: матрица A_G каталога Hipparcos (не `MilkyWay.equatorial`), как в тестах Gaia.
    private static func galactic(raHours: Double, dec: Double) -> (l: Double, b: Double) {
        let a = raHours * 15 * .pi / 180, d = dec * .pi / 180
        let e = SIMD3(cos(d) * cos(a), cos(d) * sin(a), sin(d))
        let g = SIMD3(-0.0548755604 * e.x - 0.8734370902 * e.y - 0.4838350155 * e.z,
                      0.4941094279 * e.x - 0.4448296300 * e.y + 0.7469822445 * e.z,
                      -0.8676661490 * e.x - 0.1980763734 * e.y + 0.4559837762 * e.z)
        let l = atan2(g.y, g.x) * 180 / .pi
        return ((l + 360).truncatingRemainder(dividingBy: 360), asin(g.z) * 180 / .pi)
    }

    private func look(day: CivilDate, minutes: Minutes, place: Place, basis: CameraBasis, visibility: Double = 1,
                      dark: Bool = false) -> MilkyWayGaiaLook {
        let f = MilkyWayLook.frame(day: day, minutes: minutes, in: place)
        return MilkyWayGaiaLook(pixelToSky: MilkyWayLook.pixelToSky(basis: basis, optics: .typical, viewport: phone),
                                axes: [f.x, f.y, f.z].map { SIMD3($0.east, $0.north, $0.up) }, visibility: visibility, dark: dark)
    }

    /// Азимут и высота направления «восток, север, вверх».
    private static func azAlt(_ e: SIMD3<Double>) -> (az: Double, alt: Double) {
        let az = atan2(e.x, e.y) * 180 / .pi
        return ((az + 360).truncatingRemainder(dividingBy: 360), asin(min(max(e.z, -1), 1)) * 180 / .pi)
    }

    private static func angle(_ a: (az: Double, alt: Double), _ b: (az: Double, alt: Double)) -> Double {
        func v(_ p: (az: Double, alt: Double)) -> SIMD3<Double> {
            let az = p.az * .pi / 180, al = p.alt * .pi / 180
            return SIMD3(sin(az) * cos(al), cos(az) * cos(al), sin(al))
        }
        return acos(min(simd_dot(v(a), v(b)), 1)) * 180 / .pi
    }

    // MARK: - (а) проекция

    @Test("(а) карта панорамы: (l, b) = (0, 0) — центр картинки; l растёт влево (Денеб, l ≈ 84°, левее центра; БМО, l ≈ 280°, правее); b растёт вверх")
    func mapping() {
        let c = MilkyWayPano.uv(l: 0, b: 0)
        #expect(abs(c.u - 0.5) < 1e-12 && abs(c.v - 0.5) < 1e-12)
        let deneb = Self.galactic(raHours: 20.6905, dec: 45.2803)
        let du = MilkyWayPano.uv(l: deneb.l, b: deneb.b)
        #expect(abs(deneb.l - 84.3) < 0.3, "Денеб l = \(deneb.l)")
        #expect(du.u < 0.5 && abs(du.u - (0.5 - deneb.l / 360)) < 1e-12)
        let lmc = MilkyWayPano.uv(l: 280.5, b: -32.9)
        #expect(lmc.u > 0.5 && lmc.v > 0.5, "БМО: правее и ниже центра")
        #expect(abs(MilkyWayPano.uv(l: 359.9, b: 0).u - 0.5002778) < 1e-6 && abs(MilkyWayPano.uv(l: 0.1, b: 0).u - 0.4997222) < 1e-6)
        #expect(abs(MilkyWayPano.verticalSpan - 145.5) < 1e-9)
    }

    @Test("(а) галактический центр в кадре слоя — там же, где точка ядра на суточной дуге (az, высота): три места и даты, каждые 20 минут суток, не дальше 0,02°; Денеб — там же, где в слое «Звёзды», не дальше 0,1°")
    func coreAndDenebAtTrack() throws {
        var worst = 0.0, n = 0
        for (day, place) in [(aug15, sochi), (jun15, sydney), (CivilDate(year: 2026, month: 12, day: 21), sochi)] {
            for s in MilkyWayCoreTrack.arc(day: day, in: place, step: 20) {
                let f = MilkyWayLook.frame(day: day, minutes: s.minutes, in: place)
                let lk = look(day: day, minutes: s.minutes, place: place, basis: CameraBasis(azimuth: 0, altitude: 0))
                _ = f
                let p = Self.azAlt(lk.horizon(l: 0, b: 0))
                worst = max(worst, Self.angle(p, (s.azimuth, s.altitude)))
                n += 1
            }
        }
        // Денеб: ядро и звёзды разные коды (`MilkyWay` и `StarSkyAR`) — совпасть они обязаны.
        let catalog = StarCatalogAR.current
        let i = try #require(catalog.stars.firstIndex { $0.nameKey == "star.deneb" })
        let g = Self.galactic(raHours: catalog.stars[i].ra, dec: catalog.stars[i].dec)
        var worstDeneb = 0.0
        for (day, place) in [(aug15, sochi), (jun15, sydney)] {
            for minutes in stride(from: 0.0, to: 1440, by: 60) {
                let hp = StarSkyAR.horizontals(catalog: catalog, day: day, minutes: minutes, in: place)[i]
                let lk = look(day: day, minutes: minutes, place: place, basis: CameraBasis(azimuth: 0, altitude: 0))
                worstDeneb = max(worstDeneb, Self.angle(Self.azAlt(lk.horizon(l: g.l, b: g.b)), (hp.azimuth, hp.altitude)))
            }
        }
        print(String(format: "PANO a.track points=%d coreWorst=%.5f° denebWorst=%.5f° denebL=%.2f°", n, worst, worstDeneb, g.l))
        #expect(worst <= 0.02, "ядро: \(worst)°")
        #expect(worstDeneb <= 0.1, "Денеб: \(worstDeneb)°")
    }

    // MARK: - (б) картинка

    /// RGBA 8 бит файла панорамы (как его читает видеокарта) и размер.
    private static func pixels(_ name: String) -> (px: [UInt8], w: Int, h: Int)? {
        guard let url = MilkyWayPano.url(name), let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (px, w, h) : nil
    }

    private static func lum(_ p: (px: [UInt8], w: Int, h: Int), x: Int, y: Int) -> Double {
        let i = (y * p.w + x) * 4
        return (0.2126 * Double(p.px[i]) + 0.7152 * Double(p.px[i + 1]) + 0.0722 * Double(p.px[i + 2])) / 255
    }

    /// Средняя яркость в квадрате ±`r`° вокруг (l, b) по картинке.
    private static func windowMean(_ p: (px: [UInt8], w: Int, h: Int), l: Double, b: Double, r: Double) -> Double {
        let pxPerDeg = Double(p.w) / 360
        let uv = MilkyWayPano.uv(l: l, b: b)
        let cx = uv.u * Double(p.w), cy = uv.v * Double(p.h)
        let k = Int((r * pxPerDeg).rounded())
        var sum = 0.0, n = 0
        for dy in -k...k {
            for dx in -k...k {
                let y = Int(cy.rounded()) + dy
                guard y >= 0, y < p.h else { continue }
                let x = ((Int(cx.rounded()) + dx) % p.w + p.w) % p.w
                sum += lum(p, x: x, y: y); n += 1
            }
        }
        return sum / Double(max(n, 1))
    }

    @Test("(б) по картинке: ядро (l = 0, b = 0) — самое яркое место полосы на ±6° и ярче среднего по полосе в 2,5 раза; БМО (l = 280,5°, b = −32,9°) ярче своих отражений по l и по b вдвое", arguments: MilkyWayPano.names)
    func imageOrientation(name: String) throws {
        guard let p = Self.pixels(name) else { print("PANO b.image \(name) нет файла — пропуск"); return }
        let core = Self.windowMean(p, l: 0, b: 0, r: 2)
        var bestL = 0.0, best = 0.0, strip = 0.0, count = 0.0
        for l in stride(from: -180.0, to: 180, by: 2) {
            let v = Self.windowMean(p, l: l, b: 0, r: 2)
            strip += v; count += 1
            if v > best { best = v; bestL = l }
        }
        let lmc = Self.windowMean(p, l: 280.5, b: -32.9, r: 3)
        let flipL = Self.windowMean(p, l: 79.5, b: -32.9, r: 3)
        let flipB = Self.windowMean(p, l: 280.5, b: 32.9, r: 3)
        print(String(format: "PANO b.image %@ %dx%d core=%.3f stripMean=%.3f brightestL=%.0f° lmc=%.3f flipL=%.3f flipB=%.3f", name, p.w, p.h,
                     core, strip / count, bestL, lmc, flipL, flipB))
        #expect(abs(bestL) <= 6, "самый яркий участок полосы на l = \(bestL)°")
        #expect(core >= 2.5 * strip / count)
        #expect(lmc >= 2 * flipL && lmc >= 2 * flipB, "БМО: \(lmc) против \(flipL) (l зеркально) и \(flipB) (b зеркально)")
        // Края картинки: чёрные полосы сверху и снизу прозрачны (чёрное).
        #expect(Self.windowMean(p, l: 0, b: 70, r: 1) < 0.02 && Self.windowMean(p, l: 0, b: -70, r: 1) < 0.02)
    }

    // MARK: - (в) кадр видеокарты

    #if os(iOS)

    /// Кадр 90° × 60° с центром (l0, b0), верх — галактический север (оси как у `preview.py`).
    private func centeredLook(l0: Double, b0: Double, visibility: Double = 1, dark: Bool = false) -> (MilkyWayGaiaLook, CGSize) {
        let f = MilkyWayGaiaLook.unit(l: l0, b: b0)
        let r = simd_normalize(simd_cross(f, SIMD3(0, 0, 1)))
        let u = simd_cross(r, f)
        let to = simd_double3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1)))
        let from = simd_double3x3(columns: (r, u, f))
        let m = to * from.transpose
        let axes = [m * SIMD3(1, 0, 0), m * SIMD3(0, 1, 0), m * SIMD3(0, 0, 1)]
        let size = CGSize(width: 600, height: 600 * tan(Double.pi / 6))
        let focal = size.width / 2
        let basis = CameraBasis(forward: SkyVector(east: 0, north: 0, up: 1), right: SkyVector(east: 1, north: 0, up: 0),
                                up: SkyVector(east: 0, north: -1, up: 0))
        let cx = size.width / 2, cy = size.height / 2
        func row(_ k: KeyPath<SkyVector, Double>) -> [Double] {
            [basis.right[keyPath: k] / focal, -basis.up[keyPath: k] / focal,
             basis.forward[keyPath: k] - cx / focal * basis.right[keyPath: k] + cy / focal * basis.up[keyPath: k]]
        }
        return (MilkyWayGaiaLook(pixelToSky: row(\.east) + row(\.north) + row(\.up), axes: axes, visibility: visibility, dark: dark), size)
    }

    private func gpu(_ name: String) throws -> MilkyWayPanoGPU {
        try #require(MilkyWayPanoGPU.shared(name), "панорамы \(name) нет в приложении")
    }

    private static func frameLum(_ px: [UInt8], _ i: Int) -> Double {
        (0.0722 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.2126 * Double(px[i + 2])) / 255
    }

    private static func centerMean(_ r: (pixels: [UInt8], width: Int, height: Int), half: Int = 8) -> Double {
        var s = 0.0, n = 0.0
        for y in (r.height / 2 - half)..<(r.height / 2 + half) {
            for x in (r.width / 2 - half)..<(r.width / 2 + half) { s += frameLum(r.pixels, (y * r.width + x) * 4); n += 1 }
        }
        return s / n
    }

    @Test("(в) кадр видеокарты на (l, b) = (0, 0): центр яркий, а кадр на БМО (l = 280,5°) ярче кадра на зеркальной точке (l = 79,5°) в полтора раза — направление l в самом кадре", arguments: MilkyWayPano.names)
    func gpuOrientation(name: String) throws {
        guard MilkyWayPano.url(name) != nil else { return }
        let g = try gpu(name)
        func centre(_ l: Double, _ b: Double) throws -> Double {
            let (lk, size) = centeredLook(l0: l, b0: b)
            return Self.centerMean(try #require(g.render(lk, size: size, scale: 1)))
        }
        let core = try centre(0, 0), lmc = try centre(280.5, -32.9), mirror = try centre(79.5, -32.9), mirrorB = try centre(280.5, 32.9)
        print(String(format: "PANO c.gpu %@ core=%.3f lmc=%.3f mirrorL=%.3f mirrorB=%.3f", name, core, lmc, mirror, mirrorB))
        #expect(core >= 0.3)
        #expect(lmc >= 1.5 * mirror && lmc >= 1.5 * mirrorB)
    }

    /// Процессорный расчёт кадра по картинке: тот же луч, обратная рефракция, (l, b), билинейно по уровню 0.
    private func cpuFrame(_ p: (px: [UInt8], w: Int, h: Int), look lk: MilkyWayGaiaLook, size: CGSize) -> [Double] {
        let w = Int(size.width), h = Int(size.height)
        var out = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let s = MilkyWayLook.sky(at: ScreenPoint(x: Double(x) + 0.5, y: Double(y) + 0.5), matrix: lk.pixelToSky)
                let e = MilkyWayGaiaLook.geometric(SIMD3(s.east, s.north, s.up))
                let gx = simd_dot(e, lk.axes[0]), gy = simd_dot(e, lk.axes[1]), gz = simd_dot(e, lk.axes[2])
                let l = atan2(gy, gx) * 180 / .pi, b = asin(min(max(gz, -1), 1)) * 180 / .pi
                let uv = MilkyWayPano.uv(l: l, b: b)
                guard uv.v >= 0, uv.v <= 1 else { continue }
                let fx = uv.u * Double(p.w) - 0.5, fy = min(max(uv.v * Double(p.h) - 0.5, 0), Double(p.h - 1))
                let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down)), tx = fx - Double(x0), ty = fy - Double(y0)
                func at(_ xx: Int, _ yy: Int) -> Double { Self.lum(p, x: ((xx % p.w) + p.w) % p.w, y: min(yy, p.h - 1)) }
                out[y * w + x] = (at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx) * (1 - ty) + (at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx) * ty
            }
        }
        return out
    }

    private static func blocks(_ a: [Double], w: Int, h: Int, k: Int) -> [Double] {
        let bw = w / k, bh = h / k
        var o = [Double](repeating: 0, count: bw * bh)
        for y in 0..<(bh * k) { for x in 0..<(bw * k) { o[(y / k) * bw + x / k] += a[y * w + x] / Double(k * k) } }
        return o
    }

    private static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count), ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var sab = 0.0, saa = 0.0, sbb = 0.0
        for i in a.indices { let x = a[i] - ma, y = b[i] - mb; sab += x * y; saa += x * x; sbb += y * y }
        return sab / (saa * sbb).squareRoot()
    }

    @Test("(в) кадр видеокарты по сути тот же, что процессорный расчёт по картинке: корреляция яркости в блоках 6 × 6 пикселей ≥ 0,98, среднее расходится не больше чем на 10 %; кадр с телефона, ядро над Сиднеем, камера на юг с креном 20°", arguments: MilkyWayPano.names)
    func gpuMatchesCPU(name: String) throws {
        guard let p = Self.pixels(name) else { return }
        let g = try gpu(name)
        let minutes = 1320.0
        let core = MilkyWay.corePosition(date: jun15, minutes: minutes, place: sydney)
        let basis = CameraBasis(azimuth: core.azimuth + 15, altitude: SunTrack.apparent(altitude: core.altitude) - 10, roll: 20)
        let lk = look(day: jun15, minutes: minutes, place: sydney, basis: basis)
        let size = CGSize(width: phone.width, height: phone.height)
        let r = try #require(g.render(lk, size: size, scale: 1))
        let cpu = cpuFrame(p, look: lk, size: size)
        let gpuLum = (0..<(r.width * r.height)).map { Self.frameLum(r.pixels, $0 * 4) }
        let a = Self.blocks(gpuLum, w: r.width, h: r.height, k: 6), b = Self.blocks(cpu, w: r.width, h: r.height, k: 6)
        let rho = Self.pearson(a, b)
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        print(String(format: "PANO d.cpu %@ pearson=%.4f meanGPU=%.4f meanCPU=%.4f", name, rho, ma, mb))
        #expect(rho >= 0.98)
        #expect(abs(ma - mb) <= 0.1 * mb)
    }

    // MARK: - (г) нет горизонта

    @Test("(г) полоса не обрезана горизонтом: камера смотрит на ядро, лежащее ниже горизонта на 30°, и в центре кадра светло так же, как при том же направлении над горизонтом; горизонт — только линия", arguments: MilkyWayPano.names)
    func noHorizonClipping(name: String) throws {
        guard MilkyWayPano.url(name) != nil else { return }
        let g = try gpu(name)
        // Сочи, 15.08: ядро ниже горизонта около полудня; ищем минуту, где оно на −30° … −35°.
        let low = stride(from: 0.0, to: 1440, by: 10).map { ($0, MilkyWay.corePosition(date: aug15, minutes: $0, place: sochi)) }
            .first { $0.1.altitude < -30 && $0.1.altitude > -40 }
        let (m, core) = try #require(low)
        let basis = CameraBasis(azimuth: core.azimuth, altitude: SunTrack.apparent(altitude: core.altitude))
        let lk = look(day: aug15, minutes: m, place: sochi, basis: basis)
        let r = try #require(g.render(lk, size: CGSize(width: phone.width, height: phone.height), scale: 1))
        let below = Self.centerMean(r)
        let (ref, size) = centeredLook(l0: 0, b0: 0)
        let above = Self.centerMean(try #require(g.render(ref, size: size, scale: 1)))
        print(String(format: "PANO g.floor %@ coreAlt=%.1f° centreBelowHorizon=%.3f centreReference=%.3f", name, core.altitude, below, above))
        #expect(below >= 0.8 * above, "ниже горизонта \(below), эталон \(above)")
    }

    // MARK: - (д) яркость

    @Test("(д) «Как в тёмном месте» — полная яркость при любой видимости; без него яркость не ниже пола планирования и растёт с видимостью", arguments: MilkyWayPano.names)
    func brightness(name: String) throws {
        guard MilkyWayPano.url(name) != nil else { return }
        let g = try gpu(name)
        func core(visibility: Double, dark: Bool) throws -> Double {
            let (lk, size) = centeredLook(l0: 0, b0: 0, visibility: visibility, dark: dark)
            return Self.centerMean(try #require(g.render(lk, size: size, scale: 1)))
        }
        let full = try core(visibility: 1, dark: false), day = try core(visibility: 0, dark: false)
        let dayDark = try core(visibility: 0, dark: true), mid = try core(visibility: 0.75, dark: false)
        print(String(format: "PANO e.bright %@ full=%.3f mid(0.75)=%.3f day(0)=%.3f dayDark=%.3f floor=%.2f", name, full, mid, day, dayDark,
                     MilkyWayGaiaLook.planFloor))
        #expect(abs(dayDark - full) <= 0.02 * full)
        #expect(abs(day - MilkyWayGaiaLook.planFloor * full) <= 0.05 * full)
        #expect(mid >= day && mid <= full)
    }

    // MARK: - (е) память и время

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    @Test("(е) память и время кадра: текстура 4096 × 1655 с уменьшенными копиями ≈ 36 МБ; кадр экрана 440 × 956 pt при 3× — среднее по 60 кадрам; для сравнения — кадр Gaia (свечение + звёзды) на том же виде")
    func memoryAndFrameTime() throws {
        guard MilkyWayPano.url("mw2") != nil else { return }
        let before = Self.footprintMB()
        let g = try gpu("mw2")
        let after = Self.footprintMB()
        let basis = CameraBasis(azimuth: 180, altitude: 35)
        let lk = look(day: aug15, minutes: 1350, place: sochi, basis: basis)
        let size = CGSize(width: phone.width, height: phone.height)
        func time(_ body: () -> Void) -> Double {
            for _ in 0..<5 { body() }
            let t0 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<60 { body() }
            return (CFAbsoluteTimeGetCurrent() - t0) / 60 * 1000
        }
        let pano = time { _ = g.render(lk, size: size, scale: 3) }
        var gaiaMs = -1.0
        if let gaia = MilkyWayGaiaGPU.shared { gaiaMs = time { _ = gaia.render(lk, size: size, scale: 3) } }
        print(String(format: "PANO f.cost textureMB=%.1f footprintDelta=%.1fMB panoFrameMs=%.2f gaiaFrameMs=%.2f builds=%d", g.textureMB,
                     after - before, pano, gaiaMs, MilkyWayPanoGPU.builds))
        #expect(g.textureMB < 40)
    }

    @Test("нет файла панорамы — видеокарта не собирается, слой рисует запасную гладкую полосу")
    func missingFileFallsBack() {
        #expect(MilkyWayPanoGPU.shared("no_such_pano") == nil)
    }
    #endif
}
