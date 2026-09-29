import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Контейнер блоков (`#cdEventBlocks`, итерация 26, шаг 2)

/// Блоки листа в порядке группы жанров (`AppModel.cardBlocks`). Не-блоки —
/// тревоги, студийный час — стоят над контейнером всегда, куда бы фотограф
/// ни переставил остальное. Плитка дня, наложение, свет, погода — 25–26;
/// сделка, место и дальше, заказ, деньги, сдача, заметки — шаг 4 итерации 26;
/// референсы — 27.
struct CardBlocks: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette
    let tick: Date

    var body: some View {
        if app.cardTuning {
            CardOrderList(app: app, s: s, phase: phase, pal: pal)
        } else {
            blocks
        }
    }

    @Environment(\.openURL) private var openURL

    /// Тап по документу: ссылка уходит в браузер, остальное решает модель.
    private func open(_ d: Attachment) {
        if case .url(let u) = app.openCardDoc(d) { openURL(u) }
    }

    @ViewBuilder private var blocks: some View {
        ForEach(app.cardBlocks(s, phase: phase), id: \.self) { b in
            switch b {
            case .deal: CardDealBlock(app: app, s: s, pal: pal)
            case .day: CardDayTile(app: app, s: s, phase: phase, pal: pal, tick: tick)
            case .clash: CardClash(app: app, s: s, phase: phase, pal: pal)
            case .light: CardLightBlock(app: app, s: s, phase: phase, pal: pal)
            case .place: CardPanesBlock(app: app, s: s, phase: phase, pal: pal)
            case .weather: CardWeatherBlock(app: app, s: s, phase: phase, pal: pal)
            case .route:
                if let r = app.cardRouteFold(s) {
                    CardFold(app: app, block: b, sub: r.sub, pal: pal) {
                        let lines = app.cardRouteLines(s)
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                            CardRouteLineView(line: l, first: i == 0, index: i, pal: pal)
                        }
                    }
                }
            case .brief: CardTextBlock(block: b, icon: "note_edit", tint: pal.blue, label: app.lexicon.t("cdBlock.brief"),
                                       lines: [s.brief], lineGap: 1.45, pal: pal)
            case .models: CardTextBlock(block: b, icon: "guests", tint: pal.brass, label: app.cardModelsTitle(s),
                                        lines: app.cardModels(s), lineGap: 1.5, pal: pal)
            case .docs: CardFold(app: app, block: b, sub: app.cardDocsCount(s), pal: pal) {
                ForEach(Array(app.cardDocRows(s).enumerated()), id: \.offset) { i, d in
                    CardDocLine(row: d, first: i == 0, pal: pal) { open(s.docs[i]) }
                }
                if let m = app.cardDocMessage {
                    Text(m).font(webFont(12.5)).foregroundStyle(pal.warnInk).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9).shotNode("card.docMessage", text: m)
                }
            }
            case .notes: CardTextBlock(block: b, icon: "note", tint: pal.blue, label: app.lexicon.t("card.notes"),
                                       lines: [s.notes], lineGap: 1.45, pal: pal)
            case .delivery: CardDeliveryBlock(app: app, s: s, pal: pal)
            case .money: CardMoneyBlock(app: app, s: s, pal: pal)
            case .refs: CardRefsBlock(app: app, s: s, pal: pal)
            }
        }
    }
}

// MARK: - Общее: плитка, знак на подложке

/// Плитка `.pane`: `--sheet-3`, радиус 16, поля 13×14.
private struct PaneShell<Content: View>: View {
    let pal: Palette
    let node: String
    var top: CGFloat = 9
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shotNode(node)
            .padding(.top, top)
    }
}

