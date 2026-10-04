import SwiftUI
import LightPlanCore
import LightPlanDomain
import LightPlanMapCanvas

// Режим маршрута «Карты» (итерация 24а): визир, кнопки «Маршрут» и «Моё
// место», кольцо касания и полоса черновика. Числа — справка веба
// `docs/native_24a_route_web_spec.md`.

/// Визир (`sightMorph`, `SIGHT_A/B`): головка не подменяется вторым знаком, а
/// перетекает в белую булавку. Обе фигуры — четыре кубические дуги одной
/// формы на холсте знака `pin` (24): круг r 7 с центром (12, 10) и капля с
/// остриём (12, 21); доля `t` смешивает их линейно, как `sightDraw`.
/// Натив мерит головку и булавку одними 20 pt (20г), поэтому масштаба веба
/// (13 → 10,5) нет: меняется только форма и сдвиг — у круга под центром
/// кадра центр головки, у булавки — остриё, ровно там, где встанет точка.
struct SightShape: Shape {
    var t: Double
    var animatableData: Double { get { t } set { t = newValue } }

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        let y0 = m(17, 21)
        var path = Path()
        path.move(to: p(12, y0))
        path.addCurve(to: p(19, 10), control1: p(m(15.866, 12), m(17, 21)), control2: p(19, m(13.866, 14.7)))
        path.addCurve(to: p(12, 3), control1: p(19, 6.134), control2: p(15.866, 3))
        path.addCurve(to: p(5, 10), control1: p(8.134, 3), control2: p(5, 6.134))
        path.addCurve(to: p(12, y0), control1: p(5, m(13.866, 14.7)), control2: p(m(8.134, 12), m(17, 21)))
        path.closeSubpath()
        return path
    }
}

/// Головка ротора с визиром. Рамка — холст знака 24 × 24 в масштабе булавки
/// (20 / 14); её середина ставится в центр окна. Доля анимируется снаружи
/// (`withAnimation`), `Animatable` пересобирает стекло на каждом кадре: у
/// встроенного стекла своей интерполяции формы нет.
struct SightHead: View, @preconcurrency Animatable {
    var t: Double
    let pal: Palette
    var animatableData: Double { get { t } set { t = newValue } }

    static let side: CGFloat = 24 * MapSpots.glyphScale

    var body: some View {
        let k = MapSpots.glyphScale
        ZStack(alignment: .topLeading) {
            KnobGlass(shape: SightShape(t: t), pal: pal)
            // Зрачок `r = 2,6·t` — точка сохранённой булавки (`PinGlyph`).
            Circle().fill(pal.brass)
                .frame(width: 2 * 2.6 * k * t, height: 2 * 2.6 * k * t)
                .offset(x: (12 - 2.6 * t) * k, y: (10 - 2.6 * t) * k)
        }
        .frame(width: Self.side, height: Self.side)
        // Под центром окна: у круга — центр головки (12, 10), у булавки —
        // остриё (12, 21). Середина рамки — (12, 12).
        .offset(y: (2 - 11 * t) * k)
    }
}

/// Визир уступает место булавке, стоящей ровно под его остриём (ближе
/// `cover` pt): садящаяся под ним булавка спорила с ним, а стоящая под ним
/// давала два стекла одно на другом — булавка белела скачком, когда визир
/// возвращался (Алексей 28.09, кадры симулятора). Сдвинули карту — визир
/// отделяется от булавки на первом же кадре жеста: камеру читает сам, как
/// слой булавок, и экран на каждом кадре не пересобирается.
struct SightSlot: View {
    let t: Double
    let feed: MapCameraFeed
    let fallback: MapCanvasCamera
    /// Булавки, которые визир уступает; пусто — визир виден всегда.
    let spots: [Spot]
    let pal: Palette

    /// Место точки — пять знаков после запятой, до ~0,5 м: при крупном
    /// приближении булавка встаёт на 1–3 pt в стороне от острия.
    static let cover: CGFloat = 3

    var body: some View {
        let cam = feed.camera ?? fallback
        let covered = spots.contains { sp in
            guard let la = sp.latitude, let lo = sp.longitude else { return false }
            let d = MapSpots.offset(latitude: la, longitude: lo, camera: cam)
            return abs(d.x) < Self.cover && abs(d.y) < Self.cover
        }
        SightHead(t: t, pal: pal).opacity(covered ? 0 : 1)
    }
}

