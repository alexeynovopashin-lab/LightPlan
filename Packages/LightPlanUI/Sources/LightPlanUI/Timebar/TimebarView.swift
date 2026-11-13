import SwiftUI

/// Таймбар — общий орган экранов «Свет» и «Карта» (план, § D.3): один
/// ползунок и одна лента на оба. Порт вёрстки веба (`#timebar`): строка
/// краёв (восход · «сейчас» · закат) → лента/барабан → ярус со слайдером.
///
/// Итерация 17 переносит прототип 3 в продукт: механика передачи разряда не
/// переизобретается, только подключается к настоящим суткам, погоде и луне.
public struct TimebarView: View {
    let state: TimebarState
    /// Лента суток — второй контроль, только в «Астро» (веб: `.ribbon-wrap`
    /// скрыт без `body.pro-mode`). До 19б приложение показывало её всегда
    /// (найдено 19а).
    let showRibbon: Bool
    /// На карте таймбар лежит на общем стекле дока: ни поверхности, ни
    /// волоска (`body[data-tab="s-map"] .timebar` веба).
    let bare: Bool
    /// Свой ответ кнопке «↺ сейчас»: экран AR (29.8в.3) возвращает ручку плавно, кадр за кадром. `nil` — как у
    /// «Света» и «Карты»: `jumpToNow()`.
    let onNow: (() -> Void)?
    /// Свой цвет слова «Сейчас»: экран AR кладёт панель с таймбаром на стекло, тёмное над любым небом (замер 29.8в.10:
    /// яркость стекла под словом 0,056 над белым и 0,036 над голубым), и латунь `brassDeep` держит там 3,26 и 4,01 к 1.
    /// `nil` — цвет «Света» и «Карты».
    let nowInk: Color?
    /// 30з.1: на «Свете» время рассвета и заката стоит у оснований дуги, строки краёв над лентой нет.
    let showEdges: Bool
    /// 30з.2: на «Свете» лента дат и шкала лежат на третьей плашке матового стекла (`glassPlate`), а не на сплошной поверхности с волоском;
    /// поля по бокам 16 (плашка отступает от края на 8, содержимое стоит где стояло — на 24).
    let plate: Bool
    /// 30з.2а («пульт»): верхняя строка плашки — слева что передано (капсула «Запланировать съёмку»), справа круглая «↺» на постоянном месте.
    /// Только вместе с `plate`; без неё строки нет.
    let console: AnyView?
    @Environment(\.colorScheme) private var colorScheme

    public init(_ state: TimebarState, showRibbon: Bool = true, bare: Bool = false, nowInk: Color? = nil, showEdges: Bool = true, plate: Bool = false,
                console: AnyView? = nil, onNow: (() -> Void)? = nil) {
        self.state = state
        self.showRibbon = showRibbon
        self.bare = bare
        self.nowInk = nowInk
        self.showEdges = showEdges
        self.plate = plate
        self.console = console
        self.onNow = onNow
    }

    public var body: some View {
        let pal = Palette(colorScheme)
        VStack(spacing: 8) {
            if plate, let console { consoleRow(pal, console) }
            if showEdges { edges(pal) }
            if showRibbon {
                RibbonView(state: state).shotNode("ribbon")
            }
            ScrubView(state: state)
                .offset(x: state.laneShift)
                .opacity(state.laneOpacity)
                .shotNode("track")
        }
        // `.timebar`: поля 12 · 24 · 14, поверхность экрана, волосок сверху.
        .padding(EdgeInsets(top: 13, leading: plate ? 16 : 24, bottom: 14, trailing: plate ? 16 : 24))   // 1 — волосок `border-top`
        .background {
            if plate { Color.clear.glassPlate(pal, hush: 0.7) } else { (bare ? Color.clear : pal.surface) }
        }
        // «↺» живёт в строке капсулы «Запланировать съёмку» (30з.2а, оба вида «Света»); плавающей кнопки над лентой больше нет.
        .overlay(alignment: .top) { Rectangle().fill(bare || plate ? .clear : pal.hair).frame(height: 1) }
    }

    // MARK: - Пульт (30з.2а)

    /// Высота строки пульта: капсула «Запланировать съёмку» и круглая «↺» одной высоты.
    static let consoleHeight: CGFloat = 40

