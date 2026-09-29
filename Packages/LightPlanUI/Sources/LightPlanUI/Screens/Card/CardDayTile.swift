import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Строки плитки дня (веб `renderDayTile`) — отдельно от вида, чтобы тесты
/// читали их словами.
@MainActor
struct DayTileText {
    /// Верхняя строка: «Сейчас: Прогулка», «Идёт съёмка», «18:47 – 19:47».
    var now: String
    /// Строка под ней; жирные части (зелёные) обёрнуты в `\u{1}…\u{2}`.
    var left: String
    /// Зелёная точка у верхней строки — только «во время».
    var dot: Bool
    /// Часы «сейчас» по часам места — только в сутки съёмки.
    var clock: String?
    /// Пояс места у часов, если он не пояс телефона: «UTC+3».
    var zone: String?

    /// `left` без меток жирного.
    var plainLeft: String { left.filter { $0 != "\u{1}" && $0 != "\u{2}" } }

    init(_ s: Session, phase: EventPhase, app: AppModel) {
        let f = PlannerFacts(app: app, dark: true)
        let t = f.t
        let nowMin = app.nowMinute(of: s)
        let route = Self.route(of: s)
        let cur = Self.current(route, nowMin)
        clock = nowMin.map { f.fmt(Double($0)) }
        zone = nowMin == nil ? nil : app.zoneTag(of: s)
        dot = phase == .during
        let b = { (x: String) in "\u{1}" + x + "\u{2}" }
        let done = t.t(s.kind == .meet ? "day.meetDone" : s.kind == .event ? "day.eventDone" : "day.shootDone")
        let endMin = s.endMinute
        let dur = (s.duration ?? 0) != 0 ? s.duration! : 90

        guard let first = route.first, let firstT = first.start else {
            // Без точек съёмка — отрезок: когда начинается и сколько идёт.
            switch phase {
            case .during:
                now = t.t("day.running")
                let rest = endMin - (nowMin ?? endMin)
                // «Сверх плана» бывает только при ручном завершении.
                left = rest >= 0
                    ? t.t("day.leftUntil", ["left": b(f.durLabel(rest)), "t": f.fmt(Double(endMin))])
                    : t.t("day.overBy", ["over": b(f.durLabel(-rest)), "t": f.fmt(Double(endMin))])
            case .after:
                now = done
                left = f.range(Double(s.start), Double(endMin)) + " · " + f.durLabel(dur)
            case .before:
                now = f.range(Double(s.start), Double(endMin))
                left = f.durLabel(dur) + (nowMin.map {
                    " · " + t.t("day.startsIn", ["in": f.durLabel(max(0, s.start - $0))])
                } ?? "")
            }
            return
        }
        // День с точками кончается концом последней, а не её началом.
        let last = route[route.count - 1]
        let lastEnd = last.end ?? last.start ?? firstT
        if phase == .during, cur >= 0, let nowMin {
            now = t.t("day.nowAt", ["name": route[cur].name])
            if cur + 1 < route.count, let nt = route[cur + 1].start {
                left = t.t("day.leftNext", ["left": b(f.durLabel(nt - nowMin)), "next": route[cur + 1].name])
            } else {
                left = t.t("day.lastPoint")
            }
        } else if let nowMin, phase == .before || phase == .during {
            // Сегодня до первой точки — «Скоро: …». И «во время» до первой
            // точки тоже: съёмку начали раньше неё (Алексей, 28.09). Веб здесь
            // пишет «Съёмка закончена» — ошибку эталона не переносим.
            now = t.t("day.soonAt", ["name": first.name])
            left = t.t("day.inAt", ["left": b(f.durLabel(firstT - nowMin)), "t": f.fmt(Double(firstT))])
        } else if phase == .before {
            now = f.range(Double(firstT), Double(lastEnd))
            left = f.durLabel(lastEnd - firstT) + " · " + t.count("unit.point", route.count)
        } else {
            now = done
            left = f.range(Double(firstT), Double(lastEnd))
        }
    }

