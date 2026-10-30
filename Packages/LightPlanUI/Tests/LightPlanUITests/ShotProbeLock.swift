import Foundation

/// `ShotProbe.shared` один на процесс, а тесты идут параллельно: два экрана с одинаковыми именами узлов (`cal`, `head.0`) затирали бы
/// друг другу рамки. Тест, что читает рамки узлов, берёт замок на всё своё тело.
actor ProbeLock {
    static let shared = ProbeLock()
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }

    static func run(_ body: @MainActor () async throws -> Void) async throws {
        await shared.acquire()
        do { try await body() } catch { await shared.release(); throw error }
        await shared.release()
    }
}
