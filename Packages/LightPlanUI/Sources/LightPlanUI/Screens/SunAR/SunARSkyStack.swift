import SwiftUI
import LightPlanCore

/// Всё, что экран AR кладёт между кадром камеры и подписями: полоса Млечного Пути, дуга с часами, и по каждой
/// метке — линза и налёт (шаг 29.8в.5). Вынесено из `SunARScreen`, чтобы юнит-тест рисовал тот же код, что идёт
/// на экран, и мерил смещение дуги в диске.
///
/// Порядок снизу вверх: полоса → дуга (внутри дисков вырезана) → линза метки (гнутая копия того, что под
/// диском) → налёт метки. Метки идут от нижней к верхней: следующая лежит над предыдущей целиком.
struct SunARSkyStack: View {
    let scene: SunARScene
    let night: NightSkyARScene?
    let marks: [SunARMark]
    let size: CGSize
    let clock: ClockText
    /// Восемь румбов от севера по часовой.
    let cardinals: [String]
    let coreLabel: String
    let eventText: (SunARScene.HorizonEvent) -> String
    /// Событие, совпавшее с выбранным моментом: его подпись у горизонта не ставится, время написано на метке.
    var mergedEvent: SunARScene.HorizonEvent.Kind? = nil
    /// Подпись метки выбранного момента (её плашку рисует `SunARMarkLabels`): раскладка оставляет ей место.
    var pickedText: String? = nil
    /// Небо без камеры: его кладёт под линзу, чтобы кромка гнула и его. `nil` — кадр гнёт слой Metal под дугой.
    let sky: AnyView?
    var markText: (SunARMark) -> String = { _ in "" }
    /// Какие слои рисовать. `nil` — по умолчанию (все; в отладке — по `-LPSunARLayers`). Юнит-тест выбирает
    /// слои сам: дуга и линза без налёта — чтобы по пикселям мерить смещение линии.
    var layers: Set<SunARLayers>? = nil
    /// Стекло дисков (шаг 29.8в.9а): своё — линза-копия над дугой с вырезом и налёт; системное — `.glassEffect`, оно
    /// само гнёт то, что под ним, поэтому дуга под ним целая.
    var glass: SunARGlassStyle = .own
    /// Звёзды и созвездия (29.8в.13); `nil` — оба слоя выключены.
    var stars: StarSkyARScene? = nil
    /// Слово по ключу словаря (`con.Ori`, `star.sirius`) — для подписей слоя.
    var starName: (String) -> String = { $0 }
    /// «Звёзд днём не видно».
    var starsDayText: String = ""
    /// Окно, в котором живут подписи слоя: между кнопками сверху и панелью снизу.
    var starWindow: CGRect? = nil
    /// Занятое стрелками за краем (кружок и подпись каждой): подписи слоя их обходят.
    var pointerRects: [CGRect] = []

