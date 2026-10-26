import SwiftUI
import LightPlanDomain

/// Строка под часами на экране блокировки (`accessoryInline`): «☀︎ 17:02 · съёмка 15:00» — жанр, не имя клиента.
/// Алексей 24.10 не ответил — вариант оркестратора, обратимо.
struct LockInlineView: View {
    let frame: WidgetFrame
    let alpha: Bool

    var body: some View {
        // Строка — один `Text`: система сама режет её по ширине. Идущая съёмка с отсчётом: таймер идёт сам.
        if frame.kind == .live, let c = frame.primary?.countdown {
            Text("◔ ") + Text(timerInterval: frame.now...max(c.to, frame.now), countsDown: true) + Text(liveTail)
        } else {
            Text(line)
        }
    }

    /// После таймера: следующая точка или жанр.
    var liveTail: String {
        guard let p = frame.primary else { return "" }
        let tail = alpha ? " α" : ""
        if let n = p.next { return " · \(frame.clock(n.date, in: p.zone)) \(n.name)" + tail }
        return " · \(p.shoot.title)" + tail
    }

    var line: String {
        let tail = alpha ? " α" : ""
        switch frame.kind {
        case .blank: return "☀︎ —" + tail
        case .light:
            guard let e = frame.light, let at = e.at else { return "☀︎ —" + tail }
            let name = e.kind == .sunrise ? frame.words[.sunrise] : frame.words[.sunset]
            return "☀︎ \(name) \(frame.clock(at, in: frame.zone))" + tail
        case .upcoming:
            guard let p = frame.primary else { return "☀︎ —" + tail }
            let shoot = "\(frame.words[.shoot]) \(frame.clock(p.shoot.startDate, in: p.zone))"
            if let g = p.golden { return "☀︎ \(frame.clock(g, in: p.zone)) · \(shoot)" + tail }
            return "☀︎ \(shoot)" + tail
        case .live:
            guard let p = frame.primary else { return "☀︎ —" + tail }
            if let n = p.next { return "\(frame.words[.next]) \(frame.clock(n.date, in: p.zone)) \(n.name)" + tail }
            return "\(p.shoot.title)" + tail
        }
    }
}

/// Круглый виджет экрана блокировки (30б.2в, `accessoryCircular`, ~76 pt): отсчёт до золотого часа — «4:10» с двоеточием по
/// середине цифр, вокруг дуга пройденного пути от рассвета до золотого часа. Без имён: экран виден на заблокированном телефоне.
/// Цвет — `Color.primary`: на экране блокировки система красит содержимое сама (приглушённо), свои цвета ей не нужны.
struct LockCircularView: View {
    let frame: WidgetFrame
    var alpha = false

    /// До золотого часа и доля пути от рассвета (или от полуночи, если рассвета нет).
    var goldenLeft: (left: TimeInterval, progress: Double)? {
        guard let d = frame.day, let g = d.golden, g > frame.now else { return nil }
        let from = d.sunrise ?? g.addingTimeInterval(-12 * 3600)
        let total = g.timeIntervalSince(from)
        return (g.timeIntervalSince(frame.now), total > 0 ? min(1, max(0, frame.now.timeIntervalSince(from) / total)) : 0)
    }

    /// Единственный текст круга: остаток до золотого часа («4:10»); без него круг пуст. Ничего про клиента здесь нет и быть не может.
    var label: String? { goldenLeft.map { ColonCount.text($0.left) } }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.22), lineWidth: 4)
            if let g = goldenLeft, let label {
                Circle().trim(from: 0, to: g.progress).stroke(Color.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    WidgetIcon(name: "sun", size: 13).foregroundStyle(Color.primary)
                    ColonCount(text: label, size: 21).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.6)
                }
            } else {
                WidgetIcon(name: "sun", size: 22).foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .padding(5)
        .dynamicTypeSize(...DynamicTypeSize.large)   // экран блокировки тесный: больше «обычного» не влезает
        .overlay(alignment: .topTrailing) { if alpha { Text("α").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.primary) } }
    }
}

/// Прямоугольный виджет экрана блокировки (30б.2в, `accessoryRectangular`, ~172 × 76 pt) — как у Календаря: полоса цвета,
/// «12:00–13:54 / Свадьба / место». Без имён клиентов (Алексей, 25.10: имена только на «Домой»).
struct LockRectangularView: View {
    let frame: WidgetFrame
    var alpha = false

    /// Все строки вида, как они рисуются: время точки, жанр, место. Из данных кадра берутся только эти три поля — имя клиента
    /// сюда не приходит ни параметром, ни из ленты (она его не несёт); тест сверяет текст целиком (`WidgetSketchTests`).
    var lines: [String] {
        guard let plan = DayPlan(frame) else {
            // Съёмок рядом нет: ближайший рассвет или закат тем же рисунком («17:52 / Закат / Томск»).
            guard let e = frame.light, let at = e.at else { return [frame.light.map { $0.kind == .polarNight ? frame.words[.polarNight] : frame.words[.polarDay] } ?? "—"] }
            let name = e.kind == .sunrise ? frame.words[.sunrise] : frame.words[.sunset]
            return [frame.clock(at, in: frame.zone), name] + (frame.place.name.isEmpty ? [] : [frame.place.name])
        }
        let range = plan.current.flatMap { c in plan.pointEnd.map { plan.range(c.date, $0) } } ?? plan.shootRange
        let place = plan.current?.place.isEmpty == false ? plan.current!.place : plan.shoot.place
        return [range, plan.shoot.title] + (place.isEmpty ? [] : [place])
    }

    var body: some View {
        let lines = lines
        HStack(alignment: .center, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color.primary).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                if lines.count > 1 {
                    Text(lines[0]).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Color.primary.opacity(0.75)).lineLimit(1)
                    Text(lines[1]).font(.headline).foregroundStyle(Color.primary).lineLimit(1)
                    if lines.count > 2 { Text(lines[2]).font(.caption).foregroundStyle(Color.primary.opacity(0.75)).lineLimit(1) }
                } else {
                    Text(lines[0]).font(.headline).foregroundStyle(Color.primary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}