    /// Точки дня «что во сколько» (веб `routeOf`); у встречи и события — нет.
    static func route(of s: Session) -> [RoutePoint] {
        s.kind == .shoot ? s.timedRoute : []
    }

    /// Последняя точка, начатая не позже «сейчас» (веб `curIndex`); −1 — ни одной.
    static func current(_ route: [RoutePoint], _ nowMin: Int?) -> Int {
        guard let nowMin else { return -1 }
        return route.lastIndex { ($0.start ?? .max) <= nowMin } ?? -1
    }
}

/// Плитка дня (`#cdDay`): дата слева, «что сейчас» справа, под ними лента
/// точек маршрута. Одна плитка на запись, у встречи и события тоже.
struct CardDayTile: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette
    /// Такт карточки (раз в минуту): часы места и «осталось» пересчитываются.
    let tick: Date

    var body: some View {
        let x = DayTileText(s, phase: phase, app: app)
        let f = PlannerFacts(app: app, dark: pal.dark)
        let route = DayTileText.route(of: s)
        // Сетка веба `auto | 1fr`: дата стоит по середине высоты
        // (`align-self: center`), правый столбец — сверху, и лента точек живёт
        // в нём (`.dt-main > .lane`), а не на всю ширину плитки.
        HStack(alignment: .top, spacing: 12) {
            date(f).frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                top(x)
                rich(x.left).font(webFont(12.5)).foregroundStyle(pal.ink4)
                    .shotNode("card.dayLeft", text: x.plainLeft).padding(.top, 3)
                if !route.isEmpty {
                    CardLane(app: app, s: s, route: route, phase: phase, pal: pal)
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.sheet3))
        .shotNode("card.day")
        .padding(.top, 14)
    }

    /// Число, месяц, день недели — день начала записи; справа черта.
    private func date(_ f: PlannerFacts) -> some View {
        let d = f.date(s.day)
        return VStack(spacing: 0) {
            Text("\(s.day.day)").font(webFont(42, 700)).tracking(-1.5).monospacedDigit()
                .foregroundStyle(pal.glyph).frame(height: 42 * 0.92)
            Text(f.dates.monthOfDate(d)).font(webFont(12)).tracking(0.3).foregroundStyle(pal.ink).padding(.top, 5)
            Text(f.dates.wdFull(d)).font(webFont(11)).foregroundStyle(pal.ink6).padding(.top, 2)
        }
        .padding(.trailing, 11)
        .overlay(alignment: .trailing) { Rectangle().fill(pal.surface).frame(width: 1) }
        .shotNode("card.dayDate")
    }

    private func top(_ x: DayTileText) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 7) {
                if x.dot { Circle().fill(pal.green).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 } }
                Text(x.now).font(webFont(15)).foregroundStyle(pal.ink).lineLimit(1).truncationMode(.tail)
                    .shotNode("card.dayNow", text: x.now)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let c = x.clock {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(c).font(webFont(13.5)).monospacedDigit().foregroundStyle(pal.ink3)
                    if let z = x.zone { Text(z).font(webFont(11)).foregroundStyle(pal.ink3) }
                }
                .fixedSize()
                .shotNode("card.dayClock", text: c)
            }
        }
    }

    /// Строка с зелёными частями (веб `<b>` в `.dt-left`, вес обычный).
    private func rich(_ s: String) -> Text {
        var out = Text("")
        var bold = false
        for part in s.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\u{1}" || $0 == "\u{2}" }) {
            let piece = Text(String(part))
            out = out + (bold ? piece.foregroundColor(pal.green) : piece)
            bold.toggle()
        }
        return out
    }
}

/// Лента точек дня (`#cdLane`): знак, рельс с точкой, час, первое слово имени.
/// Прошедшие — латунью, текущая — зелёным кольцом. Не влезает по 40 pt на
/// точку — колонки встают по 44 и лента прокручивается, «сейчас» посередине.
/// Своя механика барабана веба (сопротивление, доводка, щелчок) — итерация 29.
struct CardLane: View {
    let app: AppModel
    let s: Session
    let route: [RoutePoint]
    let phase: EventPhase
    let pal: Palette

