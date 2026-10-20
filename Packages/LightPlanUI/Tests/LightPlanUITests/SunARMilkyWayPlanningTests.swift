import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Млечный Путь как инструмент планирования (шаг 29.8в.17б; слово Алексея 20.10: «Я должен выехать на точку, днем,
/// поставить телефон на штатив, заранее замерить положение… мне важно знать в котором часу и откуда появится млечный
/// путь или куда он уйдет»): полоса и подпись «ядро» рисуются при любой видимости; видимость гасит только зерно и пыль;
/// траектория ядра с часами, восход и заход с азимутом; строки списка «Слоёв»; подписи не налезают на соседей.
@MainActor
struct SunARMilkyWayPlanningTests {

    private let size = CGSize(width: 440, height: 956)
    private let scale: CGFloat = 2

    // MARK: - Рисунок: пиксели

    private struct Pixels {
        let w: Int, h: Int
        let rgba: [UInt8]
        let scale: CGFloat
        func green(_ x: Double, _ y: Double) -> Double? {
            let i = Int((x * Double(scale)).rounded(.down)), j = Int((y * Double(scale)).rounded(.down))
            guard i >= 0, j >= 0, i < w, j < h else { return nil }
            return Double(rgba[(j * w + i) * 4 + 1])
        }
        /// Самая яркая точка кадра, 0…255 по зелёному каналу.
        var maxGreen: Double { stride(from: 1, to: rgba.count, by: 4).map { Double(rgba[$0]) }.max() ?? 0 }
    }

    private func render(_ view: some View, backdrop: Color = .black) throws -> Pixels {
        let content = ZStack(alignment: .topLeading) { backdrop; view }
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

    private let sochi = Place(latitude: 43.585, longitude: 39.723, zone: ZoneID("Europe/Moscow")!)
    private let day = CivilDate(year: 2026, month: 8, day: 15)

    /// Сцена с полосой, камера на точку (l, 0). `sun`, `moon`, `glow` — то, что считают видимость и справка.
    private func scene(aim l: Degrees, minutes: Minutes = 1350, sun: Degrees, moonAltitude: Degrees = -90,
                       moonFraction: Double = 0, glow: Double? = 0,
                       optics: CameraOptics = CameraOptics(longSideFOV: 10, aspect: 4.0 / 3.0)) -> NightSkyARScene {
        let d = Sky.days(date: day, minutes: minutes, utcOffsetHours: sochi.zone.utcOffsetHours(on: day))
        let aim = Sky.horizontal(MilkyWay.equatorial(galacticLongitude: l, galacticLatitude: 0), days: d,
                                 latitude: sochi.latitude, longitude: sochi.longitude)
        let input = NightSkyARScene.MilkyWayInput(
            band: [], core: MilkyWayAR.core(day: day, minutes: minutes, in: sochi), sunAltitude: sun,
            frame: MilkyWayLook.frame(day: day, minutes: minutes, in: sochi), moonAltitude: moonAltitude,
            moonFraction: moonFraction, glow: glow, center: MilkyWayAR.center(day: day, minutes: minutes, in: sochi))
        return NightSkyARScene.make(basis: CameraBasis(azimuth: aim.azimuth, altitude: max(aim.altitude, 15)), optics: optics,
                                    viewport: ScreenViewport(width: size.width, height: size.height), moon: nil, milkyWay: input)
    }

    private func mid(_ s: NightSkyARScene, parts: MilkyWaySkyShader.Parts, backdrop: Color = .black) throws -> Double {
        let px = try render(SunARMilkyWayCanvas(scene: s, parts: parts).frame(width: size.width, height: size.height),
                            backdrop: backdrop)
        return try #require(px.green(size.width / 2, size.height / 2))
    }

    @Test("полоса не гаснет: яркость гладкой части в центре кадра днём (солнце +20°), в городе (засветка 12), при засветке 40 и при яркой Луне — та же, что в тёмную ночь")
    func smoothBandIgnoresVisibility() throws {
        let night = try mid(scene(aim: 20, sun: -40), parts: .smooth)
        #expect(night > 20, "ночью середина полосы \(night)")
        let cases: [(String, NightSkyARScene)] = [
            ("день, солнце +20°", scene(aim: 20, sun: 20)),
            ("день, солнце +60°", scene(aim: 20, sun: 60)),
            ("город, засветка 12", scene(aim: 20, sun: -40, glow: 12)),
            ("засветка 40 («дальше пусто»)", scene(aim: 20, sun: -40, glow: 40)),
            ("Луна 90 % над горизонтом", scene(aim: 20, sun: -40, moonAltitude: 40, moonFraction: 0.9)),
        ]
        for (name, s) in cases {
            let pic = try #require(s.milkyWayPicture)
            // Видимость глазом у этих кадров нулевая или малая — справка, не условие рисования.
            #expect(pic.visibility.factor < 0.1, "\(name): видимость \(pic.visibility.factor)")
            let v = try mid(s, parts: .smooth)
            #expect(abs(v - night) <= 1, "\(name): середина \(v), ночью \(night)")
        }
    }

    @Test("правила видимости гасят только зерно и пыль: текстура днём пуста, ночью — нет; гладкая часть та же")
    func visibilityDimsOnlyTexture() throws {
        let nightTexture = try render(SunARMilkyWayCanvas(scene: scene(aim: 20, sun: -40), parts: [.texture, .dust])
                                        .frame(width: size.width, height: size.height))
        #expect(nightTexture.maxGreen > 30, "ночью зерно и пыль видны: \(nightTexture.maxGreen)")
        for (name, s) in [("день", scene(aim: 20, sun: 30)), ("засветка 40", scene(aim: 20, sun: -40, glow: 40)),
                          ("Луна", scene(aim: 20, sun: -40, moonAltitude: 40, moonFraction: 0.9))] {
            let px = try render(SunARMilkyWayCanvas(scene: s, parts: [.texture, .dust]).frame(width: size.width, height: size.height))
            #expect(px.maxGreen < 2, "\(name): текстура не погасла: \(px.maxGreen)")
        }
    }

    @Test("контур по краям полосы виден на белом небе, где светлая заливка не видна; на чёрном его нет")
    func edgeOutlineOnWhite() throws {
        // Широкое поле, камера на l = 20°: край полосы b = +halfWidth на экране.
        let wide = CameraOptics(longSideFOV: 100, aspect: 4.0 / 3.0)
        let l: Degrees = 20
        let s = scene(aim: l, sun: 30, optics: wide)
        let d = Sky.days(date: day, minutes: 1350, utcOffsetHours: sochi.zone.utcOffsetHours(on: day))
        func point(_ b: Degrees) -> ScreenPoint? {
            let h = Sky.horizontal(MilkyWay.equatorial(galacticLongitude: l, galacticLatitude: b), days: d,
                                   latitude: sochi.latitude, longitude: sochi.longitude)
            let aim = Sky.horizontal(MilkyWay.equatorial(galacticLongitude: l, galacticLatitude: 0), days: d,
                                     latitude: sochi.latitude, longitude: sochi.longitude)
            return SkyProjection.project(azimuth: h.azimuth, altitude: h.altitude,
                                         basis: CameraBasis(azimuth: aim.azimuth, altitude: max(aim.altitude, 15)),
                                         optics: wide, viewport: ScreenViewport(width: size.width, height: size.height))
        }
        let edge = try #require(point(MilkyWay.halfWidth(galacticLongitude: l)))
        let outside = try #require(point(MilkyWay.halfWidth(galacticLongitude: l) * 2.2))
        let onlyEdge = try render(SunARMilkyWayCanvas(scene: s, parts: .edge).frame(width: size.width, height: size.height),
                                  backdrop: .white)
        // Тёмная линия 1,5 pt вокруг точки края: самая тёмная точка рядом — не светлее 140 из 255 (белый · (1 − 0,6) = 102).
        var darkest = 255.0
        for dy in stride(from: -3.0, through: 3.0, by: 0.5) {
            for dx in stride(from: -3.0, through: 3.0, by: 0.5) {
                if let g = onlyEdge.green(edge.x + dx, edge.y + dy) { darkest = min(darkest, g) }
            }
        }
        let far = try #require(onlyEdge.green(outside.x, outside.y))
        #expect(far > 250, "вне полосы фон остаётся белым: \(far)")
        #expect(darkest < 140, "контур на белом: \(darkest)")
        // Светлая заливка на белом ничего не меняет: контур — единственное, что отличает полосу.
        let fillOnly = try render(SunARMilkyWayCanvas(scene: s, parts: .smooth).frame(width: size.width, height: size.height),
                                  backdrop: .white)
        #expect(fillOnly.green(size.width / 2, size.height / 2)! > 250)
        // Без части .edge контура нет.
        let noEdge = try render(SunARMilkyWayCanvas(scene: s, parts: [.smooth, .texture, .dust]).frame(width: size.width, height: size.height),
                                backdrop: .white)
        var darkestNoEdge = 255.0
        for dy in stride(from: -3.0, through: 3.0, by: 0.5) {
            for dx in stride(from: -3.0, through: 3.0, by: 0.5) {
                if let g = noEdge.green(edge.x + dx, edge.y + dy) { darkestNoEdge = min(darkestNoEdge, g) }
            }
        }
        #expect(darkestNoEdge > 250, "без контура край белый: \(darkestNoEdge)")
    }

    // MARK: - Траектория ядра: ядро по выбранной дате

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)

    private final class AllBodies: ARBodiesSettings {
        var moon = true
        var milkyWay = true
        var stars = true
        var constellations = true
        var planets = true
    }
    private final class SeenFlag: ARCalibrationFlag { var seen = true }

    private func model(_ place: Place, _ iso: String, glow: Double? = 0) -> SunARModel {
        let m = Moment(ISO8601DateFormatter().date(from: iso)!)
        let model = SunARModel(target: SunARTarget(place: place, moment: m), source: nil, camera: nil, clock: { m },
                               calibrationFlag: SeenFlag(), bodies: AllBodies())
        model.glow = glow
        return model
    }

    private let viewport = ScreenViewport(width: 393, height: 852)
    private let phone = CGSize(width: 393, height: 852)

    @Test("траектория ядра в сцене — дуга выбранной даты: точка в выбранные сутки совпадает с MilkyWay.corePosition; меняется с датой")
    func trackFollowsPickedDate() throws {
        // Одна модель, день меняется на ходу: кэш траектории обязан сменить сутки вместе с датой.
        let a = model(tomsk, "2026-08-30T15:00:00Z")
        func track(_ m: SunARModel) throws -> NightSkyARScene.CoreTrack {
            let aim = CameraBasis(azimuth: 180, altitude: 20)
            return try #require(m.nightScene(basis: aim, optics: .typical, viewport: viewport).coreTrack)
        }
        let ta = try track(a)
        let augustDay = a.day
        a.timebar.show(day: CivilDate(year: 2026, month: 1, day: 15), minute: 900)
        let tb = try track(a)
        #expect(a.day != augustDay)
        #expect(!ta.events.isEmpty && !tb.events.isEmpty)
        // Восход в августе и в январе — в разное время, и азимут один (ядро неподвижно на небе).
        let ra = try #require(ta.events.first { $0.kind == .rise }), rb = try #require(tb.events.first { $0.kind == .rise })
        #expect(abs(ra.minutes - rb.minutes) > 300, "время восхода за пол-года сдвигается: \(ra.minutes) и \(rb.minutes)")
        #expect(abs(ra.azimuth - rb.azimuth) < 1.0)
        // Каждая подпись часа лежит на дуге в ту же минуту.
        let p = a.place
        for h in tb.hours {
            let s = MilkyWayCoreTrack.sample(day: a.day, minutes: Double(h.hour * 60), in: p)
            #expect(abs(s.altitude - h.altitude) < 1e-9, "час \(h.hour): дуга не той даты")
        }
    }

    // MARK: - Строки списка «Слоёв»

    private func lines(_ m: SunARModel, lang: String = "ru") -> [String] {
        SunARMilkyWayNotes.lines(plan: m.milkyWayPlan, eye: m.milkyWayEyeNote,
                                 clock: ClockText(language: lang, preference: .h24), lexicon: Lexicon(lang))
    }

    @Test("Сочи, ночь, город: «ядро над горизонтом …–… · темно с …», «видимость глазом 8 %: город, засветка 12», окно съёмки, формула")
    func notesNightCity() throws {
        let m = model(sochi, "2026-08-15T19:30:00Z", glow: 12)     // 22:30 по Сочи, молодая Луна под горизонтом, ядро над ним
        let l = lines(m)
        let clock = ClockText(language: "ru", preference: .h24)
        let passage = m.milkyWayPlan.passage
        let r = try #require(passage.rise), s = try #require(passage.set)
        #expect(l[0].hasPrefix("ядро над горизонтом \(clock.fmt(r.minutes))") && l[0].contains(clock.fmt(s.minutes)), "\(l[0])")
        #expect(l[0].contains("темно с "), "\(l[0])")
        #expect(l[1] == "видимость глазом 8 %: город, засветка 12", "\(l[1])")
        #expect(l.last == "рисуется по формуле, условно")
        #expect(l.contains { $0.hasPrefix("окно съёмки") || $0.hasPrefix("окна съёмки нет") }, "\(l)")
        // То же по-английски: слова есть, «Млечный Путь» по-русски не просочился.
        let en = lines(m, lang: "en")
        #expect(en[1] == "visible to the eye 8%: city, glow 12", "\(en[1])")
    }

    @Test("днём: «днём не видно: солнце +20°» — справка, полоса при этом рисуется; Луна: «Луна 62 % освещена над горизонтом»")
    func notesDayAndMoon() throws {
        let day = model(tomsk, "2026-08-30T06:00:00Z")            // 13:00, солнце высоко
        let sunAlt = Int(day.sun.altitude.rounded())
        #expect(lines(day)[1] == "днём не видно: солнце +\(sunAlt)°", "\(lines(day)[1])")
        let moon = MilkyWayLook.eyeNote(sunAltitude: -30, moonAltitude: 30, moonFraction: 0.62, glow: 0, coreAltitude: 30)
        #expect(SunARMilkyWayNotes.eyeLine(moon, Lexicon("ru")) == "Луна 62 % освещена над горизонтом")
        let low = MilkyWayLook.eyeNote(sunAltitude: -30, moonAltitude: -30, moonFraction: 0.2, glow: 0, coreAltitude: 3)
        #expect(SunARMilkyWayNotes.eyeLine(low, Lexicon("ru")).contains("у горизонта дымка"))
    }

    @Test("широта 70° — «ядро не восходит на этой широте», −70° — «ядро не заходит»; темноты нет — так и написано")
    func notesHonestAtPolarLatitudes() {
        let north = Place(latitude: 70, longitude: 25, zone: ZoneID("Europe/Oslo")!)
        let south = Place(latitude: -70, longitude: -68, zone: ZoneID("America/Argentina/Ushuaia")!)
        let n = lines(model(north, "2026-06-21T22:00:00Z"))
        #expect(n[0] == "ядро не восходит на этой широте", "\(n[0])")
        #expect(n.contains { $0 == "окна съёмки нет: темноты нет" }, "\(n)")
        let s = lines(model(south, "2026-06-21T03:00:00Z"))
        #expect(s[0].hasPrefix("ядро не заходит"), "\(s[0])")
        #expect(lines(model(north, "2026-06-21T22:00:00Z"), lang: "en")[0] == "the core never rises at this latitude")
    }

    @Test("окно съёмки в строке — отрезки MilkyWayWindow, сросшиеся на стыке суток склеены: Сидней в июне — один отрезок через полночь")
    func notesWindowIsTheWindow() throws {
        let sydney = Place(latitude: -33.87, longitude: 151.21, zone: ZoneID("Australia/Sydney")!)
        let m = model(sydney, "2026-06-15T12:00:00Z")
        let plan = m.milkyWayPlan
        #expect(plan.window == MilkyWayWindow(date: m.day, place: sydney))
        let clock = ClockText(language: "ru", preference: .h24)
        let line = try #require(lines(m).first { $0.hasPrefix("окно съёмки") })
        #expect(line == "окно съёмки " + clock.range(plan.shooting[0].from, plan.shooting[0].to), "\(line)")
        #expect(!line.contains("23:55 – 23:55"))
    }

    // MARK: - Подписи траектории не налезают

    /// Стек так, как его собирает экран: все слои неба включены, подписи траектории ядра с текстами.
    private func stack(_ m: SunARModel, aim: CameraBasis) -> SunARSkyStack {
        let scene = SunARScene.make(basis: aim, optics: .typical, viewport: viewport, arc: m.arc, sun: m.sun, now: m.sunNow,
                                    pickedIsNow: m.pickedIsNow, solar: m.solar)
        let night = m.nightScene(basis: aim, optics: .typical, viewport: viewport)
        let marks = SunARMarks.make(sun: scene, night: night, screen: phone)
        let clock = ClockText(language: "ru", preference: .h24)
        let picked = SunARLabelLayout.pickedText(scene: scene, pickedIsNow: m.pickedIsNow, pickedMinutes: m.minutes, clock: clock,
                                                 dayCaption: nil,
                                                 eventText: { ($0.kind == .sunset ? "закат " : "восход ") + clock.fmt($0.minutes) })
        return SunARSkyStack(scene: scene, night: night, marks: marks, size: phone, clock: clock,
                             cardinals: ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"], coreLabel: "ядро",
                             eventText: { ($0.kind == .sunset ? "закат " : "восход ") + clock.fmt($0.minutes) },
                             coreEventText: { ($0.kind == .rise ? "ядро восходит " : "заходит ") + clock.fmt($0.minutes) + " · \(Int($0.azimuth.rounded()))°" },
                             pickedText: picked, sky: nil,
                             stars: m.starScene(basis: aim, optics: .typical, viewport: viewport),
                             starName: { Lexicon("ru").t($0) },
                             planets: m.planetScene(basis: aim, optics: .typical, viewport: viewport),
                             starWindow: CGRect(x: 0, y: 140, width: 393, height: 520))
    }

    private func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = max(b.minX - a.maxX, a.minX - b.maxX), dy = max(b.minY - a.maxY, a.minY - b.maxY)
        return (dx > 0 && dy > 0) ? (dx * dx + dy * dy).squareRoot() : max(dx, dy)
    }

    /// Всё, что подписи траектории ядра не должны задевать: подписи солнца, диски меток, плашка выбранного момента,
    /// подпись «ядро», подписи звёзд, созвездий и планет.
    private func neighbours(_ s: SunARSkyStack, _ m: SunARModel) -> [(String, CGRect)] {
        var out: [(String, CGRect)] = []
        let bounds = CGRect(origin: .zero, size: phone).insetBy(dx: -40, dy: -40)
        let clock = ClockText(language: "ru", preference: .h24)
        for l in SunARLabelLayout.make(scene: s.scene, cardinals: ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"],
                                       eventText: { ($0.kind == .sunset ? "закат " : "восход ") + clock.fmt($0.minutes) },
                                       clock: clock, bounds: bounds, merged: s.mergedEvent, pickedText: s.pickedText) {
            out.append(("подпись солнца «\(l.text)»", l.pill))
        }
        for k in s.marks { out.append(("диск \(k.id)", CGRect(x: k.center.x - k.radius, y: k.center.y - k.radius, width: k.diameter, height: k.diameter))) }
        if let t = s.pickedText, let p = SunARLabelLayout.pickedPill(text: t, scene: s.scene) { out.append(("плашка момента", p)) }
        if let r = s.coreNameRect { out.append(("подпись «ядро»", r)) }
        if let stars = s.stars {
            let placed = s.starLabels(stars)
            for l in placed.labels { out.append(("звезда/созвездие «\(l.text)»", l.rect)) }
        }
        if let planets = s.planets {
            for l in s.planetLabels(planets) { out.append(("планета «\(l.text)»", l.rect)) }
        }
        return out
    }

    @Test("подписи траектории ядра не налезают на подписи солнца, диски меток, плашку момента, подпись «ядро», звёзды и планеты — Томск, вечер, камера на восход и на заход ядра, SE и 15 Pro Max")
    func coreLabelsDoNotOverlap() throws {
        var checked = 0
        for iso in ["2026-08-30T12:00:00Z", "2026-08-30T14:30:00Z", "2026-08-30T15:40:00Z"] {
            let m = model(tomsk, iso)
            let track = try #require(m.nightScene(basis: CameraBasis(azimuth: 180, altitude: 20), optics: .typical,
                                                  viewport: viewport).coreTrack)
            for e in track.events {
                // Камера на событие и на дугу чуть выше него.
                for alt in [6.0, 18.0] {
                    let s = stack(m, aim: CameraBasis(azimuth: e.azimuth, altitude: alt))
                    let mine = s.coreLabels
                    let others = neighbours(s, m)
                    for l in mine {
                        for (name, r) in others {
                            let g = gap(l.pill, r)
                            #expect(g >= SunARCoreLabels.gap - 0.1, "«\(l.text)» (\(iso), альт \(alt)) задевает \(name): зазор \(g)")
                        }
                        // Целиком в экране.
                        #expect(CGRect(origin: .zero, size: phone).contains(l.pill), "«\(l.text)» за краем экрана: \(l.pill)")
                        checked += 1
                    }
                    for i in 0..<mine.count { for j in (i + 1)..<mine.count {
                        #expect(gap(mine[i].pill, mine[j].pill) >= SunARCoreLabels.gap - 0.1, "«\(mine[i].text)» и «\(mine[j].text)» налезают")
                    } }
                }
            }
        }
        #expect(checked > 6, "подписей проверено: \(checked)")
    }

    @Test("подпись восхода ядра, у которой прежнее место занято подписью солнца, не пропадает и не налезает: ищет место рядом (тропики, декабрь: ядро и солнце восходят и заходят в 5° друг от друга)")
    func eventLabelMovesInsteadOfOverlapping() throws {
        // На севере закат солнца далёк от ядра по азимуту (≥ 14°); в тропиках и на юге они сходятся. Перебор мест и дат.
        let places = [Place(latitude: -0.18, longitude: -78.47, zone: ZoneID("America/Guayaquil")!),
                      Place(latitude: -8.65, longitude: 115.22, zone: ZoneID("Asia/Makassar")!),
                      Place(latitude: -33.93, longitude: 18.42, zone: ZoneID("Africa/Johannesburg")!)]
        var best: (place: Place, iso: String, diff: Double)?
        for place in places {
            for dayOfYear in stride(from: 0, to: 365, by: 4) {
                var c = DateComponents(); c.year = 2026; c.month = 1; c.day = 1 + dayOfYear; c.hour = 12
                var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
                let iso = ISO8601DateFormatter().string(from: cal.date(from: c)!)
                let m = model(place, iso)
                let sunTimes: [(Minutes?, MilkyWayCoreTrack.Event.Kind)] = [(m.solar.set, .set), (m.solar.rise, .rise)]
                for (sunMinutes, kind) in sunTimes {
                    guard let t = sunMinutes else { continue }
                    let sunAz = m.solar.azimuth(at: t)
                    for e in m.milkyWayPlan.passage.events where e.kind == kind {
                        let d = abs(sunAz - e.azimuth)
                        if best == nil || d < best!.diff { best = (place, iso, d) }
                    }
                }
            }
        }
        let pick = try #require(best)
        #expect(pick.diff < 7, "нет дня, где азимуты близки: \(pick.diff)°")
        let m = model(pick.place, pick.iso)
        let sunEvents = SunARScene.make(basis: CameraBasis(azimuth: 90, altitude: 5), optics: .typical, viewport: viewport,
                                        arc: m.arc, sun: m.sun, now: m.sunNow, pickedIsNow: m.pickedIsNow, solar: m.solar).events
        let coreEvents = m.milkyWayPlan.passage.events
        // Камера между близкими событиями солнца и ядра.
        var pair: (sun: Double, core: Double)?
        for sunEvent in sunEvents {
            for coreEvent in coreEvents {
                let d = abs(sunEvent.azimuth - coreEvent.azimuth)
                if pair == nil || d < abs(pair!.sun - pair!.core) { pair = (sunEvent.azimuth, coreEvent.azimuth) }
            }
        }
        let near = try #require(pair)
        let s = stack(m, aim: CameraBasis(azimuth: (near.sun + near.core) / 2, altitude: 8))
        let placed = s.coreLabels
        let hasEvent = placed.contains { $0.text.contains("восходит") || $0.text.contains("заходит") }
        #expect(hasEvent, "подпись события пропала")
        // Прежнее место (над точкой, −20 pt) занято: без поиска подпись налезла бы на подпись солнца.
        let around = neighbours(s, m)
        let sunLabels = around.filter { $0.0.hasPrefix("подпись солнца") }
        let track = try #require(s.night?.coreTrack)
        let ev = try #require(track.events.first { abs($0.azimuth - near.core) < 0.01 })
        let p = try #require(ev.point)
        let sz = SunARLabelLayout.textSize("ядро восходит 00:00 · 000°", size: 11, weight: .semibold)
        let naive = CGRect(x: p.x - sz.width / 2 - 6, y: p.y - 20 - sz.height / 2 - 3, width: sz.width + 12, height: sz.height + 6)
        var naiveHits = false
        for (_, r) in sunLabels where gap(naive, r) < SunARCoreLabels.gap { naiveHits = true }
        #expect(naiveHits, "в этой геометрии прежнее место не занято — тест ничего не доказывает")
        for l in placed {
            for (name, r) in neighbours(s, m) { #expect(gap(l.pill, r) >= SunARCoreLabels.gap - 0.1, "«\(l.text)» задевает \(name)") }
        }
    }
}
