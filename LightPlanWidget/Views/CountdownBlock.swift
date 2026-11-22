import SwiftUI
import LightPlanDomain

/// Нижнее поле большого виджета (30и.13, Б2): блок отсчёта Braun — тёмный (светлый) циферблат, слева кольцо точек до ближайшей
/// съёмки (или её хода, если идёт) со знаком жанра и сроком, справа строки съёмок недели. **Рисков нет** (Алексей 16.11: «риски я не просил добавить,
/// я просил оставить там где мы их намеренно добавили» — они только у Braun). Съёмок нет — «до сб 21 съёмок нет», длина дня и закаты трёх дней.
struct CountdownBlock: View {
    let frame: WidgetFrame
    let pal: BraunPalette

    private var rows: [BraunIdle.WeekRow] { BraunIdle.weekRows(frame) }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.dial)
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pal.dialEdge, lineWidth: 0.5)
                if let first = frame.week.first { shoots(first, size: g.size) } else { empty(size: g.size) }
            }
        }
    }

    // MARK: Съёмки есть

    private func shoots(_ first: WidgetFrame.ShootFrame, size: CGSize) -> some View {
        let inner = size.height - 16
        let dia = min(inner, 96)
        let n = max(1, min(rows.count, Int(inner / 34)))
        let rh = min(40, inner / CGFloat(n))
        return HStack(alignment: .center, spacing: 14) {
            dial(first, diameter: dia)
            VStack(spacing: 0) {
                ForEach(Array(rows.prefix(n).enumerated()), id: \.offset) { i, row in
                    shootRow(row, frame.week[i], height: rh)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .frame(width: size.width, height: size.height)
    }

    private func dial(_ s: WidgetFrame.ShootFrame, diameter: CGFloat) -> some View {
        let fill = BigWidget.ringFill(s, now: frame.now)
        let running = s.shoot.startDate <= frame.now
        let t = s.shoot.startDate.timeIntervalSince(frame.now)
        let r = diameter / 2 - 5
        return ZStack {
            if BigWidget.showsRing(s, now: frame.now) { Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<36 {
                    let a = Double(i) / 36 * 2 * .pi - .pi / 2
                    let lit = Double(i) < (fill * 36).rounded()
                    let rad: CGFloat = lit ? 1.7 : 1.3
                    let p = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - rad, y: p.y - rad, width: 2 * rad, height: 2 * rad)), with: .color(lit ? pal.dot : pal.dotOff))
                }
            } }
            VStack(spacing: 1) {
                WidgetIcon(name: s.shoot.genre, size: 18, line: 1.5, genre: true).foregroundStyle(pal.amber).frame(width: 18, height: 18)
                if running {
                    Text(BigWidget.span(frame, seconds: max(60, s.shoot.endDate.timeIntervalSince(frame.now))))
                        .font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(pal.text).lineLimit(1).minimumScaleFactor(0.6)
                    Text(frame.words[.untilShoot]).font(.system(size: 9)).foregroundStyle(pal.muted).lineLimit(1).minimumScaleFactor(0.6)
                } else if t < 48 * 3600 {
                    Text(BigWidget.span(frame, seconds: t))
                        .font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(pal.text).lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text(frame.words.inDays(max(2, s.dayOffset))).font(.system(size: 11, weight: .semibold)).foregroundStyle(pal.text)
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                }
            }
            .frame(width: diameter - 20)
        }
        .frame(width: diameter, height: diameter)
    }

    func shootRow(_ row: BraunIdle.WeekRow, _ s: WidgetFrame.ShootFrame, height: CGFloat) -> some View {
        let until = BigWidget.untilText(frame, to: s.shoot.startDate, dayOffset: s.dayOffset)
        return HStack(spacing: 7) {
            WidgetIcon(name: row.genre, size: 16, line: 1.5, genre: true).foregroundStyle(row.near ? pal.amber : pal.muted).frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.names).font(.system(size: 13, weight: row.near ? .semibold : .medium)).foregroundStyle(row.near ? pal.amber : pal.text).lineLimit(1)
                (Text("\(row.day) · \(row.time)") + (until.map { Text(" · \($0)").fontWeight(.semibold) } ?? Text("")))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(pal.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .background { if row.near { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pal.pill) } }
    }

    // MARK: Съёмок нет

    /// Строка «до сб 21 съёмок нет» с длиной дня справа и закаты трёх следующих дней под ней (Алексей 16.11: «чтобы пространство не пустовало»;
    /// дни — то же правило, что у среднего: `BraunIdle.sunsetRows`, строка `BraunSunsetRow`, на большом со временем и полоской у рассвета и заката, 31.7).
    private func empty(size: CGSize) -> some View {
        let sunsets = BraunIdle.sunsetRows(frame)
        let cols = BraunSunsetRow.Cols.of(sunsets)
        let rowH = sunsets.isEmpty ? 0 : min(36, (size.height - 24 - 26 - 8) / CGFloat(sunsets.count))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(BraunIdle.emptyWeekLine(frame) ?? "").font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.text).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if let d = frame.day, let r = d.sunrise, let s = d.sunset {
                    Text("\(frame.words[.dayLength]) \(RemainText(words: frame.words).long(s.timeIntervalSince(r)))")
                        .font(.system(size: 12)).foregroundStyle(pal.muted).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(height: 26)
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                ForEach(sunsets.indices, id: \.self) { i in BraunSunsetRow(row: sunsets[i], pal: pal, width: size.width - 28, height: rowH, wide: true, cols: cols) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