/// Знак на подложке (`.pane .badge`: 38×38, радиус 12, рисунок 19).
private func paneBadge(_ icon: String, _ tint: Color, _ pal: Palette) -> some View {
    Icon(icon, size: 19, line: 1.6).foregroundStyle(tint)
        .frame(width: 38, height: 38)
        .background(pal.badgeBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}

/// Мелкая подпись `pn-k`: 11, `--ink-6`, трекинг 0,2.
private func paneKey(_ text: String, _ pal: Palette) -> some View {
    Text(text).font(webFont(11)).tracking(0.2).foregroundStyle(pal.ink6).lineLimit(1)
}

// MARK: - Сделка (`#cdDeal`)

/// Цепочка сделки: «Сделка» и подпись — что осталось; кружки со звеньями и
/// нить между ними. Плитка `--sheet-3`, радиус 18, поля 14/12/12.
struct CardDealBlock: View {
    let app: AppModel
    let s: Session
    let pal: Palette

    var body: some View {
        if let d = app.cardDeal(s) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.lexicon.t("deal.title")).font(webFont(15)).foregroundStyle(pal.ink)
                    Spacer(minLength: 8)
                    Text(d.caption).font(webFont(12.5)).foregroundStyle(pal.ink4).lineLimit(1)
                        .shotNode("card.dealCaption", text: d.caption)
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(d.links.enumerated()), id: \.offset) { _, l in link(l) }
                }
                .background(alignment: .topLeading) { thread(d.links) }
                .padding(.top, 13)
            }
            .padding(EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12))
            .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shotNode("card.block.deal")
            .padding(.top, 14)
        }
    }

    private func link(_ l: CardDealLink) -> some View {
        let lit = l.done || l.isNext
        return VStack(spacing: 6) {
            ZStack {
                Circle().fill(l.done ? pal.brass : pal.surface)
                Circle().strokeBorder(lit ? pal.brass : pal.rail3, lineWidth: 1)
                if l.done { CheckMark().stroke(pal.sheet3, style: StrokeStyle(lineWidth: 2.4 * 13 / 24, lineCap: .round, lineJoin: .round)).frame(width: 13, height: 13) }
            }
            .frame(width: 26, height: 26)
            Text(l.name).font(webFont(11)).foregroundStyle(l.isNext ? pal.brass : l.done ? pal.ink3 : pal.ink6)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .shotNode("card.dealLink.\(l.step.rawValue)", text: l.done ? "done" : l.isNext ? "next" : "open")
    }

    /// Нить между кружками — по центру, 1 pt: `--press`, у закрытого звена (слева от него) — латунь.
    private func thread(_ links: [CardDealLink]) -> some View {
        GeometryReader { g in
            let w = g.size.width / CGFloat(max(1, links.count))
            ForEach(Array(links.enumerated()).dropFirst(), id: \.offset) { i, l in
                Rectangle().fill(l.done ? pal.brass : pal.press).frame(width: w, height: 1)
                    .offset(x: w * (CGFloat(i) - 0.5), y: 13)
            }
        }
    }
}

/// Галка звена: ломаная 5,12.5 → 10,17.5 → 19,6.5 на сетке 24.
private struct CheckMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let k = r.width / 24
        p.move(to: CGPoint(x: 5 * k, y: 12.5 * k))
        p.addLine(to: CGPoint(x: 10 * k, y: 17.5 * k))
        p.addLine(to: CGPoint(x: 19 * k, y: 6.5 * k))
        return p
    }
}

// MARK: - Место и дальше (`#cdPanes`)

