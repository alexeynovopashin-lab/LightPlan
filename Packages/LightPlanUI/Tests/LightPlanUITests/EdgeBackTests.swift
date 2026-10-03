import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI

/// Итерация 28з: жест «назад» от левого края — правило отпускания, реестр слоёв, крайние случаи.
@MainActor
struct EdgeBackTests {
    private let width: CGFloat = 440

    /// Реестр с записанными слоями; `closed` копит то, что закрыл жест.
    private final class Box { var closed: [Double] = [] }

    private func edge(_ zs: [Double], box: Box, inside: [Double: Double] = [:]) -> (EdgeBack, [Double: UUID]) {
        let e = EdgeBack()
        var ids: [Double: UUID] = [:]
        for z in zs {
            let id = UUID()
            ids[z] = id
            e.register(id, z: z, inside: inside[z]) { box.closed.append(z) }
        }
        return (e, ids)
    }

    // MARK: правило отпускания

    @Test func releaseRuleTable() {
        let r = EdgeBackRule.commits
        #expect(r(width / 3 + 1, 0, width))          // дальше трети — закрыть
        #expect(!r(width / 3 - 1, 0, width))         // меньше трети и медленно — вернуть
        #expect(r(30, 700, width))                   // быстрый короткий — закрыть
        #expect(!r(30, 500, width))                  // не такой быстрый — вернуть
        #expect(!r(300, -400, width))                // дотянули дальше трети, но палец летит назад — вернуть
        #expect(r(width / 3 + 1, -100, width))       // чуть назад — всё ещё закрыть
    }

    // MARK: жест

    @Test func dragBelowThirdReturns() {
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        #expect(e.begin(width: width))
        e.move(100)
        e.end(velocity: 50)
        #expect(e.settling && !e.dragging)
        e.finishSettle(commit: false)
        #expect(box.closed.isEmpty)
        #expect(e.dx == 0 && !e.active)
    }

    @Test func fastShortSwipeCloses() {
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        #expect(e.begin(width: width))
        e.move(30)
        e.end(velocity: 900)
        e.finishSettle(commit: true)
        #expect(box.closed == [1.52])
        #expect(e.closedCount == 1 && !e.active && e.dx == 0)
    }

    @Test func releaseVelocityFromRecentMovesOnly() {
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        e.begin(width: width)
        e.move(0, at: 0); e.move(50, at: 0.05); e.move(100, at: 0.10)
        #expect(abs(e.releaseVelocity(at: 0.10) - 1000) < 1)       // идёт — 1000 pt/с
        #expect(e.releaseVelocity(at: 1.4) == 0)                   // стоял 1,3 с — скорости нет
        e.cancel()
    }

    @Test func burstOfEventsFallsBackToRecognizerVelocity() {
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        e.begin(width: width)
        e.move(0, at: 0); e.move(20, at: 0.004); e.move(44, at: 0.008)   // пачка за 8 мс — по ней скорость не посчитать
        e.end(recognizer: 700, at: 0.01)
        e.finishSettle(commit: true)
        #expect(box.closed == [1.52])                                   // быстрый короткий закрылся по скорости распознавателя
        // а палец, замерший перед отпусканием, скорость распознавателя не наследует
        let (f, _) = edge([1.0], box: box)
        f.begin(width: width)
        f.move(0, at: 0); f.move(44, at: 0.008)
        f.end(recognizer: 700, at: 1.5)
        f.finishSettle(commit: false)
        #expect(box.closed == [1.52])
    }

    @Test func stoppedFingerReleasedBelowThirdReturns() {
        // Палец дотянул до 100 pt, постоял и поднялся: скорость 0, меньше трети — слой возвращается.
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        e.begin(width: width)
        e.move(0, at: 0); e.move(100, at: 0.1)
        e.move(100, at: 1.4)
        e.end(at: 1.4)
        e.finishSettle(commit: false)
        #expect(box.closed.isEmpty)
    }

    @Test func backwardFlickBeyondThirdReturns() {
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        e.begin(width: width)
        e.move(250, at: 0); e.move(200, at: 0.05); e.move(150, at: 0.10)   // назад 1000 pt/с, всё ещё дальше трети
        e.end(at: 0.10)
        e.finishSettle(commit: false)
        #expect(box.closed.isEmpty)
    }

    @Test func fastFlickMeasuredFromMovesCloses() {
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        e.begin(width: width)
        e.move(0, at: 0); e.move(20, at: 0.03); e.move(40, at: 0.06)     // 667 pt/с, всего 40 pt
        e.end(at: 0.06)
        e.finishSettle(commit: true)
        #expect(box.closed == [1.52])
    }

    @Test func moveWithoutBeginDoesNothing() {
        // Жест не от края: распознаватель края `begin` не зовёт — слой не двигается и не закрывается.
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        e.move(200)
        e.end(velocity: 900)
        #expect(e.dx == 0 && !e.active && box.closed.isEmpty)
    }

    @Test func rootWithoutLayersIgnoresGesture() {
        let e = EdgeBack()
        #expect(!e.canBegin)
        #expect(!e.begin(width: width))
        #expect(e.dx == 0 && !e.active)
    }