/// Знак `.map-here` «Моё место» (`#mapHere`): кольцо r 4 и четыре риски.
struct MapHereGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        var p = Path()
        p.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8))
        for (a, b) in [((12.0, 2.0), (12.0, 5.0)), ((12, 19), (12, 22)), ((2, 12), (5, 12)), ((19, 12), (22, 12))] {
            p.move(to: CGPoint(x: a.0, y: a.1))
            p.addLine(to: CGPoint(x: b.0, y: b.1))
        }
        return p.applying(CGAffineTransform(scaleX: k, y: k)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Кружок карты 34 на стекле со знаком 18 / 1,8 (`.map-here`): «Моё место»
/// и «Маршрут». Нажатый и включённый — латунью.
struct MapRoundButton<Glyph: View>: View {
    let pal: Palette
    let darkCanvas: Bool
    let on: Bool
    let label: String
    let node: String
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        let ink = MapGlassCircle.ink(pal, darkCanvas: darkCanvas)
        Button(action: action) { EmptyView() }
            .buttonStyle(MapRoundPress(on: on, ink: ink, glyph: glyph))
            .modifier(MapGlassCircle(pal: pal, darkCanvas: darkCanvas))
            .accessibilityLabel(label)
            .shotNode(node)
    }
}

/// Знак кружка; нажатый — латунью (`.map-here:active { color: var(--brass) }`).
private struct MapRoundPress<Glyph: View>: ButtonStyle {
    let on: Bool
    let ink: Palette
    let glyph: () -> Glyph
    func makeBody(configuration: Configuration) -> some View {
        glyph()
            .foregroundStyle(on || configuration.isPressed ? ink.brass : ink.ink3)
            .frame(width: 18, height: 18)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
    }
}

/// Кольцо касания (`.map-tap`): 54, кант 1,4 латунью, `scale .3 → 1`,
/// `opacity .6 → 0` за 0,44 с. Говорит «нажатие засчитано» там, где палец:
/// точка родится в центре кадра, а палец жмёт мимо. Живёт вне ротора.
struct MapTapRing: View {
    let pal: Palette
    @State private var go = false

    var body: some View {
        Circle().strokeBorder(pal.brass, lineWidth: 1.4)
            .frame(width: 54, height: 54)
            .scaleEffect(go ? 1 : 0.3)
            .opacity(go ? 0 : 0.6)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.44)) { go = true } }
    }
}

/// Номер места в черновике (`.sm-no`): кружок 15 латунью, цифра 9,5 / 700
/// цветом `--surface`. У веба он слева-сверху от знака 18 px и заходит на
/// головку на 1,4; у натива головка 20 pt — то же направление и тот же нахлёст.
struct RouteNumber: View {
    let n: Int
    let pal: Palette

    /// Центр кружка от острия булавки.
    static let center = CGPoint(x: -14.9, y: -21.7)

    var body: some View {
        Text(String(n))
            .font(.system(size: 9.5, weight: .bold).monospacedDigit())
            .foregroundStyle(pal.surface)
            .frame(width: 15, height: 15)
            .background(Circle().fill(pal.brass))
    }
}

/// Строка, которую тянут: откуда, куда встанет и сдвиг пальца.
private struct RowDrag: Equatable {
    let from: Int
    var to: Int
    var dy: CGFloat
}

/// Строка списка черновика: место и способ перехода к следующей.
struct RouteRow: Identifiable, Equatable {
    let id: String
    let name: String
    /// К следующей точке — пешком; `nil` у последней: выходить ей некуда.
    let walk: Bool?
}

/// Полоса черновика (`#mapRouteBar`, `renderRouteBar`, `renderRouteList`).
/// Плашка: `--bar` на стекле, рамка 1 `--ink-10`, радиус 16, внутри 8 / 8 / 9,
/// зазор 7. Верх — знак, счёт, «＋» и «✕»; список строк 28 окном до 121;
/// низ — «Сделать съёмкой» (мест нет вовсе — «Сохранить это место»). Пока
/// висит «Вернуть» снятого черновика, она лежит на выключенной кнопке, а
/// полоса держит прежнюю высоту (`hold`).
struct RouteBar: View {
    let rows: [RouteRow]
    /// «12 км · 25 мин» — когда ответили все куски дороги.
    var dist: String? = nil
    let hasSpots: Bool
    /// Есть место не в черновике — «＋» виден.
    let canAdd: Bool
    let undo: UndoOffer?
    let lexicon: Lexicon
    let pal: Palette
    var onAdd: (CGRect) -> Void = { _ in }
    var onClear: () -> Void = {}
    var onDrop: (String) -> Void = { _ in }
    /// Перестановка: строка `from` встала на `to` (по отпусканию).
    var onMove: (Int, Int) -> Void = { _, _ in }
    var onWay: (Int) -> Void = { _ in }
    var onMake: () -> Void = {}
    var onSave: () -> Void = {}
    var onUndo: () -> Void = {}
    var onUndoExpire: (UUID) -> Void = { _ in }

