import SwiftUI

/// 31.9: минутный ход живого времени таймбара «Света» и «Карты». Один `Task`, который спит до границы минуты и зовёт
/// `followNow()`; никакой работы на кадр. Идёт только пока `running` (окно на экране и открыта «Свет» или «Карта»):
/// смена ключа снимает задачу, новая сразу догоняет часы. Двинутое пальцем время `followNow` не трогает.
struct LiveClock: ViewModifier {
    let timebar: TimebarState
    let running: Bool
    let now: @Sendable () -> Date

    func body(content: Content) -> some View {
        content.task(id: running) {
            guard running else { return }
            timebar.followNow()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(TimebarState.secondsToNextMinute(after: now())))
                guard !Task.isCancelled else { return }
                timebar.followNow()
            }
        }
    }
}

extension View {
    func liveClock(_ timebar: TimebarState, running: Bool, now: @escaping @Sendable () -> Date) -> some View {
        modifier(LiveClock(timebar: timebar, running: running, now: now))
    }
}
