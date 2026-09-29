import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Наложение в карточке (веб `renderClash`, `#cdClash`)

extension AppModel {
    /// Строка о наложении под плиткой дня: первое наложение записи и «ещё N»,
    /// если их больше. После съёмки молчит — говорить «вы были в двух местах»
    /// поздно и незачем (веб: `eventPhase(s) !== "after"`). Слова — те же, что
    /// у формы (`clash.*T` / `clash.*M`).
    func cardClash(_ s: Session, phase: EventPhase) -> WishWarning? {
        guard phase != .after, let i = snapshot.sessions.firstIndex(where: { $0.id == s.id }) else { return nil }
        let list = Overlaps.clashes(ofSessionAt: i, sessions: snapshot.sessions, blocks: snapshot.blocks,
                                    context: clashContext)
        guard let first = list.first else { return nil }
        var w = clashWords(first)
        if list.count > 1 { w.message += " " + lexicon.t("card.clashMore", ["n": "\(list.count - 1)"]) }
        return w
    }
}

/// Плашка `.say.warn` на листе: `--sheet-3`, радиус 14, поля 11×14, знак 16
/// `--brass-deep`, слова 13,5 с шагом 1,45; начало — «Время пересекается.»
/// цветом `--ink`, дальше `--ink-3`. Вокруг — ровный янтарный свет, как у
/// предупреждения формы. Живёт сразу под плиткой дня (блок `clash` в
/// `CARD_BLOCKS`); перестановка блоков — итерация 26.
struct CardClash: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette

    var body: some View {
        if let w = app.cardClash(s, phase: phase) {
            HStack(alignment: .top, spacing: 9) {
                Icon("warn", size: 16, line: 1.5).foregroundStyle(pal.brassDeep)
                    .frame(width: 16, height: 16).padding(.top, 1)
                (Text(w.title + ".").foregroundStyle(pal.ink) + Text(" " + w.message).foregroundStyle(pal.ink3))
                    .font(webFont(13.5))
                    // `line-height: 1.45` — шаг 19,6 при родном у SF 16,1.
                    .lineSpacing(13.5 * (1.45 - 1.19))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shotNode("card.clashText", text: w.title)
            }
            .padding(.vertical, 11).padding(.horizontal, 14)
            .background(pal.sheet3, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .modifier(WarnGlow(rgb: (226, 164, 76), alpha: pal.dark ? 0.32 : 0.55))
            .shotNode("card.clash")
            .padding(.top, 9)
        }
    }
}