/// Сетка из двух столбцов, зазор 9: место — во всю ширину, «Дальше», гости,
/// порода, выезд, оборудование — половинки.
struct CardPanesBlock: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette

    var body: some View {
        let rows = layout(app.cardPanes(s, phase: phase))
        VStack(spacing: 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 9) {
                    ForEach(row, id: \.self) { p in pane(p) }
                }
            }
        }
        .shotNode("card.block.place")
        .padding(.top, 9)
    }

    private func layout(_ panes: [CardPane]) -> [[CardPane]] {
        var rows: [[CardPane]] = []
        var pending: CardPane?
        for p in panes {
            if p.wide { rows.append([p]) }
            else if let a = pending { rows.append([a, p]); pending = nil }
            else { pending = p }
        }
        if let a = pending { rows.append([a]) }
        return rows
    }

    private func pane(_ p: CardPane) -> some View {
        // «Дальше»: мелкая строка под всем рядом (знак + текст), на всю ширину плитки, mt 8;
        // час — `--brass`. Пара мерила 4 pt ниже веба: строка стояла в колонке текста и обрезалась.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                paneBadge(p.icon, pal.brass, pal)
                VStack(alignment: .leading, spacing: 0) {
                    if let k = p.label { paneKey(k, pal) }
                    if let t = p.title {
                        Text(t).font(webFont(15)).foregroundStyle(pal.ink).lineLimit(1).padding(.top, p.label == nil ? 0 : 2)
                    }
                    if let v = p.value { Text(v).font(webFont(17)).monospacedDigit().foregroundStyle(pal.ink) }
                    if p.kind != .next, let sub = p.sub {
                        Text(sub).font(webFont(12)).foregroundStyle(pal.ink6).lineLimit(1).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let w = p.weather { weather(w) }
            }
            if p.kind == .next, let sub = p.sub { nextLine(sub, at: p.at).padding(.top, 8) }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shotNode("card.pane.\(String(describing: p.kind))")
    }

    private func nextLine(_ sub: String, at: String?) -> some View {
        let base = Text(sub).foregroundStyle(pal.ink6)
        guard let at, let r = sub.range(of: at, options: .backwards) else {
            return base.font(webFont(12)).lineLimit(1)
        }
        return (Text(String(sub[..<r.lowerBound])).foregroundStyle(pal.ink6)
            + Text(at).foregroundStyle(pal.brass)
            + Text(String(sub[r.upperBound...])).foregroundStyle(pal.ink6))
            .font(webFont(12)).lineLimit(1)
    }

    /// Справа у места: знак и градус (19), слово неба (12).
    private func weather(_ w: CardPaneWeather) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                if let sky = w.sky {
                    Icon(sky, size: 22, line: 1.4)
                        .foregroundStyle(sky == "clear" ? pal.brassSoft : sky == "rain" ? pal.blue : pal.ink4)
                        .frame(width: 24, height: 22)
                }
                Text(w.temp).font(webFont(19)).foregroundStyle(pal.ink)
            }
            Text(w.word).font(webFont(12)).foregroundStyle(pal.ink6)
        }
        .fixedSize()
    }
}

// MARK: - Задание, модели, заметки

/// Плитка во всю ширину: знак, подпись и текст (13, шаг 1,45; у моделей 1,5).
/// Цвет текста — токен темы, не прибитый `#C9C2B6` веба (ошибка 11 справки).
struct CardTextBlock: View {
    let block: CardBlock
    let icon: String
    let tint: Color
    let label: String
    let lines: [String]
    let lineGap: CGFloat
    let pal: Palette

