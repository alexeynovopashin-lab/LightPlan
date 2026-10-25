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