    /// Наименьший зазор между плашками подписей горизонта и часов, pt (для снимков; 99 — подпись одна).
    private var labelGap: CGFloat {
        #if DEBUG
        let labels = SunARLabelLayout.make(scene: scene, cardinals: cardinals, eventText: eventText, clock: clock,
                                           bounds: CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40),
                                           merged: mergedEvent, pickedText: pickedText)
        return SunARLabelLayout.minimumGap(labels) ?? 99
        #else
        return 99
        #endif
    }

    /// Числа картины для замера по кадру (`Tools/ar_milkyway.py`): видимость и причина, лучи окна, оси галактики,
    /// фокус, высота и азимут ядра, середина полосы на экране (`MilkyWay.band` через `SkyProjection`).
    private static let reporting = UserDefaults.standard.string(forKey: "LPShotReport") != nil

    private static func pictureText(_ night: NightSkyARScene) -> String {
        // Сотня чисел строкой на каждый кадр — только когда снимается отчёт.
        guard reporting else { return "" }
        guard let p = night.milkyWayPicture else { return " vis=—" }
        let f = p.frame
        let nums = (p.pixelToSky + [f.x, f.y, f.z].flatMap { [$0.east, $0.north, $0.up] }).map { String(format: "%.9g", $0) }
        let line = p.centerLine.filter { $0.x > -2000 && $0.x < 4000 && $0.y > -2000 && $0.y < 6000 }
            .map { String(format: "%.2f,%.2f", $0.x, $0.y) }
        return String(format: " vis=%.4f hidden=%@ focal=%.4f coreAlt=%.3f coreAz=%.3f", p.visibility.factor,
                      p.visibility.hidden?.rawValue ?? "none", p.focal, night.coreAltitude, night.coreAzimuth)
            + " m=" + nums.joined(separator: ",") + " line=" + line.joined(separator: ";")
    }

    private func shown(_ l: SunARLayers) -> Bool { layers?.contains(l) ?? SunARLayers.shown(l) }

    /// Занятое на экране, мимо чего подписи слоя звёзд не ставятся: подписи горизонта, часов и сторон света, плашка
    /// выбранного момента, диски меток солнца и луны, подпись ядра Млечного Пути, стрелки за краем (29.8в.6, 29.8в.10).
    var starTaken: [CGRect] {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40)
        var taken = SunARLabelLayout.make(scene: scene, cardinals: cardinals, eventText: eventText, clock: clock,
                                          bounds: bounds, merged: mergedEvent, pickedText: pickedText).map(\.pill)
        if let text = pickedText, let plate = SunARLabelLayout.pickedPill(text: text, scene: scene) { taken.append(plate) }
        taken += marks.map { CGRect(x: $0.center.x - $0.radius, y: $0.center.y - $0.radius,
                                    width: $0.diameter, height: $0.diameter).insetBy(dx: -2, dy: -2) }
        if let c = night?.core, night?.milkyWayOn == true {
            // Подпись ядра: 11 pt по числу знаков, плашка 7 · 2, лежит на 30 pt ниже ядра (`SunARMilkyWayLayer`).
            let w = CGFloat(coreLabel.count) * 6.5 + 14
            taken.append(CGRect(x: c.x - w / 2, y: c.y + 30 - 10, width: w, height: 20))
        }
        return taken + pointerRects
    }

    /// Подписи слоя звёзд и дневная плашка. Днём подписывать нечего — звёзд нет, остаётся плашка.
    private func starLabels(_ stars: StarSkyARScene) -> (labels: [SunARStarLabels.Placed], note: SunARStarLabels.Placed?) {
        let window = starWindow ?? CGRect(origin: .zero, size: size)
        let taken = starTaken
        if stars.daylight {
            return ([], SunARStarLabels.dayNote(text: starsDayText, taken: taken, window: window))
        }
        guard stars.visibility > 0 else { return ([], nil) }
        let cands = SunARStarLabels.candidates(scene: stars, window: window, name: starName)
        return (SunARStarLabels.place(cands, taken: taken, window: window), nil)
    }

    var body: some View {
        let holes = glass == .own ? marks.map(SunARHole.init) : []
        let moonDiscs = marks.filter { !$0.isSun }.map { ($0.center, $0.radius) }
        ZStack(alignment: .topLeading) {
            if shown(.milkyWay), let night, night.milkyWayOn {
                SunARMilkyWayLayer(scene: night, coreLabel: coreLabel, holes: holes)
                    .frame(width: size.width, height: size.height)
                    .shotNode("ar.milkyWay", text: String(format: "polys=%d core=%@ ghost=%d", night.band.count,
                                                          night.core.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                          night.skyGhost ? 1 : 0) + Self.pictureText(night))
            }
            if shown(.stars), let stars, stars.isOn {
                let placed = starLabels(stars)
                SunARStarLayer(scene: stars, labels: placed.labels, dayNote: placed.note, holes: holes)
                    .frame(width: size.width, height: size.height)
                    .shotNode("ar.stars", text: String(format: "dots=%d lines=%d figures=%d labels=%d vis=%.2f day=%d",
                                                        stars.dots.count, stars.segments.count, stars.figures.count,
                                                        placed.labels.count, stars.visibility, stars.daylight ? 1 : 0))
            }
            if shown(.arc) {
                SunAROverlay(scene: scene, moonArc: night?.arc ?? [], moonDiscs: moonDiscs, clock: clock,
                             cardinals: cardinals, eventText: eventText, merged: mergedEvent, pickedText: pickedText, holes: holes, screen: size)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                    .shotNode("ar.overlay", text: String(format: "marker=%@ now=%@ merged=%d arcSegments=%d hours=%d events=%d labelGap=%.1f",
                                                         scene.marker.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                         scene.nowMarker.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                         scene.markerIsNow ? 1 : 0, scene.arc.count, scene.hours.count,
                                                         scene.events.count, labelGap))
            }
            ForEach(marks) { m in
                if glass == .system {
                    if shown(.paint) { SunARSystemGlassMark(mark: m, shotText: markText(m)) }
                } else {
                    ownMark(m, moonDiscs: moonDiscs)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func ownMark(_ m: SunARMark, moonDiscs: [(CGPoint, CGFloat)]) -> some View {
        if shown(.lens) {
            LensRefraction(diameter: m.diameter, origin: m.origin) { o, side in
                lensContent(windowOrigin: o, side: side, moonDiscs: moonDiscs)
            }
        }
        if shown(.paint) {
            SunARMarkPaint(mark: m, shotText: markText(m))
        }
    }

    /// Что лежит под диском метки, от левого верхнего угла окна линзы: небо без камеры, полоса Млечного Пути и
    /// дуга с подписями — тот же рисунок, что на экране, в маленьком холсте со сдвигом (холст на весь экран на
    /// каждую метку стоил бы четырёх лишних полных отрисовок за кадр).
    @ViewBuilder
    private func lensContent(windowOrigin o: CGPoint, side: CGSize, moonDiscs: [(CGPoint, CGFloat)]) -> some View {
        ZStack(alignment: .topLeading) {
            if let sky {
                sky.offset(x: -o.x, y: -o.y)
            }
            if shown(.milkyWay), let night, night.milkyWayOn {
                SunARMilkyWayCanvas(scene: night, origin: o)
                    .frame(width: side.width, height: side.height)
            }
            if shown(.stars), let stars, stars.isOn {
                SunARStarCanvas(scene: stars, origin: o)
                    .frame(width: side.width, height: side.height)
            }
            if shown(.arc) {
                SunAROverlay(scene: scene, moonArc: night?.arc ?? [], moonDiscs: moonDiscs, clock: clock,
                             cardinals: cardinals, eventText: eventText, merged: mergedEvent, pickedText: pickedText, origin: o, screen: size)
                    .frame(width: side.width, height: side.height)
            }
        }
    }
}
