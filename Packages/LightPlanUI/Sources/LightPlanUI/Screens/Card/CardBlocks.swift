import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Контейнер блоков (`#cdEventBlocks`, итерация 26, шаг 2)

/// Блоки листа в порядке группы жанров (`AppModel.cardBlocks`). Не-блоки —
/// тревоги, студийный час — стоят над контейнером всегда, куда бы фотограф
/// ни переставил остальное. Готовы плитка дня и наложение (25), свет и
/// погода (26, шаг 3); остальные — заглушки до шага 4: знак и имя.
struct CardBlocks: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette
    let tick: Date

    var body: some View {
        ForEach(app.cardBlocks(s, phase: phase), id: \.self) { b in
            switch b {
            case .day: CardDayTile(app: app, s: s, phase: phase, pal: pal, tick: tick)
            case .clash: CardClash(app: app, s: s, phase: phase, pal: pal)
            case .light: CardLightBlock(app: app, s: s, phase: phase, pal: pal)
            case .weather: CardWeatherBlock(app: app, s: s, phase: phase, pal: pal)
            case .docs: CardFold(app: app, block: b, pal: pal) {
                ForEach(Array(s.docs.enumerated()), id: \.offset) { _, d in
                    Text(d.name ?? d.url ?? "").font(webFont(15)).foregroundStyle(pal.ink2)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9)
                }
            }
            default: CardBlockStub(app: app, block: b, pal: pal)
            }
        }
    }
}

/// Знак блока на подложке (`.pane` веба: 38×38, радиус 12, рисунок 19).
private func blockBadge(_ b: CardBlock, _ pal: Palette) -> some View {
    Icon(b.iconName, size: 19, line: 1.6).foregroundStyle(pal.brass)
        .frame(width: 38, height: 38)
        .background(pal.badgeBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}

/// Заглушка блока до шагов 3–4: плитка `--sheet-3`, знак и имя.
struct CardBlockStub: View {
    let app: AppModel
    let block: CardBlock
    let pal: Palette

    var body: some View {
        HStack(spacing: 12) {
            blockBadge(block, pal)
            Text(app.lexicon.t("cdBlock.\(block.rawValue)")).font(webFont(15)).foregroundStyle(pal.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shotNode("card.block.\(block.rawValue)")
        .padding(.top, block == .deal ? 14 : 9)
    }
}

/// Свёртка (`.fold`: маршрут, документы): заголовок-кнопка, шеврон
/// поворачивается на 180° за 0,35 с, тело — без анимации высоты. Открытая
/// держится, пока карточка открыта (`AppModel.cardFolds`).
struct CardFold<Content: View>: View {
    let app: AppModel
    let block: CardBlock
    let pal: Palette
    @ViewBuilder let content: () -> Content

    var body: some View {
        let open = app.isCardFoldOpen(block)
        VStack(spacing: 0) {
            Button { app.toggleCardFold(block) } label: {
                HStack(spacing: 12) {
                    blockBadge(block, pal)
                    Text(app.lexicon.t("cdBlock.\(block.rawValue)")).font(webFont(15)).foregroundStyle(pal.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pal.ink4)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .animation(.easeInOut(duration: 0.35), value: open)
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { VStack(spacing: 0) { content() }.padding(.horizontal, 14).padding(.bottom, 4) }
        }
        .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shotNode("card.block.\(block.rawValue)", text: open ? "open" : "shut")
        .padding(.top, 9)
    }
}