    @Test func nestedLayersCloseOnlyTheTopOne() {
        // Карточка → организация → документы: закрывается верхний, нижние остаются.
        let box = Box()
        let (e, _) = edge([1.0, 1.52, 1.6], box: box)
        #expect(e.top?.z == 1.6)
        e.begin(width: width); e.move(300); e.end(velocity: 0); e.finishSettle(commit: true)
        #expect(box.closed == [1.6])
        // Закрытый слой ещё в дереве (уходит) — следующий жест его не берёт, берёт слой под ним.
        #expect(e.top?.z == 1.52)
        e.begin(width: width); e.move(300); e.end(velocity: 0); e.finishSettle(commit: true)
        #expect(box.closed == [1.6, 1.52])
        #expect(e.top?.z == 1.0)
    }

    @Test func secondGestureDuringAnimationRefused() {
        let box = Box()
        let (e, _) = edge([1.0, 1.52], box: box)
        e.begin(width: width); e.move(300); e.end(velocity: 0)
        #expect(e.settling)
        #expect(!e.canBegin)
        #expect(!e.begin(width: width))
        e.finishSettle(commit: true)
        e.finishSettle(commit: true)   // запоздавший второй вызов (таймер) ничего не закрывает
        #expect(box.closed == [1.52])
    }

    @Test func equalHeightLaterLayerIsOnTop() {
        let box = Box()
        let (e, ids) = edge([1.5], box: box)
        let second = UUID()
        e.register(second, z: 1.5) { box.closed.append(99) }
        #expect(e.top?.id == second)
        _ = ids
    }

    @Test func unregisterDropsLayer() {
        let box = Box()
        let (e, ids) = edge([1.0, 1.52], box: box)
        e.unregister(ids[1.52]!)
        #expect(e.top?.z == 1.0)
    }

    // MARK: нижний слой

    @Test func offsetsFollowFingerAndParallax() {
        let box = Box()
        let (e, ids) = edge([1.0, 1.52], box: box)
        #expect(e.offset(of: ids[1.52]!) == 0)               // жеста нет — всё на местах
        e.begin(width: width); e.move(110)
        #expect(e.offset(of: ids[1.52]!) == 110)             // верхний за пальцем
        #expect(abs(e.offset(of: ids[1.0]!) - (-0.3 * (width - 110))) < 0.001)   // нижний на 30 % левее и доезжает
        #expect(e.baseOffset(.tabs) == 0)                    // под верхним лежит слой, а не вкладки
        e.cancel()
    }

    @Test func tabsShiftWhenNoLayerBelow() {
        let box = Box()
        let (e, ids) = edge([1.52], box: box)
        e.begin(width: width); e.move(0)
        #expect(abs(e.baseOffset(.tabs) - (-0.3 * width)) < 0.001)
        #expect(e.baseOffset(.planner) == 0)
        #expect(e.offset(of: ids[1.52]!) == 0)
        e.move(width)
        #expect(e.baseOffset(.tabs) == 0)                    // дотянули до конца — основа на месте
        e.cancel()
    }

    @Test func plannerBaseShiftsForPlannerLayers() {
        let box = Box()
        let (e, _) = edge([0.3], box: box)                   // статистика «Съёмок»
        e.begin(width: width); e.move(0)
        #expect(abs(e.baseOffset(.planner) - (-0.3 * width)) < 0.001)
        #expect(e.baseOffset(.tabs) == 0)
        e.cancel()
    }

    @Test func docsSectionDoesNotAddOffsetsOfItsHost() {
        // Раздел внутри «Документов»: хозяин (0,9) стоит на месте, пока раздел едет; бумага над разделом — разница.
        let box = Box()
        let (e, ids) = edge([0.9, 0.91], box: box, inside: [0.91: 0.9])
        e.begin(width: width); e.move(200)
        #expect(e.offset(of: ids[0.91]!) == 200 - (-0.3 * (width - 200)))   // свой = нужный − сдвиг хозяина
        #expect(abs(e.offset(of: ids[0.9]!) - (-0.3 * (width - 200))) < 0.001)
        e.cancel()
    }

    // MARK: лист и клавиатура

    #if os(iOS)
    private func windowPresenting(_ style: UIModalPresentationStyle) async throws -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let vc = UIViewController()
        vc.modalPresentationStyle = style
        root.present(vc, animated: false)
        try await Task.sleep(for: .milliseconds(300))
        #expect(root.presentedViewController === vc)
        return window
    }

    @Test func fullScreenCoverTakesGestureSheetDoesNot() async throws {
        let bare = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        bare.rootViewController = UIViewController()
        #expect(EdgeBackGate.allowsBack(bare))                                      // ничего поверх — берёт
        #expect(EdgeBackGate.allowsBack(try await windowPresenting(.fullScreen)))   // форма на весь экран — берёт
        #expect(!EdgeBackGate.allowsBack(try await windowPresenting(.pageSheet)))   // лист — не берёт
        #expect(!EdgeBackGate.allowsBack(try await windowPresenting(.formSheet)))
        // SwiftUI поднимает `fullScreenCover` как `.overFullScreen` — форма записи берёт жест (измерено: style=5).
        #expect(EdgeBackGate.allowsBack(try await windowPresenting(.overFullScreen)))
    }
    #endif
}
