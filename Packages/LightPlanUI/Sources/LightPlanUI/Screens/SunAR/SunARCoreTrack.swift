import SwiftUI
import LightPlanCore

/// Подписи траектории ядра Млечного Пути (шаг 29.8в.17б): часы дуги, «восходит 22:40 · 195°», «заходит 04:10 · 262°».
/// Чистая раскладка, как `SunARLabelLayout`: экран рисует то, что она вернула, тест меряет зазоры.
///
/// Подписи ядра ставятся **после** подписей солнца и обходят их: плашки подписей горизонта и часов солнца (уже
/// стоящие), точки их часов и событий, плашка выбранного момента, диски меток солнца и луны, подпись «ядро» у ядра,
/// стрелки за краем (`avoid`). Подписи звёзд, созвездий и планет обходят уже эти (`SunARSkyStack.starTaken`).
/// Подпись события не отбрасывается: ищет место выше, ниже и сдвигом по сторонам; подпись часа, как у солнца, —
/// только в свободное место, иначе точка остаётся без подписи.
enum SunARCoreLabels {
    /// Просвет до чужих плашек, pt: тот же, что у подписей солнца.
    static let gap = SunARLabelLayout.gap

    /// Размер значков точек: часа (как у часа солнца — 10 pt в расчёте занятого) и события.
    static let hourDot: CGFloat = 10
    static var eventDot: CGFloat { SunARInk.eventDot + 3 }

    static func place(track: NightSkyARScene.CoreTrack, scene: SunARScene, sunLabels: [SunARLabelLayout.Placed],
                      avoid: [CGRect], clock: ClockText, eventText: (NightSkyARScene.CoreTrack.Event) -> String,
                      screen: CGRect) -> [SunARLabelLayout.Placed] {
        let bounds = screen.insetBy(dx: -40, dy: -40)
        var taken = sunLabels.map(\.pill) + avoid
        // Значки точек солнца: час и событие.
        let sunHourDots = scene.hours.compactMap { h -> CGRect? in
            let c = CGPoint(x: h.point.x, y: h.point.y)
            return bounds.contains(c) && !SunARLabelLayout.isUnderSun(h, scene: scene)
                ? CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10) : nil
        }
        let sunEventDots = scene.events.compactMap { e -> CGRect? in
            guard let p = e.point, bounds.contains(CGPoint(x: p.x, y: p.y)) else { return nil }
            return CGRect(x: p.x - eventDot / 2, y: p.y - eventDot / 2, width: eventDot, height: eventDot)
        }
        taken += sunHourDots + sunEventDots
        // Свои значки: подписи часов и событий обходят и их.
        var ownDots: [CGRect] = []
        for e in track.events {
            guard let p = e.point, bounds.contains(CGPoint(x: p.x, y: p.y)) else { continue }
            ownDots.append(CGRect(x: p.x - eventDot / 2, y: p.y - eventDot / 2, width: eventDot, height: eventDot))
        }
        for h in track.hours {
            let c = CGPoint(x: h.point.x, y: h.point.y)
            guard bounds.contains(c), !isUnderSun(h, scene: scene) else { continue }
            ownDots.append(CGRect(x: c.x - hourDot / 2, y: c.y - hourDot / 2, width: hourDot, height: hourDot))
        }

        func free(_ r: CGRect, ignoring own: CGRect?) -> Bool {
            let grown = r.insetBy(dx: -gap, dy: -gap)
            return !taken.contains { grown.intersects($0) } && !ownDots.contains { $0 != own && grown.intersects($0) }
        }
        func inside(_ r: CGRect) -> Bool { screen.contains(r) }

        var out: [SunARLabelLayout.Placed] = []