    @State private var height: CGFloat = 0
    @State private var held: CGFloat?
    @State private var addFrame: CGRect = .zero
    @State private var drag: RowDrag?
    /// Палец держит строку. Система сбрасывает это сама, когда жест прерван
    /// (шторка, звонок, уход в фон) — там `onEnded` не приходит, и строка
    /// оставалась поднятой до перезапуска (замечание 5 ревью 24а; телефон и
    /// симулятор, 29.09).
    @GestureState private var holding = false
    @State private var lifts = 0
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var scrollY: CGFloat = 0

    static let rowH: CGFloat = 28
    /// Окно списка: 4 строки + 9 (`max-height: 121px`).
    static let listMax: CGFloat = 121

    var body: some View {
        let count = rows.count
        let routeUndo = undo.flatMap { $0.isRoute ? $0 : nil }
        VStack(spacing: 7) {
            top(count)
            if !rows.isEmpty { list }
            bottom(routeUndo)
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 9, trailing: 8))
        .frame(minHeight: routeUndo != nil ? held : nil, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.bar)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(pal.ink10, lineWidth: 1))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onChange(of: routeUndo?.token) { _, t in if t == nil { held = nil } }
        .shotNode("map.routeBar")
    }

    // MARK: верх

    private func top(_ count: Int) -> some View {
        HStack(spacing: 9) {
            Icon("route", size: 17, line: 1.7).foregroundStyle(pal.brass)
            VStack(alignment: .leading, spacing: 1) {
                if count > 0 {
                    // Км и минуты — только от маршрутизатора.
                    let sum = lexicon.count("unit.point", count) + (dist.map { " · " + $0 } ?? "")
                    Text(sum)
                        .font(.system(size: 11)).foregroundStyle(pal.ink4).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .shotNode("route.sum", text: sum)
                } else {
                    Text(lexicon.t(hasSpots ? "map.routeHint" : "map.routeNoSpots"))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.ink)
                        .shotNode("route.sum", text: lexicon.t(hasSpots ? "map.routeHint" : "map.routeNoSpots"))
                    Text(lexicon.t(hasSpots ? "map.routeFromSaved" : "map.routeNoSpotsSub"))
                        .font(.system(size: 11)).foregroundStyle(pal.ink4)
                }
            }
            Spacer(minLength: 0)
            // Кнопкам нечего делать — они уходят, а не гаснут.
            if canAdd {
                Button { onAdd(addFrame) } label: {
                    Icon("plus", size: 15, line: 2).foregroundStyle(pal.brass)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(pal.pressBrass))
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("mapScreen")) } action: { addFrame = $0 }
                .accessibilityLabel(lexicon.t("map.routeAdd"))
                .shotNode("route.add")
            }
            if count > 0 {
                Button {
                    held = height
                    onClear()
                } label: {
                    Icon("close", size: 15, line: 1.7).foregroundStyle(pal.ink4)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(pal.ink10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lexicon.t("map.routeClear"))
                .shotNode("route.clear")
            }
        }
        .padding(.leading, 5)
        .frame(minHeight: 28)
    }

    // MARK: список

    /// Шаг строки: 28 и волосок.
    private static let pitch: CGFloat = rowH + 1

    private var list: some View {
        let full = CGFloat(rows.count) * Self.rowH + CGFloat(max(0, rows.count - 1))
        let window = min(full, Self.listMax)
        let scrolls = full > Self.listMax
        return ScrollView(.vertical) {
            VStack(spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    row(i, r, window: window, full: full)
                }
            }
            // Волоски и пустой слот стоят на сетке строк: строки ездят над ними.
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    ForEach(1 ..< max(1, rows.count), id: \.self) { k in
                        Rectangle().fill(pal.hairline).frame(height: 1)
                            .offset(y: CGFloat(k) * Self.pitch - 1)
                    }
                    if let d = drag {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pal.hair3)
                            .frame(height: Self.rowH)
                            .offset(y: CGFloat(d.to) * Self.pitch)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .coordinateSpace(.named("rbList"))
        }
        .scrollPosition($scroll)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in scrollY = y }
        .scrollDisabled(drag != nil)
        .onChange(of: holding) { _, on in if !on { drop() } }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: window)
        // Строки уходят под низ окна — маска 16 (`mask-image` веба). Пока
        // строку тянут, маски нет: она гасила бы строку у нижнего края.
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: scrolls && drag == nil ? 16 : 0)
            }
        }
        .sensoryFeedback(.selection, trigger: lifts)
        .shotNode("route.list")
    }

    /// Где строка стоит сейчас: поднятая — на слоте, остальные — сдвинуты им.
    private func place(_ i: Int) -> Int {
        guard let d = drag else { return i }
        if i == d.from { return d.to }
        let p = i > d.from ? i - 1 : i
        return p >= d.to ? p + 1 : p
    }

    private func row(_ i: Int, _ r: RouteRow, window: CGFloat, full: CGFloat) -> some View {
        let at = place(i)
        let lifted = drag?.from == i
        return HStack(spacing: 0) {
            // Номер — рукоять перестановки: удержание 250 мс (сдвиг > 8 —
            // отмена), дальше строка идёт за пальцем (`rbHold`).
            Text(String(at + 1))
                .font(.system(size: lifted ? 12 : 9.5, weight: .bold).monospacedDigit())
                .foregroundStyle(pal.surface)
                .frame(width: lifted ? 22 : 15, height: lifted ? 22 : 15)
                .background(Circle().fill(pal.brass))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .gesture(hold(i, window: window, full: full))
                .shotNode("route.no.\(i + 1)")
            Text(r.name).font(.system(size: 13.5)).foregroundStyle(pal.ink).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let walk = r.walk {
                Button { onWay(i) } label: {
                    Icon(walk ? "hiker" : "car", size: 16, line: 1.6)
                        .foregroundStyle(walk ? pal.brass : pal.ink7)
                        .frame(width: 30, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lexicon.t(walk ? "map.wayWalk" : "map.wayDrive"))
                .shotNode("route.way.\(i + 1)")
            }
            Button { onDrop(r.id) } label: {
                Icon("close", size: 13, line: 1.8).foregroundStyle(pal.ink7)
                    .frame(width: 34, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lexicon.t("map.routeDrop"))
        }
        .frame(height: Self.rowH)
        // Поднятая строка: 34 (по 3 за края), радиус 10, `--peek-2`, тень
        // `0 10 24 --glass-cast`, кант латунью .35 (`.rb-row.drag`).
        .background {
            if lifted {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pal.peek2)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(red: 226 / 255, green: 164 / 255, blue: 76 / 255, opacity: 0.35), lineWidth: 1))
                    .shadow(color: pal.glassCast, radius: 12, y: 10)
                    .padding(.vertical, -3)
            }
        }
        .offset(y: lifted ? drag?.dy ?? 0 : CGFloat(at - i) * Self.pitch)
        .zIndex(lifted ? 1 : 0)
        .shotNode("route.row.\(i + 1)", text: r.name)
    }

    private func hold(_ i: Int, window: CGFloat, full: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("rbList")))
            .updating($holding) { v, on, _ in if case .second(true, _) = v { on = true } }
            .onChanged { v in
                guard case .second(true, let g) = v else { return }
                if drag == nil {
                    drag = RowDrag(from: i, to: i, dy: 0)
                    lifts += 1
                }
                guard let g, var d = drag else { return }
                d.dy = g.translation.height
                // У краёв окна список едет сам на 6 за кадр жеста.
                let y = g.location.y - scrollY
                if full > window {
                    if y < 22 { scroll.scrollTo(y: max(0, scrollY - 6)) }
                    else if y > window - 22 { scroll.scrollTo(y: min(full - window, scrollY + 6)) }
                }
                d.to = max(0, min(rows.count - 1, Int(((CGFloat(i) * Self.pitch + d.dy) / Self.pitch).rounded())))
                drag = d
            }
            .onEnded { _ in drop() }
    }

    /// Строку отпустили — или жест прервала система: встаёт туда, куда её
    /// дотащили, как у веба (`pointercancel` → `rbDragEnd`). Второй вызов
    /// (конец жеста и сброс `holding` приходят оба) ничего не делает.
    private func drop() {
        guard let d = drag else { return }
        drag = nil
        if d.to != d.from { onMove(d.from, d.to) }
    }

    // MARK: низ

    @ViewBuilder
    private func bottom(_ routeUndo: UndoOffer?) -> some View {
        if !hasSpots {
            Button(action: onSave) {
                HStack(spacing: 8) {
                    Icon("bookmark", size: 16, line: 1.6)
                    Text(lexicon.t("map.routeSaveHere")).font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(pal.brass)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(pal.brassDark, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shotNode("route.save")
        } else {
            let on = !rows.isEmpty
            Button(action: onMake) {
                Text(lexicon.t("map.routeMake")).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(on ? pal.surface : pal.ink5)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? pal.brass : pal.ink10))
            }
            .buttonStyle(.plain)
            .disabled(!on)
            .overlay { if let u = routeUndo { undoPlate(u) } }
            .shotNode("route.make")
        }
    }

    /// «Маршрут снят · 3 точки» и «Вернуть» — на выключенной кнопке, 6 с.
    private func undoPlate(_ u: UndoOffer) -> some View {
        HStack(spacing: 12) {
            Text(u.text).font(.system(size: 13)).foregroundStyle(pal.ink4).lineLimit(1)
                .shotNode("undo.text", text: u.text)
            Spacer(minLength: 0)
            Button(action: onUndo) {
                Text(lexicon.t("plan.undo")).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(pal.brass).padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .shotNode("undo.btn")
        }
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.overlay3))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(pal.hairline, lineWidth: 1))
        .transition(.opacity)
        .task(id: u.token) {
            try? await Task.sleep(for: .seconds(UndoOffer.seconds))
            onUndoExpire(u.token)
        }
    }
}

