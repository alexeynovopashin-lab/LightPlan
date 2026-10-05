import Testing
import Foundation
@testable import LightPlanData

// MARK: - Подставное

/// Проба, которую тест переставляет: ответила / отказала / висит (отмену слышит, как `URLSession`).
private actor ScriptedProbe: ReachProbe {
    enum Mode: Sendable { case answers, refuses, hangs, deaf }
    private var mode: Mode
    private(set) var calls = 0
    private var gate: CheckedContinuation<Bool, Never>?
    init(_ mode: Mode) { self.mode = mode }
    func set(_ m: Mode) { mode = m }
    /// Отпустить «глухую» пробу с таким ответом: отмену она не слышит, поэтому её ответ придёт позже нового.
    func release(_ answer: Bool) { gate?.resume(returning: answer); gate = nil }

    func probe() async -> Bool {
        calls += 1
        switch mode {
        case .answers: return true
        case .refuses: return false
        case .hangs:
            do { try await Task.sleep(for: .seconds(3600)) } catch {}
            return false
        case .deaf:
            return await withCheckedContinuation { gate = $0 }
        }
    }
}

/// Путь, которым управляет тест: `send(true)` — сеть есть, `send(false)` — нет.
private final class ScriptedPath: NetworkReachability, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Bool>.Continuation?
    func updates() -> AsyncStream<Bool> {
        AsyncStream { c in lock.lock(); continuation = c; lock.unlock() }
    }
    func send(_ online: Bool) { lock.lock(); let c = continuation; lock.unlock(); c?.yield(online) }
}

/// «Срок пробы вышел сразу» и «пауза между проверками не кончится никогда».
private let timeoutNow: @Sendable (Duration) async throws -> Void = { _ in }
private let neverPause: @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) }

private actor Durations {
    private(set) var asked: [Duration] = []
    func note(_ d: Duration) { asked.append(d) }
}

