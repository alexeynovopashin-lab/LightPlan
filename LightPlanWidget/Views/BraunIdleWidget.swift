import SwiftUI
import LightPlanDomain

// 30б.2в-5 — средний виджет «Braun» без маршрута, «Семья виджетов» Алексея 27.10
// (`light_plan:Light_Plan/docs/widget_design_2026-10-26/`: `FamilySizes.dc.html` — числа, `_gen/family.js` — раскладка: `lightColM`, `rateGauge`,
// `shootM`, `mediumB`, `mediumGDE`). Б — съёмка идёт, маршрута нет: круг считает всю съёмку, справа свет (`BraunLightDrum`, круг и шапка — в
// `BraunWidget.swift`). Г, Д, Е — слева свет, справа неделя съёмок (`BraunIdleView`). Числа и правила — в Domain (`WidgetBraunIdle.swift`).
// Всё на заданных pt: плашку виду сообщает `GeometryReader`, шрифты не растут от Dynamic Type; не влезший текст сначала мельчает, и только потом `…`.

// MARK: - Знаки

enum BraunSign {
    static func light(_ kind: BraunIdle.LightKind) -> String {
        switch kind {
        case .sunrise: "sunrise"
        case .golden: "golden"
        case .sunset: "sunset"
        }
    }

    /// Знак оценки заката — «закат с отражением» (`sunset_glow`, коммит `0760049` с `wt/icons-golden`, взят в эту ветку по слову Алексея 27.10).
    /// Нет в таблице (расширение собрано из библиотеки без него) — рисуется «закат».
    static var rating: String { WidgetIconTable.common["sunset_glow"] != nil ? "sunset_glow" : "sunset" }
}

// MARK: - Палитра: чернила и волосок

extension BraunPalette {
    /// Чернила темы с прозрачностью: основа дорожки столбика, волоска и чёрточек (`ink(a)` генератора доски).
    func ink(_ a: Double) -> Color { dark ? Color(.sRGB, red: 236 / 255, green: 236 / 255, blue: 234 / 255, opacity: a) : Color(.sRGB, red: 17 / 255, green: 17 / 255, blue: 17 / 255, opacity: a) }
    /// Волосок между светом и неделей: 28 %.
    var hairline: Color { ink(0.28) }
}

// MARK: - Время по двоеточию

/// «13:48»: двоеточия всех строк стоят на одной вертикали, хотя центр крупнее (Спецификация 27.10): часы прижаты вправо в поле 21, двоеточие по
/// центру поля 4, минуты влево в поле 21. 12-часовое время («5:56 PM», в японском и китайском «午後5:56») делится так же, а приставка
/// и суффикс (AM / PM) стоят мелко по краям своих полей: ширину полей даёт раскладка (`reserves` — самые широкие на барабане), поэтому
/// двоеточия по-прежнему на одной вертикали, а название начинается с одного x (ревью GPT к bd4357e: «12:56 PM» в колонке 46 резалось).
struct ColonTime: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    /// Ширина поля приставки слева и суффикса справа (0 — 24-часовые часы).
    var before: Double = 0
    var after: Double = 0

    /// Размер приставки и суффикса.
    static let affixSize = 8.0

    /// «5:56 PM» → ("", "5", "56", "PM"); «午後5:56» → ("午後", "5", "56", ""); нет «ч:мм» — `nil`.
    static func split(_ text: String) -> (prefix: String, h: String, m: String, suffix: String)? {
        let chars = Array(text)
        guard let colon = chars.firstIndex(of: ":"), colon >= 1, colon + 2 < chars.count else { return nil }
        var a = colon
        while a > 0, chars[a - 1].isNumber, colon - a < 2 { a -= 1 }
        let mm = chars[(colon + 1)...(colon + 2)]
        guard a < colon, mm.allSatisfy(\.isNumber) else { return nil }
        func trim(_ x: ArraySlice<Character>) -> String { String(x).trimmingCharacters(in: .whitespacesAndNewlines) }
        return (trim(chars[0..<a]), String(chars[a..<colon]), String(mm), trim(chars[(colon + 3)...]))
    }

    /// Поля под приставки и суффиксы всех строк барабана: самые широкие плюс зазор 2; нет приставок — 0.
    static func reserves(_ texts: [String]) -> (before: Double, after: Double) {
        var b = 0.0, a = 0.0
        for t in texts {
            guard let p = split(t) else { continue }
            if !p.prefix.isEmpty { b = max(b, BraunText.width(p.prefix, size: affixSize, semibold: false) + 2) }
            if !p.suffix.isEmpty { a = max(a, BraunText.width(p.suffix, size: affixSize, semibold: false) + 2) }
        }
        return (b, a)
    }

    var body: some View {
        let font = Font.system(size: size, weight: weight).monospacedDigit()
        let affix = Font.system(size: Self.affixSize, weight: .medium)
        HStack(spacing: 0) {
            if let p = Self.split(text) {
                Text(p.prefix).font(affix).lineLimit(1).frame(width: before, alignment: .trailing)
                Group {
                    Text(p.h).frame(width: 21, alignment: .trailing)
                    Text(":").frame(width: 4)
                    Text(p.m).frame(width: 21, alignment: .leading)
                }
                .font(font)
                Text(p.suffix).font(affix).lineLimit(1).padding(.leading, after > 0 ? 2 : 0).frame(width: after, alignment: .leading)
            } else {
                Text(text).font(font).lineLimit(1).minimumScaleFactor(0.6).frame(width: BraunDrum.timeColumn + before + after, alignment: .trailing)
            }
        }
        .lineLimit(1).frame(width: BraunDrum.timeColumn + before + after)
    }
}

