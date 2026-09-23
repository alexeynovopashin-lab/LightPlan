import SwiftUI
import LightPlanCore

/// Прибор карты (итерация 20а): что рисуется поверх холста и следует за
/// временем. Порт `renderMap` веба до сводки — лимб, деления, восемь чисел
/// азимута, две оси, буквы сторон, пояс рабочей высоты, путь солнца с
/// часовыми засечками, луна, облако Млечного Пути, трек ядра, светило, чип.
///
/// Геометрия отдельно от рисования: сцена — список примитивов в системе
/// `viewBox` веба (358 × 340, центр 179/170), в том же порядке, что узлы SVG.
/// Числа сверяются с вебом один к одному, а вид рисует их одним `Canvas`.
struct MapInstrument {
    static let size = CGSize(width: 358, height: 340)
    static let cx = 179.0, cy = 170.0
    /// Радиус горизонта: зенит — центр круга, горизонт — это кольцо.
    static let horizonR = 118.0
    static let pathMinAlt = -18.0
    static let pathMaxR = horizonR * (1 - pathMinAlt / 90)
    static let compassR = 160.0
    static let tickOut = 154.0
    static let hourLabelMax = 142.0

    /// Радиус высоты светила (`altR`).
    static func altR(_ alt: Double) -> Double {
        max(8, min(pathMaxR, horizonR * (1 - alt / 90)))
    }

    /// Точка на азимуте и радиусе (`A`): север вверх, по часовой.
    static func at(_ az: Double, _ r: Double) -> CGPoint {
        let a = az * .pi / 180
        return CGPoint(x: cx + r * sin(a), y: cy - r * cos(a))
    }

    // MARK: - Вход

    enum Chip: Equatable {
        /// Палец на ползунке: чипы всех включённых светил, без высоты.
        case drag
        /// Тап по светилу: один чип с высотой, значения тапа держатся отдельно.
        case tapSun(az: Double, alt: Double)
        case tapMoon(az: Double, alt: Double)
    }

    struct Input {
        var date: CivilDate
        var minute: Minutes
        var solar: SolarDay
        var place: Place
        var layers: MapLayers
        var pro: Bool
        /// Тема приложения — у колец и латуни (`ringColor`, `brassRing`).
        var lightTheme: Bool
        var chip: Chip?
        /// Время события словами часов приложения (`fmt`).
        var clock: (Minutes) -> String
        /// «С», «В», «Ю», «З» — словарь (`card.n` …).
        var cardinals: [String]
    }

    /// Светлый ли холст (`lightCanvas`): со звёздами карта чернеет и в светлой
    /// теме — точки облака на светлых улицах тонут.
    static func lightCanvas(lightTheme: Bool, layers: MapLayers) -> Bool { lightTheme && !layers.mw }

    // MARK: - Примитивы

    enum Anchor { case start, middle, end }

    enum Element {
        case circle(CGPoint, r: Double, fill: RGBA?, stroke: RGBA?, width: Double, dash: [CGFloat])
        case scrim(CGPoint, r: Double)
        case line(CGPoint, CGPoint, stroke: RGBA, width: Double, dash: [CGFloat], round: Bool)
        case path([[CGPoint]], stroke: RGBA, width: Double, dash: [CGFloat])
        case dots([CGPoint], color: RGBA, width: Double)
        /// `center` — середина строки по высоте (там, где веб ставит
        /// базовую линию на 0,36 кегля ниже).
        case text(String, center: CGPoint, size: Double, weight: Font.Weight, mono: Bool, color: RGBA,
                  anchor: Anchor, tracking: Double)
        case chip(String, center: CGPoint, size: Double, color: RGBA, background: RGBA, tick: (CGPoint, CGPoint, Double, RGBA)?)
    }

    /// Узлы для пары снимков: рамки в системе `viewBox`.
    struct Marks {
        var sun: CGRect?
        var sunGhost: CGRect?
        var moon: CGRect?
        var core: CGRect?
        var rise: (CGPoint, Anchor)?
        var set: (CGPoint, Anchor)?
        var north: CGPoint?
        var chips: [CGPoint] = []
        /// Точек облака на холсте по ярусам — сверяется строкой с вебом.
        var dust: [Int] = []
        var hourDots = 0
    }