    /// Меньше стольких pt на точку — лента подвижная (веб `LANE_FIT`).
    static let fit: CGFloat = 40
    static let column: CGFloat = 44

    var body: some View {
        let nowMin = app.nowMinute(of: s)
        // Текущая — последняя начатая, только «во время».
        let cur = phase == .during ? DayTileText.current(route, nowMin) : -1
        // Опора — где «сейчас»: текущая, иначе последняя пройденная, иначе начало.
        let anchor = cur >= 0 ? cur : max(0, route.indices.last { past($0, nowMin) } ?? 0)
        GeometryReader { g in
            let scroll = g.size.width / CGFloat(route.count) < Self.fit
            let w = scroll ? Self.column : g.size.width / CGFloat(route.count)
            if scroll {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        track(w, nowMin, cur)
                    }
                    .onAppear { proxy.scrollTo(anchor, anchor: .center) }
                }
            } else {
                track(w, nowMin, cur)
            }
        }
        .frame(height: 26 + 14 + 6 + 13 + 2 + 12)
        .shotNode("card.lane", text: "\(route.count)")
    }

    private func past(_ i: Int, _ nowMin: Int?) -> Bool {
        if phase == .after { return true }
        guard let nowMin, let t = route[i].start else { return false }
        return t <= nowMin
    }

    private func track(_ w: CGFloat, _ nowMin: Int?, _ cur: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(route.indices, id: \.self) { i in
                point(i, w, now: i == cur, past: i != cur && past(i, nowMin)).id(i)
            }
        }
    }

    private func point(_ i: Int, _ w: CGFloat, now: Bool, past: Bool) -> some View {
        let r = route[i], n = route.count
        // Концы ленты прижаты к краям плитки: точка и нить — в 13 pt от края.
        let edge: HorizontalAlignment = n > 1 && i == 0 ? .leading : n > 1 && i == n - 1 ? .trailing : .center
        let dotX: CGFloat = edge == .leading ? 13 : edge == .trailing ? w - 13 : w / 2
        let place = r.placeText.isEmpty ? (app.spots.first { $0.id == r.spotId }?.name ?? "") : r.placeText
        let studio = app.studios.contains { $0.id == r.studioId }
        let alignment: Alignment = edge == .leading ? .leading : edge == .trailing ? .trailing : .center
        return VStack(alignment: edge, spacing: 0) {
            Icon(point: r.name, place: place, studio: studio, size: 20, line: 1.4)
                .foregroundStyle(now ? pal.ink : past ? pal.brass : pal.ink5b)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(now ? pal.green : .clear, lineWidth: 1.4))
            Canvas { ctx, size in
                let y = size.height / 2
                let leftOn = i > 0, rightOn = i < n - 1
                if leftOn {
                    ctx.fill(Path(CGRect(x: 0, y: y - 0.7, width: dotX, height: 1.4)),
                             with: .color(past || now ? pal.brass : pal.rail4))
                }
                if rightOn {
                    ctx.fill(Path(CGRect(x: dotX, y: y - 0.7, width: size.width - dotX, height: 1.4)),
                             with: .color(past ? pal.brass : pal.rail4))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: dotX - 4, y: y - 4, width: 8, height: 8)),
                         with: .color(now ? pal.green : past ? pal.brass : pal.ink8))
            }
            .frame(width: w, height: 14)
            Text(r.start.map { PlannerFacts(app: app, dark: pal.dark).fmt(Double($0)) } ?? "")
                .font(webFont(11)).monospacedDigit().foregroundStyle(now ? pal.ink : pal.ink3)
                .padding(.top, 6)
            Text(Self.word(r.name)).font(webFont(9.5)).tracking(-0.2).foregroundStyle(pal.ink7)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: max(0, w - 8), alignment: alignment)
                .padding(.top, 2)
        }
        .frame(width: w, alignment: alignment)
    }

    /// На ленте помещается одно слово: «Сборы жениха» → «Сборы» (веб `laneWord`).
    static func word(_ n: String) -> String {
        let w = n.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return w.count > 11 ? String(w.prefix(10)) + "…" : w
    }
}
