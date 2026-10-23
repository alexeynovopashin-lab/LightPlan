import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Стопка карточек дня (веб `dayStack` + `renderStack`, шаг 4 итерации 25)

/// Чья стопка над листом (шаг К5): соседи по дню или все долги.
public enum CardStackMode: Sendable {
    /// Записи того же дня (веб `dayStack`).
    case day
    /// Все несданные съёмки (`Debts`): так открывает календарь нажатие на несданную.
    case debts
}

extension AppModel {
    /// Долг ли запись сейчас (`Debts.isDebt`): часы места съёмки и «Завершать вручную» — те же, что у фазы карточки.
    func isDebt(_ s: Session) -> Bool {
        Debts.isDebt(s, now: wallNow(at: s), manualEnd: settings.manualEnd)
    }

    /// Все долги, старый первым (`Debts.stack`).
    func debts() -> [Session] {
        Debts.stack(snapshot.sessions, now: { self.wallNow(at: $0) }, manualEnd: settings.manualEnd)
    }

    /// Вход из календаря (месяц, неделя, лента дня): нажали несданную съёмку — над её карточкой все долги;
    /// сданную, будущую, встречу — обычная стопка дня. Отдельной кнопки «Долги» нет (Алексей, 21.10).
    public func openCardFromCalendar(id: String) {
        guard let s = snapshot.sessions.first(where: { $0.id == id }) else { return }
        openCard(id: id, stack: isDebt(s) ? .debts : .day)
    }

    /// Соседи карточки в стопке. В стопке долгов — все долги, кроме самой карточки, старый ближе к листу; режим
    /// держится, пока карточка открыта: отмеченная «сдана» остаётся листом и уходит из стопки, когда открыли следующий.
    func stack(of s: Session) -> [Session] {
        switch cardStackMode {
        case .day: dayStack(of: s)
        case .debts: debts().filter { $0.id != s.id }
        }
    }

    /// Соседи карточки в стопке: все записи её дня, кроме неё самой, — съёмки,
    /// встречи и события, без слоя событий (веб `onDay` без `shownRec`).
    /// Порядок — от ближнего к листу краю: последняя по началу съёмка дня
    /// первой, при равном начале — позже записанная (`b.min − a.min || b.i − a.i`).
    /// Правило «свадьба первой» у веба живёт только в списке дня, на стопку не
    /// влияет. Съёмка через полночь лежит в обоих днях (`partOfDay`).
    func dayStack(of s: Session) -> [Session] {
        snapshot.sessions.enumerated()
            .filter { $0.element.id != s.id && $0.element.part(on: s.day) != nil }
            .sorted { a, b in
                a.element.start != b.element.start ? a.element.start > b.element.start : a.offset > b.offset
            }
            .map(\.element)
    }
}

/// Слова края стопки — отдельно от вида, чтобы тесты читали их словами.
@MainActor
struct PeekText {
    /// Жанр словом, у встречи — «Встреча» (веб `isMeet ? plan.meet : evTypeName`).
    var genre: String
    /// Имя клиента — крупно: день с двумя портретами различают именно имена.
    var name: String
    /// «14:00 – 15:30» — у веба `fmt` начала и конца, без `range`.
    var time: String
    /// Перекрывает карточку по времени — время терракотой (веб `.peek-t.over`).
    var over: Bool
    /// Вторая строка, «где»: город слева, точка съёмки справа (веб `placeTown`,
    /// `place`). Нет обоих — строки нет.
    var town: String
    var spot: String
    /// Третья строка: первая строка заметки (веб `notes.split("\n")[0].trim()`).
    var note: String

    /// - Parameter debts: край стопки долгов (К5): справа не часы, а день съёмки и просрочка — «2 окт · −7 дн»,
    ///   просроченный терракотой; соседи из разных дней по часам не сравниваются.
    /// День долга коротко, как в эскизе: «2 окт»; долг прошлого года — с годом.
    static func debtDay(_ day: CivilDate, app: AppModel) -> String {
        let f = PlannerFacts(app: app, dark: true), d = f.date(day)
        return day.year == app.today.year ? f.dates.dMonShort(d) : f.dates.dMonShortYear(d)
    }

