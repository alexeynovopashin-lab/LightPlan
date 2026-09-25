import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Сетка выбора даты `#fwSDate` / `#fwEDate` веба: месяц с понедельника, заголовок
/// «Месяц ГГГГ» и стрелки; дни вне предела не убираются, а гаснут.
struct FormDateGrid: View {
    let selected: CivilDate
    /// Границы выбора (у конца — начало и начало плюс неделя).
    var range: ClosedRange<Int>?
    let dates: DateText
    let date: (CivilDate) -> Date
    let weekdays: [String]
    let onPick: (CivilDate) -> Void
    @State private var month: CivilDate
    @Environment(\.colorScheme) private var scheme

    init(selected: CivilDate, range: ClosedRange<Int>? = nil, dates: DateText, date: @escaping (CivilDate) -> Date,
         onPick: @escaping (CivilDate) -> Void) {
        self.selected = selected
        self.range = range
        self.dates = dates
        self.date = date
        self.weekdays = dates.weekdayRow()
        self.onPick = onPick
        _month = State(initialValue: PlannerState.first(of: selected))
    }

    var body: some View {
        let pal = Palette(scheme)
        let first = month
        let start = PlannerState.weekStart(first)
        let last = PlannerState.addMonths(first, 1).adding(days: -1)
        let end = PlannerState.weekStart(last).adding(days: 6)
        let days = (0...end.days(since: start)).map { start.adding(days: $0) }
        VStack(spacing: 6) {
            HStack {
                arrow("chevron", flip: true, pal) { month = PlannerState.addMonths(month, -1) }
                Spacer()
                Text(dates.monthTitle(date(first)) + " " + String(first.year))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.ink)
                Spacer()
                arrow("chevron", flip: false, pal) { month = PlannerState.addMonths(month, 1) }
            }
            HStack(spacing: 0) {
                ForEach(weekdays.indices, id: \.self) { i in
                    Text(weekdays[i]).font(.system(size: 10, weight: .semibold)).foregroundStyle(pal.ink6)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(days, id: \.self) { d in
                    let inMonth = PlannerState.sameMonth(d, first)
                    let ok = range.map { $0.contains(d.ordinal) } ?? true
                    let on = d == selected
                    Button { onPick(d) } label: {
                        Text(String(d.day)).font(.system(size: 16).monospacedDigit())
                            .foregroundStyle(on ? pal.onBrass : (inMonth ? pal.ink : pal.ink7))
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .background(on ? pal.brass : .clear, in: Circle())
                            .opacity(ok ? 1 : 0.3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!ok)
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 12)
    }

    private func arrow(_ name: String, flip: Bool, _ pal: Palette, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Icon(name, size: 18, line: 2).rotationEffect(.degrees(flip ? 180 : 0))
                .foregroundStyle(pal.ink4).frame(width: 40, height: 34)
        }
        .buttonStyle(.plain)
    }
}

/// Колесо часа и минуты — **системное** (DECISIONS «Барабаны формы — системное
/// колесо»): шаг минут — свойство колеса (`minuteInterval`). Формат 12 или 24
/// часа берётся из настройки приложения, а не из локали телефона: локаль
/// задаётся явно (`@hours=h12` / `h23`). Значение — минуты от полуночи; колесо
/// живёт в UTC, чтобы часовой пояс телефона не сдвигал числа.
#if canImport(UIKit)
struct FormTimeWheel: UIViewRepresentable {
    let minute: Int
    let step: Int
    let twelveHour: Bool
    let language: String
    let onChange: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIDatePicker {
        let p = UIDatePicker()
        p.datePickerMode = .time
        p.preferredDatePickerStyle = .wheels
        p.timeZone = TimeZone(identifier: "UTC")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        p.calendar = cal
        p.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return p
    }

    func updateUIView(_ p: UIDatePicker, context: Context) {
        context.coordinator.onChange = onChange
        p.minuteInterval = step
        p.locale = Locale(identifier: Lexicon.base(language) + (twelveHour ? "_US@hours=h12" : "_RU@hours=h23"))
        let want = Date(timeIntervalSinceReferenceDate: Double(minute * 60))
        if abs(p.date.timeIntervalSince(want)) > 30 { p.setDate(want, animated: false) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 140)
    }

    final class Coordinator: NSObject {
        var onChange: (Int) -> Void = { _ in }
        @objc func changed(_ p: UIDatePicker) {
            onChange(Int(p.date.timeIntervalSinceReferenceDate / 60) % 1440)
        }
    }
}
#else
/// На Mac (только для сборки пакета на хосте) — обычный выбор времени.
struct FormTimeWheel: View {
    let minute: Int
    let step: Int
    let twelveHour: Bool
    let language: String
    let onChange: (Int) -> Void
    var body: some View {
        DatePicker("", selection: Binding(get: { Date(timeIntervalSinceReferenceDate: Double(minute * 60)) },
                                          set: { onChange(Int($0.timeIntervalSinceReferenceDate / 60) % 1440) }),
                   displayedComponents: .hourAndMinute).labelsHidden()
    }
}
#endif
