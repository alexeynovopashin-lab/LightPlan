import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Неделя (веб `renderWeek`): семь строк занятости, а не световых лент.
/// Слева число, день недели и погода; справа съёмки дня (сначала с маршрутом,
/// потом по времени) или «свободно», строка света (закат у занятого дня,
/// золотой час у свободного) и что сдать в этот день. Тап по голове строки
/// выбирает день и раскрывает подробности; открыта всегда одна.
struct PlannerWeekBody: View {
    @Bindable var app: AppModel
    let f: PlannerFacts

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(app.planner.week.enumerated()), id: \.element) { i, d in
                WeekRow(app: app, f: f, day: d).shotNode("wk.\(i)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .shotNode("week")
        .padding(.bottom, 20)
    }
}

private struct WeekRow: View {
    @Bindable var app: AppModel
    let f: PlannerFacts
    let day: CivilDate
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let st = app.planner
        let today = f.today
        let isToday = day == today, sel = day == st.selected, open = st.weekOpen == day
        let q = f.weather(day).quality
        HStack(alignment: .top, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { app.planner.tapWeekRow(day) }
            } label: {
                VStack(spacing: 1) {
                    Text("\(day.day)").font(webFont(19, isToday ? 650 : 400)).monospacedDigit()
                        .foregroundStyle(isToday ? pal.brass : pal.ink)
                        .frame(height: 22)
                    Text(f.dates.wdShort(f.date(day))).font(webFont(10)).tracking(0.6)
                        .foregroundStyle(isToday ? pal.brass : pal.ink7)
                        .frame(height: 12)
                    VStack(spacing: 1) {
                        Icon(q.weekSignName, size: 17).foregroundStyle(pal.ink4)
                        Text("\(f.temp(day))°").font(webFont(11)).monospacedDigit().foregroundStyle(pal.ink4)
                            .frame(height: 13)
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 4)
                .frame(width: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            list(pal, open: open, sel: sel)
        }
        .padding(8)
        .opacity(day < today ? 0.5 : 1)
    }

    private func list(_ pal: Palette, open: Bool, sel: Bool) -> some View {
        let shoots = f.shown(on: day).enumerated().sorted {
            let aw = Self.hasRoute($0.element.genre) ? 0 : 1
            let bw = Self.hasRoute($1.element.genre) ? 0 : 1
            return (aw, $0.element.start, $0.offset) < (bw, $1.element.start, $1.offset)
        }.map(\.element)
        let due = app.sessions.filter { s in
            !s.delivered && Delivery.deadline(for: s, setting: app.delivery, prefs: app.genrePrefs) == day
        }
        let sky = f.sky(day)
        return VStack(alignment: .leading, spacing: 0) {
            if shoots.isEmpty {
                Text(f.t.t(open ? "week.freeOpen" : "week.free"))
                    .font(webFont(13.5)).foregroundStyle(pal.ink7)
                    .padding(.horizontal, 12).padding(.vertical, 9)
            } else {
                ForEach(shoots, id: \.id) { s in card(s, pal) }
            }
            if sky.set != nil || sky.goldenB != nil {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if shoots.isEmpty {
                        Icon("golden", size: 14)
                        Text(f.t.t("week.goldenAt", ["t": f.fmt(sky.goldenB ?? sky.set)]))
                    } else {
                        Icon("sunset", size: 14)
                        Text(f.t.t("week.sunsetAt", ["t": f.fmt(sky.set)]))
                    }
                }
                .font(webFont(12)).monospacedDigit()
                .foregroundStyle(pal.brassDeep)
                .frame(height: 17)
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 8, trailing: 12))
            }
            if !due.isEmpty {
                let list = due.map { s in
                    let n = f.words.clientName(s)
                    return n.isEmpty ? f.words.typeName(s) : n
                }.joined(separator: ", ")
                HStack(spacing: 7) {
                    Icon("clock", size: 14)
                    Text(f.t.t("week.dueList", ["list": list])).lineLimit(1)
                }
                .font(webFont(12)).foregroundStyle(pal.terra)
                .frame(height: 15)
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            if open { details(pal, sky: sky) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet)
                .overlay {
                    if sel { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pal.brassDark, lineWidth: 1) }
                }
        }
    }

    /// Маршрут у жанра всегда (веб `hasRoute`): свой признак жанра сильнее группы.
    static func hasRoute(_ g: Genre?) -> Bool {
        guard let g else { return false }
        return g.spec.explicitRoute ?? (g.group.spec.route == .always)
    }

    private func card(_ s: Session, _ pal: Palette) -> some View {
        let meet = s.kind == .meet, soft = !s.kind.isWork
        let who = f.words.clientName(s)
        let title = meet ? f.t.t("week.meetWith", ["genre": f.words.shortType(s).lowercased()])
            : soft ? f.t.t("plan.event") + (who.isEmpty ? "" : " · " + who)
            : f.words.typeName(s) + (who.isEmpty ? "" : " · " + who)
        return HStack(spacing: 9) {
            Group {
                if soft { Icon(meet ? "guests" : "view_month", size: 17) }
                else if let n = f.words.iconName(s) { Icon(n, size: 17) }
                else { Icon(genre: s.genre?.rawValue ?? "", size: 17) }
            }
            .foregroundStyle(meet ? pal.ink5 : pal.brass)
            Text(title).font(webFont(14)).foregroundStyle(soft ? pal.ink3 : pal.ink).lineLimit(1)
            Spacer(minLength: 8)
            Text(f.range(Double(s.start), Double(s.endMinute))).font(webFont(12.5)).monospacedDigit()
                .foregroundStyle(pal.ink4)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    /// Раскрытый день (`.wk-more`): рассвет, закат, золотой час и погода.
    private func details(_ pal: Palette, sky: SolarDay) -> some View {
        let wx = f.weather(day)
        return VStack(alignment: .leading, spacing: 4) {
            det(pal, "sunrise", f.t.t("tele.sunrise"), f.fmt(sky.rise), gold: false)
            if sky.set != nil { det(pal, "sunset", f.t.t("tele.sunset"), f.fmt(sky.set), gold: false) }
            if sky.goldenB != nil { det(pal, "clock", f.t.t("tele.golden"), f.range(sky.goldenB, sky.blueB), gold: true) }
            Text(f.t.t("week.wx", ["cloud": "\(wx.cloud)", "wind": "\(wx.wind)"]))
                .font(webFont(12)).foregroundStyle(pal.ink4)
        }
        .padding(EdgeInsets(top: 2, leading: 12, bottom: 10, trailing: 12))
    }

    private func det(_ pal: Palette, _ ic: String, _ k: String, _ v: String, gold: Bool) -> some View {
        HStack(spacing: 6) {
            Icon(ic, size: 14).foregroundStyle(pal.brass)
            Text(k).foregroundStyle(pal.ink4)
            Spacer(minLength: 8)
            Text(v).monospacedDigit().foregroundStyle(gold ? pal.brass : pal.ink2)
        }
        .font(webFont(12.5))
    }
}
