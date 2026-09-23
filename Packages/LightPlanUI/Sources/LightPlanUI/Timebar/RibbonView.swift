import SwiftUI
import LightPlanCore
import LightPlanTimeline
import LightPlanData

/// Лента под ползунком: контекст соседних суток. Два вида — полоса и
/// барабан (`state.machine.ribbonMode`).
///
/// Порт `Spikes/TimebarSpike/App/RibbonView.swift` (итерация 3) на настоящие
/// даты, знаки погоды (`state.weatherSignName`) и фазы луны
/// (`state.moonFraction`) вместо выдуманных суток спайка.
///
/// Нативного скролла здесь нет вовсе, как и в вебе: жест читает только сдвиг
/// пальца, позицию всегда ставит код (DECISIONS «Лента без нативного
/// скролла»).
struct RibbonView: View {
    let state: TimebarState
    /// Образец в настройках (`.drum-preview` веба): три ячейки — вчера,
    /// сегодня, завтра — по центру, без касаний и без сдвига ленты.
    var preview = false
    @Environment(\.drumSlot) private var drumSlot
    @Environment(\.colorScheme) private var colorScheme

    /// `.ribbon-wrap { height: 30px }` — и полоса, и барабан. До 19б здесь
    /// стояли 54 pt прототипа с днём недели и крупным числом.
    static let height = 30.0