    var body: some View {
        PaneShell(pal: pal, node: "card.block.\(block.rawValue)") {
            HStack(alignment: .top, spacing: 12) {
                paneBadge(icon, tint, pal)
                VStack(alignment: .leading, spacing: 0) {
                    paneKey(label, pal)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            Text(l).font(webFont(13)).foregroundStyle(pal.ink2)
                                .lineSpacing(13 * (lineGap - 1.19))
                                // Межстрочье CSS — на каждой строке, `lineSpacing` — только между ними:
                                // полшага сверху и снизу добирают высоту (пара: блок был ниже веба на 2,5).
                                .padding(.vertical, 13 * (lineGap - 1.19) / 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Гонорар и сдача

struct CardMoneyBlock: View {
    let app: AppModel
    let s: Session
    let pal: Palette

    var body: some View {
        if let m = app.cardMoney(s) {
            PaneShell(pal: pal, node: "card.block.money") {
                HStack(alignment: .center, spacing: 12) {
                    paneBadge("purse", pal.brass, pal)
                    VStack(alignment: .leading, spacing: 0) {
                        paneKey(app.lexicon.t("pane.fee"), pal)
                        (Text(m.income).font(webFont(17)).foregroundStyle(pal.ink)
                            + Text(m.expenseNote.map { " " + $0 } ?? "").font(webFont(12)).foregroundStyle(pal.ink6))
                            .monospacedDigit()
                            .padding(.top, 2) // `.pn-v { margin-top: 2px }`
                        if let p = m.prepayNote {
                            Text(p).font(webFont(12)).foregroundStyle(pal.ink6).padding(.top, 3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(m.net).font(webFont(17)).monospacedDigit().foregroundStyle(pal.brass)
                }
            }
        }
    }
}

/// Сдача: весь ряд — кнопка; слова срочности цветом ступени, срок мельче,
/// справа тумблер. Тап переключает «сдан» и ставит дату.
struct CardDeliveryBlock: View {
    let app: AppModel
    let s: Session
    let pal: Palette

    var body: some View {
        if let d = app.cardDelivery(s) {
            let f = PlannerFacts(app: app, dark: pal.dark)
            PaneShell(pal: pal, node: "card.block.delivery") {
                HStack(alignment: .center, spacing: 12) {
                    paneBadge("clock", pal.brass, pal)
                    VStack(alignment: .leading, spacing: 0) {
                        paneKey(app.lexicon.t("pane.handover"), pal)
                        (Text(d.label).font(webFont(15)).foregroundStyle(f.deliveryColor(d.status))
                            + Text(d.byDate.map { " · " + $0 } ?? "").font(webFont(12.5)).foregroundStyle(pal.ink6))
                            .lineLimit(2).padding(.top, 2)
                            .shotNode("card.deliveryText", text: d.label)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("", isOn: Binding(get: { d.delivered }, set: { _ in app.toggleDelivered(id: s.id) }))
                        .labelsHidden().tint(pal.brass)
                        .accessibilityLabel(app.lexicon.t("form.delivered"))
                }
                .contentShape(Rectangle())
                .onTapGesture { app.toggleDelivered(id: s.id) }
            }
        }
    }
}

// MARK: - Документы и маршрут

/// Строка документа: знак `doc`, имя (15) и вид (12). Знак и имя — во всю
/// оставшуюся ширину, не в узком столбце (ошибка 15 справки). Тап — открыть.
struct CardDocLine: View {
    let row: CardDocRow
    let first: Bool
    let pal: Palette
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) { line }.buttonStyle(.plain)
    }

    private var line: some View {
        HStack(spacing: 12) {
            Icon("doc", size: 18, line: 1.5).foregroundStyle(pal.ink5b).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(webFont(15)).foregroundStyle(pal.ink2).lineLimit(1)
                Text(row.kind).font(webFont(11.5)).foregroundStyle(pal.ink7).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { if !first { Rectangle().fill(pal.surface).frame(height: 1) } }
        .shotNode("card.docRow")
    }
}

/// Строка ленты маршрута (`.sc-item`): знак 26, время 50, имя с местом,
/// справа слово света. Прошедшая бледная (0,45), текущая — имя чернилами и
/// зелёный знак. Между строками щель, у первой её нет.
struct CardRouteLineView: View {
    let line: CardRouteLine
    let first: Bool
    var index = 0
    let pal: Palette

    var body: some View {
        HStack(spacing: 10) {
            Icon(line.sign, size: 18, line: 1.4).foregroundStyle(line.state == .now ? pal.green : pal.ink5b)
                .frame(width: 26, alignment: .leading)
            Text(line.time).font(webFont(14)).monospacedDigit().foregroundStyle(pal.ink3)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.name).font(webFont(15)).foregroundStyle(line.state == .now ? pal.ink : pal.ink2)
                if let p = line.place { Text(p).font(webFont(11.5)).foregroundStyle(pal.ink7) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let w = line.word {
                Text(w).font(webFont(11.5)).foregroundStyle(line.blue ? pal.blue : pal.brass)
            }
        }
        .padding(.vertical, 9)
        .opacity(line.state == .past ? 0.45 : 1)
        .overlay(alignment: .top) { if !first { Rectangle().fill(pal.surface).frame(height: 1) } }
        .shotNode("card.routeRow.\(index)", text: "\(line.state)")
    }
}

/// Свёртка (`.fold`: маршрут, документы): заголовок-кнопка, шеврон
/// поворачивается на 180° за 0,35 с, тело — без анимации высоты, поля `0 14 13`
/// (`.fold-body`, замер пары 27: было 4, тело короче веба на 9). Открытая
/// держится, пока карточка открыта (`AppModel.cardFolds`).
struct CardFold<Content: View>: View {
    let app: AppModel
    let block: CardBlock
    var sub: String? = nil
    let pal: Palette
    @ViewBuilder let content: () -> Content

    var body: some View {
        let open = app.isCardFoldOpen(block)
        VStack(spacing: 0) {
            Button { app.toggleCardFold(block) } label: {
                HStack(spacing: 12) {
                    paneBadge(block.iconName, pal.brass, pal)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.lexicon.t("cdBlock.\(block.rawValue)")).font(webFont(15)).foregroundStyle(pal.ink)
                        if let sub { Text(sub).font(webFont(12)).foregroundStyle(pal.ink6).padding(.top, 2) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pal.ink4)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .animation(.easeInOut(duration: 0.35), value: open)
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { VStack(spacing: 0) { content() }.padding(.horizontal, 14).padding(.bottom, 13) }
        }
        .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shotNode("card.block.\(block.rawValue)", text: open ? "open" : "shut")
        .padding(.top, 9)
    }
}
