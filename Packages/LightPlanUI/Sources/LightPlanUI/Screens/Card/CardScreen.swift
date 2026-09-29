import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Карточка события — порт `#cardOverlay` веба (итерация 25). Слой во весь
/// экран над вкладками, как `.overlay` веба (`z-index 78`); форма открывается
/// поверх карточки и, закрывшись, возвращает на неё.
///
/// Шаг 2 — каркас: полоса, лист, нижний ряд, фаза. Шаг 3 — шапка со знаком,
/// плитка дня и студийный час; шаг 4 — стопка соседей и раскладка по парам
/// веб / натив (поля 24, полоса формы, студийный час над плиткой дня).
/// Порядок блоков («ползунки», `#cardOrder`) и сами блоки — итерация 26,
/// гармошка стопки — 29. Справка — `Light_Plan/docs/card_reference.md`.
struct CardScreen: View {
    @Bindable var app: AppModel
    let s: Session
    @Environment(\.colorScheme) private var scheme

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        // Фаза переключается сама, пока карточка открыта: раз в минуту —
        // шаг, с которым меняется минута шкалы. Момент такта уходит в плитки
        // входом: без него SwiftUI видит те же `app`, `s`, `phase` и тела
        // плиток не пересчитывает — часы плитки дня и студийный час стояли
        // (телефон, 29.09: «40 минут и не двигается»).
        TimelineView(.everyMinute) { ctx in
            let phase = app.phase(of: s)
            // Поля слоя — 24 (`.overlay { padding: 0 24px }`); полоса стоит на
            // месте, пока лист едет под ней (`position: sticky`), и начинается
            // под вырезом экрана: на 46 от верха, как у формы, средняя кнопка
            // уходила под островок на 4 pt (телефон, 29.09).
            VStack(spacing: 0) {
                bar(pal)
                ScrollView {
                    VStack(spacing: 0) {
                        CardStack(app: app, s: s, pal: pal) { sheet(pal, phase, ctx.date) }
                        // Пожелание к небу не сбудется — строка под листом.
                        CardWishMissed(app: app, s: s, phase: phase, pal: pal)
                        acts(pal)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
                // Сосед из стопки открывается листом сверху, как у веба
                // (`openCard(i, false, …)` сбрасывает прокрутку).
                .id(s.id)
            }
            .shotNode("card.phase", text: phase.rawValue)
        }
        .background(pal.surface.ignoresSafeArea())
    }

    // MARK: - Полоса (`.form-bar`)

    /// «✕», «новая съёмка на этот день» и справа «Заполнить» (у события её
    /// нет) — разнесены по краям (`justify-content: space-between`), поэтому
    /// средняя кнопка стоит посередине свободного места, а не у «✕».
    /// «Ползунки» порядка блоков — итерация 26: с ними правая группа шире на
    /// 50 и средняя кнопка сдвинется влево на 25, как у веба.
    private func bar(_ pal: Palette) -> some View {
        HStack(spacing: 0) {
            FormBarButton(node: "card.back", kind: .close, label: t.t("card.close")) {
                withAnimation(overlaySlide) { app.closeCard() }
            }
            Spacer(minLength: 10)
            // Режим перестановки прячет «＋» и «Заполнить»: палец, ведущий блок,
            // не должен встретить лишнего (веб, замечание Алексея).
            if !app.cardTuning {
                Button { app.openForm(day: s.day) } label: {
                    PlanGlyph(kind: .add)
                        .stroke(pal.ink3, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 18, height: 18)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                        // Нажатие ловит весь круг, а не только линии знака.
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .shotNode("card.add")
                .accessibilityLabel(t.t("card.addShoot"))
                Spacer(minLength: 10)
            }
            HStack(spacing: 10) {
                if s.kind != .event && !app.cardTuning {
                    Button { app.openForm(editing: s.id) } label: {
                        Text(t.t("card.fill")).font(webFont(15, 600)).foregroundStyle(pal.brassDeep)
                            .padding(.horizontal, 15).padding(.vertical, 9)
                            .background(Capsule().fill(pal.press))
                    }
                    .buttonStyle(.plain)
                    .shotNode("card.edit")
                }
                tuneButton(pal)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    /// «Ползунки» (`#cardOrder`): круглая 40×40 стеклянная; в режиме залита
    /// `--ink`, знак `--surface`. Повторный тап — выход.
    private func tuneButton(_ pal: Palette) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.26)) { app.toggleCardTuning() } } label: {
            Icon("sliders", size: 18, line: 1.8)
                .foregroundStyle(app.cardTuning ? pal.surface : pal.ink3)
                .frame(width: 40, height: 40)
                .background { if app.cardTuning { Circle().fill(pal.ink) } }
                .glassEffect(.regular, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shotNode("card.tune", text: app.cardTuning ? "on" : "off")
        .accessibilityLabel(t.t("card.tune"))
    }

    // MARK: - Лист

    /// Лист `.card-sheet`: шапка, студийный час, плитка дня, наложение.
    /// Опросник — 28, сделка, тревоги, погода и остальные блоки — 26–27.
    private func sheet(_ pal: Palette, _ phase: EventPhase, _ tick: Date) -> some View {
        VStack(spacing: 0) {
            CardHead(app: app, s: s, phase: phase, pal: pal, tick: tick)
            // Тревога прогноза и сдвиг времени на ленте — не блоки: стоят над
            // студийным часом, тревога выше.
            CardShiftLine(app: app, s: s, phase: phase, pal: pal)
            CardMoved(app: app, s: s, pal: pal)
            // Студийный час — над переставляемыми блоками: веб переносит блоки
            // в конец `#cdEventBlocks`, а не-блоки (тревоги, студия, звонок
            // администратору) остаются выше — «читается первой, куда бы
            // фотограф ни переставил остальное».
            CardStudio(app: app, s: s, phase: phase, pal: pal, tick: tick)
            // Переставляемые блоки: плитка дня, наложение (сразу под ней по
            // умолчанию — Алексей, телефон 29.09) и остальные (итерация 26).
            CardBlocks(app: app, s: s, phase: phase, pal: pal, tick: tick)
        }
        .padding(EdgeInsets(top: 18, leading: 12, bottom: 16, trailing: 12))
        // Тень вверх и кант по кромке — у листа всегда, и без стопки
        // (`.card-sheet`: `0 −7px 18px −4px`, `inset 0 1px 0`).
        .background(StackPlate(fill: pal.sheet2, edge: pal.stackEdge, radius: 22,
                               shade: .init(color: pal.stackShade, y: -7, blur: 18, spread: -4)))
        .shotNode("card.sheet")
    }

    // MARK: - Нижний ряд (`.card-acts`)

    /// «Завершить» — только в ручном режиме у идущей съёмки, у левого края
    /// ряда: «Удалить» прижата вправо (`margin-left: auto`), остальное стоит
    /// слева (веб перенёс кнопку из плитки дня 1.09). Удаление — тем же путём,
    /// что из списка: в корзину и полоса «Вернуть».
    private func acts(_ pal: Palette) -> some View {
        HStack(spacing: 12) {
            if app.canFinish(s) {
                // Контур 1 pt у веба снаружи полей 9×15 — у SwiftUI внутри,
                // поэтому поля 10×16 (пара шага 4: 109,5×37).
                Button { app.finishSession(id: s.id) } label: {
                    Text(t.t("day.finish")).font(webFont(14, 600)).foregroundStyle(pal.green)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .overlay(Capsule().strokeBorder(pal.green, lineWidth: 1))
                }
                .buttonStyle(PressFade())
                .shotNode("card.finish")
            }
            Spacer(minLength: 0)
            // В режиме перестановки «Удалить» скрыта — как «＋» и «Заполнить».
            if !app.cardTuning { Button {
                let id = s.id
                withAnimation(overlaySlide) { app.closeCard() }
                app.trashSession(id: id)
            } label: {
                // Пилюля `.card-del`: фон `--bad-bg`, слово `--bad-ink`, поля
                // 10×16 (пара шага 4: было голое слово терракотой).
                Text(t.t(s.kind == .meet ? "card.delMeet" : "card.delShoot")).font(webFont(14, 600))
                    .foregroundStyle(pal.badInk)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(pal.badBg))
            }
            .buttonStyle(PressFade())
            .shotNode("card.delete") }
        }
        .padding(.top, 22).padding(.bottom, 4)   // `.card-acts`: gap 12, margin 22/0/4
    }
}
