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

extension StudioTileState {
    /// Звонок администратору (поле-1, п. 8): кнопка «Позвонить админу» звонит на тот же номер, что раньше показывала строка.
    static func callURL(_ tel: (shown: String, dial: String)) -> URL? { URL(string: "tel:" + tel.dial) }
}

/// Двоеточие остатка (поле-1, п. 7): в SF двоеточие сидит между базовой линией и высотой строчной, а цифры — до высоты
/// прописной, и оно выглядело лежащим на строке. `lift` — на сколько его поднять, чтобы середина двоеточия легла на середину
/// высоты цифр. Считается по метрикам того же шрифта, а не подобрана на глаз, поэтому верна при любом кегле.
enum StudioColon {
    static func lift(size: CGFloat, weight: Int) -> CGFloat {
        let font = webPlatformFont(size, weight) as CTFont
        func mid(_ ch: Character) -> CGFloat {
            var unit = Array(String(ch).utf16)
            var glyph = [CGGlyph](repeating: 0, count: unit.count)
            guard CTFontGetGlyphsForCharacters(font, &unit, &glyph, unit.count) else { return 0 }
            var box = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyph, &box, 1)
            return box.midY
        }
        return mid("0") - mid(":")
    }
}

/// Студийный час (`#cdStudio`): кольцо 104 pt, внутри час выхода и остаток,
/// справа студия с залом, окно аренды и номер администратора. Последние
/// 15 минут счёт идёт по секундам.
///
/// Такт — полсекунды всегда: двоеточие в остатке мигает в такт секунде —
/// загорается вместе со сменой секунды, через полсекунды гаснет, и так
/// каждую секунду (Алексей, телефон 29.09: «если секунда — целая, точки —
/// две целых», мигать через такт неверно). У веба не мигает; веб
/// перерисовывает плитку раз в 20 с, а по секундам — только последние 15 минут.
struct CardStudio: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette
    /// Такт карточки (раз в минуту): появиться плитка может и без своего такта.
    let tick: Date

    var body: some View {
        // Такты — на целой секунде и на половине: начало отсчёта — ближайшая
        // прошедшая целая секунда, иначе двоеточие мигало бы невпопад смене цифр.
        let whole = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down))
        TimelineView(.periodic(from: whole, by: 0.5)) { ctx in
            content(colon: ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) < 0.25)
        }
    }

    @ViewBuilder private func content(colon: Bool) -> some View {
        let tel = StudioTileState.tel(s, app: app)
        if let st = StudioTileState.of(s, phase: phase, app: app) {
            tile(st, tel, colon: colon)
        } else if let tel {
            telRow(tel).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 9)
        }
    }

    /// Кегль и вес остатка в кольце — по ним и считается подъём двоеточия.
    private static let numSize: CGFloat = 25
    private static let numWeight = 700
    private static let colonLift = StudioColon.lift(size: numSize, weight: numWeight)

    /// Остаток с двоеточием: `on` — первая половина секунды. Место под
    /// двоеточие держится — цифры не прыгают.
    private func blink(_ clock: String, _ color: Color, on: Bool) -> Text {
        guard let i = clock.firstIndex(of: ":") else { return Text(clock).foregroundStyle(color) }
        return Text(clock[..<i]).foregroundStyle(color)
            + Text(":").foregroundStyle(on ? color : .clear).baselineOffset(Self.colonLift)
            + Text(clock[clock.index(after: i)...]).foregroundStyle(color)
    }

    private func tint(_ st: StudioTileState) -> (arc: Color, num: Color, at: Color) {
        switch st.stage {
        case .calm: (pal.brass, pal.glyph, pal.ink6)
        case .wrap: (pal.brassDeep, pal.brassDeep, pal.ink6)
        case .leave: (pal.terra, pal.terra, pal.terra)
        }
    }

    private func tile(_ st: StudioTileState, _ tel: (shown: String, dial: String)?, colon: Bool) -> some View {
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
                    blink(st.clock, c.num, on: colon).font(webFont(Self.numSize, Self.numWeight)).tracking(-0.8).monospacedDigit()
                        // Поднятое двоеточие растит строку сверху на `colonLift`; без этой подкладки цифры и «колокольчик»
                        // над ними сдвинулись бы в кольце на полподъёма (замер: цифры на 1,3 pt ниже прежнего).
                        .padding(.top, -Self.colonLift)
                        .shotNode("card.studioNum", text: st.clock)
                }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 0) {
                Text(st.title).font(webFont(15)).foregroundStyle(pal.ink)
                    // `line-height: 1.3` — шаг строк 19,5; у SF свой шаг 1,19
                    // кегля, добавляется разница (пара шага 4: было 40,5 на 37,5).
                    .lineSpacing(15 * (1.3 - 1.19))
                    // В такте `TimelineView` имя без этого резалось многоточием
                    // в одну строку вместо переноса (симулятор, 29.09).
                    .fixedSize(horizontal: false, vertical: true)
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
        .shotNode("card.studio")
        .padding(.top, 9)
    }

    /// Кнопка «Позвонить админу» (поле-1, п. 8; слово Алексея 25.10: номер в плитке не нужен, нужна кнопка): звонит на тот же
    /// номер администратора, самого номера на экране нет. Нет номера у студии — нет и кнопки (`tel` тогда `nil`). Внутри плитки
    /// кегль 15, плашка латунным тоном; без плитки (последние пять минут) — кегль 17 на её месте.
    private func telRow(_ tel: (shown: String, dial: String), inside: Bool = false) -> some View {
        Button { if let u = StudioTileState.callURL(tel) { openURL(u) } } label: {
            HStack(spacing: 7) {
                Icon("phone", size: inside ? 14 : 16)
                Text(app.lexicon.t("studio.callAdmin")).font(webFont(inside ? 15 : 17, 600)).lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(pal.brass)
            .padding(.horizontal, 12).padding(.vertical, inside ? 8 : 10)
            .background(pal.pressBrass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressFade())
        .accessibilityLabel(app.lexicon.t("studio.callAdmin"))
        .shotNode("card.studioTel")
        .padding(.top, inside ? 8 : 0)
    }

    @Environment(\.openURL) private var openURL
}