/// Линия черновика на холсте (`placeRoutePath`). Слой под булавками, над
/// вуалью; куски — `routeRuns`. Пока дорогу ещё спрашивают — прямая штрихом,
/// 2,2 латунью .45, `dash 6 6`; не ответил никто — куска на карте нет (28л.5). Дорога машиной — ореол 7,5 / .2 и линия 2,8 / .95; пешком —
/// цепочка точек 2,8 / .9, `dash 0 5,6` (круглый конец делает точку).
struct RoutePathLayer: View {
    let runs: [RouteRun]
    /// Ответ на каждый кусок по порядку; `nil` — ещё спрашивают (прямая
    /// штрихом), `.some(nil)` — не ответил никто (линии нет).
    let roads: [RoadAnswer??]
    let feed: MapCameraFeed
    let fallback: MapCanvasCamera
    let anchor: CGPoint
    let pal: Palette

    var body: some View {
        let cam = feed.camera ?? fallback
        let raw = path(cam) { road, _ in if case .none = road { true } else { false } }
        let car = path(cam) { road, run in (road ?? nil) != nil && run.mode == .car }
        let foot = path(cam) { road, run in (road ?? nil) != nil && run.mode == .foot }
        ZStack {
            car.stroke(pal.brass.opacity(0.2), style: StrokeStyle(lineWidth: 7.5, lineCap: .round, lineJoin: .round))
            car.stroke(pal.brass.opacity(0.95), style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
            foot.stroke(pal.brass.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round, dash: [0, 5.6]))
            raw.stroke(pal.brass.opacity(0.45),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, dash: [6, 6]))
        }
        .allowsHitTesting(false)
        .shotNode("route.line")
    }

    /// Точки линии каждого куска: прямая у спрашиваемого, дорога у ответившего,
    /// пусто у отказа.
    static func lines(runs: [RouteRun], roads: [RoadAnswer??]) -> [[MapCanvasCenter]] {
        runs.enumerated().map { j, run in
            switch j < roads.count ? roads[j] : nil {
            case .none: return run.points
            case .some(.none): return []
            case .some(.some(let a)): return a.line
            }
        }
    }

    private func path(_ cam: MapCanvasCamera, _ take: (RoadAnswer??, RouteRun) -> Bool) -> Path {
        let lines = Self.lines(runs: runs, roads: roads)
        return Path { p in
            for (j, run) in runs.enumerated() {
                let road: RoadAnswer?? = j < roads.count ? roads[j] : nil
                guard take(road, run) else { continue }
                for (i, c) in lines[j].enumerated() {
                    let d = MapSpots.offset(latitude: c.latitude, longitude: c.longitude, camera: cam)
                    let pt = CGPoint(x: anchor.x + d.x, y: anchor.y + d.y)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
        }
    }
}
