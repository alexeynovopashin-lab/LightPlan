import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Лист «Занять время» (веб `#blkSheet`, итерация 22): выходной, дорога,
/// перелёт, «занято». Своя форма, а не съёмка без полей: у отпуска нет ни
/// клиента, ни жанра, ни сдачи. Правка живёт в листе и пишется по «Готово»;
/// «Убрать из календаря» — с полосой «Вернуть» (у веба — навсегда, DECISIONS
/// итерации 22). Колёса — системные, как в форме (ответ Алексея, 26.09).
struct BlockSheet: View {
    @Bindable var app: AppModel
    @State private var b: Block
    let editing: Bool
    let windowHeight: CGFloat
    @State private var open: Row?
    @State private var contentHeight: CGFloat = 600
    @Environment(\.colorScheme) private var scheme

    enum Row { case fromDate, fromTime, toDate, toTime }

    init(app: AppModel, draft: BlockDraft, windowHeight: CGFloat) {
        self.app = app
        _b = State(initialValue: draft.block)
        editing = draft.editing
        self.windowHeight = windowHeight
    }

    /// Предел длительности по часам (веб: колёса дают 15 … 2880 минут).
    static let minDur = 15, maxDur = 2880
    /// «По» у занятости на весь день — не дальше двух месяцев (веб `from + 60`).
    static let maxSpan = 60

