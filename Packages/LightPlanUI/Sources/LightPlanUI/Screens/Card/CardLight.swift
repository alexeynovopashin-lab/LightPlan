import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Блоки условий: свет, погода (итерация 26, шаг 3)

/// Плашка `.say` (`#cdSay`): `--sheet-3`, радиус 14, поля 11×14, знак 16,
/// слова 13,5 с шагом 1,45 цветом `--ink-3`. Плохое небо — знак `warn`
/// терракотой и терракотовый свет по периметру, как у студийного часа.
struct CardSayPlate: View {
    let icon: String
    let tint: Color
    let text: Text
    let glow: (Double, Double, Double)?
    let pal: Palette
    let node: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Icon(icon, size: 16, line: 1.5).foregroundStyle(tint)
                .frame(width: 16, height: 16).padding(.top, 1)
            text.font(webFont(13.5))
                .lineSpacing(13.5 * (1.45 - 1.19))
                .padding(.vertical, 13.5 * (1.45 - 1.19) / 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11).padding(.horizontal, 14)
        .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .modifier(OptionalGlow(rgb: glow, alpha: pal.dark ? 0.32 : 0.55))
        .shotNode(node)
    }
}

private struct OptionalGlow: ViewModifier {
    let rgb: (Double, Double, Double)?
    let alpha: Double
    func body(content: Content) -> some View {
        if let rgb { content.modifier(WarnGlow(rgb: rgb, alpha: alpha)) } else { content }
    }
}

/// Блок «Свет» (`light`): золотой час у «Заката», своя строка у «Звёзд» и
/// «Луны» (натив, Алексей 29.09). Реплики — одна под другой, зазор 9.
struct CardLightBlock: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette

    var body: some View {
        VStack(spacing: 9) {
            ForEach(app.cardSays(s, phase: phase), id: \.self) { say in
                CardSayPlate(icon: say.icon, tint: say.bad ? pal.terra : pal.brass,
                             text: Text(say.text).foregroundStyle(pal.ink3),
                             glow: say.bad ? (201, 102, 61) : nil, pal: pal, node: "card.say.\(say.kind)")
            }
        }
        .shotNode("card.block.light")
        .padding(.top, 9)
    }
}

/// Блок «Погода» (`#cdWx`, `.wx-pane`): колонки часов — время, знак неба,
/// градус, облачность и ряд света, если свет есть хоть у одной колонки. До
/// съёмки дальше, чем видит прогноз, — честная строка, что данных пока нет.
struct CardWeatherBlock: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette

    var body: some View {
        Group {
            switch app.cardWeather(s, phase: phase) {
            case .columns(let cols)?: columns(cols)
            case .noData?:
                HStack(alignment: .top, spacing: 9) {
                    Icon("cloud", size: 16, line: 1.5).foregroundStyle(pal.ink4)
                        .frame(width: 16, height: 16).padding(.top, 1)
                    Text(app.lexicon.t("card.wxNoData")).font(webFont(13.5)).foregroundStyle(pal.ink3)
                        .lineSpacing(13.5 * (1.45 - 1.19))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .shotNode("card.wxNoData")
                }
            case nil: EmptyView()
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shotNode("card.block.weather")
        .padding(.top, 9)
    }

    /// ≤ 5 колонок — поровну по ширине; больше — по краям с зазором 10.
    private func columns(_ cols: [WxColumn]) -> some View {
        let lightRow = cols.contains { $0.light != nil }
        let clock = PlannerFacts(app: app, dark: pal.dark)
        let even = cols.count <= 5
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cols.enumerated()), id: \.offset) { i, c in
                if even || i > 0 { Spacer(minLength: even ? 0 : 10) }
                column(c, lightRow: lightRow, clock: clock)
            }
            if even { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
        .shotNode("card.wxCols", text: "\(cols.count)")
    }

    /// Колонка: время 10,5, знак неба 20 (солнце `--brass-soft`, дождь
    /// `--blue`), градус 11,5, облачность 10, знак света 16. Час до и после
    /// съёмки — прозрачность 0,45.
    private func column(_ c: WxColumn, lightRow: Bool, clock: PlannerFacts) -> some View {
        VStack(spacing: 0) {
            Text(clock.fmt(Double(c.minute))).font(webFont(10.5)).monospacedDigit().foregroundStyle(pal.ink4)
            Group {
                if let sky = c.sky {
                    Icon(sky, size: 20, line: 1.4)
                        .foregroundStyle(sky == "sun" ? pal.brassSoft : sky == "rain" ? pal.blue : pal.ink4)
                } else {
                    Color.clear
                }
            }
            .frame(width: 20, height: 20).padding(.vertical, 4)
            Text(c.temp).font(webFont(11.5)).foregroundStyle(pal.ink)
            Text(c.cloud).font(webFont(10)).foregroundStyle(pal.ink7)
            if lightRow {
                Group {
                    if let l = c.light { Icon(l, size: 16, line: 1.5).foregroundStyle(c.blue ? pal.blue : pal.brass) }
                    else { Color.clear }
                }
                .frame(width: 16, height: 16).padding(.top, 2)
            }
        }
        .opacity(c.aside ? 0.45 : 1)
    }
}

/// «Прогноз переменился» (`#cdShift`): над сдвигом времени и студийным часом;
/// янтарный свет, как у наложения. Гаснет, когда карточку закрыли.
struct CardShiftLine: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette

    var body: some View {
        if let sh = app.cardShift(s, phase: phase) {
            CardSayPlate(icon: "warn", tint: pal.brassDeep,
                         text: Text(sh.title + ".").foregroundStyle(pal.ink) + Text(" " + sh.text).foregroundStyle(pal.ink3),
                         glow: (226, 164, 76), pal: pal, node: "card.shift")
                .padding(.top, 9)
        }
    }
}

/// «Время сдвинуто в календаре» (`#cdMoved`): над студийным часом, все фазы;
/// «✕» стирает отметку.
struct CardMoved: View {
    let app: AppModel
    let s: Session
    let pal: Palette

    var body: some View {
        if let m = app.cardMoved(s) {
            HStack(alignment: .top, spacing: 0) {
                CardSayPlate(icon: "clock", tint: pal.brassDeep,
                             text: Text(app.lexicon.t("card.movedT") + ".").foregroundStyle(pal.ink)
                                + Text(" " + app.lexicon.t("card.movedM", ["from": m.from, "to": m.to])).foregroundStyle(pal.ink3),
                             glow: (226, 164, 76), pal: pal, node: "card.moved")
                    .overlay(alignment: .topTrailing) {
                        Button { app.clearDayMoved(id: s.id) } label: {
                            Icon("close", size: 14, line: 1.6).foregroundStyle(pal.ink6)
                                .frame(width: 32, height: 32).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(app.lexicon.t("card.movedX"))
                        .shotNode("card.movedX")
                        .padding(.top, 4).padding(.trailing, 4)
                    }
            }
            .padding(.top, 9)
        }
    }
}

/// Строка под листом (`#cdWarn`): пожелание к небу не сбудется по прогнозу.
/// 13 pt терракотой, шаг 1,45, поля 10/4/0.
struct CardWishMissed: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette

    var body: some View {
        if let text = app.cardWishMissed(s, phase: phase) {
            Text(text).font(webFont(13)).foregroundStyle(pal.terra)
                .lineSpacing(13 * (1.45 - 1.19))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10).padding(.horizontal, 4)
                .shotNode("card.warn")
        }
    }
}
