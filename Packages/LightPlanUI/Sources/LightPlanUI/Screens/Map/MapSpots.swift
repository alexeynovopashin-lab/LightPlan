import SwiftUI
import LightPlanCore
import LightPlanDomain
import LightPlanData
import LightPlanMapCanvas

/// Сохранённые точки на карте (итерация 20б): булавки над ночной вуалью и под
/// прибором (`#mapSpots` веба). Проекцию веб берёт у движка (`lmap.project`);
/// здесь холст сообщает камеру — центр и крупность, — а перевод в точки кадра
/// считается меркатором (плитка 512, как `metersPerPoint`), одинаково для
/// MapLibre и MapKit. Центр камеры стоит под головкой наблюдателя.
enum MapSpots {
    /// Сдвиг точки от центра камеры в точках кадра.
    static func offset(latitude: Double, longitude: Double, camera: MapCanvasCamera) -> CGPoint {
        let world = 512 * pow(2, camera.zoom)
        return CGPoint(x: (mercX(longitude) - mercX(camera.center.longitude)) * world,
                       y: (mercY(latitude) - mercY(camera.center.latitude)) * world)
    }

    static func mercX(_ lon: Double) -> Double { (lon + 180) / 360 }
    static func mercY(_ lat: Double) -> Double {
        let phi = max(-85.051129, min(85.051129, lat)) * .pi / 180
        return (1 - log(tan(phi) + 1 / cos(phi)) / .pi) / 2
    }

    /// За кадром знак не рисуется (`placeMarks`: −140…w+140 по ширине,
    /// −80…h+80 по высоте слоя).
    static func onScreen(_ p: CGPoint, in size: CGSize) -> Bool {
        p.x >= -140 && p.y >= -80 && p.x <= size.width + 140 && p.y <= size.height + 80
    }

    /// Тело булавки: знак 18 × 18, остриё (12, 21) холста 24 × 24 — на 9
    /// вправо и 15,75 вниз от угла (`.spot-mark svg`).
    static let body = CGRect(x: -9, y: -15.75, width: 18, height: 18)
    /// Подпись (`.sm-name`): 8 вправо от острия, 14 вверх, не шире 132.
    static let labelOrigin = CGPoint(x: 8, y: -14)
    static let labelMax: CGFloat = 132
    static let labelHeight: CGFloat = 15

    /// Попадание тапа (`spotAtPoint`): тело с полем 6, подпись с полем 4;
    /// две булавки внахлёст — ближняя к центру задетой части.
    static func hit(_ tap: CGPoint, marks: [(id: String, tip: CGPoint, labelWidth: CGFloat)]) -> String? {
        var best: String?, bestD = CGFloat.infinity
        for m in marks {
            let parts = [(body.offsetBy(dx: m.tip.x, dy: m.tip.y), CGFloat(6)),
                         (CGRect(x: m.tip.x + labelOrigin.x, y: m.tip.y + labelOrigin.y,
                                 width: m.labelWidth, height: labelHeight), CGFloat(4))]
            for (r, pad) in parts where r.width > 0 && r.insetBy(dx: -pad, dy: -pad).contains(tap) {
                let d = pow(tap.x - r.midX, 2) + pow(tap.y - r.midY, 2)
                if d < bestD { bestD = d; best = m.id }
                break
            }
        }
        return best
    }
}

/// Слой булавок. Касаний не ловит (`pointer-events: none` веба): под ним
/// карта, которую водят пальцем, и знак с перехваченным касанием был бы
/// мёртвой зоной. Тап приходит от холста (`onTap`) и попадание считается
/// `MapSpots.hit`.
struct MapSpotsLayer: View {
    let spots: [Spot]
    let feed: MapCameraFeed
    let fallback: MapCanvasCamera
    /// Центр камеры в слое — точка под головкой наблюдателя.
    let anchor: CGPoint
    let here: GeoCoordinate
    let pal: Palette

