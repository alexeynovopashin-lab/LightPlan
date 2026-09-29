import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Перестановка блоков («ползунки», `#cardOrder`, итерация 26, шаг 5а)

/// Куда встанет строка при перетаскивании (веб: шаг = высота строки + зазор,
/// место = старт + `round(dy / 64)`, зажато краями).
enum CardOrderDrag {
    /// Высота строки 56 и зазор 8.
    static let step: CGFloat = 64
    /// Порог, с которого жест считается перетаскиванием.
    static let threshold: CGFloat = 4

    static func slot(start: Int, dy: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        // `Math.round` веба: половина уходит вверх, и −0,5 даёт 0, а не −1 (ревью GPT).
        return min(max(start + Int(((dy / step) + 0.5).rounded(.down)), 0), count - 1)
    }

    /// Строки, как они стоят, пока блок в руке: он «перескакивает по местам»,
    /// за пальцем плавно не едет (справка: плавное «читалось сломанным»).
    static func preview(_ rows: [CardBlock], moving b: CardBlock, to slot: Int) -> [CardBlock] {
        guard let i = rows.firstIndex(of: b), rows.indices.contains(slot), i != slot else { return rows }
        var out = rows
        out.remove(at: i)
        out.insert(b, at: slot)
        return out
    }
}

/// Список перестановки вместо блоков листа: строка на каждый блок с данными
/// (и выключенный — чтобы было чем вернуть), внизу «По умолчанию» и «Готово».
struct CardOrderList: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette

    @State private var hand: CardBlock?
    @State private var handStart = 0
    @State private var handSlot = 0

    var body: some View {
        let rows = app.cardOrderRows(s, phase: phase)
        let shown = hand.map { CardOrderDrag.preview(rows, moving: $0, to: handSlot) } ?? rows
        VStack(spacing: 8) {
            ForEach(shown, id: \.self) { b in row(b, rows: rows) }
        }
        // Первая строка встаёт вплотную к шапке, как у веба: пара мерила +10.
        .shotNode("card.order.list")
        footer
    }

    // MARK: Строка (`.ord-cap`)

    private func row(_ b: CardBlock, rows: [CardBlock]) -> some View {
        let off = app.isCardBlockOff(b, for: s)
        let held = hand == b
        return HStack(spacing: 12) {
            HStack(spacing: 12) {
                Icon(b.iconName, size: 17, line: 1.6).foregroundStyle(pal.brass)
                    .frame(width: 32, height: 32)
                    .background(pal.badgeBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(app.lexicon.t("cdBlock.\(b.rawValue)")).font(webFont(15.5)).foregroundStyle(pal.ink)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .opacity(off ? 0.4 : 1)
            // Тумблер сжат в 0,784 раза, как у веба (40×24 от 51×31); у iOS 26 системный
            // 63×28, на экране выходит 49×22 (замер симулятора, 29.09).
            Toggle("", isOn: Binding(get: { !off }, set: { app.setCardBlock(b, shown: $0, for: s) }))
                .labelsHidden().tint(pal.brass)
                .scaleEffect(0.784)
                .frame(width: 49, height: 22)
                .shotNode("card.order.toggle.\(b.rawValue)", text: off ? "off" : "on")
            handle(b, rows: rows)
        }
        .padding(.leading, 14)
        .frame(height: 56)
        .background(held ? pal.press : pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: held ? .black.opacity(0.45) : .clear, radius: held ? 12 : 0, y: held ? 8 : 0)
        .zIndex(held ? 1 : 0)
        .shotNode("card.order.row.\(b.rawValue)")
    }

    /// Ручка 56×56, две линии 20×20: тянуть можно только за неё, иначе жест
    /// спорит с прокруткой листа.
    private func handle(_ b: CardBlock, rows: [CardBlock]) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 4, y: 9)); p.addLine(to: CGPoint(x: 20, y: 9))
            p.move(to: CGPoint(x: 4, y: 15)); p.addLine(to: CGPoint(x: 20, y: 15))
        }
        .stroke(pal.ink7, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        .frame(width: 24, height: 24)
        .frame(width: 56, height: 56)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: CardOrderDrag.threshold, coordinateSpace: .global)
                .onChanged { g in
                    if hand != b, let i = rows.firstIndex(of: b) { hand = b; handStart = i; handSlot = i }
                    handSlot = CardOrderDrag.slot(start: handStart, dy: g.translation.height, count: rows.count)
                }
                .onEnded { g in
                    let j = CardOrderDrag.slot(start: handStart, dy: g.translation.height, count: rows.count)
                    hand = nil
                    app.moveCardBlock(b, to: j, for: s)
                }
        )
        .shotNode("card.order.handle.\(b.rawValue)")
    }

    // MARK: Подвал (`.ord-foot`)

    private var footer: some View {
        HStack(spacing: 10) {
            footButton(app.lexicon.t("card.orderReset"), color: pal.ink3, weight: 400, node: "card.order.reset") {
                app.resetCardOrder(for: s)
            }
            footButton(app.lexicon.t("card.orderDone"), color: pal.brassDeep, weight: 650, node: "card.order.done") {
                app.toggleCardTuning()
            }
        }
        .padding(.top, 18)
    }

    private func footButton(_ title: String, color: Color, weight: Int, node: String,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(webFont(15, weight)).foregroundStyle(color)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressFade())
        .shotNode(node)
    }
}