        // События: где стоят; занято — ближайшее свободное место. Подпись остаётся целиком в экране.
        for e in track.events {
            guard let p = e.point, bounds.contains(CGPoint(x: p.x, y: p.y)) else { continue }
            let text = eventText(e)
            let size = SunARLabelLayout.textSize(text, size: 11, weight: .semibold)
            let w = size.width + 2 * SunARLabelLayout.padX, h = size.height + 2 * SunARLabelLayout.padY
            let own = CGRect(x: p.x - eventDot / 2, y: p.y - eventDot / 2, width: eventDot, height: eventDot)
            // Сначала над точкой (как подпись события солнца), ниже, затем рядами дальше.
            let rows: [CGFloat] = [-20, 20, -42, 42, -64, 64, -86, 86]
            func plate(_ dy: CGFloat, _ dx: CGFloat) -> CGRect {
                var cx = p.x + dx
                cx = min(max(cx, screen.minX + 6 + w / 2), screen.maxX - 6 - w / 2)
                return CGRect(x: cx - w / 2, y: p.y + dy - h / 2, width: w, height: h)
            }
            var chosen: CGRect?
            search: for dx: CGFloat in [0, -w / 2, w / 2] {
                for dy in rows {
                    let r = plate(dy, dx)
                    if inside(r), free(r, ignoring: own) { chosen = r; break search }
                }
            }
            let r = chosen ?? plate(rows[0], 0)
            out.append(SunARLabelLayout.Placed(kind: .event, text: text, center: CGPoint(x: r.midX, y: r.midY), pill: r,
                                               fontSize: 11, weight: .semibold, opacity: 1))
            taken.append(r)
        }

        // Часы дуги: над точкой, а не нашла места — под ней; иначе точка без подписи.
        for hr in track.hours {
            let c = CGPoint(x: hr.point.x, y: hr.point.y)
            guard bounds.contains(c), !isUnderSun(hr, scene: scene) else { continue }
            let text = clock.fmt(Double(hr.hour * 60))
            let size = SunARLabelLayout.textSize(text, size: 11, weight: .medium)
            let w = size.width + 2 * SunARLabelLayout.padX, h = size.height + 2 * SunARLabelLayout.padY
            let own = CGRect(x: c.x - hourDot / 2, y: c.y - hourDot / 2, width: hourDot, height: hourDot)
            for dy: CGFloat in [-17, 17] {
                let r = CGRect(x: c.x - w / 2, y: c.y + dy - h / 2, width: w, height: h)
                guard free(r, ignoring: own) else { continue }
                out.append(SunARLabelLayout.Placed(kind: .hour, text: text, center: CGPoint(x: r.midX, y: r.midY), pill: r,
                                                   fontSize: 11, weight: .medium, opacity: hr.altitude < 0 ? 0.75 : 1))
                taken.append(r)
                break
            }
        }
        return out
    }

    /// Часы ядра рядом с меткой солнца: точка лежала бы под линзой (36 pt, как у часов солнца).
    static func isUnderSun(_ h: NightSkyARScene.CoreTrack.Hour, scene: SunARScene) -> Bool {
        [scene.marker, scene.nowMarker].contains { m in
            m.map { hypot($0.x - h.point.x, $0.y - h.point.y) < 36 } ?? false
        }
    }

    /// Занятое значками точек траектории (для подписей звёзд и планет): часы и события ядра.
    static func dots(track: NightSkyARScene.CoreTrack, scene: SunARScene, screen: CGRect) -> [CGRect] {
        let bounds = screen.insetBy(dx: -40, dy: -40)
        var out: [CGRect] = []
        for e in track.events {
            guard let p = e.point, bounds.contains(CGPoint(x: p.x, y: p.y)) else { continue }
            out.append(CGRect(x: p.x - eventDot / 2, y: p.y - eventDot / 2, width: eventDot, height: eventDot))
        }
        for h in track.hours {
            let c = CGPoint(x: h.point.x, y: h.point.y)
            guard bounds.contains(c), !isUnderSun(h, scene: scene) else { continue }
            out.append(CGRect(x: c.x - hourDot / 2, y: c.y - hourDot / 2, width: hourDot, height: hourDot))
        }
        return out
    }
}