    var body: some View {
        let cam = feed.camera ?? fallback
        GeometryReader { g in
            ForEach(spots.filter { $0.latitude != nil && $0.longitude != nil }) { sp in
                let d = MapSpots.offset(latitude: sp.latitude!, longitude: sp.longitude!, camera: cam)
                let tip = CGPoint(x: anchor.x + d.x, y: anchor.y + d.y)
                if MapSpots.onScreen(tip, in: g.size) {
                    SpotMark(spot: sp, here: sp.coordinate.isSameSpot(as: here), pal: pal,
                             onLabel: { feed.labelWidths[sp.id] = $0 })
                        .position(tip)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Одна булавка (`.spot-mark`): сплошная латунь с обводкой цветом холста;
/// взятая у геокодера — полая (`.addr`); под головкой наблюдателя — только
/// тонкое кольцо (`.here`), без подписи.
private struct SpotMark: View {
    let spot: Spot
    let here: Bool
    let pal: Palette
    let onLabel: (CGFloat) -> Void

    var body: some View {
        // Нулевая рамка с остриём в начале координат, как `.spot-mark` веба.
        ZStack(alignment: .topLeading) {
            if here {
                Circle().stroke(pal.brass, lineWidth: 1.4).opacity(0.55)
                    .frame(width: 22, height: 22)
                    .offset(x: -11, y: -11)
            } else {
                PinGlyph(pinned: spot.pinned == true, pal: pal)
                    .frame(width: 18, height: 18)
                    .offset(x: MapSpots.body.minX, y: MapSpots.body.minY)
                // Плашка та же, что у атрибуции (`--bar-2` на размытии 8):
                // не шире 132, длинное имя обрезается многоточием.
                Text(spot.name.isEmpty ? spot.coordinate.text : spot.name)
                    .font(.system(size: 11, weight: .semibold)).tracking(0.2)
                    .foregroundStyle(pal.ink2)
                    .lineLimit(1).truncationMode(.tail)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background {
                        ZStack { Rectangle().fill(.ultraThinMaterial); Rectangle().fill(pal.bar2) }
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onLabel($0) }
                    .frame(maxWidth: MapSpots.labelMax, alignment: .leading)
                    .frame(width: MapSpots.labelMax, height: MapSpots.labelHeight, alignment: .leading)
                    .offset(x: MapSpots.labelOrigin.x, y: MapSpots.labelOrigin.y)
            }
        }
        .frame(width: 0, height: 0, alignment: .topLeading)
    }
}

/// Знак `pin` залитым: у веба `fill: var(--brass); stroke: var(--canvas)`,
/// у полого (`.addr`) заливка — цвет холста, обводка латунью 1,8.
private struct PinGlyph: View {
    let pinned: Bool
    let pal: Palette

    var body: some View {
        let art = Icon.common("pin")
        let k: CGFloat = 18 / 24
        ZStack {
            ForEach(art.parts.indices, id: \.self) { i in
                let shape = IconOutline(path: art.parts[i].path)
                shape.fill(pinned ? pal.brass : pal.canvas)
                shape.stroke(pinned ? pal.canvas : pal.brass,
                             style: StrokeStyle(lineWidth: (pinned ? 1.6 : 1.8) * k, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Камера холста, которую слой булавок читает на каждом кадре жеста. Своим
/// объектом, а не состоянием экрана: иначе каждый кадр пересобирал бы весь
/// экран с прибором, а не одни знаки.
@MainActor @Observable
final class MapCameraFeed {
    var camera: MapCanvasCamera?
    /// Ширина подписей — для попадания тапа по подписи.
    @ObservationIgnored var labelWidths: [String: CGFloat] = [:]
}

/// Полоса имени точки (`#spotNameBar`): знак, поле имени и под ним координаты
/// сохранённого — доказательство, что записано место под булавкой, а не
/// место телефона; корзина терракотой и галочка латунью.
struct SpotNameBar: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let coord: String
    let lexicon: Lexicon
    let pal: Palette
    let onDelete: () -> Void
    let onDone: () -> Void
    /// Тронули полосу — обратный отсчёт снимается (`snbHold`).
    let onTouch: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Icon("pin", size: 17, line: 1.7).foregroundStyle(pal.brass)
            VStack(alignment: .leading, spacing: 1) {
                // Поле — строка 18 (15 px веба), координаты — на всю колонку,
                // как блоки колонки `.snb-fields` (замер пары 20б).
                field
                    .frame(height: 18)
                    .shotNode("spot.name", text: text)
                Text(coord)
                    .font(.system(size: 10)).tracking(0.3).monospacedDigit()
                    .foregroundStyle(pal.ink4).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shotNode("spot.coord", text: coord)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDelete) {
                Icon("trash", size: 15, line: 1.7).foregroundStyle(pal.badInk)
                    .frame(width: 30, height: 30).background(pal.badBg, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lexicon.t("map.delSpot"))
            .shotNode("spot.del")
            Button(action: onDone) {
                Icon("check", size: 17, line: 2.2).foregroundStyle(pal.surface)
                    .frame(width: 34, height: 34).background(pal.brass, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lexicon.t("map.nameDone"))
            .shotNode("spot.ok")
        }
        // Поля CSS (7 7 7 11) плюс рамка 1: у веба она снаружи полей,
        // здесь `strokeBorder` рисует внутрь.
        .padding(.leading, 12).padding(.vertical, 8).padding(.trailing, 8)
        .background {
            ZStack { Rectangle().fill(.ultraThinMaterial); Rectangle().fill(pal.bar) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pal.ink10, lineWidth: 1))
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in onTouch() })
        .shotNode("spot.bar")
    }

    private var field: some View {
        let f = TextField("", text: $text, prompt: Text(lexicon.t("map.nameSpot")).foregroundStyle(pal.ink5))
            .font(.system(size: 15)).foregroundStyle(pal.ink)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .focused(focus)
            .submitLabel(.done)
            .onSubmit(onDone)
        #if os(iOS)
        return f.textInputAutocapitalization(.sentences)
        #else
        return f
        #endif
    }
}

/// Закладка шапки (`.map-save`): 44 × 44, знак 20 чернилами `--ink-6`;
/// место под головкой сохранено — латунь с плотной заливкой.
struct MapSaveButton: View {
    let on: Bool
    let lexicon: Lexicon
    let pal: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let art = Icon.common("bookmark")
            let k: CGFloat = 20 / 24
            ZStack {
                ForEach(art.parts.indices, id: \.self) { i in
                    let shape = IconOutline(path: art.parts[i].path)
                    shape.fill(on ? pal.brass : .clear)
                    shape.stroke(on ? pal.brass : pal.ink6,
                                 style: StrokeStyle(lineWidth: 1.7 * k, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: 20, height: 20)
            .animation(.easeOut(duration: 0.18), value: on)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lexicon.t(on ? "map.dropPoint" : "map.savePoint"))
        .shotNode("map.save")
    }
}