    var body: some View {
        let look = DrumLook(scheme: colorScheme, slot: drumSlot)
        let drum = state.machine.ribbonMode == .drum
        GeometryReader { geo in
            let w = geo.size.width
            // Выравнивание по левому краю обязательно: смещения считаются от
            // начала дорожки, как в вебе (DECISIONS «Барабан в нативе»).
            ZStack(alignment: .leading) {
                if drum {
                    RoundedRectangle(cornerRadius: 8).fill(look.face)
                    // Окно — под ячейками, а не поверх: системное стекло
                    // размывает то, что под ним, и поверх ячеек съедало
                    // выбранную дату (снимок 19б). Веб кладёт его сверху, но
                    // его «стекло» только насыщает, не размывает.
                    frame(look)
                        .shotNode("ribbon.frame")
                        .offset(x: w / 2 - 25 + state.machine.wind.strain * 0.6)
                }
                if preview {
                    HStack(spacing: 0) { ForEach(-1...1, id: \.self) { cell(offset: $0, look: look) } }
                        .frame(width: w)
                } else {
                    track(width: w, look: look)
                        .offset(x: -state.machine.ribbonOffset(clipWidth: w) + state.ribbonShift)
                        .opacity(state.ribbonOpacity)
                }
                if drum {
                    DrumShade(look: look).allowsHitTesting(false)
                } else {
                    marker(look).offset(x: w / 2 - 4)
                    #if DEBUG
                    // Начало сегодняшних суток на дорожке — для пары снимков.
                    // Дорожка едет `.offset`, а он рамку в раскладке не
                    // двигает; `.position` двигает.
                    Color.clear.frame(width: w, height: Self.height)
                        .shotNode("ribbon.day0")
                        .position(x: -state.machine.ribbonOffset(clipWidth: w) + state.ribbonShift + w * 1.5,
                                  y: Self.height / 2)
                        .allowsHitTesting(false)
                    #endif
                }
            }
            .frame(width: w, height: Self.height, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        state.dragRibbon(translation: g.translation.width, clipWidth: w)
                    }
                    .onEnded { g in
                        let moved = abs(g.translation.width) + abs(g.translation.height)
                        state.releaseRibbon(tapAt: moved < 6 ? g.location.x : nil, clipWidth: w)
                    }
            )
        }
        .frame(height: Self.height)
        // Губа под барабаном — `box-shadow: 0 1px 0 var(--drum-lip)`: только
        // серп, выглядывающий снизу. Целая подложка под полупрозрачным
        // грунтом высветляла барабан вдвое (замер 19б: #444342 против
        // #1b1a18 у веба в тёмной теме).
        .background {
            if drum { DrumLip().fill(look.lip) }
        }
    }

    @ViewBuilder
    private func track(width: Double, look: DrumLook) -> some View {
        switch state.machine.ribbonMode {
        case .lane:
            HStack(spacing: 0) {
                ForEach(-1...1, id: \.self) { offset in day(offset: offset, width: width, look: look) }
            }
        case .drum:
            HStack(spacing: 0) {
                ForEach(-TimelineMachine.drumSpan...TimelineMachine.drumSpan, id: \.self) { offset in
                    cell(offset: offset, look: look)
                }
            }
        }
    }

    // MARK: - Полоса

    /// `buildRibbonDay`: рельс 4 pt у низа (2 от края) цветом пути светила
    /// за сутки, риски каждый час (1×6 `--rail-5`, шесть часов — 1×8
    /// `--ink-7`) на 10 от низа, цифры 6 · 12 · 18 и дата 8/600 прописными
    /// в одной строке сверху, шов суток — волосок слева.
    private func day(offset: Int, width: Double, look: DrumLook) -> some View {
        let pal = Palette(colorScheme)
        let pxPerMin = width / 1440
        let sun = SolarDay(date: state.date(offset: offset), place: state.place)
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(LinearGradient(gradient: Self.dayGradient(sun), startPoint: .leading, endPoint: .trailing))
                .frame(width: width, height: 4)
                .padding(.top, Self.height - 6)
            ForEach(0...24, id: \.self) { hour in
                let major = hour % 6 == 0
                Rectangle()
                    .fill(major ? pal.ink7 : pal.rail5)
                    .frame(width: 1, height: major ? 8 : 6)
                    .padding(.leading, Double(hour) * 60 * pxPerMin)
                    .padding(.top, Self.height - 10 - (major ? 8 : 6))
                if hour == 6 || hour == 12 || hour == 18 {
                    Text("\(hour)")
                        .font(.system(size: 8, weight: .semibold).monospacedDigit()).tracking(0.5)
                        .foregroundStyle(pal.ink5)
                        .fixedSize()
                        .frame(width: 20)
                        .padding(.leading, Double(hour) * 60 * pxPerMin - 10)
                }
            }
            Rectangle().fill(pal.hair).frame(width: 1, height: Self.height)
            Text(state.dayLabel(offset: offset))
                .font(.system(size: 8, weight: .semibold)).tracking(0.5)
                .foregroundStyle(pal.ink6)
                .fixedSize()
                .padding(.leading, 6)
        }
        .frame(width: width, height: Self.height, alignment: .topLeading)
    }

    /// `ribbonDayGradient`: путь светила за полные сутки, шаг 20 минут.
    static func dayGradient(_ sun: SolarDay) -> Gradient {
        Gradient(stops: stride(from: 0.0, through: 1440, by: 20).map { t in
            let c = PathStops.at(sun.elevation(at: t))
            return Gradient.Stop(color: Color(.sRGB, red: Double(c.rgb.0) / 255, green: Double(c.rgb.1) / 255,
                                              blue: Double(c.rgb.2) / 255, opacity: (c.a * 100).rounded() / 100),
                                 location: t / 1440)
        })
    }

    /// `.ribbon-marker`: волосок `--ink-7` по центру и треугольник `--terra`
    /// 8×7 у низа.
    private func marker(_ look: DrumLook) -> some View {
        let pal = Palette(colorScheme)
        return ZStack(alignment: .bottom) {
            Rectangle().fill(pal.ink7).frame(width: 1, height: Self.height)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 7)); p.addLine(to: CGPoint(x: 4, y: 0)); p.addLine(to: CGPoint(x: 8, y: 7))
                p.closeSubpath()
            }
            .fill(look.terra)
            .frame(width: 8, height: 7)
        }
        .frame(width: 8, height: Self.height)
        .allowsHitTesting(false)
    }

    // MARK: - Барабан

    /// `.drum-cell`: дата 9,5/600 с разрядкой 0,3 (`--ink-5`, у выбранной —
    /// `--ink`) и знак 11×11 под ней через 1 (`--ink-5`, у выбранной —
    /// `--terra`).
    private func cell(offset: Int, look: DrumLook) -> some View {
        let center = offset == 0
        return VStack(spacing: 1) {
            Text(state.dayLabel(offset: offset))
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit()).tracking(0.3)
                .foregroundStyle(center ? look.ink : look.ink5)
                .lineLimit(1)
                .fixedSize()
            sign(offset: offset)
                .foregroundStyle(center ? look.terra : look.ink5)
                .frame(width: 11, height: 11)
        }
        .frame(width: TimelineMachine.drumCell, height: Self.height)
    }

    @ViewBuilder
    private func sign(offset: Int) -> some View {
        if state.showMoon {
            // `viewBox -4 -4 8 8`, диск радиуса 3,4: 6,8 из 8 — 9,35 из 11.
            MoonGlyph(fraction: state.moonFraction(offset: offset))
                .fill(.foreground)
                .frame(width: 9.35, height: 9.35)
                .scaleEffect(x: state.moonMirrored(offset: offset) ? -1 : 1, y: 1)
        } else if let name = state.weatherSignName(offset: offset) {
            Icon(name, size: 11, line: 1.6)
        } else {
            Color.clear
        }
    }

    /// `.drum-frame`: окно 50×27 по центру, кант 1 `--terra`, скругление 7,
    /// прозрачность 0,9; стекло — системное (DECISIONS 21 сентября 2026),
    /// блик сверху 1,5 и тень 0 3 10 — как у веба.
    private func frame(_ look: DrumLook) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(look.glassFill)
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 7).stroke(look.shine, lineWidth: 1.5)
                    .mask(Rectangle().frame(height: 1.5).frame(maxHeight: .infinity, alignment: .top))
            }
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(look.terra, lineWidth: 1))
            .shadow(color: look.cast, radius: 5, y: 3)
            .opacity(0.9)
            .frame(width: 50, height: 27)
            .allowsHitTesting(false)
    }
}

