import SwiftUI
import LightPlanCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Подписи на линии горизонта и дуге: часы дуги, «восход 07:57», стороны света (шаг 29.8в.6). Чистая раскладка:
/// экран рисует то, что она вернула, тест меряет зазоры между теми же плашками.
///
/// Снимок Алексея 17.10: «восход 07:57» лежал поверх подписи часа «08:00» — оба в 17–20 pt над линией горизонта,
/// а час отстоит от восхода на три минуты дуги, то есть на несколько pt по горизонтали. Теперь подписи занимают
/// места по важности: восход и закат — где стоят; стороны света — где стоят, но не на метке события (ниже на
/// плашку); часы — только в свободное место, иначе точка часа остаётся без подписи (время восхода уже написано
/// рядом, на ближайшей минуте).
enum SunARLabelLayout {
    enum Kind: Equatable { case event, cardinal, hour }

    struct Placed: Equatable {
        let kind: Kind
        let text: String
        /// Центр текста и плашка под ним.
        let center: CGPoint
        let pill: CGRect
        let fontSize: CGFloat
        let weight: Font.Weight
        let opacity: Double
    }

    /// Просвет, который раскладка оставляет между плашками и до значков точек, pt.
    static let gap: CGFloat = 4
    /// Поля плашки вокруг текста: по горизонтали с каждой стороны и по вертикали, pt.
    static let padX: CGFloat = 6
    static let padY: CGFloat = 3