// MARK: - Окошко с вырезом-флажком (Б)

/// Контур окошка: правые углы скруглены 4, слева острые углы и V-вырез глубиной 5 на всю высоту (`clip-path` доски).
private struct NotchOutline: Shape {
    func path(in r: CGRect) -> Path {
        let pts = BraunWindow.notchWindowPoints(width: Double(r.width), height: Double(r.height))
        let c = 4.0
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - c, y: r.minY + c), radius: c, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addArc(center: CGPoint(x: r.maxX - c, y: r.maxY - c), radius: c, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + pts[4].x, y: r.minY + pts[4].y))
        p.closeSubpath()
        return p
    }
}

private struct NotchBand: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let pts = BraunWindow.notchBandPoints(height: Double(r.height))
        p.move(to: CGPoint(x: r.minX + pts[0].x, y: r.minY + pts[0].y))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: r.minX + q.x, y: r.minY + q.y)) }
        p.closeSubpath()
        return p
    }
}

/// Окошко Braun «осталось свадьбы» с красным флажком по левому краю. Цифры рисует вид поверх (живой таймер последним). Утоплено, как у А:
/// тень у верхней кромки, светлая кромка снизу, в тёмной тонкая обводка — всё это по прямоугольнику, который вырез обрезает.
struct BraunNotchWindow: View {
    let pal: BraunPalette

    var body: some View {
        let box = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack(alignment: .topLeading) {
            ZStack {
                box.fill(pal.win)
                box.fill(LinearGradient(colors: [pal.winTopShadow, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22)))
                box.fill(LinearGradient(colors: [.clear, pal.winBottomRim], startPoint: UnitPoint(x: 0.5, y: 0.9), endPoint: .bottom))
                if let ring = pal.winRing { box.strokeBorder(ring, lineWidth: 0.5) }
            }
            .clipShape(NotchOutline())
            // Полоса — левый край окошка по всей высоте, но не выше его видимого тела: в тёмной обводка 0,5 сверху срезана. Те же слои блика, что у окошка
            // (тень сверху, кромка снизу, обводка), идут по полосе до её внешнего края, по её контуру: флажок — торец окошка, а не красная фигура рядом (30.10).
            let inset = BraunWindow.notchBandInsetTop(ringed: pal.winRing != nil)
            let extra = BraunWindow.notchExtra
            ZStack(alignment: .topLeading) {
                ZStack {
                    Rectangle().fill(pal.flag)
                    Rectangle().fill(LinearGradient(colors: [pal.flagTopShadow, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22)))
                    Rectangle().fill(LinearGradient(colors: [.clear, pal.flagBottomRim], startPoint: UnitPoint(x: 0.5, y: 0.9), endPoint: .bottom))
                }
                .frame(width: extra, height: 18)
                .mask(alignment: .bottom) { Rectangle().frame(width: extra, height: 18 - inset) }
                .clipShape(NotchBand())
                // Обводка тёмного — прямыми отрезками по верху и низу до самого края (у окошка её ведёт скруглённый угол, который полоса закрывает).
                if let ring = pal.winRing {
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(ring).frame(width: extra, height: BraunWindow.ringWidth)
                        Rectangle().fill(ring).frame(width: extra, height: BraunWindow.ringWidth).offset(y: 18 - BraunWindow.ringWidth)
                    }
                    .frame(width: extra, height: 18, alignment: .topLeading)
                    .clipShape(NotchBand())
                }
            }
            .frame(width: extra, height: 18)
        }
    }
}

