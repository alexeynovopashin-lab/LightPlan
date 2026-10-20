import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Картина Млечного Пути в AR (шаг 29.8в.14, ревью к 25efebf): рисуется без многоугольников полосы, ширина шейдера —
/// ширина ядра (`MilkyWay.halfWidth`), засветка старого места после смены места не пишется. Рисует тот же код, что
/// идёт на экран (`SunARMilkyWayCanvas`), через `ImageRenderer`; числа — по пикселям.
@MainActor
struct SunARMilkyWayTests {

    private let size = CGSize(width: 440, height: 956)
    private let scale: CGFloat = 2

    private struct Pixels {
        let w: Int, h: Int
        let rgba: [UInt8]
        let scale: CGFloat
        /// Зелёный канал в точке окна (pt).
        func green(_ x: Double, _ y: Double) -> Double? {
            let i = Int((x * Double(scale)).rounded(.down)), j = Int((y * Double(scale)).rounded(.down))
            guard i >= 0, j >= 0, i < w, j < h else { return nil }
            return Double(rgba[(j * w + i) * 4 + 1])
        }
    }

    private func render(_ view: some View) throws -> Pixels {
        let content = ZStack(alignment: .topLeading) { Color.black; view }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: content)
        r.scale = scale
        let img = try #require(r.cgImage)
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Pixels(w: w, h: h, rgba: buf, scale: scale)
    }

    private struct Night {
        let place: Place
        let day: CivilDate
        let minutes: Minutes
    }

    /// Ночи без луны и засветки (те же, что у `MilkyWayLookTests` и `ar_milkyway.py`).
    private let nights = [
        Night(place: Place(latitude: 43.585, longitude: 39.723, zone: ZoneID("Europe/Moscow")!),
              day: CivilDate(year: 2026, month: 8, day: 15), minutes: 1350),
        Night(place: Place(latitude: -33.87, longitude: 151.21, zone: ZoneID("Australia/Sydney")!),
              day: CivilDate(year: 2026, month: 6, day: 15), minutes: 1320),
        Night(place: Place(latitude: -0.18, longitude: -78.47, zone: ZoneID("America/Guayaquil")!),
              day: CivilDate(year: 2026, month: 7, day: 13), minutes: 1260),
        Night(place: Place(latitude: 64.15, longitude: -21.94, zone: ZoneID("Atlantic/Reykjavik")!),
              day: CivilDate(year: 2026, month: 11, day: 10), minutes: 1320),
    ]

    /// Где точка галактики над головой в эту ночь.
    private func sky(_ l: Degrees, _ b: Degrees, _ n: Night) -> HorizontalPoint {
        let d = Sky.days(date: n.day, minutes: n.minutes, utcOffsetHours: n.place.zone.utcOffsetHours(on: n.day))
        return SkyFrame(days: d, latitude: n.place.latitude, longitude: n.place.longitude).horizontal(j2000: MilkyWay.equatorial(galacticLongitude: l, galacticLatitude: b))
    }

    /// Сцена с Млечным Путём, камера на точку (l, 0); `band` можно подменить (пусто — многоугольников нет).
    private func scene(_ n: Night, aim l: Degrees, optics: CameraOptics, emptyBand: Bool = false)
        -> (NightSkyARScene, CameraBasis) {
        let aim = sky(l, 0, n)
        let basis = CameraBasis(azimuth: aim.azimuth, altitude: aim.altitude)
        let band = emptyBand ? [] : MilkyWayAR.band(day: n.day, minutes: n.minutes, in: n.place)
        let input = NightSkyARScene.MilkyWayInput(
            band: band, core: MilkyWayAR.core(day: n.day, minutes: n.minutes, in: n.place), sunAltitude: -40,
            frame: MilkyWayLook.frame(day: n.day, minutes: n.minutes, in: n.place), glow: 0,
            center: MilkyWayAR.center(day: n.day, minutes: n.minutes, in: n.place))
        let viewport = ScreenViewport(width: size.width, height: size.height)
        return (NightSkyARScene.make(basis: basis, optics: optics, viewport: viewport, moon: nil, milkyWay: input), basis)
    }

    // MARK: 1. Без многоугольников полосы

    @Test("камера в середине полосы, края за кадром, многоугольников нет — картина рисуется: середина ярче фона")
    func drawsWithoutBandPolygons() throws {
        let n = nights[0]
        // Узкое поле зрения (10°): края полосы (±11,5° у ядра) за кадром.
        let narrow = CameraOptics(longSideFOV: 10, aspect: 4.0 / 3.0)
        let (s, _) = scene(n, aim: 20, optics: narrow, emptyBand: true)
        #expect(s.band.isEmpty)
        let pic = try #require(s.milkyWayPicture)
        #expect(pic.visibility.isVisible)
        let px = try render(SunARMilkyWayCanvas(scene: s, parts: .smooth).frame(width: size.width, height: size.height))
        // Фон — чёрная подложка (0). Узкое поле — полоса на весь кадр, поэтому сравнение с нулём и с формулой:
        // 255 · зелёный тон (0,80…0,84) · smooth(l, b) · 0,55 в середине кадра.
        let mid = try #require(px.green(size.width / 2, size.height / 2))
        let back = try render(Color.clear.frame(width: size.width, height: size.height))
        let empty = try #require(back.green(size.width / 2, size.height / 2))
        let g = pic.frame.galactic(MilkyWayLook.sky(at: ScreenPoint(x: size.width / 2, y: size.height / 2),
                                                    matrix: pic.pixelToSky))
        let expected = 255 * 0.82 * MilkyWayLook.smooth(l: g.l, b: g.b) * MilkyWayLook.peakAlpha
        #expect(empty == 0)
        #expect(mid > empty + 20, "середина полосы \(mid), фон \(empty)")
        #expect(abs(mid - expected) < 0.1 * expected, "середина \(mid), по формуле \(expected)")
    }

    // MARK: 2. Ширина шейдера — ширина ядра

    @Test("ширина профиля шейдера по b — MilkyWayLook.sigma (край MilkyWay.halfWidth) на пяти долготах, ≤ 2 %",
          arguments: [30.0, 60.0, 120.0, 180.0, 300.0])
    func widthMatchesCore(_ l: Degrees) throws {
        let sigma = MilkyWayLook.sigma(l)
        // Ночь, где точка выше всего: ±2σ поперёк полосы не уходят в дымку у горизонта (8°).
        let n = try #require(nights.max { sky(l, 0, $0).altitude < sky(l, 0, $1).altitude })
        #expect(sky(l, 0, n).altitude - 2 * sigma > MilkyWayDust.haze + 1, "l \(l): точка низко")
        let wide = CameraOptics(longSideFOV: 100, aspect: 4.0 / 3.0)
        let (s, basis) = scene(n, aim: l, optics: wide)
        let px = try render(SunARMilkyWayCanvas(scene: s, parts: .smooth).frame(width: size.width, height: size.height))
        let viewport = ScreenViewport(width: size.width, height: size.height)
        // Поперёк полосы по меридиану галактики: точка (l, b) → небо → экран тем же путём, что полоса ядра.
        var samples: [(b: Double, g: Double)] = []
        for k in -40...40 {
            let b = Double(k) * 0.05 * sigma
            let h = sky(l, b, n)
            guard let p = SkyProjection.project(azimuth: h.azimuth, altitude: h.altitude, basis: basis, optics: wide,
                                                viewport: viewport),
                  let g = px.green(p.x, p.y) else { continue }
            samples.append((b, g))
        }
        #expect(samples.count > 70)
        let peak = try #require(samples.map(\.g).max())
        #expect(peak > 15, "l \(l): вершина \(peak)")
        // σ по наклону ln g от b²: ln g = ln g0 − b² / (2σ²); точки ярче 20 % вершины.
        let fit = samples.filter { $0.g > 0.2 * peak }
        let xs: [Double] = fit.map { $0.b * $0.b }
        let ys: [Double] = fit.map { log($0.g) }
        let mx: Double = xs.reduce(0, +) / Double(xs.count)
        let my: Double = ys.reduce(0, +) / Double(ys.count)
        var sxy = 0.0, sxx = 0.0
        for (x, y) in zip(xs, ys) { sxy += (x - mx) * (y - my); sxx += (x - mx) * (x - mx) }
        let slope = sxy / sxx
        let measured = (-1 / (2 * slope)).squareRoot()
        let err = abs(measured - sigma) / sigma
        print(String(format: "SunARMilkyWayTests: l %.0f° — σ шейдера %.3f°, ядра %.3f°, расхождение %.2f %%", l, measured, sigma, err * 100))
        #expect(err <= 0.02, "l \(l): σ шейдера \(measured)°, ядра \(sigma)° (край \(MilkyWay.halfWidth(galacticLongitude: l))°)")
    }

    @Test("таблица σ для шейдера — MilkyWayLook.sigma в узлах и между ними (≤ 0,002°)")
    func sigmaTable() {
        let t = MilkyWaySkyShader.sigmaTable
        #expect(t.count == 121)
        #expect(abs(Double(t[0]) - MilkyWayLook.sigma(0)) < 1e-5 && abs(Double(t[120]) - MilkyWayLook.sigma(0)) < 1e-5)
        var worst = 0.0
        for k in 0..<3600 {
            let l = Double(k) / 10
            let x = l / MilkyWaySkyShader.sigmaStep, i = Int(x)
            let v = Double(t[i]) + (Double(t[i + 1]) - Double(t[i])) * (x - Double(i))
            worst = max(worst, abs(v - MilkyWayLook.sigma(l)))
        }
        #expect(worst <= 0.002, "между узлами расходится на \(worst)°")
    }

    // MARK: 3. Засветка при смене места

    private final class MemoryBodies: ARBodiesSettings {
        var moon = false
        var milkyWay = true
        var stars = false
        var constellations = false
        var planets = false
    }
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }

    /// Ответ атласа, который приходит, когда тест скажет.
    @MainActor private final class Gate {
        private var waiting: CheckedContinuation<Void, Never>?
        private var open = false
        var asked: [Place] = []
        func wait() async {
            if open { return }
            await withCheckedContinuation { waiting = $0 }
        }
        func release() { open = true; waiting?.resume(); waiting = nil }
    }

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    private let barnaul = Place(latitude: 53.3548, longitude: 83.7698, zone: ZoneID("Asia/Barnaul")!)

    private func model() -> SunARModel {
        let m = Moment(ISO8601DateFormatter().date(from: "2026-08-20T17:00:00Z")!)
        return SunARModel(target: SunARTarget(place: tomsk, moment: m), source: nil, camera: nil, clock: { m },
                          calibrationFlag: MemoryFlag(), bodies: MemoryBodies())
    }

    @Test("ответ атласа про старое место после смены места не пишется; смена места сбрасывает засветку")
    func staleGlowIsDropped() async {
        let m = model()
        m.glow = 3
        let gate = Gate()
        let task = Task { @MainActor in
            await m.loadGlow { place in gate.asked.append(place); await gate.wait(); return 12 }
        }
        while gate.asked.isEmpty { await Task.yield() }
        #expect(gate.asked == [tomsk])
        m.apply(choice: .chosen(barnaul))
        #expect(m.glow == nil, "смена места не сбросила засветку: \(String(describing: m.glow))")
        gate.release()
        await task.value
        #expect(m.glow == nil, "записан ответ про Томск после перехода в Барнаул: \(String(describing: m.glow))")
    }

    @Test("ответ про то же место пишется; отменённая задача не пишет")
    func freshGlowIsWritten() async {
        let m = model()
        await m.loadGlow { _ in 12 }
        #expect(m.glow == 12)

        let gate = Gate()
        let task = Task { @MainActor in await m.loadGlow { _ in await gate.wait(); return 27 } }
        await Task.yield()
        task.cancel()
        gate.release()
        await task.value
        #expect(m.glow == 12, "отменённая задача записала \(String(describing: m.glow))")
    }
}
