import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Раскладка экрана AR (шаг 29.8в.6): подписи у линии горизонта, зоны стрелок за краем, две стрелки на узком экране.
/// Числа печатаются строками `ARLAY` — их берёт отчёт шага.
@MainActor
struct SunARLayoutTests {

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    /// iPhone SE (3-го поколения) и iPhone 15 Pro Max, pt; верхний отступ у SE 20, у 15 Pro Max 59, низ 0 / 34.
    private let phones: [(name: String, size: CGSize, safeTop: CGFloat, safeBottom: CGFloat)] = [
        ("iPhone SE 375", CGSize(width: 375, height: 667), 20, 0),
        ("iPhone 15 Pro Max 430", CGSize(width: 430, height: 932), 59, 34),
    ]

    private final class MemoryBodies: ARBodiesSettings {
        var moon = false
        var milkyWay = false
        var stars = false
        var constellations = false
        var planets = false
    }
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }

    private func moment(_ iso: String) -> Moment { Moment(ISO8601DateFormatter().date(from: iso)!) }

    // MARK: Подписи у горизонта

    /// Сцена на рассвете: камера смотрит на восход, часы дуги «08:00» рядом с «восход 07:57».
    private func sunriseScene(size: CGSize) -> (scene: SunARScene, clock: ClockText)? {
        let when = moment("2026-10-17T02:00:00Z")      // 09:00 по Томску: рассвет дня уже позади, выбранный момент — любой
        let model = SunARModel(target: SunARTarget(place: tomsk, moment: when), source: nil, camera: nil,
                               clock: { when }, calibrationFlag: MemoryFlag(), bodies: MemoryBodies())
        let viewport = ScreenViewport(width: Double(size.width), height: Double(size.height))
        // Азимут восхода — из самой сцены с камерой куда-нибудь, затем камера на него.
        let probe = SunARScene.make(basis: CameraBasis(azimuth: 105, altitude: 5), optics: .typical, viewport: viewport,
                                    arc: model.arc, sun: model.sun, now: model.sunNow, pickedIsNow: model.pickedIsNow,
                                    solar: model.solar)
        guard let rise = probe.events.first(where: { $0.kind == .sunrise }) else { return nil }
        let scene = SunARScene.make(basis: CameraBasis(azimuth: rise.azimuth, altitude: 6), optics: .typical, viewport: viewport,
                                    arc: model.arc, sun: model.sun, now: model.sunNow, pickedIsNow: model.pickedIsNow,
                                    solar: model.solar)
        return (scene, ClockText(language: "ru", preference: .h24))
    }

    private func labels(_ s: (scene: SunARScene, clock: ClockText), size: CGSize, avoid: Bool) -> [SunARLabelLayout.Placed] {
        SunARLabelLayout.make(scene: s.scene, cardinals: ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"],
                              eventText: { e in (e.kind == .sunset ? "закат " : "восход ") + s.clock.fmt(e.minutes) },
                              clock: s.clock, bounds: CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40),
                              avoidOverlaps: avoid)
    }

    @Test("«восход 07:57» больше не лежит на подписи часа: до — плашки налезали, после — зазор не меньше 4 pt, на SE и на 15 Pro Max")
    func sunriseLabelDoesNotOverlap() throws {
        for phone in phones {
            let s = try #require(sunriseScene(size: phone.size), "в сцене нет восхода")
            let before = labels(s, size: phone.size, avoid: false)
            let after = labels(s, size: phone.size, avoid: true)
            let gapBefore = SunARLabelLayout.minimumGap(before), gapAfter = SunARLabelLayout.minimumGap(after)
            let event = try #require(after.first { $0.kind == .event })
            print(String(format: "ARLAY подписи %@: %@ · зазор между плашками до %.1f pt, после %.1f pt · подписей до %d, после %d",
                         phone.name, event.text, gapBefore ?? 99, gapAfter ?? 99, before.count, after.count))
            #expect((gapBefore ?? 99) < 0, "\(phone.name): до правки плашки не налезают — сцена не воспроизводит снимок (зазор \(gapBefore ?? 99))")
            #expect((gapAfter ?? 99) >= SunARLabelLayout.gap, "\(phone.name): после правки зазор \(gapAfter ?? 99) pt")
            // Восход остаётся на месте — раскладка его не двигает.
            let eventBefore = try #require(before.first { $0.kind == .event })
            #expect(eventBefore.pill == event.pill, "подпись восхода сдвинулась")
        }
    }

    // MARK: Момент выбран ровно на событии (29.8в.10)

    private let ru = ClockText(language: "ru", preference: .h24)
    private func eventWord(_ e: SunARScene.HorizonEvent) -> String {
        (e.kind == .sunset ? "закат " : "восход ") + ru.fmt(e.minutes)
    }

    /// Сцена, где выбранный момент отстоит от события на `offset` минут (0 — ровно в минуту события), камера на событии.
    /// «Сейчас» — по ту же сторону горизонта, где оно ниже метки момента и в кадре: закат — 18:30, после заката;
    /// восход — 07:20, до восхода. Тогда подпись метки момента над диском — там же, где подпись события (снимок Алексея
    /// 18.10: оба в одну минуту, «сейчас» чуть позже).
    private func pickedScene(_ kind: SunARScene.HorizonEvent.Kind, offset: Double = 0, size: CGSize)
        -> (scene: SunARScene, event: SunARScene.HorizonEvent, minutes: Double)? {
        let now = moment(kind == .sunset ? "2026-10-17T11:30:00Z" : "2026-10-17T00:20:00Z")
        let model = SunARModel(target: SunARTarget(place: tomsk, moment: now), source: nil, camera: nil,
                               clock: { now }, calibrationFlag: MemoryFlag(), bodies: MemoryBodies())
        let viewport = ScreenViewport(width: Double(size.width), height: Double(size.height))
        let probe = SunARScene.make(basis: CameraBasis(azimuth: 0, altitude: 5), optics: .typical, viewport: viewport,
                                    arc: model.arc, sun: model.sun, now: model.sunNow, pickedIsNow: model.pickedIsNow,
                                    solar: model.solar)
        guard let ev = probe.events.first(where: { $0.kind == kind }) else { return nil }
        model.timebar.show(day: model.day, minute: ev.minutes + offset)
        let scene = SunARScene.make(basis: CameraBasis(azimuth: ev.azimuth, altitude: 6), optics: .typical, viewport: viewport,
                                    arc: model.arc, sun: model.sun, now: model.sunNow, pickedIsNow: model.pickedIsNow,
                                    solar: model.solar)
        guard let event = scene.events.first(where: { $0.kind == kind }), !model.pickedIsNow else { return nil }
        return (scene, event, model.minutes)
    }

    /// Наименьший зазор между плашкой метки момента и подписями кадра, pt.
    private func gapToPicked(_ pill: CGRect, _ labels: [SunARLabelLayout.Placed]) -> CGFloat {
        labels.map { l -> CGFloat in
            let dx = max(l.pill.minX - pill.maxX, pill.minX - l.pill.maxX)
            let dy = max(l.pill.minY - pill.maxY, pill.minY - l.pill.maxY)
            return (dx > 0 && dy > 0) ? (dx * dx + dy * dy).squareRoot() : max(dx, dy)
        }.min() ?? 99
    }

    private func kindsLabel(_ k: SunARScene.HorizonEvent.Kind) -> String { k == .sunset ? "закат" : "восход" }

    @Test("момент ровно в минуту заката и восхода: «закат 18:13» и «18:13» не лежат одна на другой — остаётся одна подпись «закат 18:13», на SE и на 15 Pro Max")
    func pickedOnEventIsOneLabel() throws {
        for phone in phones {
            for kind in [SunARScene.HorizonEvent.Kind.sunset, .sunrise] {
                let s = try #require(pickedScene(kind, size: phone.size), "\(phone.name): в сцене нет \(kindsLabel(kind))")
                _ = try #require(s.scene.marker, "\(phone.name): метка момента за кадром")
                let bounds = CGRect(origin: .zero, size: phone.size).insetBy(dx: -40, dy: -40)
                let cards = ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"]
                func layout(merged: SunARScene.HorizonEvent.Kind?, picked: String) -> [SunARLabelLayout.Placed] {
                    SunARLabelLayout.make(scene: s.scene, cardinals: cards, eventText: eventWord, clock: ru, bounds: bounds,
                                          merged: merged, pickedText: picked)
                }
                let mergedKind = SunARLabelLayout.mergedEvent(in: s.scene, pickedIsNow: false, pickedMinutes: s.minutes, clock: ru)?.kind
                let text = try #require(SunARLabelLayout.pickedText(scene: s.scene, pickedIsNow: false, pickedMinutes: s.minutes,
                                                                    clock: ru, dayCaption: nil, eventText: eventWord))
                // Метка момента выше «сейчас» — подпись над диском, там же, где подпись события.
                let plate = try #require(SunARLabelLayout.pickedPill(text: text, scene: s.scene))
                let plateOld = try #require(SunARLabelLayout.pickedPill(text: ru.fmt(s.minutes), scene: s.scene))
                #expect(plate.maxY <= (s.scene.marker?.y ?? 0), "\(phone.name): подпись метки не над диском — сцена не воспроизводит снимок")
                let before = layout(merged: nil, picked: ru.fmt(s.minutes)), after = layout(merged: mergedKind, picked: text)
                let gapBefore = gapToPicked(plateOld, before), gapAfter = gapToPicked(plate, after)
                print(String(format: "ARLAY момент = %@ %@: плашка «%@» (до — «%@»), зазор до %.1f pt, после %.1f pt · подписей события до %d, после %d",
                             phone.name, kindsLabel(kind), text, ru.fmt(s.minutes), gapBefore, gapAfter,
                             before.filter { $0.kind == .event }.count, after.filter { $0.kind == .event }.count))
                #expect(mergedKind == kind, "\(phone.name): событие не опознано как совпавшее: \(String(describing: mergedKind))")
                #expect(text == eventWord(s.event), "\(phone.name): на метке «\(text)», ждали «\(eventWord(s.event))»")
                #expect(gapBefore < 0, "\(phone.name): до правки плашки не налезают (зазор \(gapBefore)) — сцена не воспроизводит снимок")
                #expect(gapAfter >= SunARLabelLayout.gap, "\(phone.name): после правки зазор \(gapAfter) pt")
                #expect(after.filter { $0.kind == .event }.isEmpty, "\(phone.name): подпись события у горизонта осталась")
                #expect(text.contains(ru.fmt(s.event.minutes)), "в подписи нет времени события")
            }
        }
    }

    @Test("момент на минуту мимо события, «сейчас» и дата: подписи не сливаются, дата остаётся, на метке «сейчас» подписи нет")
    func pickedOffEventKeepsBoth() throws {
        let phone = phones[0]
        let s = try #require(pickedScene(.sunset, offset: 2, size: phone.size))
        #expect(SunARLabelLayout.mergedEvent(in: s.scene, pickedIsNow: false, pickedMinutes: s.minutes, clock: ru) == nil,
                "на две минуты мимо заката подписи не сливаются")
        #expect(SunARLabelLayout.pickedText(scene: s.scene, pickedIsNow: false, pickedMinutes: s.minutes, clock: ru,
                                            dayCaption: nil, eventText: eventWord) == ru.fmt(s.minutes))
        let onEvent = try #require(pickedScene(.sunset, size: phone.size))
        #expect(SunARLabelLayout.pickedText(scene: onEvent.scene, pickedIsNow: false, pickedMinutes: onEvent.minutes, clock: ru,
                                            dayCaption: "15 июн", eventText: eventWord) == "15 июн · " + eventWord(onEvent.event),
                "дата не пропала")
        #expect(SunARLabelLayout.pickedText(scene: onEvent.scene, pickedIsNow: true, pickedMinutes: onEvent.minutes, clock: ru,
                                            dayCaption: nil, eventText: eventWord) == nil, "на метке «сейчас» подписи времени нет")
        #expect(SunARLabelLayout.mergedEvent(in: onEvent.scene, pickedIsNow: true, pickedMinutes: onEvent.minutes, clock: ru) == nil)
    }

    @Test("справка, не проверка: на сколько минут мимо события плашка метки ещё налезает на подпись у горизонта")
    func overlapBand() throws {
        let phone = phones[1]
        var rows: [String] = []
        for off in stride(from: -8.0, through: 8.0, by: 2.0) {
            guard let s = pickedScene(.sunset, offset: off, size: phone.size) else { continue }
            let bounds = CGRect(origin: .zero, size: phone.size).insetBy(dx: -40, dy: -40)
            let ls = SunARLabelLayout.make(scene: s.scene, cardinals: ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"],
                                           eventText: eventWord, clock: ru, bounds: bounds)
            guard let plate = SunARLabelLayout.pickedPill(text: ru.fmt(s.minutes), scene: s.scene) else { continue }
            rows.append(String(format: "%+.0f мин: %.1f pt", off, gapToPicked(plate, ls)))
        }
        print("ARLAY полоса наложения (подпись метки против подписи заката, 15 Pro Max): " + rows.joined(separator: " · "))
    }

    // MARK: Зоны стрелок

    @Test("стрелка нужна светилу под кнопками и под панелью, не нужна на виду между ними (на SE и на 15 Pro Max, одна и две строки кнопок)")
    func pointerZones() {
        for phone in phones {
            let panelTop = phone.size.height - 200 - max(phone.safeBottom, 12) - 4
            for (label, bottom) in [("одна строка", phone.safeTop + 8 + SunARInk.touch), ("две строки", phone.safeTop + 8 + 2 * SunARInk.touch + 8)] {
                let window = SunARZones.visibleWindow(size: phone.size, safeTop: phone.safeTop, buttonsBottom: bottom, panelTop: panelTop)
                let underButtons = CGPoint(x: phone.size.width / 2, y: phone.safeTop + 8 + SunARInk.touch / 2)
                let between = CGPoint(x: phone.size.width / 2, y: (bottom + panelTop) / 2)
                let underPanel = CGPoint(x: phone.size.width / 2, y: panelTop + 40)
                #expect(!window.contains(underButtons), "\(phone.name), \(label): диск под кнопками считается видимым — стрелки не будет")
                #expect(window.contains(between), "\(phone.name), \(label): диск на виду между кнопками и панелью без стрелки не остаётся")
                #expect(!window.contains(underPanel), "\(phone.name), \(label): диск под панелью — стрелка нужна")
                print(String(format: "ARLAY зона %@, %@: окно видимости y %.1f…%.1f pt (кнопки до %.1f, панель с %.1f)",
                             phone.name, label, window.minY, window.maxY, bottom, panelTop))
            }
            // До измерения кнопок — запас на две строки.
            let reserve = SunARZones.visibleWindow(size: phone.size, safeTop: phone.safeTop, buttonsBottom: nil, panelTop: panelTop)
            #expect(reserve.minY == SunARZones.reservedButtonsBottom(safeTop: phone.safeTop))
        }
    }

    @Test("стрелка нужна, если диск виден не целиком: край под кнопками, под панелью или за краем экрана; центр в окне ничего не решает")
    func pointerNeededUnlessDiscFullyVisible() {
        for phone in phones {
            let panelTop = phone.size.height - 200 - max(phone.safeBottom, 12) - 4
            for bottom in [phone.safeTop + 8 + SunARInk.touch, phone.safeTop + 8 + 2 * SunARInk.touch + 8] {
                let w = SunARZones.visibleWindow(size: phone.size, safeTop: phone.safeTop, buttonsBottom: bottom, panelTop: panelTop)
                let r = SunARInk.nowLensDiameter / 2
                let x = phone.size.width / 2
                func visible(_ cx: CGFloat, _ cy: CGFloat) -> Bool { SunARZones.discFullyVisible(center: CGPoint(x: cx, y: cy), radius: r, in: w) }
                #expect(visible(x, (w.minY + w.maxY) / 2), "\(phone.name): диск посреди окна виден целиком")
                #expect(visible(x, w.minY + r) && visible(x, w.maxY - r), "\(phone.name): диск вплотную к краям окна виден целиком")
                // Верхний край диска на 1 pt под кнопками, центр уже в окне — раньше стрелки не было.
                #expect(!visible(x, w.minY + r - 1), "\(phone.name): верхний край под кнопками")
                #expect(w.contains(CGPoint(x: x, y: w.minY + r - 1)), "контроль: центр такого диска в окне — прежнее правило стрелку бы не дало")
                #expect(!visible(x, w.minY - r), "\(phone.name): диск целиком под кнопками")
                #expect(!visible(x, w.maxY - r + 1), "\(phone.name): нижний край под панелью")
                #expect(w.contains(CGPoint(x: x, y: w.maxY - r + 1)))
                #expect(!visible(r - 1, w.midY) && !visible(phone.size.width - r + 1, w.midY), "\(phone.name): край за краем экрана")
                print(String(format: "ARLAY рамка диска %@: окно y %.1f…%.1f, диск %.0f pt виден целиком при центре y %.1f…%.1f",
                             phone.name, w.minY, w.maxY, 2 * r, w.minY + r, w.maxY - r))
            }
        }
    }

    // MARK: Две стрелки

    /// Стрелки луны и ядра Млечного Пути на кадре `toggles` — как их строит экран, до раскладки.
    private func toggleArrows(phone: (name: String, size: CGSize, safeTop: CGFloat, safeBottom: CGFloat)) -> [(CGPoint, String)] {
        let viewport = ScreenViewport(width: Double(phone.size.width), height: Double(phone.size.height))
        let panelTop = phone.size.height - 200 - max(phone.safeBottom, 12) - 4
        let box = SunARZones.pointerBox(size: phone.size, safeTop: phone.safeTop, panelTop: panelTop)
        let basis = CameraBasis(azimuth: 162, altitude: 24)
        func arrow(_ az: Double, _ alt: Double, _ text: String) -> (CGPoint, String)? {
            guard let p = EdgePointing.pointer(azimuth: az, altitude: alt, basis: basis, optics: .typical, viewport: viewport, box: box)
            else { return nil }
            return (CGPoint(x: p.point.x, y: p.point.y), text)
        }
        return [arrow(111, -21, "111° · −21°"), arrow(130, -5, "130° · −5°")].compactMap { $0 }
    }

    @Test("луна и ядро Млечного Пути уходят в одну сторону: значки и подписи не накладываются, зазор не меньше 8 pt; стрелка остаётся в рамке")
    func twoArrowsDoNotOverlap() throws {
        for phone in phones {
            let arrows = toggleArrows(phone: phone)
            try #require(arrows.count == 2, "\(phone.name): стрелок не две")
            let panelTop = phone.size.height - 200 - max(phone.safeBottom, 12) - 4
            let box = SunARZones.pointerBox(size: phone.size, safeTop: phone.safeTop, panelTop: panelTop)
            let flip = phone.size.height - 200 - 40
            func clearance(_ pts: [CGPoint]) -> CGFloat {
                SunARPointerLayout.clearance(
                    SunARPointerLayout.occupied(center: pts[0], text: arrows[0].1, screen: phone.size, flipY: flip),
                    SunARPointerLayout.occupied(center: pts[1], text: arrows[1].1, screen: phone.size, flipY: flip))
            }
            let before = clearance(arrows.map(\.0))
            let spread = SunARPointerLayout.spread(arrows.map { (point: $0.0, text: $0.1) },
                                                   box: CGRect(x: box.minX, y: box.minY, width: box.maxX - box.minX, height: box.maxY - box.minY),
                                                   screen: phone.size, flipY: flip)
            let after = clearance(spread)
            print(String(format: "ARLAY стрелки %@: зазор до %.1f pt, после %.1f pt; вторая сдвинута на %.1f pt",
                         phone.name, before, after, hypot(spread[1].x - arrows[1].0.x, spread[1].y - arrows[1].0.y)))
            #expect(before < 0, "\(phone.name): до раскладки стрелки не накладываются (зазор \(before)) — кадр не воспроизводит замечание")
            #expect(after >= SunARPointerLayout.gap, "\(phone.name): после раскладки зазор \(after)")
            #expect(spread[0] == arrows[0].0, "первая (важнейшая) стрелка не должна сдвигаться")
            for p in spread {
                #expect(p.x >= box.minX - 0.5 && p.x <= box.maxX + 0.5 && p.y >= box.minY - 0.5 && p.y <= box.maxY + 0.5,
                        "\(phone.name): стрелка вне рамки: \(p)")
            }
        }
    }

    @Test("одна стрелка и две в разные стороны не двигаются")
    func farApartArrowsStay() {
        let phone = phones[1]
        let panelTop = phone.size.height - 200 - max(phone.safeBottom, 12) - 4
        let box = SunARZones.pointerBox(size: phone.size, safeTop: phone.safeTop, panelTop: panelTop)
        let rect = CGRect(x: box.minX, y: box.minY, width: box.maxX - box.minX, height: box.maxY - box.minY)
        let pts: [(point: CGPoint, text: String)] = [(CGPoint(x: rect.minX, y: rect.midY), "300° · +10°"),
                                                     (CGPoint(x: rect.maxX, y: rect.midY), "60° · +10°")]
        let out = SunARPointerLayout.spread(pts, box: rect, screen: phone.size, flipY: phone.size.height - 240)
        #expect(out == pts.map(\.point))
        #expect(SunARPointerLayout.spread([pts[0]], box: rect, screen: phone.size, flipY: 700) == [pts[0].point])
    }
}