    struct Scene {
        var elements: [Element] = []
        var marks = Marks()
        var sunAt: CGPoint?
        var moonAt: CGPoint?
        var sunHorizontal: (az: Double, alt: Double)?
        var moonHorizontal: (az: Double, alt: Double)?
    }

    // MARK: - Сутки

    /// Всё, что зависит от дня и места, а не от минуты: путь солнца шагом 4,
    /// подгоризонтная нить шагом 8, часы, луна шагом 8, трек ядра. Считается
    /// раз на день — ползунок трогает только деление «прошлое / впереди».
    struct Day {
        struct Sample { let minute: Double; let alt: Double; let az: Double }
        let date: CivilDate
        let place: Place
        let sun: [Sample]
        let ghost: [Sample]
        let hours: [Sample]
        let moon: [Sample]
        let coreTrack: [Sample]
        let rise: Sample?
        let set: Sample?

        init(date: CivilDate, place: Place, solar: SolarDay) {
            self.date = date
            self.place = place
            func s(_ m: Double) -> Sample { Sample(minute: m, alt: solar.elevation(at: m), az: solar.azimuth(at: m)) }
            sun = stride(from: 0.0, through: 1440, by: 4).map(s)
            ghost = stride(from: 0.0, through: 1440, by: 8).map(s)
            hours = (0..<24).map { s(Double($0 * 60)) }
            moon = stride(from: 0.0, through: 1440, by: 8).map { m in
                let mo = MoonSample(date: date, minutes: m, place: place)
                return Sample(minute: m, alt: mo.altitude, az: mo.azimuth)
            }
            var track: [Sample] = []
            var wt = solar.mint.rounded(.toNearestOrAwayFromZero)
            let end = solar.maxt.rounded(.toNearestOrAwayFromZero)
            while wt <= end {
                let c = MilkyWay.corePosition(date: date, minutes: wt, place: place)
                // Ядро вне астрономической ночи не рисуется — отмечаем высотой
                // −∞, чтобы разрыв встал там же, где у веба.
                let dark = solar.elevation(at: wt) <= -18
                track.append(Sample(minute: wt, alt: dark ? c.altitude : -.infinity, az: c.azimuth))
                wt += 8
            }
            coreTrack = track
            rise = solar.rise.map(s)
            set = solar.set.map(s)
        }
    }

    // MARK: - Сцена

