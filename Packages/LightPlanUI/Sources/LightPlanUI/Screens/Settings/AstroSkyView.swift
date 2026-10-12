import SwiftUI
import LightPlanCore

/// Небо при включении «Астро» — порт `.astro-sky` беты (шаг 29.9).
///
/// Слой поверх «Настроек», касаний не ловит, гаснет сам через 2,4 с. Купол во
/// весь слой: зенит в центре, север вверху, восток слева (поле 200 × 430,
/// `xMidYMid meet`). Что где стоит — `AstroSky.scene` (Core, сверено со
/// стендом паритета); здесь только время.
///
/// Времена и кривые — из CSS беты, кадр считается по часам, а не отдельными
/// анимациями: у каждой звезды своя задержка, а кривая у каждого отрезка
/// ключевых кадров своя (как у CSS).
///
/// Два места, где бета и её замер расходятся с задумкой:
/// - звезда `scale(0.4 → 1)` в SVG растёт вокруг НАЧАЛА ПОЛЯ, а не вокруг
///   себя — звёзды слетаются от верхнего левого угла к своим местам за 0,42 с.
///   Замерено в Chromium и WebKit (`getBoundingClientRect`); переносим то,
///   что видно, а не то, что подразумевал комментарий.
/// - у луны CSS-`transform` анимации перекрывает атрибут `transform` с её
///   местом: в бете она сидит в углу поля, а в WebKit ещё и перескакивает на
///   место в момент 0,72 с. Здесь она сразу на своём месте с тем же подъёмом
///   на 9 единиц и поворотом −12°.
struct AstroSkyView: View {
    let scene: AstroSky.Scene
    let start: Date

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var still

    /// Жизнь слоя, секунды (`setTimeout(…, 2400)` беты).
    static let lifetime = 2.4

    var body: some View {
        let brass = Palette(colorScheme).brass
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                draw(ctx, size: size, t: t, brass: brass)
            }
            // `as-veil`: затемнение и всё небо одной прозрачностью.
            .background(Color.black.opacity(0.42))
            .opacity(Self.veil(t))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, t: Double, brass: Color) {
        // viewBox 200×430, preserveAspectRatio meet: по центру, без обрезки поля.
        let k = min(size.width / AstroSky.fieldWidth, size.height / AstroSky.fieldHeight)
        let ox = (size.width - AstroSky.fieldWidth * k) / 2
        let oy = (size.height - AstroSky.fieldHeight * k) / 2
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * k, y: oy + y * k) }

        // Нити: прочерчиваются по длине, задержка 0,3 с, 1,5 с, кривая (0,3 0,9 0,4 1).
        for l in scene.lines {
            let p = still ? 1 : Self.draw(t)
            if p <= 0 { continue }
            let a = at(l.x1, l.y1), b = at(l.x2, l.y2)
            var path = Path()
            path.move(to: a)
            path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p))
            ctx.stroke(path, with: .color(brass.opacity(0.34)),
                       style: StrokeStyle(lineWidth: 0.6 * k, lineCap: .round, lineJoin: .round))
        }

        // Звёзды: `as-lit` 1,9 с с задержкой по номеру; масштаб вокруг начала поля.
        for s in scene.stars {
            let (opacity, scale) = still ? (0.9, 1.0) : Self.lit(t - s.delay)
            if opacity <= 0 { continue }
            let c = at(s.x * scale, s.y * scale), r = s.radius * scale * k
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .color(brass.opacity(opacity)))
        }

        // Луна: на своём месте, значок `moon` — та же дуга, что у знака библиотеки.
        if let m = scene.moon,
           let glyph = IconArt.art(namespace: "common", name: "moon", in: IconLibrary.common)?.parts.first?.path {
            let (opacity, rise, turn) = still ? (0.9, 0.0, 0.0) : Self.moon(t)
            if opacity > 0 {
                // translate(m − 13) scale(1.1) беты; поворот вокруг центра значка.
                let u = 1.1 * k
                let origin = at(m.x - 13, m.y - 13 + rise)
                let centre = CGPoint(x: origin.x + 12 * u, y: origin.y + 12 * u)
                var tf = CGAffineTransform(translationX: centre.x, y: centre.y)
                tf = tf.rotated(by: turn * .pi / 180).translatedBy(x: -12 * u, y: -12 * u).scaledBy(x: u, y: u)
                ctx.fill(glyph.applying(tf), with: .color(brass.opacity(opacity)))
            }
        }
    }

    // MARK: - Кривые и ключевые кадры (CSS беты)

    /// `cubic-bezier(x1, y1, x2, y2)` CSS: прогресс по времени → значение.
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func f(_ a: Double, _ b: Double, _ s: Double) -> Double {
            3 * a * (1 - s) * (1 - s) * s + 3 * b * (1 - s) * s * s + s * s * s
        }
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if f(x1, x2, mid) < x { lo = mid } else { hi = mid }
        }
        return f(y1, y2, (lo + hi) / 2)
    }

    /// `ease` CSS.
    static func ease(_ x: Double) -> Double { bezier(0.25, 0.1, 0.25, 1, x) }

    /// `as-veil` 2,4 с: 0 → 1 к 14 %, держит до 72 %, → 0 к 100 % (`ease` на каждом отрезке).
    static func veil(_ t: Double) -> Double {
        let u = t / lifetime
        if u <= 0 || u >= 1 { return 0 }
        if u < 0.14 { return ease(u / 0.14) }
        if u <= 0.72 { return 1 }
        return 1 - ease((u - 0.72) / 0.28)
    }

    /// `as-lit` 1,9 с: прозрачность 0 → 1 и масштаб 0,4 → 1 к 22 %, дальше 1.
    /// До начала (задержка) — невидима.
    static func lit(_ local: Double) -> (opacity: Double, scale: Double) {
        if local <= 0 { return (0, 0.4) }
        let u = local / 1.9
        if u >= 0.22 { return (1, 1) }
        let e = ease(u / 0.22)
        return (e, 0.4 + 0.6 * e)
    }

    /// `as-draw` 1,5 с с задержкой 0,3 с, кривая `(0,3 0,9 0,4 1)`: доля длины нити.
    static func draw(_ t: Double) -> Double {
        bezier(0.3, 0.9, 0.4, 1, (t - 0.3) / 1.5)
    }

    /// `as-moon` 2,4 с, кривая `(0,25 1 0,4 1)`: 0 → 0,9 к 30 % с подъёмом 9 и поворотом −12°.
    static func moon(_ t: Double) -> (opacity: Double, rise: Double, turn: Double) {
        let u = t / lifetime
        if u <= 0 { return (0, 9, -12) }
        let p = u >= 0.3 ? 1 : bezier(0.25, 1, 0.4, 1, u / 0.3)
        return (0.9 * p, 9 * (1 - p), -12 * (1 - p))
    }
}

/// Журнал неба для замеров на симуляторе (Debug, `-LPSkyLog <файл>`; имя без
/// «/» — файл в `Documents` приложения): старт слоя и что в нём показано,
/// конец слоя, нажатия «Просто» и появление экрана с уже включённым режимом.
enum SkyLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPSkyLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    #endif
    static func note(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let url, let data = (String(format: "%.3f ", ProcessInfo.processInfo.systemUptime) + line() + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}
