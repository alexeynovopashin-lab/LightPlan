import Foundation
import LightPlanDomain
#if os(iOS)
import ActivityKit
#endif

/// Что сейчас показано на экране блокировки: съёмка, когда запрошено и последний кадр.
struct ActivityShown: Equatable {
    var shootId: String
    var startedAt: Date
    var frame: ActivityFrame
}

/// Система экрана активности — шов, как `NotificationCentering` у уведомлений: приложение решает (`AppModel+Activity`), этот слой
/// только просит у системы. Настоящий (`ActivityKitHost`) — единственный, кто знает ActivityKit; в тестах и снимках стоит подставной.
@MainActor
protocol ActivityHosting: AnyObject {
    /// Человек разрешил экран активности для приложения (iPhone → Настройки). Запрещено — не запрашиваем и не жалуемся.
    var allowed: Bool { get }
    /// Живая активность этого приложения (после перезапуска приложения система её помнит); закончившиеся не считаются.
    var shown: ActivityShown? { get }
    /// Запросить новую. Бросает, если система отказала (нет разрешения, слишком много активностей).
    func start(_ frame: ActivityFrame, startedAt: Date) throws
    func update(_ frame: ActivityFrame) async
    /// Закрыть сразу: съёмка кончилась, нажали «Завершить» или это перезапуск длинного дня.
    func end() async
    /// Человек убрал плашку с экрана блокировки сам (не мы и не система): пока съёмка та же, заново не запрашиваем.
    var onDismissed: ((String) -> Void)? { get set }
}

#if os(iOS)
@MainActor
final class ActivityKitHost: ActivityHosting {
    var onDismissed: ((String) -> Void)?
    /// Закрытые нами: их `dismissed` — не жест человека.
    private var closedByUs: Set<String> = []
    private var watching: Set<String> = []

    var allowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    nonisolated private static var live: [Activity<ShootActivityAttributes>] {
        Activity<ShootActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    var shown: ActivityShown? {
        guard let a = Self.live.first else { return nil }
        watch(a)
        return ActivityShown(shootId: a.attributes.shootId, startedAt: a.attributes.startedAt, frame: a.content.state)
    }

    func start(_ frame: ActivityFrame, startedAt: Date) throws {
        let a = try Activity.request(attributes: ShootActivityAttributes(shootId: frame.shootId, startedAt: startedAt),
                                     content: .init(state: frame, staleDate: nil), pushType: nil)
        watch(a)
    }

    // `Activity` не `Sendable`: с главного актора его не передать в `async`-вызов системы, поэтому вся работа с ним — в
    // неизолированных помощниках, где он не покидает своего контекста.
    func update(_ frame: ActivityFrame) async { await Self.updateAll(frame) }

    func end() async {
        closedByUs.formUnion(Self.live.map(\.id))
        await Self.endAll()
    }

    nonisolated private static func updateAll(_ frame: ActivityFrame) async {
        for a in live { await a.update(.init(state: frame, staleDate: nil)) }
    }

    nonisolated private static func endAll() async {
        for a in live { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// Следим за каждой своей активностью один раз: `dismissed`, которого не звали мы и не система (она сначала говорит `ended`),
    /// — человек смахнул плашку.
    private func watch(_ a: Activity<ShootActivityAttributes>) {
        guard watching.insert(a.id).inserted else { return }
        let id = a.id, shoot = a.attributes.shootId
        Task { [weak self] in
            var endedBySystem = false
            for await state in a.activityStateUpdates {
                if state == .ended { endedBySystem = true }
                if state == .dismissed {
                    await MainActor.run {
                        guard let self else { return }
                        if !endedBySystem, !self.closedByUs.contains(id) { self.onDismissed?(shoot) }
                        self.watching.remove(id)
                    }
                }
            }
        }
    }
}
#endif