/// Ждать, пока условие станет верным (до 3 с настоящих): опрос, а не часы.
private func until(_ what: String = "", _ cond: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<600 {
        if await cond() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

// MARK: - Детектор

struct ForeignReachDetectorTests {

    @Test("Срок пробы — 3 с, перепроверка: доступно — 10 мин, недоступно — 2 мин")
    func constants() {
        #expect(ForeignReachDetector.probeTimeout == .seconds(3))
        #expect(ForeignReachDetector.intervalWhenReachable == .seconds(600))
        #expect(ForeignReachDetector.intervalWhenUnreachable == .seconds(120))
    }

    @Test("Проба молчит дольше срока — «недоступно»; ответила — «доступно»; перепроверка возвращает назад")
    func timeoutThenBack() async {
        let probe = ScriptedProbe(.hangs)
        let d = ForeignReachDetector(probe: probe, sleep: timeoutNow, pause: neverPause)
        #expect(await d.state == .unknown)
        #expect(await d.recheck() == .unreachable)
        await probe.set(.answers)
        #expect(await d.recheck() == .reachable)
        await probe.set(.hangs)
        #expect(await d.recheck() == .unreachable)
    }

    @Test("Отказ соединения — тоже «недоступно»")
    func refusal() async {
        let d = ForeignReachDetector(probe: ScriptedProbe(.refuses), sleep: neverPause, pause: neverPause)
        #expect(await d.recheck() == .unreachable)
    }

    @Test("Параллельные проверки одной сети делят одну пробу")
    func concurrentRechecksShareOneProbe() async {
        let probe = ScriptedProbe(.answers)
        let d = ForeignReachDetector(probe: probe, sleep: neverPause, pause: neverPause)
        async let a = d.recheck()
        async let b = d.recheck()
        async let c = d.recheck()
        let all = await [a, b, c]
        #expect(all == [.reachable, .reachable, .reachable])
        #expect(await probe.calls == 1)
    }

    @Test("Смена сети: состояние сбрасывается и проба идёт заново; сети нет — «неизвестно» и без пробы")
    func networkChangeRechecks() async {
        let probe = ScriptedProbe(.answers)
        let path = ScriptedPath()
        let d = ForeignReachDetector(probe: probe, reachability: path, sleep: neverPause, pause: neverPause)
        await d.start()
        path.send(true)
        #expect(await until { await d.state == .reachable })
        #expect(await probe.calls == 1)

        // Перешли на сеть, где зарубежное закрыто.
        await probe.set(.refuses)
        path.send(true)
        #expect(await until { await d.state == .unreachable })
        #expect(await probe.calls == 2)

        // Сети нет: ответ прошлой сети не держим, пробу не тратим.
        path.send(false)
        #expect(await until { await d.state == .unknown })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await probe.calls == 2)

        // Сеть вернулась, и зарубежное снова открыто.
        await probe.set(.answers)
        path.send(true)
        #expect(await until { await d.state == .reachable })
        #expect(await probe.calls == 3)
        await d.stop()
    }

    @Test("Проба старой сети опоздала и ответила «недоступно» — после ответа новой сети его не принимаем")
    func staleAnswerIsDropped() async {
        let probe = ScriptedProbe(.deaf)
        let path = ScriptedPath()
        let d = ForeignReachDetector(probe: probe, reachability: path, sleep: neverPause, pause: neverPause)
        await d.start()
        path.send(true)                                    // проба 1 застряла и отмену не слышит
        #expect(await until { await probe.calls == 1 })
        await probe.set(.answers)
        path.send(true)                                    // сеть сменилась: проба 2 ответила
        #expect(await until { await d.state == .reachable })
        await probe.release(false)                         // проба 1 наконец ответила «нет» — про прежнюю сеть
        try? await Task.sleep(for: .milliseconds(80))
        #expect(await d.state == .reachable)
        await d.stop()
    }

    @Test("Таймер: после «доступно» ждём 10 мин, после «недоступно» — 2 мин, и проверяет снова")
    func pollingUsesTheStateInterval() async {
        let probe = ScriptedProbe(.refuses)
        let waits = Durations()
        // Первая пауза возвращается сразу, остальные — вечные: ровно одна перепроверка по таймеру.
        let first = Durations()
        let d = ForeignReachDetector(probe: probe, sleep: neverPause,
                                     pause: { dur in
                                         await waits.note(dur)
                                         if await first.asked.isEmpty { await first.note(dur); return }
                                         try await Task.sleep(for: .seconds(3600))
                                     })
        _ = await d.recheck()                               // недоступно
        await d.start()
        #expect(await until { await probe.calls == 2 })    // таймер сам перепроверил
        #expect(await waits.asked.first == .seconds(120))
        await probe.set(.answers)
        await d.stop()
    }

    @Test("Подписчик получает нынешнее состояние и перемены")
    func changesStream() async {
        let probe = ScriptedProbe(.answers)
        let d = ForeignReachDetector(probe: probe, sleep: neverPause, pause: neverPause)
        var seen: [ForeignReach] = []
        let stream = await d.changes()
        _ = await d.recheck()
        await probe.set(.refuses)
        _ = await d.recheck()
        for await s in stream {
            seen.append(s)
            if seen.count == 3 { break }
        }
        #expect(seen == [.unknown, .reachable, .unreachable])
    }
}

// MARK: - Боевая проба

/// Подставной ответ сети: тест решает, что вернуть на `HEAD`.
private final class StubNet: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status: Int? = 200
    nonisolated(unsafe) static var lastMethod: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastMethod = request.httpMethod
        if let status = Self.status {
            let r = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        }
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct HeadProbeTests {
    @Test("HEAD на api.open-meteo.com; любой HTTP-ответ — «открыт», сбой — «закрыт»")
    func headMeansReachable() async {
        let probe = HeadProbe(protocolClasses: [StubNet.self])
        StubNet.status = 200
        #expect(await probe.probe())
        #expect(StubNet.lastMethod == "HEAD")
        StubNet.status = 503
        #expect(await probe.probe())
        StubNet.status = nil
        #expect(await probe.probe() == false)
        #expect(HeadProbe.defaultURL.host == "api.open-meteo.com")
    }
}
