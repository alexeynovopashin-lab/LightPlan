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