    /// Размер текста подписи в системном шрифте с моноширинными цифрами — как рисует `Text` на холсте.
    static func textSize(_ text: String, size: CGFloat, weight: Font.Weight) -> CGSize {
        #if canImport(UIKit)
        let w: UIFont.Weight = weight == .semibold ? .semibold : .medium
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: w)
        let s = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(s.width), height: ceil(font.lineHeight))
        #else
        let w: NSFont.Weight = weight == .semibold ? .semibold : .medium
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: w)
        let s = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(s.width), height: ceil(font.ascender - font.descender))
        #endif
    }

    private static func pill(center c: CGPoint, text: String, size: CGFloat, weight: Font.Weight) -> CGRect {
        let s = textSize(text, size: size, weight: weight)
        return CGRect(x: c.x - s.width / 2 - padX, y: c.y - s.height / 2 - padY,
                      width: s.width + 2 * padX, height: s.height + 2 * padY)
    }

    /// Событие дня, с которым совпал выбранный момент, — по минуте, как её читает человек на подписях: «18:13» метки
    /// и «закат 18:13» у горизонта. Оба текста стояли бы одно на другом (метка лежит на точке события, снимок Алексея
    /// 18.10). Остаётся одна подпись — на метке момента: она несёт и дату, если день не сегодняшний, а подпись у
    /// горизонта, которую раскладка тогда не ставит (`make(merged:)`), дала бы то же время второй раз. `nil` — момент
    /// «сейчас» (на его метке времени нет) или не совпал ни с каким событием.
    static func mergedEvent(in scene: SunARScene, pickedIsNow: Bool, pickedMinutes: Double,
                            clock: ClockText) -> SunARScene.HorizonEvent? {
        guard !pickedIsNow else { return nil }
        let picked = clock.fmt(pickedMinutes)
        return scene.events.first { clock.fmt($0.minutes) == picked }
    }

    /// Текст подписи на метке выбранного момента: время («18:13»), с датой, если день не сегодняшний («15 июн · 18:13»);
    /// совпал с событием — «закат 18:13» (`mergedEvent`), та же подпись, что стояла бы у горизонта. `nil` — момент «сейчас».
    static func pickedText(scene: SunARScene, pickedIsNow: Bool, pickedMinutes: Double, clock: ClockText,
                           dayCaption: String?, eventText: (SunARScene.HorizonEvent) -> String) -> String? {
        guard !pickedIsNow else { return nil }
        let time = mergedEvent(in: scene, pickedIsNow: pickedIsNow, pickedMinutes: pickedMinutes, clock: clock)
            .map(eventText) ?? clock.fmt(pickedMinutes)
        return dayCaption.map { "\($0) · \(time)" } ?? time
    }

    /// Плашка подписи метки момента — те же числа и то же правило стороны, что у `SunARMarkLabels` (12 pt, поля 8 · 3;
    /// метка выше «сейчас» — плашка над диском, иначе под ним, на радиус + `SunARInk.markerLabelGap`). Плашку рисует
    /// вид; раскладка занимает её место, чтобы часы и стороны света не легли под неё, а тест меряет зазор до неё.
    static func pickedPill(text: String, scene: SunARScene) -> CGRect? {
        guard let m = scene.marker else { return nil }
        let above = scene.nowMarker.map { m.y < $0.y } ?? false
        let s = textSize(text, size: 12, weight: .medium)
        let radius = SunARInk.pickedLensDiameter / 2
        let c = CGPoint(x: m.x, y: m.y + (above ? -1 : 1) * (radius + SunARInk.markerLabelGap))
        return CGRect(x: c.x - s.width / 2 - 8, y: c.y - s.height / 2 - 3, width: s.width + 16, height: s.height + 6)
    }

    /// Все подписи кадра. `avoidOverlaps == false` — прежнее размещение (каждая на своём месте, без проверок): им
    /// меряется «до». `merged` — событие, чья подпись слита с меткой момента (`mergedEvent`): у горизонта её нет.
    /// `pickedText` — подпись метки момента: её плашка занимает место, стороны света и часы обходят её.
    static func make(scene: SunARScene, cardinals names: [String], eventText: (SunARScene.HorizonEvent) -> String,
                     clock: ClockText, bounds: CGRect, avoidOverlaps: Bool = true,
                     merged: SunARScene.HorizonEvent.Kind? = nil, pickedText: String? = nil) -> [Placed] {
        var out: [Placed] = []
        // Занятое: плашки уже поставленных подписей и значки точек (час, восход/закат).
        var taken: [CGRect] = []
        let dotGlyph = SunARInk.eventDot + 3
        var eventDots: [CGRect] = []
        for e in scene.events {
            guard let pt = e.point else { continue }
            let c = CGPoint(x: pt.x, y: pt.y)
            guard bounds.contains(c) else { continue }
            eventDots.append(CGRect(x: c.x - dotGlyph / 2, y: c.y - dotGlyph / 2, width: dotGlyph, height: dotGlyph))
        }
        if let text = pickedText, let plate = pickedPill(text: text, scene: scene) { taken.append(plate) }
        var hourDots: [CGRect] = []
        for h in scene.hours {
            let c = CGPoint(x: h.point.x, y: h.point.y)
            guard bounds.contains(c), !isUnderSun(h, scene: scene) else { continue }
            hourDots.append(CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
        }
        func free(_ r: CGRect, ignoring own: CGRect?) -> Bool {
            let grown = r.insetBy(dx: -gap, dy: -gap)
            return !taken.contains { grown.intersects($0) }
                && !eventDots.contains { $0 != own && grown.intersects($0) }
                && !hourDots.contains { $0 != own && grown.intersects($0) }
        }

        // Восход и закат: где стоят.
        for e in scene.events {
            guard let pt = e.point else { continue }
            let c = CGPoint(x: pt.x, y: pt.y)
            guard bounds.contains(c), e.kind != merged else { continue }
            let text = eventText(e)
            let at = CGPoint(x: c.x, y: c.y - 20)
            let r = pill(center: at, text: text, size: 11, weight: .semibold)
            out.append(Placed(kind: .event, text: text, center: at, pill: r, fontSize: 11, weight: .semibold, opacity: 1))
            taken.append(r)
        }
        // Стороны света: ниже линии горизонта; налезли на значок или подпись события — на плашку ниже.
        for c in scene.cardinals {
            let p = CGPoint(x: c.point.x, y: c.point.y)
            guard bounds.contains(p), c.index < names.count, !names[c.index].isEmpty else { continue }
            let size: CGFloat = c.isMain ? 13 : 10.5, weight: Font.Weight = c.isMain ? .semibold : .medium
            var at = CGPoint(x: p.x, y: p.y + (c.isMain ? 18 : 15))
            var r = pill(center: at, text: names[c.index], size: size, weight: weight)
            if avoidOverlaps, !free(r, ignoring: nil) {
                let lower = CGPoint(x: at.x, y: at.y + r.height + gap)
                let rl = pill(center: lower, text: names[c.index], size: size, weight: weight)
                if free(rl, ignoring: nil) { at = lower; r = rl }
            }
            out.append(Placed(kind: .cardinal, text: names[c.index], center: at, pill: r, fontSize: size, weight: weight,
                              opacity: c.isMain ? 1 : 0.9))
            taken.append(r)
        }
        // Часы дуги: подпись над точкой; не нашла места — точка остаётся без подписи.
        for h in scene.hours {
            let c = CGPoint(x: h.point.x, y: h.point.y)
            guard bounds.contains(c) else { continue }
            if isUnderSun(h, scene: scene) { continue }
            let text = clock.fmt(Double(h.hour * 60))
            let at = CGPoint(x: c.x, y: c.y - 17)
            let r = pill(center: at, text: text, size: 11, weight: .medium)
            let own = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
            if avoidOverlaps, !free(r, ignoring: own) { continue }
            out.append(Placed(kind: .hour, text: text, center: at, pill: r, fontSize: 11, weight: .medium,
                              opacity: h.altitude < 0 ? 0.75 : 1))
            taken.append(r)
        }
        return out
    }

    /// Солнце стоит на часе — точка и подпись лежали бы под линзой: её роль играет панель времени.
    static func isUnderSun(_ h: SunARScene.Hour, scene: SunARScene) -> Bool {
        [scene.marker, scene.nowMarker].contains { m in
            m.map { hypot($0.x - h.point.x, $0.y - h.point.y) < 36 } ?? false
        }
    }

    /// Наименьший зазор между плашками подписей, pt (отрицательный — наложение); `nil` — подпись одна.
    static func minimumGap(_ labels: [Placed]) -> CGFloat? {
        var best: CGFloat?
        for i in 0..<labels.count {
            for j in (i + 1)..<labels.count {
                let a = labels[i].pill, b = labels[j].pill
                let dx = max(b.minX - a.maxX, a.minX - b.maxX)
                let dy = max(b.minY - a.maxY, a.minY - b.maxY)
                let c = (dx > 0 && dy > 0) ? (dx * dx + dy * dy).squareRoot() : max(dx, dy)
                best = min(best ?? c, c)
            }
        }
        return best
    }
}