// MARK: - Барабан света (Б)

/// Правая колонка Б: рассвет, золотой час, закат (и завтрашний рассвет после заката) вместо точек маршрута. Центр — ближайшее, на подложке.
/// Строки одной высоты, дальние гаснут маской по краям колонки (27.10). Время по двоеточию, знак и название с одного x.
struct BraunLightDrum: View {
    let layout: BraunLayout
    let plan: DayPlan
    let pal: BraunPalette

    var body: some View {
        let d = layout.diameter
        ZStack(alignment: .topLeading) {
            ForEach(layout.rows.indices, id: \.self) { i in
                let row = layout.rows[i]
                if let item = row.light { lightRow(row, item).offset(y: row.slot.y) }
            }
        }
        .frame(width: layout.drum.width, height: d, alignment: .topLeading)
        .mask(LinearGradient(stops: fadeStops(d), startPoint: .top, endPoint: .bottom))
    }

    private func fadeStops(_ d: Double) -> [Gradient.Stop] {
        BraunIdle.drumFade(height: d).map { Gradient.Stop(color: .black.opacity($0.opacity), location: $0.at / d) }
    }

    private func lightRow(_ row: BraunLayout.Row, _ item: BraunIdle.LightItem) -> some View {
        let centre = row.slot.offset == 0
        let weight: Font.Weight = centre ? .semibold : .medium
        let signSize: CGFloat = centre ? 16 : 13
        let name = plan.words[item.kind == .sunrise ? .sunrise : (item.kind == .golden ? .golden : .sunset)]
        let natural = BraunText.naturalLineHeight(size: row.step.size, semibold: centre)
        func extraView(_ word: String) -> some View {
            HStack(spacing: 3) {
                if row.extraIcon { WidgetIcon(name: BraunSign.rating, size: 12, line: 1.5) }
                Text(word).font(.system(size: row.extraSize, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(pal.muted).fixedSize()
        }
        return HStack(spacing: layout.timeGap) {
            ColonTime(text: plan.frame.clock(item.at, in: plan.frame.zone), size: centre ? 16 : 13, weight: weight, before: layout.timeBefore, after: layout.timeAfter)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    WidgetIcon(name: BraunSign.light(item.kind), size: signSize, line: 1.5)
                    Text(name)
                        .font(.system(size: row.step.size, weight: weight)).lineSpacing(max(0, row.step.lineHeight - natural))
                        .lineLimit(row.step.lines).multilineTextAlignment(.leading)
                    // Рядом с названием; не влезла — ниже, под названием (центр барабана).
                    if let word = row.extra, !row.extraStacked { extraView(word).padding(.leading, 3) }
                }
                if let word = row.extra, row.extraStacked { extraView(word).padding(.leading, signSize + 5) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(centre ? pal.amber : pal.muted)
        .padding(.horizontal, layout.rowPadding)
        .frame(width: layout.drum.width, height: row.slot.height)
        .background { if centre { RoundedRectangle(cornerRadius: BraunDrum.pillRadius, style: .continuous).fill(pal.pill) } }
    }
}

// MARK: - Г, Д, Е: свет слева, неделя справа

/// Средний вид без съёмки, что идёт: слева свет (подпись места, рассвет, золотой час, закат, оценка и столбик балла), тонкая полоска 0,5,
/// справа неделя съёмок. Риски по периметру — световой день, только когда съёмка сегодня впереди (Г). Вечером после заката (Е) ближайшее —
/// завтрашний рассвет, столбика нет.
struct BraunIdleView: View {
    let frame: WidgetFrame
    var alpha = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            if g.size.width > 0, g.size.height > 0 {
                BraunIdleContent(frame: frame, size: g.size, alpha: alpha, pal: BraunPalette(dark: scheme == .dark))
            }
        }
    }
}

struct BraunIdleContent: View {
    let frame: WidgetFrame
    let size: CGSize
    let alpha: Bool
    let pal: BraunPalette

    private var W: Double { Double(size.width) }
    private var H: Double { Double(size.height) }
    /// Плашка 338 × 158: числа доски заданы на 364 × 170, по высоте они сжаты (ряды света ближе, столбик ниже), список по ширине уже.
    private var compact: Bool { H < 170 }
    /// На 338 pt список недели шире не становится: полоска и список сдвинуты влево на 9, иначе «ср 28 · 11:00 · через 3 дня» не влезает даже в 9
    /// (число не из доски: на 338 × 158 её нет; столбик заканчивается на 154, до полоски остаётся 5).
    private var shift: Double { W < 364 ? 9 : 0 }
    private var night: Bool { BraunIdle.isNight(frame) }
    private var words: WidgetFeed.Words { frame.words }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Фон рисует сам вид (система на «Домой» осветляет подложку, 30б.2в-4).
            Rectangle().fill(pal.bg).frame(width: size.width, height: size.height)
            if BraunIdle.shootToday(frame) { ring }
            left
            Rectangle().fill(pal.hairline).frame(width: 0.5, height: H - 32).offset(x: 168 - shift, y: 16)
            right
            if alpha {
                AlphaBadge().frame(width: size.width - 12, height: size.height - 12, alignment: .bottomTrailing)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: Риски — световой день

    @ViewBuilder private var ring: some View {
        if let day = frame.day, let a = day.sunrise, let b = day.sunset, b > a { ringLayers(from: a, to: b) }
    }

    private func ringLayers(from a: Date, to b: Date) -> some View {
        let duration = b.timeIntervalSince(a), elapsed = frame.now.timeIntervalSince(a)
        let startLocal = a.timeIntervalSince1970 + Double(frame.zone.secondsFromGMT(for: a))
        let hours = BraunTicks.hourIndexes(start: startLocal, duration: duration)
        let radius = BraunPlate.cornerRadius(plateHeight: H)
        func layer(_ past: Bool, _ hour: Bool) -> some View {
            BraunTickLayer(radius: radius, past: past, hour: hour, duration: duration, elapsed: elapsed, hours: hours)
                .stroke(past ? pal.tickOff : (hour ? pal.tickHour : pal.tickMinor),
                        style: StrokeStyle(lineWidth: hour ? BraunTicks.hourWidth : BraunTicks.minorWidth, lineCap: .round))
        }
        return ZStack { layer(true, false); layer(true, true); layer(false, false); layer(false, true) }
            .frame(width: size.width, height: size.height).allowsHitTesting(false)
    }

    // MARK: Слева: свет

    /// Строка по доске: `y` на плашке 170 pt, `squeezed` — на 158 pt.
    private func y(_ full: Double, _ squeezed: Double) -> Double { compact ? squeezed : full }

    /// Текст в одну строку: размер из цепочки, в который влез (по ширине `avail`), иначе последний.
    private func fitted(_ text: String, _ sizes: [Double], semibold: Bool, mono: Bool = true, avail: Double) -> Double {
        sizes.first { BraunText.width(text, size: $0, semibold: semibold, mono: mono) <= avail } ?? sizes.last ?? 12
    }

    private func timeText(_ date: Date?) -> String { date.map { frame.clock($0, in: frame.zone) } ?? "—" }

    private func color(_ role: BraunIdle.Role) -> Color {
        switch role { case .past: pal.dim; case .next: pal.amber; case .far: pal.text }
    }

    @ViewBuilder private var left: some View {
        let name = frame.place.name.isEmpty ? "Light Plan" : frame.place.name
        Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(pal.muted).lineLimit(1)
            .frame(width: 120, height: 16, alignment: .leading).offset(x: 16, y: 16)
        if let d = frame.day, d.sunrise != nil || d.sunset != nil {
            if night { eveningRows } else { dayRows(d) }
        } else if let d = frame.day {
            Text(d.polar == .night ? words[.polarNight] : words[.polarDay])
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.text).lineLimit(2)
                .frame(width: 140, height: 40, alignment: .topLeading).offset(x: 16, y: 40)
        }
    }

    private func dayRows(_ d: WidgetFeed.DayLight) -> some View {
        let roles = BraunIdle.roles(now: frame.now, [d.sunrise, d.golden, d.sunset])
        let rise = timeText(d.sunrise), golden = timeText(d.golden), set = timeText(d.sunset)
        // Что оценивается — рассвет (до конца утреннего золотого часа) или закат; подпись и столбик идут за ним.
        let rated = BraunIdle.ratedEvent(frame)
        let rating = BraunIdle.ratingLine(frame).map { Self.ratingFit($0, icon: true) }
        let gauge = rated?.score
        // Столбик стоит на x 129…154 (25 pt): время заката 22 уступает ему место.
        let setSize = fitted(set, [22, 20, 18, 16], semibold: true, avail: (gauge != nil ? BraunGauge.x - 2 : 160) - 50)
        return ZStack(alignment: .topLeading) {
            row(sign: BraunSign.light(.sunrise), signSize: 18, signY: 42, text: rise, size: 14, textY: 40, textH: 22, role: roles[0])
            row(sign: BraunSign.light(.golden), signSize: 18, signY: y(68, 66), text: golden, size: 14, textY: y(66, 64), textH: 22, role: roles[1])
            row(sign: BraunSign.light(.sunset), signSize: 26, signY: y(96, 90), text: set, size: setSize, textY: y(94, 88), textH: 30, role: roles[2], x: 50, tracking: -0.3)
            if let rating {
                if rating.icon {
                    WidgetIcon(name: BraunSign.rating, size: 14, line: 1.5).foregroundStyle(pal.muted).frame(width: 14, height: 14).offset(x: 16, y: y(129, 123))
                }
                Text(rating.text).font(.system(size: rating.size, weight: .medium)).foregroundStyle(pal.muted).lineLimit(1)
                    .frame(width: rating.width, height: 16, alignment: .leading).offset(x: rating.x, y: y(128, 122))
            }
            if let gauge { BraunGauge(pal: pal, score: gauge, height: H - 54).offset(x: BraunGauge.x, y: 38) }
        }
    }

    /// Строка оценки («рассвет · яркий», `BraunIdle.ratingLine`) и как она стоит. Со знаком — текст от x 36 до столбика минус 1 (`ratingWidth`, 92 pt;
    /// было 99, пока столбик был 18 шириной), мельчает 12 → 11 → 10 → 9. Слова неба 30.10 длиннее прежних («рассвет · туманный», «atardecer · con
    /// niebla» не влезают в 92 и в 9 pt), поэтому дальше — без знака, от x 16 (`ratingWidthBare`, 112), снова 12 → 9, и только потом «…».
    struct RatingFit: Equatable {
        var text: String
        var size: Double
        var icon: Bool
        var x: Double { icon ? 36 : 16 }
        var width: Double { icon ? BraunIdleContent.ratingWidth : BraunIdleContent.ratingWidthBare }
    }

    static let ratingWidth = BraunGauge.x - 1 - 36
    static let ratingWidthBare = BraunGauge.x - 1 - 16
    static let ratingSizes = [12.0, 11, 10, 9]

    static func ratingFit(_ text: String, icon: Bool) -> RatingFit {
        func size(_ avail: Double) -> Double? { ratingSizes.first { BraunText.width(text, size: $0, semibold: false) <= avail } }
        if icon, let s = size(ratingWidth) { return RatingFit(text: text, size: s, icon: true) }
        return RatingFit(text: text, size: size(ratingWidthBare) ?? ratingSizes.last ?? 9, icon: false)
    }

    private func row(sign: String, signSize: Double, signY: Double, text: String, size: Double, textY: Double, textH: Double, role: BraunIdle.Role,
                     x: Double = 42, tracking: Double = 0) -> some View {
        ZStack(alignment: .topLeading) {
            WidgetIcon(name: sign, size: signSize, line: 1.5).foregroundStyle(color(role)).frame(width: signSize, height: signSize).offset(x: 16, y: signY)
            Text(text).font(.system(size: size, weight: .semibold)).monospacedDigit().tracking(tracking).foregroundStyle(color(role)).lineLimit(1)
                .frame(width: 100, height: textH, alignment: .leading).offset(x: x, y: textY)
        }
    }

    /// Е: ближайшее — завтрашний рассвет янтарём; золотой час и закат сегодняшние, тусклые.
    private var eveningRows: some View {
        let rise = timeText(frame.tomorrow?.sunrise), golden = timeText(frame.day?.golden), set = timeText(frame.day?.sunset)
        return ZStack(alignment: .topLeading) {
            WidgetIcon(name: BraunSign.light(.sunrise), size: 26, line: 1.5).foregroundStyle(pal.amber).frame(width: 26, height: 26).offset(x: 16, y: 44)
            Text(rise).font(.system(size: fitted(rise, [22, 20, 18, 16], semibold: true, avail: (BraunIdle.ratedEvent(frame)?.score != nil ? BraunGauge.x - 2 : 160) - 50), weight: .semibold))
                .monospacedDigit().tracking(-0.3).foregroundStyle(pal.amber).lineLimit(1)
                .frame(width: 100, height: 30, alignment: .leading).offset(x: 50, y: 42)
            // Завтрашний рассвет — с оценкой (30б.2в-6) и столбиком, как днём: «рассвет · яркий», без «завтра» (Алексей 30.10: «человек сам
            // понимает, что рассвет будет завтра»); нет прогноза — строки нет. Знака здесь нет: строка от x 16 до столбика (`ratingWidthBare`).
            if let rating = BraunIdle.ratingLine(frame).map({ Self.ratingFit($0, icon: false) }) {
                Text(rating.text).font(.system(size: rating.size, weight: .medium)).foregroundStyle(pal.muted).lineLimit(1)
                    .frame(width: rating.width, height: 14, alignment: .leading).offset(x: rating.x, y: 76)
            }
            if let gauge = BraunIdle.ratedEvent(frame)?.score { BraunGauge(pal: pal, score: gauge, height: H - 54).offset(x: BraunGauge.x, y: 38) }
            dim(BraunSign.light(.golden), golden, signY: y(106, 102), textY: y(104, 100))
            dim(BraunSign.light(.sunset), set, signY: y(128, 122), textY: y(126, 120))
        }
    }

    private func dim(_ sign: String, _ text: String, signY: Double, textY: Double) -> some View {
        ZStack(alignment: .topLeading) {
            WidgetIcon(name: sign, size: 14, line: 1.5).foregroundStyle(pal.dim).frame(width: 14, height: 14).offset(x: 16, y: signY)
            Text(text).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(pal.dim).lineLimit(1)
                .frame(width: 90, height: 18, alignment: .leading).offset(x: 36, y: textY)
        }
    }

    // MARK: Справа: неделя

    @ViewBuilder private var right: some View {
        let x = 182.0 - shift, w = W - 16 - x
        let rows = BraunIdle.weekRows(frame)
        if let line = BraunIdle.emptyWeekLine(frame) {
            let size = [13.0, 12, 11].first { BraunText.width(line, size: $0, semibold: false) <= w } ?? 11
            Text(line).font(.system(size: size, weight: .medium)).foregroundStyle(pal.muted).lineLimit(1)
                .frame(width: w, height: 18, alignment: .leading).offset(x: x, y: 16)
        } else {
            let h = BraunIdle.weekRowHeights(plateHeight: H)
            VStack(spacing: BraunIdle.weekRowGap) {
                ForEach(rows.indices, id: \.self) { i in
                    BraunWeekRow(row: rows[i], pal: pal, width: w, height: rows[i].near ? h.near : h.other)
                }
            }
            .frame(width: w, alignment: .topLeading).offset(x: x, y: 16)
        }
    }
}

/// Строка недели: знак жанра 14 + имена 13 (ближайшая semibold), ниже «ср 28 · 11:00» 11 medium. Ближайшая на подложке радиуса 9, как центр барабана.
struct BraunWeekRow: View {
    let row: BraunIdle.WeekRow
    let pal: BraunPalette
    let width: Double
    let height: Double

    /// Кегли строки: имена 13 → 12 → 11, вторая строка 11 → 10 → 9; `…Fits` — влезло ли в последнем шаге (иначе строку режет `…`).
    static func fit(_ row: BraunIdle.WeekRow, width: Double) -> (name: Double, line: Double, nameFits: Bool, lineFits: Bool) {
        // Внутри полей 10: знак 14 и зазор 6 слева от имён.
        let inner = width - 20
        func nameW(_ s: Double) -> Double { BraunText.width(row.names, size: s, semibold: row.near) }
        func lineW(_ s: Double) -> Double { BraunText.width(row.line2, size: s, semibold: false, mono: true) }
        let name = [13.0, 12, 11].first { nameW($0) <= inner - 20 } ?? 11
        // Вторая строка доски — 148 pt текста в рамке 146: она выходит на 2 pt в правое поле 10, поэтому ей отдаётся и 6 pt правого поля.
        let lineAvail = inner + 6
        let line = [11.0, 10, 9].first { lineW($0) <= lineAvail } ?? 9
        return (name, line, nameW(name) <= inner - 20, lineW(line) <= lineAvail)
    }

    var body: some View {
        let fit = Self.fit(row, width: width)
        let nameSize = fit.name, lineSize = fit.line
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                WidgetIcon(name: row.genre, size: 14, line: 1.5, genre: true)
                Text(row.names).font(.system(size: nameSize, weight: row.near ? .semibold : .medium)).lineLimit(1)
            }
            .frame(height: 16).foregroundStyle(row.near ? pal.amber : pal.muted)
            // Влезла (с правом на 6 pt правого поля, как у доски) — рисуется как есть, без обрезки; не влезла и в 9 — режется «…».
            Group {
                if fit.lineFits { Text(row.line2).fixedSize(horizontal: true, vertical: false) } else { Text(row.line2) }
            }
            .font(.system(size: lineSize, weight: .medium)).monospacedDigit().lineLimit(1)
            .frame(height: 14, alignment: .leading).foregroundStyle(row.near ? pal.muted : pal.dim)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: height, alignment: .leading)
        .background { if row.near { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pal.pill) } }
    }
}