    /// «↺» на постоянном месте справа от капсулы: время и день уже «сейчас» — приглушена и не отзывается; сдвинули время или день —
    /// загорается акцентом и возвращает оба (то же, что «↺ сейчас» / «↺ сегодня» до пульта). Не появляется, не исчезает, ничего не двигает.
    private func consoleRow(_ pal: Palette, _ content: AnyView) -> some View {
        HStack(spacing: 8) {
            content
            NowResetButton(state: state, pal: pal, onNow: onNow)
        }
        .frame(height: Self.consoleHeight)
    }

    // MARK: - Края: восход, «сейчас», закат

    /// `.now-tick`: 11/600, разрядка 0,4, `--brass-deep`; поле
    /// 9 · 14 — для пальца, а не для глаза.
    /// «Свет» (30з.1): «↺ Сейчас» стоит ровно посередине между низом капсулы съёмки и верхом ленты дат. Рамки: верх ленты = верх таймбара + 13
    /// (поле); низ капсулы = верх таймбара − 8 (зазор вставки) − 28 (строка «Сейчас», `LightScreenView.nowLift`) − 3 (поле капсулы) = −39.
    /// Щель 52 pt, середина −13: 26 pt до капсулы и 26 pt до ленты. Кнопка 34 pt высотой → верх на −13 − 17 = −30.
    static let floatingNowHeight: CGFloat = 34
    static let floatingNowOffset: CGFloat = -13 - floatingNowHeight / 2

    private func nowButton(_ pal: Palette, floating: Bool = false) -> some View {
        Button { if let onNow { onNow() } else { state.jumpToNow() } } label: {
            Text(state.nowButtonLabel)
                .font(.system(size: floating ? 13 : 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(nowInk ?? pal.brassDeep)
                // На «Свете» (30з.1) кнопка 34 pt высотой — центр считается из рамок (см. оверлей ниже); на «Карте» и в AR поле 9 · 14, как было.
                .padding(.vertical, floating ? 0 : 9).padding(.horizontal, 14)
                .frame(height: floating ? Self.floatingNowHeight : nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("now", text: state.nowButtonLabel)
    }

    private func edges(_ pal: Palette) -> some View {
        ZStack {
            HStack(spacing: 0) {
                edge(state.riseEdge, pal).shotNode("edge.rise")
                Spacer(minLength: 24)
                if let setEdge = state.setEdge { edge(setEdge, pal).shotNode("edge.set") }
            }
            if state.nowButtonVisible { nowButton(pal) }
        }
        .frame(height: 19)
    }

    /// `.edge`: знак 19 (`--brass-deep`, линия 1,6), зазор 7, время 11/500
    /// цифрами одной ширины, `--ink-4`.
    @ViewBuilder
    private func edge(_ content: TimebarState.EdgeContent, _ pal: Palette) -> some View {
        switch content {
        case .time(let icon, let minutes):
            HStack(spacing: 7) {
                Icon(icon, size: 19, line: 1.6).foregroundStyle(pal.brassDeep)
                Text(state.clockString(minutes))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(pal.ink4)
            }
        case .text(let text):
            Text(text)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(pal.ink4)
        }
    }
}

/// Круглая «↺» пульта (30з.2а): на постоянном месте, время и день уже «сейчас» — приглушена и не отзывается; сдвинули — горит акцентом и
/// возвращает оба. Одна на оба вида «Света»: в плашке «время» и в строке капсулы вида «Без блоков».
struct NowResetButton: View {
    let state: TimebarState
    let pal: Palette
    var onNow: (() -> Void)? = nil

    var body: some View {
        let active = state.nowButtonVisible
        Button { if let onNow { onNow() } else { state.jumpToNow() } } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? pal.brassInk : pal.ink4.opacity(0.4))
                .frame(width: TimebarView.consoleHeight, height: TimebarView.consoleHeight)
                .glassEffect(.regular, in: Circle())
                .flatGlass(Circle(), light: !pal.dark)
                .overlay { if !pal.dark { Circle().strokeBorder(pal.hair4, lineWidth: 1).allowsHitTesting(false) } }
                .contentShape(Circle())
                .animation(.easeOut(duration: 0.2), value: active)
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .accessibilityLabel(String(state.nowButtonLabel.dropFirst(2)))
        .shotNode("now", text: active ? state.nowButtonLabel : "")
    }
}
