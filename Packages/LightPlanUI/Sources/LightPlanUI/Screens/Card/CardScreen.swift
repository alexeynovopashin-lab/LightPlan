import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Карточка события — порт `#cardOverlay` веба (итерация 25). Слой во весь
/// экран над вкладками, как `.overlay` веба (`z-index 78`); форма открывается
/// поверх карточки и, закрывшись, возвращает на неё.
///
/// Шаг 2 — каркас: полоса, лист, нижний ряд, фаза. Шаг 3 — шапка со знаком,
/// плитка дня и студийный час; стопка соседей — шаг 4; порядок блоков
/// («ползунки», `#cardOrder`) и сами блоки — итерация 26. Справка —
/// `Light_Plan/docs/card_reference.md`.
struct CardScreen: View {
    @Bindable var app: AppModel
    let s: Session
    @Environment(\.colorScheme) private var scheme

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        // Фаза переключается сама, пока карточка открыта: раз в минуту —
        // шаг, с которым меняется минута шкалы.
        TimelineView(.everyMinute) { _ in
            let phase = app.phase(of: s)
            VStack(spacing: 0) {
                bar(pal)
                ScrollView {
                    VStack(spacing: 0) {
                        sheet(pal, phase)
                        acts(pal)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
            .shotNode("card.phase", text: phase.rawValue)
        }
        .background(pal.surface.ignoresSafeArea())
    }

    // MARK: - Полоса (`.form-bar`)

    /// Слева «✕» и «новая съёмка на этот день», справа «Заполнить» (у события
    /// её нет). «Ползунки» порядка блоков — итерация 26.
    private func bar(_ pal: Palette) -> some View {
        HStack(spacing: 10) {
            FormBarButton(node: "card.back", kind: .close, label: t.t("card.close")) {
                withAnimation(overlaySlide) { app.closeCard() }
            }
            Button { app.openForm(day: s.day) } label: {
                PlanGlyph(kind: .add)
                    .stroke(pal.ink3, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .shotNode("card.add")
            .accessibilityLabel(t.t("card.addShoot"))
            Spacer(minLength: 0)
            if s.kind != .event {
                Button { app.openForm(editing: s.id) } label: {
                    Text(t.t("card.fill")).font(webFont(15, 600)).foregroundStyle(pal.brassDeep)
                        .padding(.horizontal, 15).padding(.vertical, 9)
                        .background(Capsule().fill(pal.press))
                }
                .buttonStyle(.plain)
                .shotNode("card.edit")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Лист

    /// Лист `.card-sheet`: шапка, плитка дня, студийный час. Опросник — 28,
    /// сделка, тревоги, погода и остальные блоки — 26–27.
    private func sheet(_ pal: Palette, _ phase: EventPhase) -> some View {
        VStack(spacing: 0) {
            CardHead(app: app, s: s, phase: phase, pal: pal)
            CardDayTile(app: app, s: s, phase: phase, pal: pal)
            CardStudio(app: app, s: s, phase: phase, pal: pal)
        }
        .padding(EdgeInsets(top: 18, leading: 12, bottom: 16, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(pal.sheet2))
    }

    // MARK: - Нижний ряд (`.card-acts`)

    /// «Завершить» — только в ручном режиме у идущей съёмки, слева от
    /// «Удалить» (веб перенёс её из плитки дня 1.09). Удаление — тем же путём,
    /// что из списка: в корзину и полоса «Вернуть».
    private func acts(_ pal: Palette) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            if app.canFinish(s) {
                Button { app.finishSession(id: s.id) } label: {
                    Text(t.t("day.finish")).font(webFont(14, 600)).foregroundStyle(pal.green)
                        .padding(.horizontal, 15).padding(.vertical, 9)
                        .overlay(Capsule().strokeBorder(pal.green, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .shotNode("card.finish")
            }
            Button {
                let id = s.id
                withAnimation(overlaySlide) { app.closeCard() }
                app.trashSession(id: id)
            } label: {
                Text(t.t(s.kind == .meet ? "card.delMeet" : "card.delShoot")).font(webFont(14, 600))
                    .foregroundStyle(pal.terra)
                    .padding(.horizontal, 15).padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .shotNode("card.delete")
        }
        .padding(.top, 16)
    }
}