    static func scene(_ input: Input, day: Day) -> Scene {
        var sc = Scene()
        let light = lightCanvas(lightTheme: input.lightTheme, layers: input.layers)
        let ink = light ? RGBA.hex(0xFBF9F5) : RGBA.hex(0x14110E)
        let t = input.minute
        let e = input.solar.elevation(at: t), az = input.solar.azimuth(at: t)
        let moonNow = MoonSample(date: input.date, minutes: t, place: input.place)
        sc.sunHorizontal = (az, e)
        sc.moonHorizontal = (moonNow.azimuth, moonNow.altitude)
        guard input.layers.compass else { return sc }

        func ring(_ a: Double) -> RGBA {
            input.lightTheme ? RGBA(30, 26, 20, fixed(a * 1.5, 2)) : RGBA(239, 234, 224, a)
        }
        func brass(_ a: Double) -> RGBA { RGBA(226, 164, 76, fixed(input.lightTheme ? min(1, a * 1.6) : a, 2)) }
        let c0 = CGPoint(x: cx, y: cy)

        // Виньетка обода — только на тёмном холсте.
        if !light { sc.elements.append(.scrim(c0, r: 170)) }
        sc.elements.append(.circle(c0, r: horizonR, fill: nil, stroke: ring(0.20), width: 1, dash: []))
        sc.elements.append(.circle(c0, r: tickOut, fill: nil, stroke: brass(0.30), width: 1, dash: []))

        // Деления через 10°, латунью каждые 30°, четвертей нет — там буква.
        for g in stride(from: 0, to: 360, by: 10) where g % 90 != 0 {
            let big = g % 30 == 0
            sc.elements.append(.line(at(Double(g), tickOut - (big ? 6 : 3)), at(Double(g), tickOut),
                                     stroke: big ? brass(0.42) : ring(0.10), width: big ? 1.2 : 1, dash: [], round: false))
            if big && input.pro {
                sc.elements.append(.text(String(g), center: at(Double(g), compassR), size: 8, weight: .regular,
                                         mono: true, color: ring(0.38), anchor: .middle, tracking: 0))
            }
        }
        // Две оси, пунктиром.
        for ax in [(0.0, 180.0), (90.0, 270.0)] {
            sc.elements.append(.line(at(ax.0, horizonR), at(ax.1, horizonR), stroke: ring(0.08), width: 1,
                                     dash: [2, 6], round: false))
        }
        // Буквы сторон: север латунью и крупнее; в астро все по 12 с разрядкой.
        for (i, deg) in [0.0, 90, 180, 270].enumerated() {
            let north = i == 0
            let size = input.pro ? 12.0 : (north ? 13 : 11)
            let p = at(deg, compassR)
            let center = CGPoint(x: p.x, y: p.y + size * 0.36 - size * textMid)
            sc.elements.append(.text(i < input.cardinals.count ? input.cardinals[i] : "", center: center, size: size,
                                     weight: .bold, mono: false, color: north ? .hex(0xE2A44C) : .hex(0x8A8478),
                                     anchor: .middle, tracking: input.pro ? 1 : 0))
            if north { sc.marks.north = center }
        }
        sc.elements.append(.line(at(0, tickOut - 9), at(0, tickOut - 3), stroke: RGBA(226, 164, 76, 0.85),
                                 width: 1.8, dash: [], round: true))

        // Пояс рабочей высоты — только со звёздами.
        if input.layers.mw {
            let rLo = altR(MilkyWay.workLow), rHi = altR(MilkyWay.workHigh)
            sc.elements.append(.circle(c0, r: (rLo + rHi) / 2, fill: nil, stroke: RGBA(198, 170, 232, 0.07),
                                       width: abs(rLo - rHi), dash: []))
            for r in [rLo, rHi] {
                sc.elements.append(.circle(c0, r: r, fill: nil, stroke: RGBA(198, 170, 232, 0.22), width: 0.8, dash: [3, 5]))
            }
        }

        if input.layers.sun {
            sunPath(&sc, day: day, t: t)
            hourMarks(&sc, day: day, ink: ink, clock: input.clock)
        }

        if input.layers.moon {
            var runs: [[CGPoint]] = [], cur: [CGPoint] = []
            for m in day.moon {
                if m.alt < -2 { if !cur.isEmpty { runs.append(cur); cur = [] }; continue }
                cur.append(round1(at(m.az, altR(m.alt))))
            }
            if !cur.isEmpty { runs.append(cur) }
            // Путь из одной точки веб тоже рисует (`M x y`), но с круглым
            // концом и без длины он невидим — пропускаем.
            if !runs.isEmpty { sc.elements.append(.path(runs, stroke: RGBA(207, 214, 222, 0.30), width: 1.2, dash: [4, 5])) }
            if moonNow.altitude > -3 {
                let p = at(moonNow.azimuth, altR(moonNow.altitude))
                sc.elements.append(.circle(p, r: 4.5, fill: moonNow.altitude > 0 ? .hex(0xCFD6DE) : RGBA(207, 214, 222, 0.45),
                                           stroke: ink, width: 1.5, dash: []))
                sc.moonAt = p
                sc.marks.moon = box(p, 4.5)
            }
        }

        if input.layers.mw { milkyWay(&sc, input: input, day: day) }

        if input.layers.sun {
            let p = at(az, altR(e))
            sc.sunAt = p
            if e <= pathMinAlt {
                sc.elements.append(.circle(p, r: 5.5, fill: nil, stroke: RGBA(124, 156, 196, 0.6), width: 1.6, dash: []))
                sc.elements.append(.circle(p, r: 1.5, fill: RGBA(124, 156, 196, 0.6), stroke: nil, width: 0, dash: []))
                sc.marks.sunGhost = box(p, 5.5)
            } else {
                sc.elements.append(.line(c0, p, stroke: e > 0 ? RGBA(226, 164, 76, 0.55) : RGBA(124, 156, 196, 0.45),
                                         width: 1.5, dash: [], round: false))
                sc.elements.append(.circle(p, r: 11, fill: e > 0 ? RGBA(226, 164, 76, 0.18) : RGBA(124, 156, 196, 0.15),
                                           stroke: nil, width: 0, dash: []))
                sc.elements.append(.circle(p, r: 5.5, fill: e > 0 ? .hex(0xE2A44C) : .hex(0x7C9CC4), stroke: ink,
                                           width: 2, dash: []))
                sc.marks.sun = box(p, 5.5)
            }
        }

        if let chip = input.chip { chips(&sc, chip: chip, input: input, light: light, sunAz: az,
                                         moon: (moonNow.azimuth, moonNow.altitude), ring: ring) }
        return sc
    }

