import Foundation
import CoreGraphics
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Падающая звезда — пасхалка «тишина под звёздами» (веб, `spawnMeteor`).
/// Изредка, пока прибор докручен до звёзд и его не трогают, падает звезда;
/// любое касание возвращает тишину в исходное.
///
/// Момент и путь каждой звезды не сверяются с вебом — оба берут `Math.random`
/// не для физики продукта, а для того, чтобы небо не повторялось; посева тут
/// нет и в вебе. Числа диапазонов (угол, дальность, длительность) перенесены
/// как есть.
struct DomeMeteor: Identifiable {
    let id = UUID()
    let start: Date
    /// Точка появления на куполе, доли `viewBox`.
    let x0: Double
    let y0: Double
    /// Единичное направление полёта.
    let ux: Double
    let uy: Double
    /// Дальность в px и длительность полёта.
    let distance: Double
    let duration: TimeInterval

    static func spawn() -> DomeMeteor {
        let ux = (Double.random(in: 0..<1) < 0.5 ? -1.0 : 1.0) * (0.72 + Double.random(in: 0..<1) * 0.16)
        let uy = (1 - ux * ux).squareRoot()
        return DomeMeteor(
            start: Date(),
            x0: 60 + Double.random(in: 0..<1) * 270,
            y0: 14 + Double.random(in: 0..<1) * 95,
            ux: ux, uy: uy,
            distance: 80 + Double.random(in: 0..<1) * 70,
            duration: 0.65 + Double.random(in: 0..<1) * 0.5
        )
    }

    /// Хвост длиной 22 px, отставший от головы против направления полёта.
    var tail: CGPoint { CGPoint(x: CGFloat(-ux * 22), y: CGFloat(-uy * 22)) }

    /// Голова в момент `date`: линейно по пути, непройденный кусок не рисуется.
    func head(at date: Date) -> (point: CGPoint, opacity: Double)? {
        let k = date.timeIntervalSince(start) / duration
        guard k >= 0, k <= 1 else { return nil }
        let point = CGPoint(x: CGFloat(x0 + ux * distance * k), y: CGFloat(y0 + uy * distance * k))
        // Тот же ключевой кадр, что у вебовской WAAPI-анимации: 0 → 0.8 на
        // 18 % пути, затем плавно к 0 у конца.
        let opacity = k < 0.18 ? 0.8 * (k / 0.18) : 0.8 * (1 - (k - 0.18) / 0.82)
        return (point, opacity)
    }
}

/// Хозяин пасхалки: раз в 1,5 с решает, не уронить ли звезду — как
/// вебовский `setInterval`, только без глобального таймера страницы.
@MainActor
@Observable
final class DomeMeteorController {
    private(set) var active: [DomeMeteor] = []
    private var lastActivity = Date()
    private var timer: Timer?

    /// Звезда роняется только там, где небо уже видно — порог низкий
    /// нарочно: белой ночью звёзды едва проступают (≈0,3), но именно тогда
    /// падающая — редкий подарок (веб, тот же порог 0,22).
    var starsOpacity: () -> Double = { 1 }

    /// Экран не тревожат: снижена анимация в системе.
    private var reducedMotion: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        active.removeAll()
    }

    /// Касание интерфейса — тишина начинается заново.
    func noteActivity() {
        lastActivity = Date()
    }

    private func tick() {
        active.removeAll { Date().timeIntervalSince($0.start) > $0.duration }
        guard !reducedMotion else { return }
        guard Date().timeIntervalSince(lastActivity) >= 4 else { return }
        guard starsOpacity() >= 0.22 else { return }
        guard Double.random(in: 0..<1) < 0.32 else { return }
        active.append(.spawn())
    }
}
