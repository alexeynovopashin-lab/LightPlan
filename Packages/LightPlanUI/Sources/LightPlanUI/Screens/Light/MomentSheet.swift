import SwiftUI
import LightPlanCore

/// Лист «Когда смотрим» — порт `#sheet` веба (итерация 19в): тап по
/// показаниям купола открывает три барабана — дата, час, минута, — фишки
/// «Сегодня / Через неделю / Через месяц» и «Готово». Выбранное доезжает до
/// купола и таймбара (`LightScreenModel.pick`).
///
/// Вид — прототипа, не системный `DatePicker`: барабаны веба свои (строка
/// 34, перспектива, полоса выбора), лист — плотный `--sheet`, не стекло
/// (у веба на нём нет `backdrop-filter`, в таблице имитаций плана его нет).
struct MomentSheetHost: View {
    @Bindable var model: LightScreenModel

    /// `.scrim` 0,3 с по прозрачности, `.sheet` 0,38 с `cubic-bezier(0.25, 1,
    /// 0.4, 1)` снизу.
    var body: some View {
        ZStack(alignment: .bottom) {
            if model.pickerOpen {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { model.pickerOpen = false }
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                // Низ — 34 от края экрана, как у веба на телефоне: его
                // правило «34 + полоса „домой“» перебито поздним `.sheet`
                // (DECISIONS, 19в).
                MomentSheet(model: model)
                    .transition(.move(edge: .bottom).animation(.timingCurve(0.25, 1, 0.4, 1, duration: 0.38)))
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(.timingCurve(0.25, 1, 0.4, 1, duration: 0.38), value: model.pickerOpen)
    }
}

private struct MomentSheet: View {
    let model: LightScreenModel
    @Environment(\.colorScheme) private var colorScheme

    private let days: [(day: CivilDate, label: String)]
    @State private var dateIndex: Int
    @State private var hour: Int
    @State private var minute: Int
    /// Нажатая фишка (`.chip.active`); открытие листа — без выбранной.
    @State private var chip: Int?

    private static let chipDays = [(0, "pick.today"), (7, "pick.week"), (30, "pick.month")]

    init(model: LightScreenModel) {
        self.model = model
        let days = model.pickerDays()
        self.days = days
        let start = model.pickerStart
        // Дня нет в списке (ушли дальше месяца назад) — барабан встаёт на
        // первый, как `di = 0` веба.
        _dateIndex = State(initialValue: days.firstIndex { $0.day == start.day } ?? 0)
        _hour = State(initialValue: start.minute / 60)
        _minute = State(initialValue: start.minute % 60)
    }

    /// `.sheet`: поля 10 · 24 · 34, скругление 24 сверху,
    /// `--sheet`; ручка 38×4 и 18 под ней; заголовок 19/650, подпись 13
    /// `--ink-4` через 5; барабаны 170 через 14; фишки через 12; «Готово»
    /// через 20.
    var body: some View {
        let pal = Palette(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 3).fill(pal.edge)
                .frame(width: 38, height: 4)
                .shotNode("pick.grip")
                .frame(maxWidth: .infinity)
                .padding(.bottom, 18)
            Text(model.lexiconWord("pick.title"))
                .font(webFont(19, 650)).tracking(-0.2)
                .foregroundStyle(pal.ink)
                .shotNode("pick.title", text: model.lexiconWord("pick.title"))
            Text(model.lexiconWord("pick.sub"))
                .font(webFont(13))
                .foregroundStyle(pal.ink4)
                .shotNode("pick.sub", text: model.lexiconWord("pick.sub"))
                .padding(.top, 5)
            wheels(pal)
                .padding(.top, 14)
            chips(pal)
                .padding(.top, 12)
            Button(action: done) {
                Text(model.lexiconWord("pick.done"))
                    .font(webFont(16, 650))
                    .foregroundStyle(pal.onBrass)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(pal.brass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shotNode("pick.done", text: model.lexiconWord("pick.done"))
            .padding(.top, 20)
        }
        .padding(.top, 10)
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .fill(pal.sheet)
        }
        .shotNode("pick.sheet")
    }

    /// `.picker`: высота 170, барабаны 1,7 : 0,6 : 0,6, полоса выбора 34 на
    /// 68 от верха, `rgba(120,120,128,0.16)`, скругление 9.
    private func wheels(_ pal: Palette) -> some View {
        GeometryReader { geo in
            let unit = geo.size.width / 2.9
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.16))
                    .frame(height: WheelColumn.row)
                    .shotNode("pick.band")
                    .padding(.top, WheelColumn.pad)
                HStack(spacing: 0) {
                    WheelColumn(labels: days.map(\.label), loops: false, index: $dateIndex,
                                alignment: .trailing, inset: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
                        .frame(width: unit * 1.7)
                        .shotNode("pick.date", text: days[dateIndex].label)
                    WheelColumn(labels: (0..<24).map(model.pickerHourLabel), loops: true, index: $hour,
                                alignment: .trailing, inset: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 5))
                        .frame(width: unit * 0.6)
                        .shotNode("pick.hour", text: model.pickerHourLabel(hour))
                    WheelColumn(labels: (0..<60).map { String(format: "%02d", $0) }, loops: true, index: $minute,
                                alignment: .leading, inset: EdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 0))
                        .frame(width: unit * 0.6)
                        .shotNode("pick.min", text: String(format: "%02d", minute))
                }
            }
        }
        .frame(height: WheelColumn.height)
    }

    /// `.chips`: зазор 8; фишка 13 pt, поля 10 · 15, скругление 20, `--press`
    /// и `--ink-3`; нажатая — `--press-brass`, латунь, 600.
    private func chips(_ pal: Palette) -> some View {
        HStack(spacing: 8) {
            ForEach(Self.chipDays.indices, id: \.self) { i in
                let on = chip == i
                Button {
                    chip = i
                    withAnimation(.easeOut(duration: 0.3)) {
                        dateIndex = LightScreenModel.pickBack + Self.chipDays[i].0
                    }
                } label: {
                    Text(model.lexiconWord(Self.chipDays[i].1))
                        .font(webFont(13, on ? 600 : 400))
                        .foregroundStyle(on ? pal.brass : pal.ink3)
                        .padding(.vertical, 10).padding(.horizontal, 15)
                        .background(on ? pal.pressBrass : pal.press, in: Capsule())
                }
                .buttonStyle(.plain)
                .shotNode("pick.chip.\(i)", text: model.lexiconWord(Self.chipDays[i].1))
            }
        }
    }

    private func done() {
        model.pick(day: days[dateIndex].day, minute: Double(hour * 60 + minute))
        model.pickerOpen = false
    }
}