/// Серп под барабаном: скругление, сдвинутое на 1 вниз, минус само
/// скругление — то, что CSS рисует тенью `0 1px 0`.
private struct DrumLip: Shape {
    func path(in rect: CGRect) -> Path {
        let body = Path(roundedRect: rect, cornerRadius: 8)
        return body.offsetBy(dx: 0, dy: 1).subtracting(body)
    }
}

/// Цвета прорези барабана — переменные `.ribbon-wrap.drum` веба. Грунт,
/// глубина краёв и блик берутся из темы; в светлой теме «Графит» и «Окно»
/// тёмные (`--drum-face` 0,72 и 0,88), и чернила ячеек у них светлые
/// (`--ink: #F0EBE1`, свои `--ink-5` и `--terra`). В тёмной теме три вида
/// сходятся в один — CSS красит их только под `[data-theme="light"]`.
struct DrumLook {
    let face: Color
    let ink: Color
    let ink5: Color
    let terra: Color
    /// `--drum-ink` и `--drum-deep`: цвет и сила затемнения краёв.
    let deepInk: (Double, Double, Double)
    let deep: Double
    let shine: Color
    let lip: Color
    let glass: Color
    let glassFill: Color
    let cast: Color

    init(scheme: ColorScheme, slot: AppSettings.DrumSlot) {
        let pal = Palette(scheme)
        let darkSlot = scheme == .light && slot != .paper
        face = darkSlot ? (slot == .graphite ? Color(hex: 0x231F18, alpha: 0.72) : Color(hex: 0x17150F, alpha: 0.88))
                        : pal.drumFace
        ink = darkSlot ? Color(hex: 0xF0EBE1) : pal.ink
        ink5 = darkSlot ? (slot == .graphite ? Color(hex: 0xC4BCAC) : Color(hex: 0x9A9384)) : pal.ink5
        terra = darkSlot ? (slot == .graphite ? Color(hex: 0xD0704A) : Color(hex: 0xC9663D)) : pal.terra
        deepInk = (scheme == .light && !darkSlot) ? (23, 21, 15) : (0, 0, 0)
        deep = darkSlot ? (slot == .graphite ? 0.74 : 0.86) : (scheme == .light ? 0.55 : 0.78)
        shine = darkSlot ? Color(white: 1, opacity: 0.90) : pal.glassShine
        lip = pal.drumLip
        glass = pal.drumGlass
        glassFill = darkSlot ? Color(white: 1, opacity: 0.07) : pal.glassFill
        cast = pal.glassCast
    }

    func deepColor(_ k: Double) -> Color {
        Color(.sRGB, red: deepInk.0 / 255, green: deepInk.1 / 255, blue: deepInk.2 / 255, opacity: deep * k)
    }
}

/// Цилиндр барабана — `::after` веба: края темнеют к 13 % ширины ступенями
/// 1 · 0,92 · 0,70 · 0,42 · 0,18 · 0, у самых торцов — блик 3 pt, сверху
/// блик стекла 1 pt, волосок-кант по периметру, снизу блик 1 pt и
/// внутренняя тень сверху 0 4 6 −2.
private struct DrumShade: View {
    let look: DrumLook

    var body: some View {
        let edge: [(Double, Double)] = [(0, 1), (0.02, 0.92), (0.045, 0.70), (0.075, 0.42), (0.10, 0.18), (0.13, 0)]
        let stops = edge.map { Gradient.Stop(color: look.deepColor($0.1), location: $0.0) }
            + edge.reversed().map { Gradient.Stop(color: look.deepColor($0.1), location: 1 - $0.0) }
        let shape = RoundedRectangle(cornerRadius: 8)
        ZStack {
            shape.fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
            HStack(spacing: 0) {
                LinearGradient(colors: [look.shine, look.shine.opacity(0)], startPoint: .leading, endPoint: .trailing).frame(width: 3)
                Spacer(minLength: 0)
                LinearGradient(colors: [look.shine.opacity(0), look.shine], startPoint: .leading, endPoint: .trailing).frame(width: 3)
            }
            // Внутренняя тень сверху: 4 pt вниз, размытие 6, стянута на 2 —
            // спадает быстрее прямой: на 3 pt от кромки у веба 0,3 от силы
            // у кромки (замер пары 19б), прямая давала 0,55.
            LinearGradient(stops: [.init(color: look.deepColor(0.6), location: 0),
                                   .init(color: look.deepColor(0.33), location: 0.05),
                                   .init(color: look.deepColor(0.18), location: 0.10),
                                   .init(color: look.deepColor(0.06), location: 0.16),
                                   .init(color: look.deepColor(0), location: 0.22)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Rectangle().fill(look.glass).frame(height: 1)
                Spacer(minLength: 0)
                Rectangle().fill(look.shine).frame(height: 1)
            }
            shape.strokeBorder(look.deepColor(0.55), lineWidth: 1)
        }
        .clipShape(shape)
    }
}

extension EnvironmentValues {
    /// Вид прорези барабана из настроек (`drumSlot` веба).
    @Entry var drumSlot: AppSettings.DrumSlot = .paper
}