    /// Середина строки ниже верха на столько кеглей: у SF восхождение 0,95,
    /// нисхождение 0,24 — середина на 0,355 выше базовой линии. Веб ставит
    /// базовую линию на 0,36 кегля ниже точки — буква садится на неё серединой.
    static let textMid = 0.355

    // MARK: - Слои

    /// Путь солнца: сегменты по цвету высоты, прошлое тоньше и в 0,4
    /// прозрачности; делит положение ползунка, а не часы телефона.
    private static func sunPath(_ sc: inout Scene, day: Day, t: Double) {
        struct Run { var rgb: (Int, Int, Int); var a: Double; var w: Double; var past: Bool; var pts: [CGPoint] }
        var run: Run?
        func flush() {
            if let r = run, r.pts.count >= 2 {
                sc.elements.append(.path([r.pts], stroke: RGBA(Double(r.rgb.0), Double(r.rgb.1), Double(r.rgb.2),
                                                                 fixed(r.a * (r.past ? 0.40 : 1), 3)),
                                         width: fixed(r.w * (r.past ? 0.6 : 1), 2), dash: []))
            }
            run = nil
        }
        for s in day.sun {
            if s.alt < pathMinAlt { flush(); continue }
            let c = PathStops.at(s.alt), past = s.minute < t
            let xy = round1(at(s.az, altR(s.alt)))
            if let r = run {
                let d = abs(r.rgb.0 - c.rgb.0) + abs(r.rgb.1 - c.rgb.1) + abs(r.rgb.2 - c.rgb.2)
                if past != r.past || d > 12 { run?.pts.append(xy); flush() }
            }
            if run == nil { run = Run(rgb: c.rgb, a: c.a, w: c.w, past: past, pts: []) }
            run?.pts.append(xy)
        }
        flush()
        // Подгоризонтный ход — нитью по пределу пути.
        var runs: [[CGPoint]] = [], cur: [CGPoint] = []
        for s in day.ghost {
            if s.alt >= pathMinAlt { if !cur.isEmpty { runs.append(cur); cur = [] }; continue }
            cur.append(round1(at(s.az, pathMaxR)))
        }
        if !cur.isEmpty { runs.append(cur) }
        if !runs.isEmpty { sc.elements.append(.path(runs, stroke: RGBA(124, 156, 196, 0.45), width: 1.2, dash: [1, 4])) }
    }

