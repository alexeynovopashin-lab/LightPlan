import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Лист «день рождения» / «годовщина» карточки клиента (шаг К6): три барабана — число, месяц, год. У дня рождения год
/// необязателен (первая строка барабана «Без года»), как в Контактах iPhone. Барабан не обрезается: числа, которых нет в
/// выбранном месяце, приглушены, и колесо само доезжает до последнего настоящего (31 → 30, 29 февраля без года остаётся).
struct ClientDateSheet: View {
    struct Words { let title: String; let noYear: String; let ok: String; let cancel: String; let clear: String }
    enum Answer { case set(year: Int?, month: Int, day: Int), clear, cancel }

    let words: Words
    let yearOptional: Bool
    /// Есть ли что убирать: у пустого поля «Убрать» не показывается.
    let canClear: Bool
    let thisYear: Int
    let initial: (year: Int?, month: Int, day: Int)
    let monthName: (Int) -> String
    let answer: (Answer) -> Void

    @State private var day = 1
    @State private var month = 1
    /// 0 — без года.
    @State private var year = 0
    @Environment(\.colorScheme) private var scheme

    private var years: [Int] {
        let top = yearOptional ? thisYear : thisYear + 1
        return (yearOptional ? [0] : []) + Array(stride(from: top, through: thisYear - 100, by: -1))
    }

    /// Последнее настоящее число месяца; без года февраль — 29.
    private var lastDay: Int { Greetings.observed(month: month, day: 31, in: year == 0 ? 2000 : year).day }

    var body: some View {
        let pal = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(pal.edge).frame(width: 38, height: 4).frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 18)
            Text(words.title).font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
            HStack(spacing: 0) {
                Picker("", selection: $day) {
                    ForEach(1...31, id: \.self) { d in
                        Text("\(d)").foregroundStyle(d > lastDay ? pal.ink7 : pal.ink).tag(d)
                    }
                }
                #if os(iOS)
                .pickerStyle(.wheel)
                #endif
                .frame(width: 64).clipped()
                .shotNode("clc.dateDay", text: "\(day)")
                Picker("", selection: $month) {
                    ForEach(1...12, id: \.self) { m in Text(monthName(m)).tag(m) }
                }
                #if os(iOS)
                .pickerStyle(.wheel)
                #endif
                .frame(maxWidth: .infinity).clipped()
                .shotNode("clc.dateMonth", text: "\(month)")
                Picker("", selection: $year) {
                    ForEach(years, id: \.self) { y in Text(y == 0 ? words.noYear : String(y)).tag(y) }
                }
                #if os(iOS)
                .pickerStyle(.wheel)
                #endif
                .frame(width: 118).clipped()
                .shotNode("clc.dateYear", text: "\(year)")
            }
            .frame(height: 180)
            .padding(.top, 8)
            .onChange(of: month) { settle() }
            .onChange(of: year) { settle() }
            .onChange(of: day) { settle() }
            Button { answer(.set(year: year == 0 ? nil : year, month: month, day: min(day, lastDay))) } label: {
                Text(words.ok).font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.onBrass)
                    .frame(maxWidth: .infinity).padding(16)
                    .background(pal.brass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .shotNode("clc.dateOk")
            HStack(spacing: 0) {
                if canClear {
                    Button { answer(.clear) } label: {
                        Text(words.clear).font(.system(size: 15)).foregroundStyle(Color(hex: pal.dark ? 0xB9603D : 0x9E4722))
                            .frame(maxWidth: .infinity).padding(.vertical, 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .shotNode("clc.dateClear")
                }
                Button { answer(.cancel) } label: {
                    Text(words.cancel).font(.system(size: 15)).foregroundStyle(pal.ink3)
                        .frame(maxWidth: .infinity).padding(.vertical, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
        .background(pal.surface.ignoresSafeArea())
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.hidden)
        .shotNode("clc.dateSheet", text: words.title)
        .onAppear {
            day = initial.day
            month = initial.month
            year = initial.year.flatMap { y in years.contains(y) ? y : nil } ?? (yearOptional ? 0 : thisYear)
        }
    }

    /// Числа, которого нет в месяце, колесо не держит: доезжает до последнего настоящего.
    private func settle() {
        if day > lastDay { withAnimation { day = lastDay } }
    }
}
