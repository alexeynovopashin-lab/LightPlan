import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Стеклянные диски солнца и луны на экране AR (шаг 29.8в.5): линза гнёт дугу, кромка видна, оттенок по свету,
/// лучиков нет, ночью солнце и луна различимы в оттенках серого. Рисует тот же код, что идёт на экран
/// (`SunARSkyStack`, `SunARMarkPaint`), через `ImageRenderer` — числа мерятся по пикселям.
@MainActor
struct SunARGlassTests {

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    private let size = CGSize(width: 393, height: 852)
    private let scale: CGFloat = 4

    private final class MemoryBodies: ARBodiesSettings {
        var moon = false
        var milkyWay = false
    }
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }

    private func moment(_ iso: String) -> Moment { Moment(ISO8601DateFormatter().date(from: iso)!) }

    // MARK: Пиксели

    private struct Pixels {
        let w: Int, h: Int
        let rgba: [UInt8]
        let scale: CGFloat

        /// Яркость 0…1 в точке окна (pt).
        func luma(_ x: CGFloat, _ y: CGFloat) -> Double {
            let ix = min(w - 1, max(0, Int((x * scale).rounded(.down)))), iy = min(h - 1, max(0, Int((y * scale).rounded(.down))))
            let i = (iy * w + ix) * 4
            return (0.2126 * Double(rgba[i]) + 0.7152 * Double(rgba[i + 1]) + 0.0722 * Double(rgba[i + 2])) / 255
        }

        func rgb(_ x: CGFloat, _ y: CGFloat) -> (Double, Double, Double) {
            let ix = min(w - 1, max(0, Int((x * scale).rounded(.down)))), iy = min(h - 1, max(0, Int((y * scale).rounded(.down))))
            let i = (iy * w + ix) * 4
            return (Double(rgba[i]) / 255, Double(rgba[i + 1]) / 255, Double(rgba[i + 2]) / 255)
        }

        /// Центр тяжести яркости в колонке `x` по окну `y0…y1` (pt) — положение светлой линии с точностью
        /// до долей пикселя.
        func lineCentroid(x: CGFloat, y0: CGFloat, y1: CGFloat) -> Double? {
            var sum = 0.0, weighted = 0.0
            var y = y0
            while y <= y1 {
                let l = luma(x, y)
                sum += l; weighted += l * Double(y)
                y += 1 / scale
            }
            return sum > 0.05 ? weighted / sum : nil
        }
    }

    private func render(_ view: some View, background: Color = .black) throws -> Pixels {
        let content = ZStack(alignment: .topLeading) { background; view }
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

    // MARK: Дуга в диске

    /// Сцена, где диск солнца низко над горизонтом: линия горизонта идёт под центром диска на 12…16 pt и пересекает
    /// кромку не по центру — смещение у кромки видно поперёк линии.
    private func lowSunScene() throws -> (scene: SunARScene, marks: [SunARMark], dy: CGFloat, base: Moment) {
        let base = moment("2026-10-14T00:30:00Z").date
        for k in 0..<90 {
            let when = Moment(base.addingTimeInterval(Double(k) * 60))
            let s = SunTrack.sample(at: when, in: tomsk)
            guard s.apparentAltitude > 0.9, s.apparentAltitude < 1.4 else { continue }
            let model = SunARModel(target: SunARTarget(place: tomsk, moment: when), source: nil, camera: nil,
                                   clock: { when }, calibrationFlag: MemoryFlag(), bodies: MemoryBodies())
            let basis = CameraBasis(azimuth: s.azimuth, altitude: s.apparentAltitude)
            let scene = SunARScene.make(basis: basis, optics: .typical, viewport: ScreenViewport(width: 393, height: 852),
                                        arc: model.arc, sun: model.sun, now: model.sunNow, pickedIsNow: model.pickedIsNow,
                                        solar: model.solar)
            let marks = SunARMarks.make(sun: scene, night: nil, screen: size)
            guard let marker = scene.marker, let horizon = scene.horizon.first?.first else { continue }
            let dy = CGFloat(horizon.y - marker.y)
            if dy > 12, dy < 16 { return (scene, marks, dy, when) }
        }
        throw TestFailure("нет момента с солнцем на 12…16 pt над горизонтом")
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    private func stack(_ s: (scene: SunARScene, marks: [SunARMark], dy: CGFloat, base: Moment),
                       layers: Set<SunARLayers>) -> some View {
        SunARSkyStack(scene: s.scene, night: nil, marks: s.marks, size: size, clock: ClockText(language: "ru"),
                      cardinals: [], coreLabel: "", eventText: { _ in "" }, sky: AnyView(Color.black),
                      layers: layers)
    }

    /// Где линия, лежащая в плоскости `yLine`, видна в колонке `x` внутри диска: точка, чьё «содержимое» (точка за
    /// кромкой, `p + n·s`) лежит на линии. Формула шейдера `glassRing`: сдвиг `lensShift · t²` от внутренней
    /// границы кромки `R − rim` к краю `R`.
    private func expectedDisplayedY(x: CGFloat, yLine: CGFloat, center: CGPoint, radius: CGFloat, rim: CGFloat) -> CGFloat {
        var y = yLine
        for _ in 0..<40 {
            let dx = x - center.x, dyc = y - center.y
            let rho = hypot(dx, dyc)
            let rin = radius - rim
            let t = rho <= rin ? 0 : min(1, (rho - rin) / rim)
            let shift = SunARInk.lensShift * t * t
            y = yLine - (rho > 0 ? dyc / rho : 0) * shift
        }
        return y
    }

    @Test("линия горизонта внутри диска солнца гнётся у кромки: смещена на ≈ 2,5 pt против линии снаружи, в середине — один к одному, линия одна")
    func lineIsBentByTheLens() throws {
        let s = try lowSunScene()
        let mark = try #require(s.marks.first { $0.isSun })
        let c = mark.center, r = mark.radius, rim = SunARInk.rim(for: mark.diameter)
        let yLine = CGFloat(try #require(s.scene.horizon.first?.first).y)
        let px = try render(stack(s, layers: [.arc, .lens]))
        let window = (yLine - 9)...(yLine + 9)
        // У кромки линию тянет к центру (вверх, до ≈ 3 pt), а ниже слева лежит жила самой дуги: окно уже.
        let edgeWindow = (yLine - 7)...(yLine + 3)

        // Снаружи диска, слева и справа от него.
        let outsideX: [CGFloat] = [c.x - 90, c.x - 70, c.x + 70, c.x + 90]
        let outside = try outsideX.map { try #require(px.lineCentroid(x: $0, y0: window.lowerBound, y1: window.upperBound)) }
        for o in outside { #expect(abs(o - Double(yLine)) < 0.2, "линия снаружи \(o) вместо \(yLine)") }

        // Середина диска: плоская, один к одному.
        let mid = try #require(px.lineCentroid(x: c.x, y0: window.lowerBound, y1: window.upperBound))
        #expect(abs(mid - Double(yLine)) < 0.25, "середина диска: \(mid) вместо \(yLine)")

        // У кромки: колонка внутри диска на 1 pt от края по линии. Смещение по формуле шейдера и по пикселям.
        // Сторона — та, где жила самой дуги дальше от линии горизонта (на другой они ложатся друг на друга).
        let half = sqrt(r * r - s.dy * s.dy)
        func arcGap(_ x: CGFloat) -> CGFloat {
            let ys = s.scene.arc.flatMap { $0 }.filter { abs(CGFloat($0.point.x) - x) < 4 }.map { CGFloat($0.point.y) }
            return ys.map { abs($0 - yLine) }.min() ?? 100
        }
        let sign: CGFloat = arcGap(c.x - half) >= arcGap(c.x + half) ? -1 : 1
        let edgeX = c.x + sign * (half - 1)
        #expect(arcGap(edgeX) > 12, "жила дуги рядом с линией у кромки: \(arcGap(edgeX)) pt")
        let expected = Double(expectedDisplayedY(x: edgeX, yLine: yLine, center: c, radius: r, rim: rim))
        let measured = try #require(px.lineCentroid(x: edgeX, y0: edgeWindow.lowerBound, y1: edgeWindow.upperBound))
        let shift = Double(yLine) - measured
        print(String(format: "ARGLASS edge: line outside %.2f, mid %.2f, at edge %.2f (formula %.2f), shift %.2f pt, disc d=%.0f rim=%.1f lensShift=%.0f",
                     outside[0], mid, measured, expected, shift, mark.diameter, rim, SunARInk.lensShift))
        #expect(shift > 2.0, "линия у кромки внутри диска смещена на \(shift) pt (нужно > 2)")
        #expect(abs(measured - expected) < 0.6, "измерено \(measured), по формуле шейдера \(expected)")

        // Линия одна: профиль яркости в колонке у кромки имеет один пик в окне.
        var peaks = 0
        var prev = 0.0, rising = false
        var y = edgeWindow.lowerBound
        while y <= edgeWindow.upperBound {
            let l = px.luma(edgeX, y)
            if l > prev + 0.01 { rising = true } else if l < prev - 0.01, rising, prev > 0.3 { peaks += 1; rising = false }
            prev = l
            y += 0.25
        }
        #expect(peaks <= 1, "двойная линия у кромки: пиков \(peaks)")
    }

    @Test("без линзы дуга внутри диска вырезана — линза единственный источник линии в диске (проверка метода: без слоя линии в диске нет)")
    func withoutTheLensTheDiscHasNoLine() throws {
        let s = try lowSunScene()
        let mark = try #require(s.marks.first { $0.isSun })
        let yLine = CGFloat(try #require(s.scene.horizon.first?.first).y)
        let px = try render(stack(s, layers: [.arc]))
        // Колонка в середине диска, окно у линии: оригинал вырезан, копии нет.
        let l = (0..<20).map { px.luma(mark.center.x, yLine - 5 + CGFloat($0) * 0.5) }.max() ?? 0
        #expect(l < 0.05, "линия в диске без линзы: яркость \(l)")
    }

    // MARK: Лучиков нет

    @Test("вокруг диска солнца нет лучиков: кольцо r+3…r+10 тёмное (было 8 жёлтых штрихов)")
    func sunHasNoRays() throws {
        let mark = SunARMark(id: "sun.now", kind: .sun, center: CGPoint(x: 196, y: 400), diameter: 48, fade: 1, altitude: 40)
        let px = try render(SunARMarkPaint(mark: mark))
        var brightest = 0.0
        for k in 0..<72 {
            let a = Double(k) * .pi / 36
            for rr in stride(from: 24 + 3.0, through: 24 + 10.0, by: 0.5) {
                brightest = max(brightest, px.luma(196 + rr * cos(a), 400 + rr * sin(a)))
            }
        }
        #expect(brightest < 0.12, "вокруг диска что-то светлое (лучик?): яркость \(brightest)")
    }

    // MARK: Кромка

    @Test("кромка видна на белом небе: светлая полоска сверху ярче, чем снизу, и тёмный контур снаружи темнее неба")
    func rimIsVisibleOnWhiteSky() throws {
        let mark = SunARMark(id: "sun.now", kind: .sun, center: CGPoint(x: 196, y: 400), diameter: 48, fade: 1, altitude: 40)
        let px = try render(SunARMarkPaint(mark: mark), background: .white)
        // Контур снаружи: чуть за краем диска сверху и снизу — темнее неба.
        let outsideTop = px.luma(196, 400 - 24 - 0.5), outsideBottom = px.luma(196, 400 + 24 + 0.5)
        #expect(outsideTop < 0.6 && outsideBottom < 0.6, "контур: сверху \(outsideTop), снизу \(outsideBottom) (небо 1,0)")
        // Свет по кромке: сверху внутри диска светлее, чем у кромки снизу (там стекло темнеет).
        let insideTop = px.luma(196, 400 - 24 + 1.2), insideBottom = px.luma(196, 400 + 24 - 1.2)
        #expect(insideTop > insideBottom + 0.05, "кромка: сверху \(insideTop), снизу \(insideBottom)")
    }

    // MARK: Ночью без цвета

    @Test("ночью солнце и луна различимы в оттенках серого: контур солнца пунктирный (≥ 16 смен), у луны сплошной; внутри луны фаза")
    func sunAndMoonDifferInGray() throws {
        // Солнце на −20° (астрономическая ночь): призрак, контур пунктиром; луна — половина, растущая.
        let sun = SunARMark(id: "sun.now", kind: .sun, center: CGPoint(x: 120, y: 400), diameter: 48, fade: SunARMarks.ghostFade,
                            altitude: -20, belowHorizon: true)
        let moon = SunARMark(id: "moon.now", kind: .moon(illuminated: 0.5, waxing: true, limb: 0), center: CGPoint(x: 280, y: 400),
                             diameter: 40, fade: 1)
        let view = ZStack(alignment: .topLeading) { SunARMarkPaint(mark: sun); SunARMarkPaint(mark: moon) }
        // Фон — средний серый: чёрный контур и белый штрих на нём различимы.
        let px = try render(view, background: Color(white: 0.5))

        func transitions(center: CGPoint, radius: CGFloat) -> Int {
            // Кольцо на 0,75 pt за краем диска, 720 точек; порог — середина между тёмным контуром и белым штрихом.
            var states: [Bool] = []
            for k in 0..<720 {
                let a = Double(k) * .pi / 360
                states.append(px.luma(center.x + (radius + 0.75) * cos(a), center.y + (radius + 0.75) * sin(a)) > 0.62)
            }
            var n = 0
            for i in 0..<states.count where states[i] != states[(i + 1) % states.count] { n += 1 }
            return n
        }
        let sunSwitches = transitions(center: sun.center, radius: sun.radius)
        let moonSwitches = transitions(center: moon.center, radius: moon.radius)
        #expect(sunSwitches >= 16, "контур солнца: смен светлого и тёмного \(sunSwitches)")
        #expect(moonSwitches <= 2, "контур луны: смен \(moonSwitches)")

        // Внутри луны фаза: разброс яркости велик; внутри солнца — ровный налёт.
        func spread(center: CGPoint, radius: CGFloat) -> Double {
            var values: [Double] = []
            for iy in stride(from: -radius + 4, through: radius - 4, by: 1) {
                for ix in stride(from: -radius + 4, through: radius - 4, by: 1) where hypot(ix, iy) < radius - 4 {
                    values.append(px.luma(center.x + ix, center.y + iy))
                }
            }
            let mean = values.reduce(0, +) / Double(values.count)
            return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
        }
        let moonSpread = spread(center: moon.center, radius: moon.radius)
        let sunSpread = spread(center: sun.center, radius: sun.radius)
        #expect(moonSpread > 0.15, "внутри луны разброс яркости \(moonSpread)")
        #expect(sunSpread < 0.05, "внутри солнца разброс яркости \(sunSpread)")
    }

    // MARK: Оттенок по свету

    @Test("оттенок диска солнца: пять моментов суток дают пять разных оттенков; день светлее всех, ночь темнее всех; закат краснее всех")
    func discTintByLight() {
        // Высоты: день, золотой час, закат (центр у горизонта), синий час, астрономическая ночь.
        let moments: [(String, Double)] = [("день", 40), ("золотой час", 3), ("закат", -0.8), ("синий час", -5), ("ночь", -20)]
        let rgb = moments.map { SunARInk.sunDiscRGB(altitude: $0.1) }
        func lum(_ c: (r: Double, g: Double, b: Double)) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
        func sat(_ c: (r: Double, g: Double, b: Double)) -> Double {
            let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
            return mx == 0 ? 0 : (mx - mn) / mx
        }
        // Попарно разные: расстояние в 0…255 не меньше 20.
        for i in 0..<rgb.count {
            for j in (i + 1)..<rgb.count {
                let d = 255 * sqrt(pow(rgb[i].r - rgb[j].r, 2) + pow(rgb[i].g - rgb[j].g, 2) + pow(rgb[i].b - rgb[j].b, 2))
                #expect(d >= 20, "\(moments[i].0) и \(moments[j].0) почти одного цвета: \(d)")
            }
        }
        for (i, m) in moments.enumerated() {
            let c = rgb[i]
            print(String(format: "ARTINT %@ alt=%+.1f rgb=(%.0f,%.0f,%.0f) lum=%.3f sat=%.2f", m.0, m.1, c.r * 255, c.g * 255, c.b * 255, lum(c), sat(c)))
        }
        let lums = rgb.map(lum)
        #expect(lums[0] == lums.max())
        #expect(lums[4] == lums.min())
        // Закат — самый красный: доля красного в сумме каналов.
        let redShare = rgb.map { $0.r / ($0.r + $0.g + $0.b) }
        #expect(redShare[2] == redShare.max(), "закат не самый красный: \(redShare)")
        // Ниже золотого часа и вне красной примеси — таблица «Света» один в один.
        for alt in [-5.0, -6.0, -12.0, -18.0] {
            let table = PathStops.at(alt).rgb
            let got = SunARInk.sunDiscRGB(altitude: alt)
            #expect(abs(got.r * 255 - Double(table.0)) < 0.5 && abs(got.g * 255 - Double(table.1)) < 0.5
                    && abs(got.b * 255 - Double(table.2)) < 0.5, "высота \(alt): диск не берёт цвет рельса")
        }
    }

    @Test("оттенок диска меняется непрерывно по ручке: за минуту суток канал сдвигается меньше чем на 8 из 255, без ступеней")
    func discTintIsContinuous() {
        let day = CivilDate(year: 2026, month: 10, day: 14)
        var worst = 0.0
        var prev: (r: Double, g: Double, b: Double)?
        for m in 0..<1440 {
            let alt = SunTrack.sample(day: day, minutes: Double(m), in: tomsk).altitude
            let c = SunARInk.sunDiscRGB(altitude: alt)
            if let p = prev {
                worst = max(worst, 255 * max(abs(c.r - p.r), abs(c.g - p.g), abs(c.b - p.b)))
            }
            prev = c
        }
        #expect(worst < 8, "самый большой скачок канала за минуту: \(worst) из 255")
    }

    @Test("метка солнца берёт высоту из сцены: выбранный момент и «сейчас» — каждая со своим оттенком; слились — один")
    func marksCarryTheirOwnAltitude() throws {
        let noon = moment("2026-10-14T05:00:00Z")      // 12:00 по Томску
        let evening = moment("2026-10-14T10:30:00Z")   // 17:30: солнце низко
        let model = SunARModel(target: SunARTarget(place: tomsk, moment: evening), source: nil, camera: nil,
                               clock: { noon }, calibrationFlag: MemoryFlag(), bodies: MemoryBodies())
        let s = model.sun, n = model.sunNow
        let basis = CameraBasis(azimuth: 215, altitude: 10)
        let scene = SunARScene.make(basis: basis, optics: CameraOptics(longSideFOV: 150, aspect: 4.0 / 3.0),
                                    viewport: ScreenViewport(width: 393, height: 852), arc: model.arc, sun: s, now: n,
                                    pickedIsNow: model.pickedIsNow, solar: model.solar)
        #expect(scene.markerAltitude == s.altitude)
        #expect(scene.nowAltitude == n.altitude)
        #expect(scene.markerAltitude < scene.nowAltitude!)
        let marks = SunARMarks.make(sun: scene, night: nil, screen: size)
        if let picked = marks.first(where: { $0.id == "sun.picked" }), let now = marks.first(where: { $0.id == "sun.now" }) {
            #expect(picked.altitude == s.altitude && now.altitude == n.altitude)
            #expect(picked.tint != now.tint)
        }
    }

    // MARK: Насыщенность диска (29.8в.6)

    /// Три фона замера: белый (кадр на ярком небе: яркость 0,95), серый, чёрный.
    private let backdrops: [(name: String, level: Double)] = [("белый", 0.95), ("серый", 0.5), ("чёрный", 0.0)]

    /// Затухание призрака на этой высоте — как в `SunARMarks` (ниже `SunTrack.visibleFrom` метка идёт призраком).
    private func fade(at altitude: Double) -> Double { altitude < SunTrack.visibleFrom ? SunARMarks.ghostFade : 1 }

    @Test("насыщенность диска на белом, сером и чёрном: золотой час и закат ≥ 0,55, под горизонтом и призрак ≥ 0,40, день остаётся светло-жёлтым (≤ 0,40)")
    func discSaturationOnThreeBackdrops() {
        var worstGolden = 1.0, worstBelow = 1.0, dayMax = 0.0
        var alt = -30.0
        while alt <= 45 {
            for b in backdrops {
                let sat = SunARInk.saturation(SunARInk.sunDiscOnBackdrop(altitude: alt, fade: fade(at: alt), backdrop: b.level))
                if alt >= -1, alt <= 6 { worstGolden = min(worstGolden, sat) }
                if alt < -1.5 { worstBelow = min(worstBelow, sat) }
                if alt >= 30 { dayMax = max(dayMax, sat) }
            }
            alt += 0.25
        }
        print(String(format: "ARSAT золотой час и закат %.3f · под горизонтом и призрак %.3f · день не больше %.3f", worstGolden, worstBelow, dayMax))
        #expect(worstGolden >= 0.55, "золотой час и закат: \(worstGolden)")
        #expect(worstBelow >= 0.40, "под горизонтом и призрак: \(worstBelow)")
        #expect(dayMax <= 0.40, "днём диск уже не светло-жёлтый: \(dayMax)")
    }

    @Test("тон по таблице света не теряется: у стекла тот же тон (HSV) с точностью 12°, что у цвета света — на золотом часе, закате, синем часе и ночью")
    func glassKeepsTheTone() {
        func hue(_ c: (r: Double, g: Double, b: Double)) -> Double {
            let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
            guard d > 0 else { return 0 }
            var h: Double
            if mx == c.r { h = (c.g - c.b) / d } else if mx == c.g { h = 2 + (c.b - c.r) / d } else { h = 4 + (c.r - c.g) / d }
            h *= 60
            return h < 0 ? h + 360 : h
        }
        for alt in [40.0, 3, -0.8, -2, -5, -8, -12, -20] {
            let table = hue(SunARInk.sunDiscRGB(altitude: alt)), glass = hue(SunARInk.sunGlassRGB(altitude: alt))
            var d = abs(table - glass)
            if d > 180 { d = 360 - d }
            #expect(d <= 12, "высота \(alt): тон стекла \(glass)°, света \(table)°")
        }
    }

    @Test("цвет стекла меняется непрерывно: за минуту суток канал сдвигается меньше чем на 8 из 255 — Томск 14.10 и 21.06, 56,5° на равноденствие")
    func glassTintIsContinuous() {
        func altitude(minutes m: Double, lat: Double, declination: Double) -> Double {
            let h = (m - 720) / 4 * .pi / 180, la = lat * .pi / 180, de = declination * .pi / 180
            return asin(sin(la) * sin(de) + cos(la) * cos(de) * cos(h)) * 180 / .pi
        }
        var worst = 0.0
        // Томск 14.10 — настоящий ход солнца приложения; ещё два дня — приближённая формула (то же, что считал замер).
        var prev: (r: Double, g: Double, b: Double)?
        let day = CivilDate(year: 2026, month: 10, day: 14)
        for m in 0..<1440 {
            let c = SunARInk.sunGlassRGB(altitude: SunTrack.sample(day: day, minutes: Double(m), in: tomsk).altitude)
            if let p = prev { worst = max(worst, 255 * max(abs(c.r - p.r), abs(c.g - p.g), abs(c.b - p.b))) }
            prev = c
        }
        let tomskWorst = worst
        for (lat, decl) in [(56.5, -8.2), (56.5, 0.0), (55.7, 23.4)] {
            prev = nil
            for m in 0..<1440 {
                let c = SunARInk.sunGlassRGB(altitude: altitude(minutes: Double(m), lat: lat, declination: decl))
                if let p = prev { worst = max(worst, 255 * max(abs(c.r - p.r), abs(c.g - p.g), abs(c.b - p.b))) }
                prev = c
            }
        }
        print(String(format: "ARSAT скачок стекла за минуту: Томск 14.10 %.2f, все дни %.2f из 255", tomskWorst, worst))
        #expect(worst < 8, "самый большой скачок канала за минуту: \(worst) из 255")
    }

    /// Насыщенность по пикселям: тот же код, что идёт на экран (`SunARMarkPaint` → `LensGlass`), на сплошном фоне.
    private func renderedSaturation(altitude: Double, background: Color) throws -> Double {
        let mark = SunARMark(id: "sun.now", kind: .sun, center: CGPoint(x: 196, y: 400), diameter: 48,
                             fade: fade(at: altitude), altitude: altitude, belowHorizon: altitude < 0)
        let px = try render(SunARMarkPaint(mark: mark), background: background)
        let c = px.rgb(196, 400)
        return SunARInk.saturation((c.0, c.1, c.2))
    }

    @Test("насыщенность по пикселям на белом, сером и чёрном: диск золотого часа ≥ 0,55, призрак ≥ 0,40 (на экране рисует тот же LensGlass)")
    func renderedDiscSaturation() throws {
        let fills: [(String, Color)] = [("белый", Color(white: 0.95)), ("серый", Color(white: 0.5)), ("чёрный", .black)]
        for (name, bg) in fills {
            let golden = try renderedSaturation(altitude: 3, background: bg)
            let ghost = try renderedSaturation(altitude: -12, background: bg)
            print(String(format: "ARSAT пиксели %@: золотой час %.3f, призрак −12° %.3f", name, golden, ghost))
            #expect(golden >= 0.55, "\(name) фон: золотой час \(golden)")
            #expect(ghost >= 0.40, "\(name) фон: призрак \(ghost)")
        }
    }

    // MARK: Призрак пропускает кадр (29.8в.7)

    private func renderedColour(altitude: Double, background: Double) throws -> (r: Double, g: Double, b: Double) {
        let mark = SunARMark(id: "sun.now", kind: .sun, center: CGPoint(x: 196, y: 400), diameter: 48,
                             fade: fade(at: altitude), altitude: altitude, belowHorizon: altitude < 0)
        let c = try render(SunARMarkPaint(mark: mark), background: Color(white: background)).rgb(196, 400)
        return (c.0, c.1, c.2)
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

    @Test("призрак пропускает кадр: яркость внутри диска / вне на белом −8° ≥ 0,70, −12° ≥ 0,65, −20° ≥ 0,60, насыщенность ≥ 0,40 на белом, сером и чёрном")
    func ghostLetsTheFrameThrough() throws {
        let floors: [(Double, Double)] = [(-8, 0.70), (-12, 0.65), (-20, 0.60)]
        for (alt, floor) in floors {
            let white = try renderedColour(altitude: alt, background: 0.95)
            let through = luminance(white) / 0.95
            var lowest = 1.0
            for level in [0.95, 0.5, 0.0] {
                lowest = min(lowest, SunARInk.saturation(try renderedColour(altitude: alt, background: level)))
            }
            print(String(format: "ARSAT призрак %+.0f°: яркость внутри/вне %.3f (порог %.2f), насыщенность на трёх фонах не ниже %.3f", alt, through, floor, lowest))
            #expect(through >= floor, "призрак \(alt)°: яркость внутри/вне \(through) < \(floor)")
            #expect(lowest >= 0.40, "призрак \(alt)°: насыщенность \(lowest) < 0,40")
        }
    }

    @Test("обычное солнце не изменилось: золотой час и закат — цвет по прежней формуле «умножение × налёт», день не темнее золотого часа")
    func ordinarySunIsUnchanged() throws {
        for alt in [3.0, -0.8] {
            let t = SunARInk.sunGlassRGB(altitude: alt)
            let got = try renderedColour(altitude: alt, background: 0.95)
            // Формула f18b07f: фон × цвет (умножение 1,0), затем налёт 0,42 тем же цветом.
            func expected(_ x: Double) -> Double { 0.95 * x * (1 - SunARInk.glassTintOpacity) + x * SunARInk.glassTintOpacity }
            #expect(abs(got.r - expected(t.r)) < 0.01 && abs(got.g - expected(t.g)) < 0.01 && abs(got.b - expected(t.b)) < 0.01,
                    "высота \(alt): \(got) вместо (\(expected(t.r)), \(expected(t.g)), \(expected(t.b)))")
        }
        let day = luminance(try renderedColour(altitude: 40, background: 0.95))
        let golden = luminance(try renderedColour(altitude: 3, background: 0.95))
        #expect(day >= golden, "день темнее золотого часа: \(day) < \(golden)")
    }
}
