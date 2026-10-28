import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Стопка долгов как в Wallet (К5; Алексей 23.10: «подобно стопкам Wallet», «перспектива не нужна»)
//
// Вид 1 — открыт долг: карточка сверху, над ней пусто, остальные долги — стопкой внизу экрана (`DebtPile`):
// две-три кромки одной ширины и строка «Ещё несданных: N». Нажатие на стопку — вид 2 (`DebtsListScreen`): все
// долги полосами, старый сверху, без предела, листается; нажатие на полосу — она открывается видом 1.

extension AppModel {
    /// Вид 2: все долги, старый сверху (тот же порядок, что `Debts.stack`), открытая карточка тоже, пока она долг.
    func debtsList() -> [Session] { debts() }

    /// Нажатие на стопку внизу карточки долга.
    func openDebtsList() {
        guard card != nil, cardStackMode == .debts else { return }
        debtsListOpen = true
    }

    /// «✕» списка и свайп от края: назад к открытой карточке.
    func closeDebtsList() { debtsListOpen = false }

    /// Нажатие на полосу: этот долг — видом 1, остальные — снова стопкой внизу.
    func openDebtFromList(id: String) { openCard(id: id, stack: .debts) }
}

extension PlanMotion {
    /// Стопка уезжает вверх списком, полоса возвращается карточкой — одно движение слоя, без физики.
    @MainActor static func debtsList(_ app: AppModel, open: Bool) {
        withAnimation(pick(overlay)) { open ? app.openDebtsList() : app.closeDebtsList() }
    }

    @MainActor static func openDebt(_ app: AppModel, id: String) {
        withAnimation(pick(overlay)) { app.openDebtFromList(id: id) }
    }
}

/// Стопка долгов внизу карточки (вид 1): кромки одной ширины — без сужения и перспективы, — каждая следующая на
/// `step` ниже, передняя (нижняя) несёт строку «Ещё несданных: N». Вся стопка — одна кнопка.
struct DebtPile: View {
    let app: AppModel
    let s: Session
    let pal: Palette

    /// Сколько кромок рисуется: не больше трёх, сколько бы ни было долгов.
    static func plates(_ n: Int) -> Int { min(3, n) }
    /// Высота передней кромки и шаг между кромками.
    static var plateHeight: CGFloat { 44 }
    static var step: CGFloat { 8 }

    var body: some View {
        let n = app.stack(of: s).count
        if n > 0 {
            let m = Self.plates(n)
            Button { PlanMotion.debtsList(app, open: true) } label: {
                ZStack(alignment: .top) {
                    ForEach(0..<m, id: \.self) { k in
                        let front = k == m - 1
                        StackPlate(fill: front ? pal.peek1 : pal.peek2, edge: pal.stackEdge, radius: 18,
                                   shade: .init(color: pal.stackShade, y: -4, blur: 10, spread: -3))
                            .frame(height: Self.plateHeight)
                            .overlay {
                                if front {
                                    HStack(spacing: 6) {
                                        Text(app.lexicon.t("card.debtsMore", ["n": "\(n)"]))
                                            .font(webFont(13, 600)).foregroundStyle(pal.ink4)
                                            .shotNode("card.debtsMore", text: "\(n)")
                                        Icon("chevron", size: 11, line: 2).rotationEffect(.degrees(-90))
                                            .foregroundStyle(pal.ink6).frame(width: 11, height: 11)
                                    }
                                }
                            }
                            .padding(.top, CGFloat(k) * Self.step)
                            .zIndex(Double(k))
                            .shotNode("card.pile.\(k)")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(pal.surface)
            .shotNode("card.debtsPile", text: "\(n)")
        }
    }
}

/// Вид 2: все долги полосами одной ширины, как карты в Wallet — каждая следующая ложится на предыдущую, видна её
/// верхняя часть (жанр, имя, день и просрочка, «где»), последняя — целиком. Листается; нажатие — долг видом 1.
struct DebtsListScreen: View {
    let app: AppModel
    @Environment(\.colorScheme) private var scheme

    /// Видимая часть полосы под следующей: жанр с именем и строка «где» (до 49 pt), заметку прячет следующая полоса;
    /// высота полосы — как у края стопки дня.
    static var bandStep: CGFloat { 52 }
    static var bandHeight: CGFloat { CardStack<EmptyView>.peekHeight }

    var body: some View {
        let pal = Palette(scheme)
        let list = app.debtsList()
        VStack(spacing: 0) {
            ZStack {
                Text(app.lexicon.t("card.debtsAll", ["n": "\(list.count)"]))
                    .font(webFont(15, 600)).foregroundStyle(pal.ink3)
                    .shotNode("debts.title", text: "\(list.count)")
                HStack {
                    FormBarButton(node: "debts.back", kind: .close, label: app.lexicon.t("card.close")) {
                        PlanMotion.debtsList(app, open: false)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: Self.bandStep - Self.bandHeight) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { k, p in
                        band(p, k, pal)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .shotNode("debts.list", text: "\(list.count)")
            }
            .scrollJump(app.lexicon, node: "sj.debts")
        }
        .background(pal.surface.ignoresSafeArea())
    }

    private func band(_ p: Session, _ k: Int, _ pal: Palette) -> some View {
        Button { PlanMotion.openDebt(app, id: p.id) } label: {
            PeekLabel(app: app, p: p, x: PeekText(p, card: p, app: app, debts: true), pal: pal, node: "debts.band", k: k)
                .padding(.top, 8)
        }
        .buttonStyle(PeekPress(fill: pal.peek1, press: pal.press, edge: pal.stackEdge, shade: pal.stackShade))
        .frame(height: Self.bandHeight)
        .zIndex(Double(k))
        .shotNode("debts.band.\(k)", text: p.id)
    }
}