    /// Часовые засечки, подпись каждые три часа (уступает восходу и закату),
    /// восход и закат — метки со временем.
    private static func hourMarks(_ sc: inout Scene, day: Day, ink: RGBA, clock: (Minutes) -> String) {
        func nearRiseSet(_ x: Double) -> Bool {
            (day.rise.map { abs(x - $0.minute) < 34 } ?? false) || (day.set.map { abs(x - $0.minute) < 34 } ?? false)
        }
        for (h, s) in day.hours.enumerated() {
            if s.alt < pathMinAlt { continue }
            let r = altR(s.alt), p = at(s.az, r), lit = s.alt > -0.833
            sc.elements.append(.circle(p, r: lit ? 1.9 : 1.5, fill: lit ? RGBA(226, 164, 76, 0.9) : RGBA(124, 156, 196, 0.55),
                                       stroke: nil, width: 0, dash: []))
            sc.marks.hourDots += 1
            if h % 3 != 0 || nearRiseSet(s.minute) { continue }
            let lp = at(s.az, min(r + 10, hourLabelMax))
            sc.elements.append(.text((h < 10 ? "0" : "") + String(h), center: CGPoint(x: lp.x, y: lp.y + 3.4 - 9 * textMid),
                                     size: 9, weight: .regular, mono: true, color: RGBA(168, 156, 134, 0.72),
                                     anchor: .middle, tracking: 0))
        }
        for (s, anchor, dx) in [(day.rise, Anchor.start, 9.0), (day.set, Anchor.end, -9.0)] {
            guard let s else { continue }
            let p = at(s.az, altR(s.alt))
            sc.elements.append(.circle(p, r: 3.5, fill: ink, stroke: .hex(0xE2A44C), width: 1.5, dash: []))
            let c = CGPoint(x: p.x + dx, y: p.y + 4 - 11 * textMid)
            sc.elements.append(.text(clock(s.minute), center: c, size: 11, weight: .semibold, mono: false,
                                     color: .hex(0xA89C86), anchor: anchor, tracking: 0))
            if anchor == .start { sc.marks.rise = (c, anchor) } else { sc.marks.set = (c, anchor) }
        }
    }

    /// Облако точек пятью ярусами, подгоризонтная нить полосы, трек ядра за
    /// астрономическую ночь и мишень ядра.
    private static func milkyWay(_ sc: inout Scene, input: Input, day: Day) {
        let tiers: [(w: Double, a: Double)] = [(1.5, 0.70), (1.1, 0.55), (0.85, 0.38), (0.62, 0.26), (0.45, 0.16)]
        var pts = Array(repeating: [CGPoint](), count: tiers.count)
        let d = Sky.days(date: input.date, minutes: input.minute,
                         utcOffsetHours: input.place.zone.utcOffsetHours(on: input.date))
        let lat = input.place.latitude, lon = input.place.longitude
        for p in MilkyWayDust.points {
            let h = Sky.horizontal(p.equatorial, days: d, latitude: lat, longitude: lon)
            guard MilkyWayDust.visible(p, altitude: h.altitude) else { continue }
            pts[p.tier].append(round1(at(h.azimuth, altR(h.altitude))))
        }
        for (i, tr) in tiers.enumerated() where !pts[i].isEmpty {
            sc.elements.append(.dots(pts[i], color: RGBA(198, 170, 232, tr.a), width: tr.w))
        }
        sc.marks.dust = pts.map(\.count)

        var runs: [[CGPoint]] = [], cur: [CGPoint] = []
        for b in MilkyWay.band {
            let c = Sky.horizontal(b.center, days: d, latitude: lat, longitude: lon)
            if c.altitude >= 0 || c.altitude < pathMinAlt { if !cur.isEmpty { runs.append(cur); cur = [] }; continue }
            cur.append(round1(at(c.azimuth, altR(c.altitude))))
        }
        if !cur.isEmpty { runs.append(cur) }
        if !runs.isEmpty { sc.elements.append(.path(runs, stroke: RGBA(168, 140, 214, 0.16), width: 1, dash: [1, 5])) }

        runs = []; cur = []
        for s in day.coreTrack {
            if s.alt < 0 { if !cur.isEmpty { runs.append(cur); cur = [] }; continue }
            cur.append(round1(at(s.az, altR(s.alt))))
        }
        if !cur.isEmpty { runs.append(cur) }
        if !runs.isEmpty { sc.elements.append(.path(runs, stroke: RGBA(198, 170, 232, 0.5), width: 1.3, dash: [2, 4])) }

        let core = MilkyWay.corePosition(date: input.date, minutes: input.minute, place: input.place)
        if core.altitude >= pathMinAlt {
            let p = at(core.azimuth, altR(core.altitude))
            let live = core.altitude >= MilkyWay.workLow
            let c = live ? RGBA.hex(0xC6AAE8) : RGBA(198, 170, 232, 0.4)
            sc.elements.append(.circle(p, r: 5.5, fill: nil, stroke: c, width: 1.6, dash: []))
            sc.elements.append(.circle(p, r: 1.6, fill: c, stroke: nil, width: 0, dash: []))
            sc.marks.core = box(p, 5.5)
        }
    }

