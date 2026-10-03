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
        #expect(e.pendingCommit == false)
        e.finishSettle()
        #expect(box.closed.isEmpty)
        #expect(e.dx == 0 && !e.active)
    }

    @Test func fastShortSwipeCloses() {
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        #expect(e.begin(width: width))
        e.move(30)
        e.end(velocity: 900)
        #expect(e.pendingCommit == true)
        e.finishSettle()
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
        #expect(e.pendingCommit == true)
        e.finishSettle()
        #expect(box.closed == [1.52])                                   // быстрый короткий закрылся по скорости распознавателя
        // а палец, замерший перед отпусканием, скорость распознавателя не наследует
        let (f, _) = edge([1.0], box: box)
        f.begin(width: width)
        f.move(0, at: 0); f.move(44, at: 0.008)
        f.end(recognizer: 700, at: 1.5)
        #expect(f.pendingCommit == false)
        f.finishSettle()
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
        #expect(e.pendingCommit == false)
        e.finishSettle()
        #expect(box.closed.isEmpty)
    }

    @Test func backwardFlickBeyondThirdReturns() {
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        e.begin(width: width)
        e.move(250, at: 0); e.move(200, at: 0.05); e.move(150, at: 0.10)   // назад 1000 pt/с, всё ещё дальше трети
        e.end(at: 0.10)
        #expect(e.pendingCommit == false)
        e.finishSettle()
        #expect(box.closed.isEmpty)
    }

    @Test func fastFlickMeasuredFromMovesCloses() {
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        e.begin(width: width)
        e.move(0, at: 0); e.move(20, at: 0.03); e.move(40, at: 0.06)     // 667 pt/с, всего 40 pt
        e.end(at: 0.06)
        #expect(e.pendingCommit == true)
        e.finishSettle()
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
        e.begin(width: width); e.move(300); e.end(velocity: 0); #expect(e.pendingCommit == true); e.finishSettle()
        #expect(box.closed == [1.6])
        // Закрытый слой ещё в дереве (уходит) — следующий жест его не берёт, берёт слой под ним.
        #expect(e.top?.z == 1.52)
        e.begin(width: width); e.move(300); e.end(velocity: 0); #expect(e.pendingCommit == true); e.finishSettle()
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
        #expect(e.pendingCommit == true)
        e.finishSettle()
        e.finishSettle()   // запоздавший второй вызов (таймер) ничего не закрывает
        #expect(box.closed == [1.52])
    }

    @Test func closesTheLayerGrabbedAtBeginEvenIfAnotherAppearedOnTop() {
        let box = Box()
        let (e, _) = edge([1.0], box: box)
        e.begin(width: width); e.move(300); e.end(velocity: 0)
        e.register(UUID(), z: 1.6) { box.closed.append(1.6) }     // за время доезда сверху открылся другой слой
        e.finishSettle()
        #expect(box.closed == [1.0])
    }

    @Test func grabbedLayerGoneMeansNothingClosed() {
        let box = Box()
        let (e, ids) = edge([1.0, 1.52], box: box)
        e.begin(width: width); e.move(300); e.end(velocity: 0)
        e.unregister(ids[1.52]!)                                   // слой ушёл сам
        e.finishSettle()
        #expect(box.closed.isEmpty && !e.active)
    }

    @Test func layersOfHiddenTabAreNotCandidates() {
        let box = Box()
        let (e, _) = edge([0.3], box: box)                         // статистика «Съёмок»
        e.isLive = { _ in false }                                  // вкладка «Съёмок» не выбрана
        #expect(!e.canBegin)
        e.isLive = { _ in true }
        #expect(e.canBegin)
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

    // MARK: 28з.5 — подлаги

    private final class Flag: @unchecked Sendable { var hit = false }

    @Test func hiddenTabReadsNothingAndStaysPut() {
        // Сдвиг всего стека вкладок стоил ≈ 9 из 13 мс на кадр: спрятанная вкладка не едет и жеста не читает.
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        let flag = Flag()
        withObservationTracking { _ = e.baseOffset(.tabs, shown: false) } onChange: { flag.hit = true }
        e.begin(width: width); e.move(0); e.move(120); e.move(300)
        #expect(!flag.hit)                                     // ни начало жеста, ни движение её не будят
        #expect(e.baseOffset(.tabs, shown: false) == 0)
        #expect(e.baseOffset(.planner, shown: false) == 0)
        e.cancel()
    }

    @Test func shownTabFollowsFingerAndEqualsPlainBase() {
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        e.begin(width: width); e.move(60)
        let flag = Flag()
        withObservationTracking { _ = e.baseOffset(.tabs, shown: true) } onChange: { flag.hit = true }
        e.move(110)
        #expect(flag.hit)                                      // видимая вкладка идёт за пальцем
        #expect(e.baseOffset(.tabs, shown: true) == e.baseOffset(.tabs))
        #expect(abs(e.baseOffset(.tabs, shown: true) - (-0.3 * (width - 110))) < 0.001)
        e.cancel()
    }

    @Test func shadeIsAStripThatFadesAndIsNeverThereAtRest() {
        #expect(EdgeBackRule.shadeFade(dx: 0, width: width) == 1)
        #expect(EdgeBackRule.shadeFade(dx: width / 2, width: width) == 0.5)
        #expect(EdgeBackRule.shadeFade(dx: width, width: width) == 0)
        #expect(EdgeBackRule.shadeFade(dx: -20, width: width) == 1)       // за пределы не выходит
        #expect(EdgeBackRule.shadeFade(dx: width + 20, width: width) == 0)
        #expect(EdgeBackRule.shadeOpacity == 0.18 && EdgeBackRule.shadeWidth == 20)
        // В покое «верхним» не считается никто: полоса прозрачна, под содержимым тени нет.
        let box = Box()
        let (e, ids) = edge([1.0, 1.52], box: box)
        #expect(!e.isTop(ids[1.52]!) && !e.isTop(ids[1.0]!))
        e.begin(width: width); e.move(0)
        #expect(e.isTop(ids[1.52]!) && !e.isTop(ids[1.0]!))               // тень — только у ведомого слоя
        e.cancel(); e.finishSettle()
        #expect(!e.isTop(ids[1.52]!))                                     // доехал — тени снова нет
    }

    @Test func cancelMidwayReturnsWithoutClosing() {
        // Систему оборвала жест на полпути: слой возвращается, ничего не закрыто, новый жест после доезда берётся.
        let box = Box()
        let (e, _) = edge([1.52], box: box)
        e.begin(width: width); e.move(0, at: 0); e.move(180, at: 0.1)
        e.cancel()
        #expect(e.settling && !e.dragging && e.pendingCommit == false)
        #expect(!e.canBegin)                                              // идёт доезд
        e.finishSettle()
        #expect(box.closed.isEmpty && e.dx == 0 && e.canBegin && e.closedCount == 0)
        #expect(e.begin(width: width))
        e.cancel(); e.finishSettle()
    }

    @Test func freshLayerTakesGestureRightAfterRegister() {
        // Слой записался в первом кадре въезда: жест сразу после тапа берётся и закрывает именно его.
        let box = Box()
        let e = EdgeBack()
        let id = UUID()
        e.register(id, z: 1.52) { box.closed.append(1.52) }
        #expect(e.canBegin && e.begin(width: width))
        e.move(30, at: 0); e.move(60, at: 0.05)
        e.end(at: 0.05)                                                   // 600 pt/с — быстрый короткий
        e.finishSettle()
        #expect(box.closed == [1.52])
    }

    @Test func twoGesturesInARowCloseTwoLayers() {
        // Слои закрывает состояние, дерево убирает их позже: закрытый жестом слой ещё записан, но второй жест берёт нижний.
        let box = Box()
        let (e, ids) = edge([1.0, 1.52], box: box)
        e.begin(width: width); e.move(200); e.end(velocity: 0)
        e.finishSettle()
        #expect(box.closed == [1.52] && e.top?.z == 1.0)                  // 1.52 всё ещё записан, но не кандидат
        #expect(e.begin(width: width))
        e.move(250); e.end(velocity: 0)
        e.finishSettle()
        #expect(box.closed == [1.52, 1.0] && e.closedCount == 2)
        _ = ids
    }

    @Test func slowAndFastSwipesDecideByDistanceAndSpeed() {
        let r = EdgeBackRule.commits
        #expect(r(width / 3 + 1, 20, width))                              // медленный, но дальше трети — закрыть
        #expect(!r(width / 3 - 1, 20, width))                             // медленный и короткий — вернуть
        #expect(r(40, 2000, width))                                       // очень быстрый и короткий — закрыть
        #expect(!r(width, -300, width))                                   // до края и резко назад — вернуть
    }

    #if DEBUG && os(iOS)
    @Test func meterCountsMissedFramesByDisplayPeriod() {
        let p = 1.0 / 60
        let s = EdgeBackMeter.stats([p, p, 2 * p, 3 * p, p], period: p)!
        #expect(s.n == 5 && s.missed == 3)                                // 0 + 0 + 1 + 2 + 0
        #expect(abs(s.max - 3 * p) < 1e-12)
        #expect(EdgeBackMeter.stats([], period: p) == nil)
        #expect(EdgeBackMeter.stats([p * 1.2, p * 0.8, p * 1.4], period: p)!.missed == 0)   // дрожь — не пропуск
        // На 120 Гц период вдвое короче: тот же интервал — на один пропуск больше.
        #expect(EdgeBackMeter.stats([p], period: p / 2)!.missed == 1)
    }

    @Test func meterQuantilesComeFromSortedSeries() {
        let dts = (1...20).map { Double($0) / 1000 }.reversed().map { $0 }   // 1…20 мс, в обратном порядке
        let s = EdgeBackMeter.stats(dts, period: 1.0 / 60)!
        #expect(abs(s.p50 - 0.011) < 1e-12 && abs(s.p95 - 0.020) < 1e-12 && abs(s.max - 0.020) < 1e-12)
    }
    #endif

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