// MARK: - Столбик балла заката

/// Балл заката 0…100 столбиком (Алексей 27.10; число внутрь — 28.10, «при нуле шкала похожа на презерватив»): капсула 25 × `height`, дорожка —
/// чернила × 0,10, снизу до балла заливка цветами рейки света (синий час → сирень → золото → янтарь), чёрточки 6 × 0,5 на 20 / 40 / 60 / 80.
/// Число 10 semibold стоит внутри трубки в стеклянной линзе (светлая пластинка, тонкая кромка, как на образце Алексея) по центру уровня заливки;
/// линза всегда целиком в капсуле: при 0 она у дна, при 100 — у верха. Отдельной полоски уровня и числа над трубкой больше нет.
struct BraunGauge: View {
    let pal: BraunPalette
    let score: Int
    let height: Double
    /// Ширину задаёт самое широкое число: «100» 10 semibold = 20,04 pt (замер `BraunText`) → линза 22 → трубка 25 (была 18). Шире нельзя: строка
    /// оценки слева («Рассвет · отличный», 9 pt = 91,73 на UIFont) и без того стоит впритык — место ей остаётся 154 − 25 − 1 − 36 = 92.
    static let width = 25.0
    /// Левый край столбика на плашке (правый — 154, как был: на 338 до волоска остаётся 5); колонка слева считает место от него.
    static let x = 154.0 - width
    static let numberSize = 10.0
    static let lensHeight = 14.0
    static let lensCorner = 6.0
    /// Зазор линзы до стенки трубки и самая узкая линза (для «0»…«9»).
    static let lensInset = 1.5
    static let lensMinWidth = 16.0