    /// Чип азимута — верхний слой прибора.
    private static func chips(_ sc: inout Scene, chip: Chip, input: Input, light: Bool, sunAz: Double,
                              moon: (az: Double, alt: Double), ring: (Double) -> RGBA) {
        let sunInk = light ? RGBA.hex(0x8A5A18) : RGBA.hex(0xE2A44C)
        let moonInk = light ? RGBA.hex(0x3F6088) : RGBA.hex(0xCFD6DE)
        var list: [(az: Double, alt: Double?, color: RGBA, rIn: Double)] = []
        switch chip {
        case .drag:
            if input.layers.sun { list.append((sunAz, nil, sunInk, 0)) }
            if input.layers.moon && moon.alt > -3 { list.append((moon.az, nil, moonInk, 0)) }
        case .tapSun(let a, let h): list.append((a, h, sunInk, 0))
        case .tapMoon(let a, let h): list.append((a, h, moonInk, 0))
        }
        if list.count == 2 {
            let dAz = abs(((list[0].az - list[1].az + 540).truncatingRemainder(dividingBy: 360)) - 180)
            if dAz < 14 { list[1].rIn = 12 }
        }
        let bg = light ? RGBA(251, 249, 245, 0.86) : RGBA(20, 17, 14, 0.86)
        for c in list {
            let norm = ((c.az.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            let near = Int((norm / 10).rounded(.toNearestOrAwayFromZero)) * 10 % 360
            var tick: (CGPoint, CGPoint, Double, RGBA)?
            if near % 90 != 0 {
                let big = near % 30 == 0
                tick = (at(Double(near), tickOut - (big ? 6 : 3)), at(Double(near), tickOut), big ? 1.6 : 1.3, ring(0.5))
            }
            let p = at(c.az, compassR - c.rIn)
            let size = c.alt != nil ? 11.0 : 10
            var label = String(Int(norm.rounded(.toNearestOrAwayFromZero)) % 360) + "°"
            if let h = c.alt {
                label += "  " + (h >= 0 ? "+" : "\u{2212}") + String(Int(abs(h).rounded(.toNearestOrAwayFromZero))) + "°"
            }
            sc.elements.append(.chip(label, center: CGPoint(x: p.x, y: p.y + size * 0.36 - size * textMid), size: size,
                                     color: c.color, background: bg, tick: tick))
            sc.marks.chips.append(p)
        }
    }

    // MARK: - Мелочи

    /// Веб пишет координаты путей с одним знаком (`toFixed(1)`).
    static func round1(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x * 10).rounded(.toNearestOrAwayFromZero) / 10, y: (p.y * 10).rounded(.toNearestOrAwayFromZero) / 10)
    }

    static func fixed(_ v: Double, _ digits: Int) -> Double {
        let k = pow(10, Double(digits))
        return (v * k).rounded(.toNearestOrAwayFromZero) / k
    }

    static func box(_ p: CGPoint, _ r: Double) -> CGRect {
        CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
    }
}

/// Цвет числами веба: 0…255 и прозрачность.
struct RGBA: Equatable {
    var r: Double, g: Double, b: Double, a: Double
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    static func hex(_ v: Int, _ a: Double = 1) -> RGBA {
        RGBA(Double((v >> 16) & 0xff), Double((v >> 8) & 0xff), Double(v & 0xff), a)
    }
    var color: Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a) }
}

/// Слои карты — `mapLayers` снимка веба. Меню слоёв — итерация 20б; здесь
/// слои читаются из данных, как их оставил веб или прошлый запуск.
public struct MapLayers: Equatable, Sendable {
    public var sun = true, moon = true, mw = false, compass = true, spots = true

    public init() {}

    /// Недостающий ключ — умолчание веба: солнце и луна, без звёзд; компас
    /// и свои места включены (`mapLayers.compass === undefined` → да).
    init(_ saved: [String: Bool]?) {
        guard let o = saved else { return }
        sun = o["sun"] ?? true; moon = o["moon"] ?? true; mw = o["mw"] ?? false
        compass = o["compass"] ?? true; spots = o["spots"] ?? true
    }
}
