import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Стопка карточек дня (веб `dayStack` + `renderStack`, шаг 4 итерации 25)

extension AppModel {
    /// Соседи карточки в стопке: все записи её дня, кроме неё самой, — съёмки,
    /// встречи и события, без слоя событий (веб `onDay` без `shownRec`).
    /// Порядок — от ближнего к листу краю: последняя по началу съёмка дня
    /// первой, при равном начале — позже записанная (`b.min − a.min || b.i − a.i`).
    /// Правило «свадьба первой» у веба живёт только в списке дня, на стопку не
    /// влияет. Съёмка через полночь лежит в обоих днях (`partOfDay`).
    func stack(of s: Session) -> [Session] {
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

    init(_ p: Session, card s: Session, app: AppModel) {
        let f = PlannerFacts(app: app, dark: true)
        genre = p.kind == .meet ? f.t.t("plan.meet") : f.words.typeName(p)
        name = f.words.clientName(p)
        time = f.fmt(Double(p.start)) + " – " + f.fmt(Double(p.endMinute))
        // Минуты — каждой записи в своих сутках, как у веба (`s.min`, `shootEnd`).
        over = p.start < s.endMinute && s.start < p.endMinute
    }
}

/// Края соседних карточек над листом (`.peeks`). Край k = 0 — ближний к листу:
/// каждый следующий выше на 22 pt и уже на 10 pt с каждой стороны, ступень
/// ширины перестаёт расти на четвёртом. Видна полоса 22 pt, остальное прячет
/// лист. Тап по краю открывает соседа листом (веб `openCard(i, false, true)`):
/// стопка пересчитывается, движения подмены у веба нет (класс `swap` без
/// стиля). Гармошка — потянуть лист вниз — итерация 29.
struct CardStack<Sheet: View>: View {
    let app: AppModel
    let s: Session
    let pal: Palette
    @ViewBuilder let sheet: () -> Sheet

    /// Высота края (веб `PEEK_H`) и видимая полоса (`PEEK_STEP`).
    static var peekHeight: CGFloat { 74 }
    static var peekStep: CGFloat { 22 }

    /// Отступ края с каждой стороны (веб `10 + min(k, 3)·10`).
    static func inset(_ k: Int) -> CGFloat { CGFloat(10 + min(k, 3) * 10) }

    var body: some View {
        let others = app.stack(of: s)
        let n = others.count
        ZStack(alignment: .top) {
            ForEach(Array(others.enumerated()), id: \.element.id) { k, p in
                edge(p, k)
                    .padding(.horizontal, Self.inset(k))
                    .padding(.top, CGFloat(n - 1 - k) * Self.peekStep)
                    .zIndex(Double(9 - k))
            }
            // Лист над краями (`.card-sheet { z-index: 1 }` над слоем `.peeks`):
            // отступ даёт обёртка — `N·22`.
            sheet()
                .padding(.top, CGFloat(n) * Self.peekStep)
                .zIndex(10)
        }
    }

    private func edge(_ p: Session, _ k: Int) -> some View {
        let x = PeekText(p, card: s, app: app)
        let w = PlannerWords(lexicon: app.lexicon, orgs: app.orgs)
        return Button { app.openCard(id: p.id) } label: {
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
            .font(webFont(11.5))
            .foregroundStyle(pal.ink4)
            .frame(height: 18)
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
