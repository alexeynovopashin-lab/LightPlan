import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Большой виджет (30и.13, вариант Б2; выбор Алексея 15.11: «Большой виджет Б… поле снизу меняется на виджет с отсчётом Браун»).
/// Сверху «Свет» как в приложении: шапка, купол с Солнцем **и** Луной (ушедшие под горизонт — призраки по правилу купола), ножки с временем и оценкой
/// рассвета и заката; под щелью — блок отсчёта Braun: циферблат с кольцом точек до ближайшей съёмки и её строки. Подложка и цвета — Braun
/// (`WidgetStyle`); рисков на большом нет — они только у Braun (Алексей 16.11). Эскиз: `docs/30i13_big_widget.html` § 8.
/// Плашка 364 × 382 (Pro Max) и 338 × 354 (iPhone 14); поля 16, высоты полос: 16 + 4 + купол 158·s + 2 + ножки 38 + 8 + блок.
struct LargeView: View {
    let frame: WidgetFrame
    var alpha = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            Inner(frame: frame, alpha: alpha, pal: BraunPalette(dark: scheme == .dark), st: WidgetStyle(dark: scheme == .dark), size: g.size)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    struct Inner: View {
        let frame: WidgetFrame
        let alpha: Bool
        let pal: BraunPalette
        let st: WidgetStyle
        let size: CGSize
        static let pad: CGFloat = 16

        private var iw: CGFloat { size.width - 2 * Self.pad }
        private var s: CGFloat { iw / DomeFit.canvasWidth }
        private var domeH: CGFloat { (DomeFit.bottomUnits - DomeFit.topUnits) * s }
        private var zone: TimeZone { frame.zone }

        private func dateLine() -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: frame.lang)
            f.timeZone = zone
            f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
            let t = f.string(from: frame.now)
            return t.prefix(1).uppercased() + t.dropFirst()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(dateLine()) · \(frame.place.name.isEmpty ? "Light Plan" : frame.place.name)")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(pal.muted).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if alpha { AlphaBadge() }
                }
                .frame(height: 16)
                Spacer().frame(height: 4)
                dome
                Spacer().frame(height: 2)
                feet.frame(height: 38)
                Spacer().frame(height: 8)
                CountdownBlock(frame: frame, pal: pal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Self.pad)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }

        // MARK: Купол

        @ViewBuilder private var dome: some View {
            if let d = frame.day, let rise = d.sunrise, let set = d.sunset {
                let sky = BigWidget.sky(frame)
                SunArc(rise: rise, set: set, now: frame.now, clock: frame.clock(frame.now, in: zone),
                       word: sky.map { BigWidget.phaseWord($0.code, frame.words) } ?? frame.words[.sunrise].uppercased(), st: st, skyNow: sky)
                    .frame(width: iw, height: domeH)
            } else {
                // Полярные сутки/ночь: купола нет, слово места.
                Text(frame.day?.polar == .night ? frame.words[.polarNight] : frame.words[.polarDay])
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.text).frame(width: iw, height: domeH)
            }
        }

        // MARK: Ножки купола: восход · золотой час · закат, ширина — по дуге (от (32 − 14)·s до (358 + 14)·s холста)

        private var feet: some View {
            let inset = 18 * s
            let rating = frame.rating
            return ZStack(alignment: .top) {
                HStack(alignment: .top, spacing: 0) {
                    cell(frame.words[.sunrise], "sunrise", frame.day?.sunrise, score: rating?.sunrise, accent: false, align: .leading)
                    Spacer(minLength: 0)
                    cell(frame.words[.sunset], "sunset", frame.day?.sunset, score: rating?.score, accent: false, align: .trailing)
                }
                cell(frame.words[.golden], "sun", frame.day?.golden, score: nil, accent: true, align: .center)
            }
            .padding(.horizontal, inset)
            .frame(width: iw, alignment: .top)
        }

        private func cell(_ name: String, _ sign: String, _ at: Date?, score: Int?, accent: Bool, align: HorizontalAlignment) -> some View {
            let passed = at.map { $0 < frame.now } ?? false
            return VStack(alignment: align, spacing: 1) {
                HStack(spacing: 5) {
                    WidgetIcon(name: sign, size: 15).foregroundStyle(accent ? pal.amber : pal.muted)
                    Text(at.map { frame.clock($0, in: zone) } ?? "—")
                        .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(accent ? pal.amber : pal.text.opacity(passed ? 0.55 : 1))
                }
                if let line = BigWidget.scoreLine(score, frame.words) {
                    Text(line).font(.system(size: 11)).foregroundStyle(pal.muted).lineLimit(1).minimumScaleFactor(0.7)
                } else if accent {
                    Text(name).font(.system(size: 11)).foregroundStyle(pal.muted).lineLimit(1)
                }
            }
        }
    }
}