    var body: some View {
        let pal = Palette(scheme)
        let f = PlannerFacts(app: app, dark: scheme != .light)
        let t = f.t
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(pal.edge).frame(width: 38, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 18)
                Text(t.t(editing ? "blk.titleEdit" : "blk.title"))
                    .font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
                    .shotNode("blk.title")
                Text(t.t("blk.sub")).font(.system(size: 13)).foregroundStyle(pal.ink4)
                    .padding(.top, 5)
                kinds(t, pal)
                FormGroup(node: "blk.group") {
                    allDayRow(t, pal)
                    fromRow(f, pal)
                    if open == .fromDate {
                        FormDateGrid(selected: b.from, dates: f.dates, date: f.date) { d in b.from = d; open = nil }
                    }
                    if open == .fromTime {
                        wheel(b.start ?? 600) { m in b.start = m }
                    }
                    toRow(f, pal)
                    if open == .toDate {
                        FormDateGrid(selected: b.lastDay, range: b.from.ordinal...(b.from.ordinal + Self.maxSpan),
                                     dates: f.dates, date: f.date) { d in
                            b.days = max(1, d.days(since: b.from) + 1); open = nil
                        }
                    }
                    if open == .toTime {
                        wheel(((b.start ?? 600) + (b.duration ?? 120) - shift) % 1440) { m in setEnd(m) }
                    }
                    FormTextField(placeholder: t.t("blk.notePh"), text: $b.note).shotNode("blk.note")
                }
                .padding(.top, 14)
                Button(action: done) {
                    Text(t.t("pick.done")).font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.onBrass)
                        .frame(maxWidth: .infinity).padding(16)
                        .background(pal.brass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .shotNode("blk.done")
                .padding(.top, 20)
                if editing {
                    Button {
                        app.blockSheet = nil
                        app.removeBlock(id: b.id)
                    } label: {
                        HStack(spacing: 8) {
                            Icon("close", size: 18, line: 1.6)
                            Text(t.t("blk.remove")).font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(pal.ink3)
                        .frame(maxWidth: .infinity).padding(.vertical, 13).padding(.horizontal, 15)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .shotNode("blk.del")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .shotNode("blk.sheet")
        .presentationDetents([.height(min(contentHeight, windowHeight * 0.86))])
        .presentationDragIndicator(.hidden)
        .animation(.snappy(duration: 0.25), value: open)
    }

    // MARK: - Вид занятости

    /// Четыре `.tool` в `.chips` (перенос строк, зазор 8): по ширине подписи,
    /// знак 22 и подпись 10 через 6; выбранный — латунь на `--press-warm`.
    private func kinds(_ t: Lexicon, _ pal: Palette) -> some View {
        HStack(spacing: 8) {
            ForEach(BlockKind.allCases, id: \.self) { k in
                let on = b.kind == k
                Button { b.kind = k } label: {
                    VStack(spacing: 6) {
                        Icon(k.iconName, size: 22, line: 1.5)
                        Text(t.t("blkKind." + k.rawValue)).font(.system(size: 10)).tracking(0.2).lineLimit(1)
                    }
                    .foregroundStyle(on ? pal.brass : pal.ink5)
                    .padding(.top, 11).padding(.bottom, 9).padding(.horizontal, 2)
                    .background(on ? pal.pressWarm : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .shotNode("blk.kind.\(k.rawValue)")
            }
        }
    }

    // MARK: - Строки

    private func allDayRow(_ t: Lexicon, _ pal: Palette) -> some View {
        HStack {
            Text(t.t("blk.allDay")).font(.system(size: 16)).foregroundStyle(pal.ink)
            Spacer()
            Toggle("", isOn: Binding(get: { b.allDay }, set: { v in
                b.allDay = v
                if !v { b.start = b.start ?? 600; b.duration = b.duration ?? 120 }
                open = nil
            }))
            .labelsHidden().tint(pal.brass)
        }
        // `.row` веба: поля 14 × 15 (пара 22: строка 59 при переключателе 31).
        // Переключатель веба 31 в высоту, системный — 28: строка держит 59, как у веба.
        .padding(.vertical, 14).padding(.horizontal, 15).frame(minHeight: 59)
        .shotNode("blk.allDay")
    }

    private func fromRow(_ f: PlannerFacts, _ pal: Palette) -> some View {
        row(label: f.t.t("blk.from"), tz: shiftOn ? Self.tzText(b.zoneFrom) : nil, pal) {
            FormCapsule(node: "blk.fromDate", text: f.dates.dMonShortYear(f.date(b.from)), open: open == .fromDate) { toggle(.fromDate) }
            if !b.allDay {
                FormCapsule(node: "blk.fromTime", text: f.fmt(Double(b.start ?? 600)), open: open == .fromTime) { toggle(.fromTime) }
            }
        } sub: { EmptyView() }
        .shotNode("blk.from")
    }

    private func toRow(_ f: PlannerFacts, _ pal: Palette) -> some View {
        row(label: f.t.t(shiftOn ? "blk.arrive" : "blk.to"), tz: shiftOn ? Self.tzText(b.zoneTo) : nil, pal) {
            if b.allDay {
                FormCapsule(node: "blk.toDate", text: f.dates.dMonShortYear(f.date(b.lastDay)), open: open == .toDate) { toggle(.toDate) }
            } else {
                FormCapsule(node: "blk.toTime", text: f.fmt(Double(end - shift)), open: open == .toTime) { toggle(.toTime) }
            }
        } sub: {
            // `.row .sub` веба: 11, `--ink-6`, через 2 под капсулой.
            Text(span(f)).font(.system(size: 11)).foregroundStyle(pal.ink6).monospacedDigit()
                .shotNode("blk.span")
        }
        .shotNode("blk.to")
    }

    /// Строка группы: подпись (и метка пояса) слева, капсулы справа, под
    /// ними — мелкая строка длины.
    private func row<C: View, S: View>(label: String, tz: String?, _ pal: Palette,
                                       @ViewBuilder caps: () -> C, @ViewBuilder sub: () -> S) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 16)).foregroundStyle(pal.ink)
                if let tz { Text(tz).font(.system(size: 11)).foregroundStyle(pal.ink4) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) { caps() }
                sub()
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 15).frame(minHeight: 52)
    }

    private func wheel(_ minute: Int, _ set: @escaping (Int) -> Void) -> some View {
        let clock = ClockText(language: app.language, preference: app.light.clockPreference)
        return FormTimeWheel(minute: minute, step: app.settings.timeStep, twelveHour: clock.is12,
                             language: app.language, onChange: set)
            .padding(.horizontal, 10)
    }

    private func toggle(_ r: Row) { open = open == r ? nil : r }

    // MARK: - Счёт

    /// Конец по часам вылета (веб `blkEnd`).
    private var end: Int { (b.start ?? 600) + (b.duration ?? 120) }

    /// На сколько минут пояс прилёта отстаёт от пояса вылета (веб `blkShift`).
    private var shift: Int {
        guard let a = b.zoneFrom, let z = b.zoneTo else { return 0 }
        return Int(((a - z) * 60).rounded())
    }

    private var shiftOn: Bool { !b.allDay && shift != 0 }

    /// «По» по часам (веб: `d = hh·60 + mm − min + shift`, не короче 15 минут,
    /// раньше начала — значит, назавтра; не дольше двух суток).
    private func setEnd(_ m: Int) {
        var d = m - (b.start ?? 600) + shift
        while d < Self.minDur { d += 1440 }
        b.duration = min(d, Self.maxDur)
    }

    /// Строка длины (веб `#blkSpan`).
    private func span(_ f: PlannerFacts) -> String {
        if b.allDay {
            return b.dayCount > 1 ? f.t.count("unit.day", b.dayCount) : f.t.t("blk.oneDay")
        }
        return f.durLabel(b.duration ?? 120) + (end / 1440 > 0 ? " · " + f.t.t("blk.nextDay") : "")
    }

    /// Метка пояса (веб `tzText`): «UTC+7», «UTC+5:30».
    static func tzText(_ off: Double?) -> String? {
        guard let off else { return nil }
        let a = abs(off), h = Int(a.rounded(.down)), m = Int(((a - Double(h)) * 60).rounded())
        return "UTC" + (off < 0 ? "-" : "+") + "\(h)" + (m > 0 ? String(format: ":%02d", m) : "")
    }

    /// «Готово» (веб `#blkDone`): у занятости на весь день часы стираются.
    private func done() {
        var out = b
        out.note = b.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.allDay {
            out.days = max(1, b.days)
            out.start = nil; out.duration = nil; out.zoneFrom = nil; out.zoneTo = nil
        } else {
            out.days = 1
        }
        app.saveBlock(out)
        app.blockSheet = nil
    }
}
