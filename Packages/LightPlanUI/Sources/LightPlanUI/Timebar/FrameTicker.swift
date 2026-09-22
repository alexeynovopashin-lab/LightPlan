import QuartzCore

/// Тикер на кадр — тем же вопросом занимается `Transmission.dwell` и
/// доводка барабана: обоим нужен таймер, не привязанный к жесту.
///
/// `CADisplayLink(target:selector:)` проверен на живом телефоне (iOS,
/// `Spikes/TimebarSpike`: худший кадр 16,7 мс, 60 к/с) и остаётся там как
/// есть. У macOS-таргета нет этого инициализатора вовсе (там свой путь через
/// `NSScreen`), а точность кадра там не критична — довод и удержание на
/// трекпаде не то же самое, что палец на стекле, — поэтому вторая ветка
/// просто таймер на 60 Гц.
@MainActor
final class FrameTicker {
    private var handler: ((CFTimeInterval) -> Void)?

    #if os(iOS)
    private var link: CADisplayLink?
    var isActive: Bool { link != nil }
    #else
    private var timer: Timer?
    var isActive: Bool { timer != nil }
    #endif

    func start(_ handler: @escaping (CFTimeInterval) -> Void) {
        guard !isActive else { return }
        self.handler = handler
        #if os(iOS)
        let link = CADisplayLink(target: self, selector: #selector(fire(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        #else
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.handler?(CACurrentMediaTime())
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        #endif
    }

    func stop() {
        #if os(iOS)
        link?.invalidate()
        link = nil
        #else
        timer?.invalidate()
        timer = nil
        #endif
        handler = nil
    }

    #if os(iOS)
    @objc private func fire(_ link: CADisplayLink) {
        handler?(link.timestamp)
    }
    #endif
}