/// Геометрия купола приложения (`DomeGeometry`: полуэллипс 163 × 148 на холсте 390 × 240, горизонт на y = 196), вписанная в плашку.
/// Расширение не видит `LightPlanUI`, поэтому числа скопированы (как `WidgetIcons.generated.swift`); сверка — `WidgetDomeTests`.
/// Пропорции фиксированы: форма не зависит от размера плашки, зависит только масштаб.
struct DomeFit: Equatable {
    static let rx: CGFloat = 163, ry: CGFloat = 148, canvasWidth: CGFloat = 390
    /// От макушки (с запасом на линию) до пояса под горизонтом, в единицах холста: y = 44 … 202.
    static let topUnits: CGFloat = 44, bottomUnits: CGFloat = 202, horizonUnits: CGFloat = 196

    let scale: CGFloat
    let centerX: CGFloat
    let horizonY: CGFloat
    var rx: CGFloat { Self.rx * scale }
    var ry: CGFloat { Self.ry * scale }

    /// Масштаб — по ширине плашки (как холст приложения); если не хватает высоты, меньше. Купол по центру плашки.
    init(in size: CGSize) {
        let boxH = Self.bottomUnits - Self.topUnits
        scale = max(0.01, min(size.width / Self.canvasWidth, size.height / boxH))
        centerX = size.width / 2
        horizonY = (size.height - boxH * scale) / 2 + (Self.horizonUnits - Self.topUnits) * scale
    }

    /// Точка дуги при доле дня `f` (0 — восход слева, 1 — закат справа).
    func point(_ f: Double) -> CGPoint {
        let a = Double.pi * (1 - f)
        return CGPoint(x: centerX + rx * CGFloat(cos(a)), y: horizonY - ry * CGFloat(sin(a)))
    }
}

/// Купол дня как на экране «Свет» (эскиз 14.11): небо внутри, дуга латунь → серый → латунь, диск солнца с кольцом, пунктир горизонта,
/// время и слово света в центре. Ночной вид — позже; сейчас небо одно, дневное и вечернее.
struct SunArc: View {
    let rise: Date
    let set: Date
    let now: Date
    let clock: String
    let word: String
    let st: WidgetStyle
    /// 30и.13: небо момента (Луна, слово света, ночная дорожка Солнца). `nil` — как было (тесты купола).
    var skyNow: BigWidget.Sky? = nil
    private var night: Bool { (skyNow?.sunElevation ?? 1) < -0.833 }
    /// Ночью небо тёмно-синее в обеих темах (как «Свет»: `DomeSky.nightLight`), слова поверх белые.
    private var onSky: Color { (st.dark || night) ? Color(red: 0xEC / 255, green: 0xEC / 255, blue: 0xEA / 255) : Color.black }