    static func lensWidth(score: Int) -> Double {
        min(width - 2 * lensInset, max(lensMinWidth, BraunText.width("\(score)", size: numberSize, semibold: true, mono: true) + 2))
    }

    /// Центр линзы по высоте, от верха трубки: на уровне заливки, но линза целиком в капсуле.
    static func lensCenterY(score: Int, height h: Double) -> Double {
        let level = h - h * BraunIdle.gaugeLevel(score: score)
        return min(h - lensInset - lensHeight / 2, max(lensInset + lensHeight / 2, level))
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a) }

    @Environment(\.widgetFlatGlass) private var flatGlass

    /// Линза: на телефоне — системное стекло (`.glassEffect`, Алексей 28.10: «на телефоне нативное стекло»), подкрашенное в светлое, чтобы тёмное число
    /// читалось на любой теме. `ImageRenderer` стекло не рисует, поэтому тесты и снимки (`widgetFlatGlass`) берут плоскую плашку того же размера и цвета.
    @ViewBuilder
    private func lens(width lw: Double, height lh: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.lensCorner, style: .continuous)
        let number = Text("\(score)").font(.system(size: Self.numberSize, weight: .semibold)).monospacedDigit().foregroundStyle(pal.lensText)
            .fixedSize().frame(width: lw, height: lh)
        if flatGlass {
            ZStack {
                shape.fill(pal.lens)
                shape.strokeBorder(pal.lensEdge, lineWidth: 0.5)
                number
            }
            .frame(width: lw, height: lh)
        } else {
            number.frame(width: lw, height: lh).glassEffect(.regular.tint(pal.lens), in: shape)
        }
    }

    var body: some View {
        let w = Self.width, h = height, fill = h * BraunIdle.gaugeLevel(score: score)
        let lw = Self.lensWidth(score: score), lh = Self.lensHeight, cy = Self.lensCenterY(score: score, height: h)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .bottom) {
                Capsule().fill(pal.ink(0.10))
                LinearGradient(stops: [
                    .init(color: Self.rgb(64, 92, 140, 0.75), location: 0), .init(color: Self.rgb(150, 110, 170, 0.9), location: 0.2),
                    .init(color: Self.rgb(226, 164, 76, 0.95), location: 0.45), .init(color: Self.rgb(244, 180, 0, 1), location: 1),
                ], startPoint: .bottom, endPoint: .top)
                    .frame(width: w, height: h)
                    .mask(alignment: .bottom) { Rectangle().frame(width: w, height: fill) }
            }
            .frame(width: w, height: h).clipShape(Capsule())
            ForEach(BraunIdle.gaugeMarks, id: \.self) { k in
                Rectangle().fill(pal.ink(0.35)).frame(width: 6, height: 0.5).offset(x: w / 2 - 3, y: h - h * Double(k) / 100 - 0.25)
            }
            lens(width: lw, height: lh)
                .offset(x: (w - lw) / 2, y: cy - lh / 2)
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }
}

extension BraunPalette {
    /// Линза столбика: матовое стекло чуть светлее заливки и дорожки; число на ней — всегда тёмные чернила (замер контраста в `WidgetGaugeTests`).
    var lens: Color { Color(.sRGB, red: 246 / 255, green: 243 / 255, blue: 236 / 255, opacity: dark ? 0.94 : 0.92) }
    var lensEdge: Color { Color.black.opacity(dark ? 0.55 : 0.30) }
    var lensText: Color { Color(.sRGB, red: 17 / 255, green: 17 / 255, blue: 17 / 255) }
}
