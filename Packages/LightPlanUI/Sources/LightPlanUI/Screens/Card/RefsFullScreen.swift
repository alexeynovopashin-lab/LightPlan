import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Полный экран референсов (`#refsFull`, `#refView`, итерация 27, шаг 4)

/// Экран во весь размер поверх карточки: папки, два раздела плиток в две колонки
/// в пропорциях кадров, поверх — просмотрщик. Картинок в нативе пока нет
/// (решение Алексея 29.09, 1А), плитки — штриховка `RefPlaceholder`. Закрывается
/// только ✕; смахивание вниз — у просмотрщика (как в вебе). Справка 27, раздел 4.
struct RefsFullScreen: View {
    @Bindable var app: AppModel
    let s: Session
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var tiles: [String: CGRect] = [:]
    /// Ширина сетки (экран минус поля 24) — по ней колонки и высоты плиток.
    @State private var gridW: CGFloat = 345

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        let sec = app.refSections(s)
        ZStack {
            VStack(spacing: 0) {
                head(pal)
                folders(pal)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if app.cardRefs(s).isEmpty || sec.isEmpty && app.refsFull?.tag == nil {
                            Text(t.t("refs.empty")).font(webFont(14)).foregroundStyle(pal.ink6)
                                .padding(.top, 20)
                        }
                        section(t.t("refs.own"), sec.own, pal)
                        section(t.t("refs.set", ["genre": genreName]), sec.set, pal)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 40)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width - 48 } action: { gridW = $0 }
                }
            }
            if app.refsFull?.pager != nil { RefViewerLayer(app: app, s: s, tiles: tiles) }
        }
        .coordinateSpace(name: "refs")
        .background(pal.surface.ignoresSafeArea())
        .shotNode("refs.full", text: "\(sec.flat.count)")
    }

    private var genreName: String { s.genre.map { t.t("genre.\($0.rawValue)") } ?? "" }

    // MARK: шапка и папки

    private func head(_ pal: Palette) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.t("card.refs")).font(webFont(17)).foregroundStyle(pal.ink)
                Text(app.refsFullSub(s)).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1)
            }
            Spacer(minLength: 10)
            FormBarButton(node: "refs.close", kind: .close, label: t.t("card.close")) {
                withAnimation(overlaySlide) { app.closeRefsFull() }
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 8)
    }

    @ViewBuilder private func folders(_ pal: Palette) -> some View {
        let used = RefFolders.used(in: app.cardRefs(s), genre: s.genre?.rawValue)
        if !used.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(t.t("refs.all"), on: app.refsFull?.tag == nil, pal) { app.setRefFolder(nil) }
                    ForEach(used, id: \.self) { code in
                        chip(tagName(code), on: app.refsFull?.tag == code, pal) { app.setRefFolder(code) }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 12)
        }
    }

    private func tagName(_ code: String) -> String {
        let v = t.t("tag.\(code)")
        return v == "tag.\(code)" ? code : v
    }

    private func chip(_ text: String, on: Bool, _ pal: Palette, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(webFont(13)).foregroundStyle(on ? pal.sheet : pal.ink3)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? pal.brass : .clear))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(on ? .clear : pal.press, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: сетка

    @ViewBuilder private func section(_ title: String, _ frames: [RefFrame], _ pal: Palette) -> some View {
        if !frames.isEmpty {
            HStack {
                Text(title).font(webFont(12)).foregroundStyle(pal.ink6)
                Text("· \(frames.count)").font(webFont(12)).foregroundStyle(pal.ink7)
                Spacer(minLength: 0)
            }
            .padding(.top, 16).padding(.bottom, 8)
            grid(frames, pal)
        }
    }

    /// `column-count: 2`, зазор 8: первая колонка сверху вниз, потом вторая.
    private func grid(_ frames: [RefFrame], _ pal: Palette) -> some View {
        let w = (gridW - 8) / 2
        let hs = frames.map { RefColumns.height(w: $0.w, h: $0.h, width: Double(w)) }
        let n = RefColumns.firstColumnCount(heights: hs)
        func col(_ a: ArraySlice<Double>) -> Double { a.reduce(0, +) + Double(max(0, a.count - 1)) * 8 }
        return HStack(alignment: .top, spacing: 8) {
            column(Array(frames[..<n]), Array(hs[..<n]), w, pal)
            column(Array(frames[n...]), Array(hs[n...]), w, pal)
        }
        .frame(height: CGFloat(max(col(hs[..<n]), col(hs[n...]))), alignment: .top)
    }

    private func column(_ frames: [RefFrame], _ hs: [Double], _ w: CGFloat, _ pal: Palette) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(frames.enumerated()), id: \.element.id) { i, f in
                tile(f, CGFloat(hs[i]), pal)
                    .frame(width: w, height: CGFloat(hs[i]))
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func tile(_ f: RefFrame, _ h: CGFloat, _ pal: Palette) -> some View {
        let hidden = app.refViewerFrameId == f.id
        Button {
            switch app.openRefFrame(f.id, in: s) {
            case .url(let u): openURL(u)
            case .viewer, .none: break
            }
        } label: {
            if f.kind == .link, let u = f.url {
                linkTile(u, pal)
            } else {
                RefPlaceholder(pal: pal)
            }
        }
        .buttonStyle(.plain)
        .opacity(hidden ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("refs")) } action: { tiles[f.id] = $0 }
        .shotNode("refs.tile", text: f.id)
    }

    private func linkTile(_ url: String, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(RefLink.host(url) ?? t.t("ref.link")).font(webFont(15, 600)).foregroundStyle(pal.ink).lineLimit(1)
            Text(RefLink.tail(url)).font(webFont(11.5)).foregroundStyle(pal.ink6).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Просмотрщик (`#refView`)

/// Кадр целиком на затемнённом фоне: счётчик, ✕, подсказка. Жесты — числа
/// справки: листание от 60 pt сдвига кадра, закрытие вниз от 110, щипок 1–6,
/// касание — лестница выхода. Закрытие летит в плитку кадра, на котором
/// остановились; плитка ушла за край больше чем на 40 pt — уменьшается на месте.
private struct RefViewerLayer: View {
    @Bindable var app: AppModel
    let s: Session
    let tiles: [String: CGRect]
    @Environment(\.colorScheme) private var scheme
    @State private var drag: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var shown = false
    @State private var goingHome: CGRect?
    @State private var shrinking = false
    @State private var vp = CGSize.zero

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        GeometryReader { geo in
            let full = CGRect(origin: .zero, size: geo.size)
            let id = app.refViewerFrameId ?? ""
            let frame = app.refSections(s).flat.first { $0.id == id }
            let fit = fitRect(frame, in: geo.size)
            let start = tiles[id]
            let box = RefHome.rect(open: shown, shrinkingInPlace: shrinking, home: goingHome.map(refBox),
                                   start: start.map(refBox), fit: refBox(fit))
            let rect = CGRect(x: box.x, y: box.y, width: box.w, height: box.h)
            let open = shown && !shrinking
            ZStack {
                pal.overlay2.opacity(open ? 1 : 0).ignoresSafeArea()
                RefPlaceholder(pal: pal, radius: open ? 0 : 9)
                    .frame(width: rect.width, height: rect.height)
                    .scaleEffect(scale * dragScale * (shrinking ? 0.82 : 1))
                    .offset(x: rect.midX - full.midX + drag.width * 0.9 + pan.width,
                            y: rect.midY - full.midY + max(0, drag.height) * 0.9 + min(0, drag.height) * 0.25 + pan.height)
                    .opacity((start == nil && !shown) || shrinking ? 0 : 1)
                    .gesture(gestures(pal))
                if open { chrome(pal) }
            }
            .onAppear { vp = geo.size; withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.26)) { shown = true } }
        }
    }

    /// Кадр вписан в экран с полями 24 сверху/снизу под панели.
    private func fitRect(_ f: RefFrame?, in size: CGSize) -> CGRect {
        let maxW = size.width, maxH = size.height - 160
        let ratio = CGFloat(RefColumns.height(w: f?.w, h: f?.h, width: 1))
        var w = maxW, h = w * ratio
        if h > maxH { h = maxH; w = h / ratio }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    /// Пока идёт смах вниз: `1 − dy/900`, не меньше 0,82, с dy > 60.
    private var dragScale: CGFloat { drag.height > 60 ? max(0.82, 1 - drag.height / 900) : 1 }

    private func refBox(_ r: CGRect) -> RefBox { RefBox(x: r.minX, y: r.minY, w: r.width, h: r.height) }

    private func chrome(_ pal: Palette) -> some View {
        VStack {
            HStack {
                FormBarButton(node: "refs.viewer.close", kind: .close, label: t.t("card.close")) { close() }
                Spacer()
                if let c = app.refsFull?.pager?.counter {
                    Text(c).font(webFont(14)).foregroundStyle(pal.ink3).shotNode("refs.viewer.counter", text: c)
                }
            }
            .padding(.horizontal, 24).padding(.top, 8)
            Spacer()
            if (app.refsFull?.pager?.count ?? 0) >= 2 {
                Text(t.t("mb.viewerHint")).font(webFont(12)).foregroundStyle(pal.ink6).padding(.bottom, 30)
            }
        }
        .transition(.opacity)
    }

    private func gestures(_ pal: Palette) -> some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if scale > 1.001 { pan = CGSize(width: panBase.width + v.translation.width,
                                                    height: panBase.height + v.translation.height) }
                    else { drag = v.translation }
                }
                .onEnded { v in
                    let moved = hypot(v.translation.width, v.translation.height)
                    if scale > 1.001 {
                        // Касание без движения при увеличении — сброс до целого кадра.
                        if moved < 4 { withAnimation(.easeOut(duration: 0.26)) { scale = 1; pinchBase = 1; pan = .zero; panBase = .zero } }
                        else { panBase = pan }
                        return
                    }
                    // Сдвиг кадра = палец × 0,9 (кадр идёт за пальцем).
                    let d = moved < 4 ? RefPager.tap(scale: scale)
                        : RefPager.decide(dx: v.translation.width * 0.9, dy: v.translation.height * 0.9)
                    switch d {
                    case .close: close()
                    case .next, .previous:
                        _ = app.refViewerSwipe(dx: d == .next ? -RefPager.pageShift : RefPager.pageShift, dy: 0)
                        withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.26)) { drag = .zero }
                    case .stay: withAnimation(.easeOut(duration: 0.26)) { drag = .zero }
                    }
                },
            MagnifyGesture()
                .onChanged { scale = RefPager.clampZoom(pinchBase * $0.magnification) }
                .onEnded { _ in
                    pinchBase = scale
                    if scale <= 1.001 { withAnimation(.easeOut(duration: 0.26)) { pan = .zero; panBase = .zero } }
                }
        )
    }

    /// Закрытие: кадр летит в плитку кадра, на котором остановились, или
    /// уменьшается на месте; потом просмотрщик снимается.
    private func close() {
        let id = app.refViewerFrameId
        let view = CGRect(origin: .zero, size: vp)
        let tile = id.flatMap { tiles[$0] }
        let target = RefHome.target(tile: tile.map { RefBox(x: $0.minX, y: $0.minY, w: $0.width, h: $0.height) },
                                    viewport: RefBox(x: view.minX, y: view.minY, w: view.width, h: view.height))
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.26)) {
            if target != nil { goingHome = tile; shown = false } else { shrinking = true }
            drag = .zero; scale = 1; pan = .zero
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { app.closeRefViewer() }
    }
}