    /// Небо: тёмная плашка — синее из эскиза (#101B33 → #2A3550), светлая — дневное небо палитры Д (#86BAEC → #DCEBF9).
    private var sky: Gradient {
        (st.dark || night) ? Gradient(colors: [Color(red: 0x10 / 255, green: 0x1B / 255, blue: 0x33 / 255), Color(red: 0x2A / 255, green: 0x35 / 255, blue: 0x50 / 255)])
                : Gradient(colors: [Color(red: 0x86 / 255, green: 0xBA / 255, blue: 0xEC / 255), Color(red: 0xDC / 255, green: 0xEB / 255, blue: 0xF9 / 255)])
    }
    private var grey: Color { Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x92 / 255) }

    var body: some View {
        GeometryReader { g in
            let fit = DomeFit(in: g.size)
            ZStack {
                Canvas { ctx, size in draw(ctx, fit: fit, size: size) }
                VStack(spacing: 2 * fit.scale) {
                    Text(clock).font(.system(size: 40 * fit.scale, weight: .ultraLight)).monospacedDigit().foregroundStyle(onSky)
                    Text(word).font(.system(size: 13 * fit.scale, weight: .semibold)).tracking(1.6).lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(onSky)
                }
                .frame(width: fit.rx * 1.1)
                .position(x: fit.centerX, y: fit.horizonY - fit.ry * 0.40)
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, fit: DomeFit, size: CGSize) {
        func frac(_ d: Date) -> Double { min(1, max(0, d.timeIntervalSince(rise) / set.timeIntervalSince(rise))) }
        let left = CGPoint(x: fit.centerX - fit.rx, y: fit.horizonY), right = CGPoint(x: fit.centerX + fit.rx, y: fit.horizonY)
        func arc() -> Path {
            var p = Path()
            p.move(to: fit.point(0))
            for i in 1...80 { p.addLine(to: fit.point(Double(i) / 80)) }
            return p
        }
        // Небо внутри купола.
        var dome = arc(); dome.closeSubpath()
        ctx.fill(dome, with: .linearGradient(sky, startPoint: CGPoint(x: 0, y: fit.horizonY - fit.ry), endPoint: CGPoint(x: 0, y: fit.horizonY)))
        // Дуга.
        let grad = Gradient(colors: [st.amber, grey, st.amber])
        ctx.stroke(arc(), with: .linearGradient(grad, startPoint: left, endPoint: right), style: StrokeStyle(lineWidth: 3 * max(fit.scale, 0.8), lineCap: .round))
        // Пунктир горизонта чуть шире купола.
        var horizon = Path()
        let pad = 14 * fit.scale
        horizon.move(to: CGPoint(x: max(0, left.x - pad), y: fit.horizonY)); horizon.addLine(to: CGPoint(x: min(size.width, right.x + pad), y: fit.horizonY))
        ctx.stroke(horizon, with: .color(st.ink.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        // Солнце: ореол, тёмное кольцо, ядро; до восхода и после заката стоит у края серым (прежний вид) или, если известно небо, призраком на ночной дорожке.
        let day = now >= rise && now <= set
        var p = fit.point(frac(now))
        var core = day ? st.amber : st.ink.opacity(0.4)
        var sunAlpha = 1.0
        if let sky = skyNow, !day {
            let nextRise = sky.nextRise ?? rise.addingTimeInterval(86_400)
            let th: Double
            if now > set { th = -min(1, now.timeIntervalSince(set) / max(1, nextRise.timeIntervalSince(set))) * .pi }
            else { th = .pi + min(1, rise.timeIntervalSince(now) / max(1, rise.timeIntervalSince(set.addingTimeInterval(-86_400)))) * .pi }
            p = CGPoint(x: fit.centerX + fit.rx * CGFloat(cos(th)), y: fit.horizonY + 4 * fit.scale * CGFloat(abs(sin(th))))
            core = st.amber
            sunAlpha = BigWidget.ghostOpacity(elevation: sky.sunElevation)
        }
        func disc(_ r: CGFloat, _ c: Color, at q: CGPoint, alpha: Double = 1) { ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)), with: .color(c.opacity(alpha))) }
        if day { disc(16.5 * fit.scale, st.amber.opacity(0.18), at: p) }
        disc(9.4 * fit.scale, st.dark ? Color(red: 0x0C / 255, green: 0x0B / 255, blue: 0x0A / 255) : Color.white, at: p, alpha: sunAlpha)
        disc(6.5 * fit.scale, core, at: p, alpha: sunAlpha)
        // Луна — всегда на небе: над горизонтом диском с фазой, под ним призраком (то же правило плотности, что у Солнца).
        if let sky = skyNow {
            let f = min(1, max(0, (sky.moonAzimuth - 90) / 180))
            var q = fit.point(f)
            let up = sky.moonAltitude >= 0
            if !up { q.y = fit.horizonY + 4 * fit.scale * CGFloat(abs(sin(f * .pi))) }
            let a = up ? 1 : BigWidget.ghostOpacity(elevation: sky.moonAltitude)
            let r = 6.5 * fit.scale
            disc(9.4 * fit.scale, st.dark ? Color(red: 0x0C / 255, green: 0x0B / 255, blue: 0x0A / 255) : Color.white, at: q, alpha: a)
            disc(r, Color(red: 0xE9 / 255, green: 0xE5 / 255, blue: 0xD3 / 255), at: q, alpha: a)
            // Тень неосвещённой части: круг того же радиуса, сдвинутый в сторону тени на освещённую долю, обрезан по диску.
            let d = CGFloat(sky.moonFraction) * 2 * r * (sky.moonWaxing ? -1 : 1)
            ctx.drawLayer { l in
                l.clip(to: Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)))
                l.fill(Path(ellipseIn: CGRect(x: q.x - r + d, y: q.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0x16 / 255, green: 0x22 / 255, blue: 0x3F / 255).opacity(a)))
            }
        }
    }
}