/// Барабан листа — порт `.wheel` веба: строка 34, поле 68 сверху и снизу,
/// строки поворачиваются по удалению от середины (`rotateX(d·20°)` до ±72°,
/// перспектива 700) и гаснут (`1 − |d|·0,3`), края прячет маска 0–24 % и
/// 76–100 %. Короткие барабаны (час, минута) закольцованы: список повторён,
/// барабан стоит в средней копии и после остановки незаметно возвращается в
/// неё. Даты не кольцуются — за декабрём идёт январь другого года.
struct WheelColumn: View {
    static let row: CGFloat = 34
    static let pad: CGFloat = 68
    static let height: CGFloat = 170

    let labels: [String]
    let loops: Bool
    @Binding var index: Int
    var alignment: Alignment
    var inset: EdgeInsets

    @Environment(\.colorScheme) private var colorScheme
    /// Прокрутка — как `scrollTop` веба: строка `r` под полосой при смещении
    /// `r · 34` (поле 68 сверху ставит её в середину окна 170).
    @State private var scroll: ScrollPosition
    @State private var offset: CGFloat
    private let reps: Int

    init(labels: [String], loops: Bool, index: Binding<Int>, alignment: Alignment, inset: EdgeInsets) {
        self.labels = labels
        self.loops = loops
        self._index = index
        self.alignment = alignment
        self.inset = inset
        let n = labels.count
        // `fill` веба: сутки и час — три копии, короче — столько, чтобы в
        // окне не кончалось.
        let reps = loops && n > 0 && n <= 60 ? (n >= 24 ? 3 : 2 * Int((9.0 / Double(n)).rounded(.up)) + 1) : 1
        self.reps = reps
        let y = CGFloat(Self.middle(reps: reps, n: n) + index.wrappedValue) * Self.row
        _scroll = State(initialValue: ScrollPosition(y: y))
        _offset = State(initialValue: y)
    }

    private static func middle(reps: Int, n: Int) -> Int { (reps / 2) * n }
    private var rawRow: Int { Int((offset / Self.row).rounded()) }

    var body: some View {
        let ink = Palette(colorScheme).ink
        let n = labels.count
        ScrollView(.vertical) {
            // Не ленивый: начальная прокрутка `r · 34` должна попасть в строку,
            // а ленивый список до раскладки знает высоту лишь приблизительно
            // (замер 19в: встал на 14 сентября вместо сегодня). Строк ~650.
            VStack(spacing: 0) {
                Color.clear.frame(height: Self.pad)
                ForEach(0..<(n * reps), id: \.self) { r in
                    Text(labels[r % n])
                        .font(webFont(20)).tracking(-0.2).monospacedDigit()
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .padding(inset)
                        .frame(maxWidth: .infinity, alignment: alignment)
                        .frame(height: Self.row)
                        .visualEffect { content, proxy in
                            // `styleWheel` веба: d — удаление строки от
                            // середины окна в строках.
                            let d = (proxy.frame(in: .scrollView(axis: .vertical)).midY - Self.height / 2) / Self.row
                            return content
                                .rotation3DEffect(.degrees(Double(min(72, max(-72, d * 20)))), axis: (1, 0, 0),
                                                  perspective: max(proxy.size.width, proxy.size.height) / 700)
                                .opacity(Double(max(0, 1 - abs(d) * 0.3)))
                        }
                }
                Color.clear.frame(height: Self.pad)
            }
        }
        .scrollPosition($scroll)
        .scrollTargetBehavior(RowSnap())
        .scrollIndicators(.hidden)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.24),
                                   .init(color: .black, location: 0.76), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            offset = y
            guard n > 0 else { return }
            let v = ((rawRow % n) + n) % n
            if v != index { index = v }
        }
        .onChange(of: index) { _, v in
            // Снаружи (фишка) — барабан доезжает до значения сам.
            guard n > 0, ((rawRow % n) + n) % n != v else { return }
            let raw = rawRow
            withAnimation(.easeOut(duration: 0.3)) { scroll.scrollTo(y: CGFloat(raw - raw % n + v) * Self.row) }
        }
        .onScrollPhaseChange { _, phase in
            // Возврат в среднюю копию — после остановки, не по ходу: строка
            // под пальцем та же, подмены не видно.
            guard phase == .idle, reps > 1, n > 0 else { return }
            let raw = rawRow, want = Self.middle(reps: reps, n: n) + ((raw % n) + n) % n
            if want != raw { scroll.scrollTo(y: CGFloat(want) * Self.row) }
        }
    }

    /// `scroll-snap-type: y mandatory` с `scroll-snap-align: center`: барабан
    /// встаёт так, что строка ровно под полосой.
    private struct RowSnap: ScrollTargetBehavior {
        func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
            target.rect.origin.y = (target.rect.origin.y / WheelColumn.row).rounded() * WheelColumn.row
        }
    }
}
