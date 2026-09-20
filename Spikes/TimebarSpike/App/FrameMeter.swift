import QuartzCore

/// Счётчик кадров на время жеста. Нужен, чтобы «60 кадров при ведении» было
/// числом, а не ощущением: экран телефона сам по себе выглядит гладко, пока
/// не посмотришь на худший кадр.
///
/// На ProMotion (15 Pro) экран идёт до 120 Гц, поэтому меряем и среднее, и
/// худший кадр в миллисекундах, а не «есть ли 60».
@MainActor
final class FrameMeter {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var total: CFTimeInterval = 0

    private(set) var worstMs = 0.0
    private(set) var averageFps = 0.0
    /// Кадры дольше 1/60 с — те, что глаз видит как рывок.
    private(set) var late = 0

    func start() {
        stop()
        last = 0
        frames = 0
        total = 0
        worstMs = 0
        averageFps = 0
        late = 0
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last != 0 else { return }
        let dt = link.timestamp - last
        frames += 1
        total += dt
        worstMs = max(worstMs, dt * 1000)
        if dt > 1.0 / 60 + 0.001 { late += 1 }
        averageFps = total > 0 ? Double(frames) / total : 0
    }
}
