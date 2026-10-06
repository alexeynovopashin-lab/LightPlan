import Testing
import SwiftUI
import UIKit
@testable import LightPlanUI

/// Шаг 27а.2: сжатие блоков карточки при входе в «ползунки» — высоты, обёртка,
/// «Уменьшение движения», счётчик хода.
@MainActor
struct CardTuneSqueezeTests {

    // MARK: Высоты

    @Test func heightRunsFromNaturalToRowAndBack() {
        #expect(CardTuneSqueeze.height(natural: 120, t: 0, gap: 8) == 120)
        #expect(CardTuneSqueeze.height(natural: 120, t: 1, gap: 8) == 64)    // 56 + зазор
        #expect(CardTuneSqueeze.height(natural: 120, t: 1, gap: 0) == 56)    // первая строка без зазора
        #expect(CardTuneSqueeze.height(natural: 120, t: 0.5, gap: 0) == 88)
        // Блок ниже строки (30 pt) тоже тянется к 56, а не наоборот — как `height: 56px` веба.
        #expect(CardTuneSqueeze.height(natural: 30, t: 1, gap: 0) == 56)
    }

    @Test func zeroBlockGrowsFromNothingAndShrinksToNothing() {
        #expect(CardTuneSqueeze.height(natural: 0, t: 0, gap: 8) == 0)
        #expect(CardTuneSqueeze.height(natural: 0, t: 1, gap: 8) == 64)
        #expect(CardTuneSqueeze.height(natural: -5, t: 0, gap: 0) == 0)      // отрицательной высоты не бывает
    }

    /// Повторный тап посреди хода: высота зависит только от `t`, а не от того,
    /// с какой стороны к нему пришли, и монотонна в обе стороны — скачка нет.
    @Test func reversalMidWayHasNoJumpAndNoHysteresis() {
        let down = (0...10).map { CardTuneSqueeze.height(natural: 200, t: CGFloat($0) / 10, gap: 8) }
        let up = (0...10).reversed().map { CardTuneSqueeze.height(natural: 200, t: CGFloat($0) / 10, gap: 8) }
        #expect(down == up.reversed())
        #expect(zip(down, down.dropFirst()).allSatisfy { $0 > $1 })
        let t = 0.4
        let before = CardTuneSqueeze.height(natural: 200, t: t, gap: 8)
        // Развернулись на t = 0,4: следующий кадр отличается от предыдущего на шаг, не на прыжок.
        #expect(abs(CardTuneSqueeze.height(natural: 200, t: t - 0.01, gap: 8) - before) < 3)
        #expect(abs(CardTuneSqueeze.height(natural: 200, t: t + 0.01, gap: 8) - before) < 3)
    }

    // MARK: Обёртка в SwiftUI

    private func measured(t: CGFloat, gap: CGFloat, content: CGFloat) -> CGFloat {
        let v = CardSqueezeLayout(t: t, gap: gap) {
            VStack(spacing: 0) { if content > 0 { Color.red.frame(height: content) } }
            ZStack { Color.blue }
        }
        .frame(width: 300)
        let host = UIHostingController(rootView: v)
        return host.sizeThatFits(in: CGSize(width: 300, height: 2000)).height
    }

    @Test func layoutReportsInterpolatedHeight() {
        #expect(measured(t: 0, gap: 8, content: 120) == 120)
        #expect(measured(t: 1, gap: 8, content: 120) == 64)
        #expect(measured(t: 0.5, gap: 0, content: 120) == 88)
        #expect(measured(t: 0, gap: 8, content: 0) == 0)       // выключенный блок: пусто
        #expect(measured(t: 1, gap: 8, content: 0) == 64)      // в «ползунках» у него строка
        #expect(measured(t: 1, gap: 0, content: 400) == 56)    // высокий блок не раздувает строку
    }

    @Test func layoutAnimatesThroughItsParameter() {
        var l = CardSqueezeLayout(t: 0.25, gap: 8)
        #expect(l.animatableData == 0.25)
        l.animatableData = 0.75
        #expect(l.t == 0.75)
    }

    // MARK: Уменьшение движения и ход

    @Test func reducedMotionHasNoAnimationAndNoCapFade() {
        #expect(CardTuneSqueeze.animation(still: true) == nil)
        #expect(CardTuneSqueeze.animation(still: false) != nil)
        #expect(CardTuneSqueeze.duration == 0.26 && CardTuneSqueeze.capDuration == 0.22)
        #expect(CardTuneSqueeze.rowHeight == 56)
    }
}
