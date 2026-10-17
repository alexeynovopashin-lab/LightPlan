import SwiftUI
import LightPlanCore

/// Зоны экрана AR и раскладка стрелок за краем (шаг 29.8в.6). Чистая геометрия: экран зовёт её, тест меряет её же.
///
/// Сверху лежат кнопки (одна строка или две — включатели уходят под курс на узком экране), снизу панель времени.
/// Светило, чей диск виден между ними, стрелки не получает: она легла бы на него. Диск под кнопками или под панелью
/// не виден — для него стрелка нужна (ревью GPT к 29.8в.3–4: стрелка подавлялась и под верхними кнопками).
enum SunARZones {
    /// Просвет между кнопками и экранными плашками, pt.
    static let margin: CGFloat = 8
    /// Запас под две строки кнопок до первого замера: узкий экран кладёт включатели второй строкой.
    static func reservedButtonsBottom(safeTop: CGFloat) -> CGFloat {
        safeTop + margin + 2 * (SunARInk.touch + margin)
    }

    /// Окно, где диск светила виден: ниже нижней строки кнопок, выше панели. `buttonsBottom` — измеренный низ кнопок
    /// (`nil` до первого замера — запас на две строки).
    static func visibleWindow(size: CGSize, safeTop: CGFloat, buttonsBottom: CGFloat?, panelTop: CGFloat) -> CGRect {
        let top = buttonsBottom.map { $0 + margin } ?? reservedButtonsBottom(safeTop: safeTop)
        return CGRect(x: 0, y: top, width: size.width, height: max(0, panelTop - top))
    }

    /// Диск виден целиком: вся его рамка внутри окна видимости. Хоть краем под кнопками, под панелью или за краем
    /// экрана — не целиком, и стрелка нужна (29.8в.7).
    static func discFullyVisible(center: CGPoint, radius: CGFloat, in window: CGRect) -> Bool {
        window.contains(CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }

    /// Рамка, внутри которой стоят центры стрелок: окно без полос под кнопками и панелью, на радиус значка и просвет
    /// к краю. Верх — всегда запас на две строки: стрелка не лезет под вторую строку кнопок, даже когда её нет.
    static func pointerBox(size: CGSize, safeTop: CGFloat, panelTop: CGFloat) -> ScreenBox {
        let inset = Double(SunARInk.pointerDiameter / 2 + 8)
        return ScreenBox(minX: inset, minY: Double(reservedButtonsBottom(safeTop: safeTop)) + inset,
                         maxX: Double(size.width) - inset, maxY: Double(panelTop) - inset)
    }
}

/// Раскладка стрелок вдоль рамки: два светила в одной стороне ставят значки на одно место («111° · −21°» и
/// «130° · −5°» накладывались на узком экране), поэтому следующая стрелка сдвигается по периметру рамки, пока
/// значок и подпись не освободятся — от уже стоящих, с просветом.
enum SunARPointerLayout {
    /// Просвет между занятыми прямоугольниками стрелок, pt.
    static let gap: CGFloat = 8
    /// Высота плашки подписи «азимут · высота», pt.
    static let labelHeight: CGFloat = 22
    /// Шаг поиска свободного места по периметру, pt.
    static let step: CGFloat = 4

    /// Ширина подписи — как в `SunARPointerView`.
    static func labelWidth(_ text: String) -> CGFloat { CGFloat(text.count) * 7 + 16 }

    /// Занятое стрелкой: кружок и подпись над ним или под ним (как рисует `SunARPointerView`).
    static func occupied(center p: CGPoint, text: String, screen: CGSize, flipY: CGFloat) -> [CGRect] {
        let d = SunARInk.pointerDiameter
        let w = labelWidth(text)
        let below = p.y + d / 2 + 14 < flipY
        let lx = min(max(p.x, w / 2 + 8), screen.width - w / 2 - 8)
        let ly = below ? p.y + d / 2 + 14 : p.y - d / 2 - 14
        return [CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d),
                CGRect(x: lx - w / 2, y: ly - labelHeight / 2, width: w, height: labelHeight)]
    }

    /// Наименьший зазор между занятыми прямоугольниками двух стрелок, pt (отрицательный — наложение).
    static func clearance(_ a: [CGRect], _ b: [CGRect]) -> CGFloat {
        var best = CGFloat.infinity
        for r in a {
            for q in b {
                let dx = max(q.minX - r.maxX, r.minX - q.maxX)
                let dy = max(q.minY - r.maxY, r.minY - q.maxY)
                // Разделены по обеим осям — расстояние по диагонали; по одной — по ней; пересекаются — минус глубина.
                let c = (dx > 0 && dy > 0) ? (dx * dx + dy * dy).squareRoot() : max(dx, dy)
                best = min(best, c)
            }
        }
        return best
    }

    /// Точки периметра рамки по часовой от левого верхнего угла: длина пути `t` → точка.
    private static func point(at t: CGFloat, box: CGRect) -> CGPoint {
        let w = box.width, h = box.height
        let total = 2 * (w + h)
        var s = t.truncatingRemainder(dividingBy: total)
        if s < 0 { s += total }
        if s <= w { return CGPoint(x: box.minX + s, y: box.minY) }
        s -= w
        if s <= h { return CGPoint(x: box.maxX, y: box.minY + s) }
        s -= h
        if s <= w { return CGPoint(x: box.maxX - s, y: box.maxY) }
        s -= w
        return CGPoint(x: box.minX, y: box.maxY - s)
    }

    /// Длина пути до ближайшей к `p` точки периметра.
    private static func parameter(of p: CGPoint, box: CGRect) -> CGFloat {
        let w = box.width, h = box.height
        let dTop = abs(p.y - box.minY), dBottom = abs(p.y - box.maxY)
        let dLeft = abs(p.x - box.minX), dRight = abs(p.x - box.maxX)
        let m = min(dTop, dBottom, dLeft, dRight)
        let cx = min(max(p.x, box.minX), box.maxX), cy = min(max(p.y, box.minY), box.maxY)
        if m == dTop { return cx - box.minX }
        if m == dRight { return w + (cy - box.minY) }
        if m == dBottom { return w + h + (box.maxX - cx) }
        return 2 * w + h + (box.maxY - cy)
    }

    /// Раскладывает стрелки в порядке важности: первая остаётся, каждая следующая — на ближайшее свободное место
    /// по периметру `box` (сначала вперёд, потом назад, шагом `step`). Возвращает точки в том же порядке.
    static func spread(_ items: [(point: CGPoint, text: String)], box: CGRect, screen: CGSize, flipY: CGFloat) -> [CGPoint] {
        var placed: [CGPoint] = []
        var rects: [[CGRect]] = []
        let total = 2 * (box.width + box.height)
        for item in items {
            let origin = parameter(of: item.point, box: box)
            var chosen = item.point
            var found = false
            var shift: CGFloat = 0
            while shift <= total / 2 {
                for sign in (shift == 0 ? [CGFloat(1)] : [CGFloat(1), -1]) {
                    // Нулевой сдвиг — сама точка, она может быть и внутри рамки (центр луча), не на периметре.
                    let p = shift == 0 ? item.point : point(at: origin + sign * shift, box: box)
                    let mine = occupied(center: p, text: item.text, screen: screen, flipY: flipY)
                    if rects.allSatisfy({ clearance(mine, $0) >= gap }) {
                        chosen = p; found = true
                        break
                    }
                }
                if found { break }
                shift += step
            }
            placed.append(chosen)
            rects.append(occupied(center: chosen, text: item.text, screen: screen, flipY: flipY))
        }
        return placed
    }
}
