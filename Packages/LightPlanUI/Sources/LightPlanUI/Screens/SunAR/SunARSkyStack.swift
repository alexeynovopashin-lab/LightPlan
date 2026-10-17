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
    /// Небо без камеры: его кладёт под линзу, чтобы кромка гнула и его. `nil` — кадр гнёт слой Metal под дугой.
    let sky: AnyView?
    var markText: (SunARMark) -> String = { _ in "" }
    /// Какие слои рисовать. `nil` — по умолчанию (все; в отладке — по `-LPSunARLayers`). Юнит-тест выбирает
    /// слои сам: дуга и линза без налёта — чтобы по пикселям мерить смещение линии.
    var layers: Set<SunARLayers>? = nil

    /// Наименьший зазор между плашками подписей горизонта и часов, pt (для снимков; 99 — подпись одна).
    private var labelGap: CGFloat {
        #if DEBUG
        let labels = SunARLabelLayout.make(scene: scene, cardinals: cardinals, eventText: eventText, clock: clock,
                                           bounds: CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40))
        return SunARLabelLayout.minimumGap(labels) ?? 99
        #else
        return 99
        #endif
    }

    private func shown(_ l: SunARLayers) -> Bool { layers?.contains(l) ?? SunARLayers.shown(l) }

    var body: some View {
        let holes = marks.map(SunARHole.init)
        let moonDiscs = marks.filter { !$0.isSun }.map { ($0.center, $0.radius) }
        ZStack(alignment: .topLeading) {
            if shown(.milkyWay), let night, night.milkyWayOn {
                SunARMilkyWayLayer(scene: night, coreLabel: coreLabel, holes: holes)
                    .frame(width: size.width, height: size.height)
                    .shotNode("ar.milkyWay", text: String(format: "polys=%d core=%@ ghost=%d", night.band.count,
                                                          night.core.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                          night.skyGhost ? 1 : 0))
            }
            if shown(.arc) {
                SunAROverlay(scene: scene, moonArc: night?.arc ?? [], moonDiscs: moonDiscs, clock: clock,
                             cardinals: cardinals, eventText: eventText, holes: holes, screen: size)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                    .shotNode("ar.overlay", text: String(format: "marker=%@ now=%@ merged=%d arcSegments=%d hours=%d events=%d labelGap=%.1f",
                                                         scene.marker.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                         scene.nowMarker.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "—",
                                                         scene.markerIsNow ? 1 : 0, scene.arc.count, scene.hours.count,
                                                         scene.events.count, labelGap))
            }
            ForEach(marks) { m in
                if shown(.lens) {
                    LensRefraction(diameter: m.diameter, origin: m.origin) { o, side in
                        lensContent(windowOrigin: o, side: side, moonDiscs: moonDiscs)
                    }
                }
                if shown(.paint) {
                    SunARMarkPaint(mark: m, shotText: markText(m))
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
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
            if shown(.arc) {
                SunAROverlay(scene: scene, moonArc: night?.arc ?? [], moonDiscs: moonDiscs, clock: clock,
                             cardinals: cardinals, eventText: eventText, origin: o, screen: size)
                    .frame(width: side.width, height: side.height)
            }
        }
    }
}
