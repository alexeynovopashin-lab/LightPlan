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
/// колесо»), но не `UIDatePicker`: тот умеет только минуты по шагу, и время от
/// света (18:37 при шаге 5) показывал как 18:35. Здесь два столбца
/// `UIPickerView`, как барабаны веба: минуты — шаг плюс текущая минута, если
/// она не по шагу (веб `fillMins`, `minsList`); час — всегда 0–23, у двенадцати
/// часов подпись «7 PM» без отдельного столбца AM/PM (веб `hourLabel`). Список
/// минут строится при открытии и держится, пока колесо открыто: иначе ряды
/// сдвигались бы под пальцем. Оба столбца закольцованы, как у веба и системы.
extension FormTimeWheel {
    /// Минуты столбца: шаг и минута не по шагу, по возрастанию.
    static func minutes(step: Int, current: Int?) -> [Int] {
        var out = Array(stride(from: 0, to: 60, by: max(1, step)))
        if let c = current, !out.contains(c) { out.append(c); out.sort() }
        return out
    }

    /// Подпись часа: «07» по 24 часам, «7 AM» по двенадцати.
    static func hourLabel(_ h: Int, twelveHour: Bool, language: String) -> String {
        guard twelveHour else { return (h < 10 ? "0" : "") + String(h) }
        let s = ClockText(language: language, preference: .h12).fmt(Double(h * 60))
        return s.replacingOccurrences(of: #"^(\d+):00"#, with: "$1", options: .regularExpression)
    }
}

#if canImport(UIKit)
struct FormTimeWheel: UIViewRepresentable {
    let minute: Int
    let step: Int
    let twelveHour: Bool
    let language: String
    let onChange: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIPickerView {
        let p = UIPickerView()
        p.dataSource = context.coordinator
        p.delegate = context.coordinator
        p.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return p
    }

    func updateUIView(_ p: UIPickerView, context: Context) {
        let c = context.coordinator
        c.onChange = onChange
        let m = ((minute % 1440) + 1440) % 1440
        let hours = (0..<24).map { Self.hourLabel($0, twelveHour: twelveHour, language: language) }
        if hours != c.hours { c.hours = hours; p.reloadComponent(0) }
        if c.step != step || !c.mins.contains(m % 60) {
            c.step = step
            c.mins = Self.minutes(step: step, current: m % 60)
            p.reloadComponent(1)
        }
        c.show(m, in: p)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPickerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 140)
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var onChange: (Int) -> Void = { _ in }
        var hours: [String] = []
        var mins: [Int] = []
        var step = 0
        /// Копий списка в столбце: колесо листается «без конца» и после остановки
        /// возвращается в среднюю копию.
        static let loops = 101

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent c: Int) -> Int {
            (c == 0 ? hours.count : mins.count) * Self.loops
        }
        func pickerView(_ pickerView: UIPickerView, widthForComponent c: Int) -> CGFloat {
            c == 0 && hours.first.map { $0.count > 2 } == true ? 96 : 64
        }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent c: Int) -> CGFloat { 34 }
        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent c: Int) -> String? {
            c == 0 ? hours[row % hours.count] : (mins[row % mins.count] < 10 ? "0" : "") + String(mins[row % mins.count])
        }

        func pickerView(_ p: UIPickerView, didSelectRow row: Int, inComponent c: Int) {
            let h = p.selectedRow(inComponent: 0) % hours.count
            let mm = mins[p.selectedRow(inComponent: 1) % mins.count]
            let m = h * 60 + mm
            center(p)
            onChange(m)
        }

        /// Ставит колесо на минуту, если оно стоит не на ней.
        func show(_ m: Int, in p: UIPickerView) {
            guard !hours.isEmpty, !mins.isEmpty, let mi = mins.firstIndex(of: m % 60) else { return }
            let h = m / 60
            let mid = Self.loops / 2
            if p.selectedRow(inComponent: 0) % hours.count != h { p.selectRow(mid * hours.count + h, inComponent: 0, animated: false) }
            if p.selectedRow(inComponent: 1) % mins.count != mi { p.selectRow(mid * mins.count + mi, inComponent: 1, animated: false) }
        }

        private func center(_ p: UIPickerView) {
            let mid = Self.loops / 2
            for (c, n) in [(0, hours.count), (1, mins.count)] where n > 0 {
                let r = p.selectedRow(inComponent: c)
                if r / n != mid { p.selectRow(mid * n + r % n, inComponent: c, animated: false) }
            }
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