    init(_ p: Session, card s: Session, app: AppModel, debts: Bool = false) {
        let f = PlannerFacts(app: app, dark: true)
        genre = p.kind == .meet ? f.t.t("plan.meet") : f.words.typeName(p)
        name = f.words.clientName(p)
        if debts {
            time = Self.debtDay(p.day, app: app)
            if case .overdue(let days) = app.deliveryStatus(p) {
                time += " · −" + f.t.count("unit.dayShort", days)
                over = true
            } else {
                over = false
            }
        } else {
            time = f.fmt(Double(p.start)) + " – " + f.fmt(Double(p.endMinute))
            // Минуты соседа — на шкале дня карточки: вчерашняя съёмка через полночь
            // начинается «до нуля». Веб сравнивает `s.min` без дат — ошибка эталона
            // (ревью GPT к 4224ce1).
            let d = p.day.days(since: s.day) * 1440
            over = p.start + d < s.endMinute && s.start < p.endMinute + d
        }
        town = p.placeTown
        spot = p.place
        note = (p.notes.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Края соседних карточек над листом (`.peeks`). Край k = 0 — ближний к листу:
/// каждый следующий выше на 22 pt и уже на 10 pt с каждой стороны, ступень
/// ширины перестаёт расти на четвёртом. Видна полоса 22 pt, остальное прячет
/// лист. Тап по краю открывает соседа листом (веб `openCard(i, false, true)`):
/// стопка пересчитывается, движения подмены у веба нет (класс `swap` без
/// стиля). Гармошка — потянуть лист вниз (29.3а, `StackPull`): края
/// разъезжаются за пальцем и пружинят обратно.
struct CardStack<Sheet: View>: View {
    let app: AppModel
    let s: Session
    let pal: Palette
    @ViewBuilder let sheet: () -> Sheet

    /// Доля протяга гармошки, `0…1`; на пружине обратно — с перелётом ниже нуля.
    @State private var pull: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var still

    /// Высота края (веб `PEEK_H`) и видимая полоса (`PEEK_STEP`).
    static var peekHeight: CGFloat { StackPull.peekHeight }
    static var peekStep: CGFloat { 22 }

    /// Отступ края с каждой стороны (веб `10 + min(k, 3)·10`).
    static func inset(_ k: Int) -> CGFloat { CGFloat(10 + min(k, 3) * 10) }

    /// Сколько краёв стопки долгов видно (К5). После сезона долгов десятки, а каждый край — 22 pt над листом:
    /// тридцать краёв унесли бы лист за экран. Видны самые старые, ближние к листу; остальные ждут очереди —
    /// над стопкой строка «Ещё несданных: N». Стопка дня не режется.
    static var debtsShown: Int { 6 }

    /// Края, которые рисуются, и сколько осталось за ними.
    static func shown(_ all: [Session], mode: CardStackMode) -> (edges: [Session], more: Int) {
        guard mode == .debts, all.count > debtsShown else { return (all, 0) }
        return (Array(all.prefix(debtsShown)), all.count - debtsShown)
    }

    var body: some View {
        let mode = app.cardStackMode
        let (others, more) = Self.shown(app.stack(of: s), mode: mode)
        let n = others.count
        VStack(spacing: 0) {
            if more > 0 {
                Text(app.lexicon.t("card.debtsMore", ["n": "\(more)"]))
                    .font(webFont(11.5))
                    .foregroundStyle(pal.ink6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
                    .shotNode("card.debtsMore", text: "\(more)")
            }
            stack(others, n: n, debts: mode == .debts)
        }
    }

    private func stack(_ others: [Session], n: Int, debts: Bool) -> some View {
        ZStack(alignment: .top) {
            ForEach(Array(others.enumerated()), id: \.element.id) { k, p in
                edge(p, k, debts: debts)
                    .padding(.horizontal, Self.inset(k))
                    .padding(.top, CGFloat(n - 1 - k) * Self.peekStep)
                    .modifier(PullShift(travel: StackPull.peekTravel(k: k, n: n), p: pull, tag: "k\(k)"))
                    .zIndex(Double(9 - k))
            }
            // Лист над краями (`.card-sheet { z-index: 1 }` над слоем `.peeks`):
            // отступ даёт обёртка — `N·22`.
            sheet()
                .modifier(PullShift(travel: StackPull.sheetTravel(n), p: pull, tag: "sheet"))
                #if os(iOS)
                .background { StackPullHost(gesture: pullGesture(n)) }
                #endif
                .padding(.top, CGFloat(n) * Self.peekStep)
                .zIndex(10)
        }
    }

    /// Гармошка (веб `touchstart` / `touchmove` / `touchend` на `#cdSheet`): на
    /// время жеста лист и края идут за пальцем без анимации (`.dragging`),
    /// отпустил или система отняла палец — пружина обратно. Отдачи и звука у
    /// веба на этом жесте нет.
    private func pullGesture(_ n: Int) -> StackPullGesture {
        StackPullGesture(
            down: { touches, top in
                let ok = StackPull.canStart(n: n, tuning: app.cardTuning, touches: touches, scrollTop: top)
                StackLog.note(String(format: "down n=%d top=%.1f tuning=%@ touches=%d -> %@", n, top,
                                     app.cardTuning ? "yes" : "no", touches, ok ? "take" : "none"))
                return ok
            },
            moved: { dy in
                let p = StackPull.progress(dy: dy, n: n)
                StackLog.note(String(format: "move dy=%.1f len=%.0f p=%.4f sheet=%.2f", dy, StackPull.pullLength(n), p,
                                     StackPull.sheetTravel(n) * p)
                              + (0..<n).map { String(format: " k%d=%.2f", $0, StackPull.peekOffset(k: $0, n: n, p: p)) }.joined())
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { pull = p }
            },
            ended: { cancelled in
                StackLog.note("\(cancelled ? "cancel" : "end") p=\(String(format: "%.4f", pull)) still=\(still)")
                withAnimation(StackPull.settle(still: still)) { pull = 0 }
            })
    }

    private func edge(_ p: Session, _ k: Int, debts: Bool) -> some View {
        let x = PeekText(p, card: s, app: app, debts: debts)
        let w = PlannerWords(lexicon: app.lexicon, orgs: app.orgs)
        // Край стопки долгов открывает следующий долг, и стопка остаётся стопкой долгов.
        return Button { app.openCard(id: p.id, stack: debts ? .debts : .day) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Group {
                        if let n = w.iconName(p) { Icon(n, size: 14, line: 1.5) }
                        else { Icon(genre: p.genre?.rawValue ?? "", size: 14, line: 1.5) }
                    }
                    .foregroundStyle(pal.brass)
                    .frame(width: 14, height: 14)
                    Text(x.genre + (x.name.isEmpty ? "" : " ·")).foregroundStyle(pal.ink6)
                        .fixedSize()
                    if !x.name.isEmpty {
                        Text(x.name).font(webFont(11.5, 600)).foregroundStyle(pal.ink3)
                            .lineLimit(1).truncationMode(.tail)
                            .shotNode("card.peekName.\(k)")
                    }
                    if p.repeatInfo != nil {
                        Icon("repeat", size: 12).foregroundStyle(pal.ink5)
                            .frame(width: 12, height: 12)
                            .padding(.leading, -3)
                    }
                    Spacer(minLength: 0)
                    Text(x.time).monospacedDigit().foregroundStyle(x.over ? pal.terra : pal.ink4)
                        .fixedSize()
                        .shotNode("card.peekTime.\(k)", text: x.time)
                }
                .foregroundStyle(pal.ink4)
                .frame(height: 18)
                // Строки под кромкой открываются оттянутым листом (веб `.peek-sub`):
                // «где» — 7 pt под первой, заметка — 4 pt ниже, обе `--ink-7`/`--ink-8`
                // в одну строку. Строка веба — 12 pt: текст стоит по её середине.
                if !x.town.isEmpty || !x.spot.isEmpty {
                    HStack(spacing: 10) {
                        Text(x.town).lineLimit(1).truncationMode(.tail)
                            .frame(height: 12)
                            .shotNode("card.peekTown.\(k)", text: x.town)
                        if !x.spot.isEmpty {
                            Spacer(minLength: 0)
                            Text(x.spot).lineLimit(1).truncationMode(.tail)
                                .frame(height: 12)
                                .shotNode("card.peekSpot.\(k)", text: x.spot)
                        }
                    }
                    .foregroundStyle(pal.ink7)
                    .padding(.top, 7)
                }
                if !x.note.isEmpty {
                    Text(x.note).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(pal.ink8)
                        .frame(height: 12)
                        .shotNode("card.peekNote.\(k)", text: x.note)
                        .padding(.top, 4)
                }
            }
            .font(webFont(11.5))
            .padding(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PeekPress(fill: k == 0 ? pal.peek1 : pal.peek2, press: pal.press, edge: pal.stackEdge,
                               shade: k == 0 ? pal.stackShade : nil))
        .frame(height: Self.peekHeight)
        .shotNode("card.peek.\(k)")
    }
}

/// Тон края, кант по верхней кромке (`inset 0 1px 0 --stack-edge`) и у
/// ближнего — тень вверх на лист за ним (`0 −6px 14px −4px --stack-shade`).
/// Нажатый край — `--press` (веб `.peek:active`).
private struct PeekPress: ButtonStyle {
    let fill: Color, press: Color, edge: Color
    let shade: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(StackPlate(fill: configuration.isPressed ? press : fill, edge: edge, radius: 22,
                                   shade: shade.map { StackPlate.Shade(color: $0, y: -6, blur: 14, spread: -4) }))
    }
}

/// Лист или край стопки: тон, светлый кант по верхней кромке — он называет
/// край на тёмном, где тень не видна, — и тень вверх — она делает стопку на
/// светлом. Живут оба признака сразу, каждый работает в своей теме.
struct StackPlate: View {
    struct Shade { let color: Color; let y: CGFloat; let blur: CGFloat; let spread: CGFloat }
    let fill: Color, edge: Color, radius: CGFloat
    var shade: Shade?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            // Тень CSS с отрицательным разлётом: фигура, ужатая на разлёт, с
            // размытием в половину `blur` — у SwiftUI радиус тени это сигма.
            if let sh = shade {
                shape.fill(fill).padding(-sh.spread)
                    .shadow(color: sh.color, radius: sh.blur / 2, x: 0, y: sh.y)
            }
            // Кант — тон с кантом поверх, а на нём тон, сдвинутый на 1 pt вниз:
            // остаётся полоска по верхней кромке, сходящая на нет по углам.
            ZStack {
                shape.fill(fill)
                shape.fill(edge)
                shape.fill(fill).offset(y: 1)
            }
            .clipShape(shape)
        }
    }
}
