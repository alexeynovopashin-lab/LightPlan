import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Референсы в карточке (`#cdRefFold`, итерация 27, шаг 3)

/// Одна строка: знак `camera`, «Референсы» (или «Референсы: Банкет»), «N кадров
/// · набор жанра и съёмки», стрелка вправо — это переход, а не раскрытие. Полосы
/// миниатюр нет (решение Алексея 29.09: у веба её тело не видно, ошибка 20).
/// Тап открывает полный экран (шаг 4).
struct CardRefsBlock: View {
    let app: AppModel
    let s: Session
    let pal: Palette

    var body: some View {
        if let r = app.cardRefsRow(s) {
            Button { withAnimation(overlaySlide) { app.openRefsFull(s) } } label: { row(r) }
                .buttonStyle(.plain)
                .shotNode("card.block.refs", text: "\(r.count)")
                .padding(.top, 9)
        }
    }

    private func row(_ r: CardRefsRow) -> some View {
        HStack(spacing: 12) {
            Icon(CardBlock.refs.iconName, size: 19, line: 1.6).foregroundStyle(pal.brass)
                .frame(width: 38, height: 38)
                .background(pal.badgeBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(r.title).font(webFont(15)).foregroundStyle(pal.ink).lineLimit(1)
                Text(r.sub).font(webFont(12)).foregroundStyle(pal.ink6).padding(.top, 2).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(pal.ink4)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Кадр без картинки (`.ph`): косая штриховка `--hatch` по `--sheet`, шаг 7.
/// Настоящих картинок в нативе нет — байты не ездят между устройствами, облака
/// ещё нет (решение Алексея 29.09, 1А); заглушкой рисуется сетка полного экрана.
struct RefPlaceholder: View {
    let pal: Palette
    var radius: CGFloat = 9

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x = -size.height
            while x < size.width {
                p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            ctx.stroke(p, with: .color(pal.hatch), lineWidth: 3.5)
        }
        .background(pal.sheet)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
