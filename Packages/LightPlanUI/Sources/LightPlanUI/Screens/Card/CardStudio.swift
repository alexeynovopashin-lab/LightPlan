import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Что показывает студийный час сейчас (веб `paintStudio`, `renderStudioTel`)
/// — отдельно от вида, чтобы тесты читали его числами.
@MainActor
struct StudioTileState {
    let window: RentWindow
    /// Секунды до выхода из зала.
    let seconds: Int
    /// «0:45», последние 15 минут — «07:32».
    let clock: String
    /// Час выхода: конец оплаченного минус пять минут.
    let exitAt: String
    let title: String
    /// «12:20 – 13:50».
    let span: String
    let stage: StudioHour.Stage
    let fraction: Double
    let note: String?

    /// Плитка видна: сегодня, аренда началась, съёмка не прошла, до выхода
    /// больше нуля. Дошло до нуля — плитки нет («кончилась аренда — исчез
    /// таймер», 8.09).
    static func of(_ s: Session, phase: EventPhase, app: AppModel) -> StudioTileState? {
        guard phase != .after, let nowMin = app.nowMinute(of: s),
              let w = RentWindow.of(s, studios: app.studios, now: nowMin), nowMin >= w.from else { return nil }
        // Минута шкалы съёмки, а не секунды суток: после полуночи веб
        // прибавляет сутки («25:25» вместо «1:25»).
        let sec = StudioHour.secondsLeft(deadline: w.deadline, minute: nowMin, second: app.nowSecond)
        guard sec > 0 else { return nil }
        let f = PlannerFacts(app: app, dark: true)
        let stage = StudioHour.stage(sec)
        return StudioTileState(
            window: w, seconds: sec, clock: StudioHour.clock(sec), exitAt: f.fmt(Double(w.deadline)),
            title: title(w, f.t), span: f.range(Double(w.from), Double(w.to)), stage: stage,
            fraction: StudioHour.fraction(sec, window: w),
            note: stage == .leave ? f.t.t("studio.noteNow") : stage == .wrap ? f.t.t("studio.noteWrap") : nil)
    }

    /// Телефон администратора — пока идёт оплаченное время; последние пять
    /// минут, когда плитки уже нет, — строкой на её месте (веб `renderStudioTel`).
    static func tel(_ s: Session, app: AppModel) -> (shown: String, dial: String)? {
        guard let nowMin = app.nowMinute(of: s),
              let w = RentWindow.of(s, studios: app.studios, now: nowMin),
              !w.studio.phone.isEmpty, nowMin >= w.from, nowMin <= w.to else { return nil }
        let e = TelFormat.e164(w.studio.phone, country: app.telCountry)
        return (e.isEmpty ? w.studio.phone : TelFormat.format(e, country: app.telCountry),
                e.isEmpty ? w.studio.phone.filter { $0.isNumber || $0 == "+" } : e)
    }

    /// «Фотостудия Томсон», «Фотостудия Томсон. Зал Эдисон» (веб `studioTitle`):
    /// слово «фотостудия» не повторяется, если уже стоит в имени.
    static func title(_ w: RentWindow, _ t: Lexicon) -> String {
        let def = t.t("studio.tileOnly", ["name": ""]).trimmingCharacters(in: .whitespaces)
        let name = w.studio.name.isEmpty ? ""
            : !def.isEmpty && w.studio.name.lowercased().contains(def.lowercased()) ? w.studio.name
            : t.t("studio.tileOnly", ["name": w.studio.name])
        guard let hall = w.hallName else { return name }
        return t.t("studio.hallOf", ["studio": name, "hall": hall])
    }
}

/// Студийный час (`#cdStudio`): кольцо 104 pt, внутри час выхода и остаток,
/// справа студия с залом, окно аренды и номер администратора. Последние
/// 15 минут счёт идёт по секундам.
struct CardStudio: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette

    var body: some View {
        let st = StudioTileState.of(s, phase: phase, app: app)
        if let st, st.seconds <= StudioHour.fine * 60 {
            TimelineView(.periodic(from: .now, by: 1)) { _ in content }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        let tel = StudioTileState.tel(s, app: app)
        if let st = StudioTileState.of(s, phase: phase, app: app) {
            tile(st, tel)
        } else if let tel {
            telRow(tel).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 9)
        }
    }

    private func tint(_ st: StudioTileState) -> (arc: Color, num: Color, at: Color) {
        switch st.stage {
        case .calm: (pal.brass, pal.glyph, pal.ink6)
        case .wrap: (pal.brassDeep, pal.brassDeep, pal.ink6)
        case .leave: (pal.terra, pal.terra, pal.terra)
        }
    }

    private func tile(_ st: StudioTileState, _ tel: (shown: String, dial: String)?) -> some View {
        let c = tint(st)
        return HStack(spacing: 14) {
            ZStack {
                Circle().stroke(pal.rail2, lineWidth: 5).padding(5)
                Circle().trim(from: 0, to: st.fraction)
                    .stroke(c.arc, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
                    .animation(.linear(duration: 0.9), value: st.fraction)
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Icon("bell", size: 11, line: 1.6)
                        Text(st.exitAt).monospacedDigit()
                    }
                    .font(webFont(10.5)).foregroundStyle(c.at)
                    Text(st.clock).font(webFont(25, 700)).tracking(-0.8).monospacedDigit()
                        .foregroundStyle(c.num).shotNode("card.studioNum", text: st.clock)
                }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 0) {
                Text(st.title).font(webFont(15)).foregroundStyle(pal.ink).lineSpacing(15 * 0.3)
                    .shotNode("card.studioName", text: st.title)
                Text(st.span).font(webFont(13.5)).monospacedDigit().foregroundStyle(pal.ink3).padding(.top, 3)
                if let tel { telRow(tel, inside: true) }
                if let note = st.note {
                    Text(note).font(webFont(12.5)).foregroundStyle(c.num).padding(.top, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.sheet3))
        .padding(.top, 9)
        .shotNode("card.studio")
    }

    /// Номер администратора — та же ссылка, что у клиента, но в плитке мельче:
    /// кегль 15, знак 13, поле под палец 11×8 со сдвигом назад.
    private func telRow(_ tel: (shown: String, dial: String), inside: Bool = false) -> some View {
        Button { if let u = URL(string: "tel:" + tel.dial) { openURL(u) } } label: {
            HStack(spacing: 7) {
                Text(tel.shown).font(webFont(inside ? 15 : 19)).monospacedDigit()
                Icon("phone", size: inside ? 13 : 15)
            }
            .foregroundStyle(pal.brass)
            .padding(.horizontal, inside ? 8 : 10).padding(.vertical, inside ? 11 : 9)
        }
        .buttonStyle(PressFade())
        .padding(inside ? EdgeInsets(top: -7, leading: -8, bottom: -7, trailing: 0) : EdgeInsets())
        .shotNode("card.studioTel")
    }

    @Environment(\.openURL) private var openURL
}
