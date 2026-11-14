import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Остальные съёмки дня краями внизу открытой карточки (30и.5, схема «раскрытие + стопки», кадр «карточка, края съёмок внизу»):
/// карточка выросла из стопки дня на «Съёмках», а соседи по дню лежат под ней — как стопка долгов (К5): кромки одной ширины,
/// каждая следующая на `step` ниже, передняя несёт имя и время ближней съёмки. Нажатие на кромку открывает эту съёмку листом
/// (стопка остаётся: `.fan`), как край над листом у обычной карточки дня.
struct DayPile: View {
    let app: AppModel
    let s: Session
    let pal: Palette

    /// Сколько кромок рисуется: не больше трёх; высота передней и шаг — как у `DebtPile`.
    static func plates(_ n: Int) -> Int { min(3, n) }

    var body: some View {
        let others = app.stack(of: s)
        if !others.isEmpty {
            let m = Self.plates(others.count)
            ZStack(alignment: .top) {
                ForEach(0..<m, id: \.self) { k in
                    // Задняя кромка — дальняя съёмка, передняя (нижняя) — ближняя к открытой.
                    let p = others[m - 1 - k]
                    let front = k == m - 1
                    Button { PlanMotion.openFromPile(app, id: p.id) } label: {
                        StackPlate(fill: front ? pal.peek1 : pal.peek2, edge: pal.stackEdge, radius: 18,
                                   shade: .init(color: pal.stackShade, y: -4, blur: 10, spread: -3))
                            .frame(height: DebtPile.plateHeight)
                            .overlay { if front { label(p, more: others.count - 1) } }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, CGFloat(k) * DebtPile.step)
                    .zIndex(Double(k))
                    .shotNode("card.dayPile.\(k)", text: p.id)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(pal.surface)
            .shotNode("card.dayPile", text: "\(others.count)")
        }
    }

    /// Время и имя передней съёмки; если за ней есть ещё — «ещё N» справа.
    private func label(_ p: Session, more: Int) -> some View {
        let w = PlannerWords(lexicon: app.lexicon, orgs: app.orgs)
        let name = w.clientName(p)
        let title = !name.isEmpty ? name : p.kind == .meet ? app.lexicon.t("day.meet") : p.kind == .event ? app.lexicon.t("day.event") : w.typeName(p)
        return HStack(spacing: 8) {
            Text(PlannerFacts(app: app, dark: pal.dark).fmt(Double(p.start))).font(webFont(13, 600)).monospacedDigit().foregroundStyle(pal.ink4)
            Text(title).font(webFont(13, 600)).foregroundStyle(pal.ink3).lineLimit(1)
            Spacer(minLength: 0)
            if more > 0 {
                Text(app.lexicon.t("plan.stackMore", ["n": "\(more)"])).font(webFont(12)).foregroundStyle(pal.ink5)
            }
        }
        .padding(.horizontal, 16)
    }
}
