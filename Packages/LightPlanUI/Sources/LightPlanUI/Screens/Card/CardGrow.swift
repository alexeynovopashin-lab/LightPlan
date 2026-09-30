import SwiftUI
import LightPlanDomain

/// «Назначить съёмку» у встречи (веб `#cdGrow`) и строка «Съёмка назначена на …» (`#cdGrown`); итерация 28, шаг 7.
/// Встреча кончается решением: кнопка не переименовывает запись, а порождает съёмку — разговор остаётся в
/// календаре. Пока съёмка не назначена, стоит кнопка (латунь текстом, подпись `--ink-4`, фон `--press-warm`,
/// поля 14/15, радиус 14); потом — тихая строка на `--sheet-3` (14 pt, `--ink-3`, поля 12/15). У съёмки нет ни того, ни другого.
struct CardGrow: View {
    let app: AppModel
    let s: Session
    let pal: Palette

    var body: some View {
        if MeetGrow.canGrow(s) {
            Button { app.growMeet(s.id) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.lexicon.t("card.growT")).font(webFont(16, 600)).foregroundStyle(pal.brass)
                    Text(app.lexicon.t(s.kind == .meet ? "card.growS" : "card.growSEv")).font(webFont(12)).foregroundStyle(pal.ink4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.pressWarm))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressFade())
            .padding(.top, 14)
            .shotNode("card.grow", text: app.lexicon.t("card.growT"))
        } else if let line = app.grownLine(s) {
            Text(line).font(webFont(14)).foregroundStyle(pal.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.sheet3))
                .padding(.top, 12)
                .shotNode("card.grown", text: line)
        }
    }
}
