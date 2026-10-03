import Testing
import Foundation
@testable import LightPlanData

/// Итерация 28м, шаг 3: очередь закачки пинов доски — прогресс, остановка, обрыв, повтор, без дублей.
struct PinterestImportTests {

    /// Сценарий: что отвечает `image(at:)` на адрес; считает, сколько запросов шло одновременно.
    actor Fake: PinterestReading {
        var script: [String: [PinterestFailure?]]      // по адресу: очередной ответ; nil — картинка
        var calls: [String: Int] = [:]
        var inFlight = 0
        var peak = 0
        var delay: Duration
        init(script: [String: [PinterestFailure?]] = [:], delay: Duration = .milliseconds(5)) { self.script = script; self.delay = delay }

        func board(link: String) async throws -> PinterestBoard { PinterestBoard(name: "", pinCount: 0, truncated: false, pins: []) }
        func preview(of page: String) async throws -> Data { Data([1]) }
        func image(at address: String) async throws -> Data {
            inFlight += 1; peak = max(peak, inFlight); calls[address, default: 0] += 1
            defer { inFlight -= 1 }
            try await Task.sleep(for: delay)
            if var q = script[address], !q.isEmpty {
                let first = q.removeFirst()
                script[address] = q.isEmpty ? [first] : q      // последний ответ повторяется
                if let f = first { throw f }
            }
            return Data(address.utf8)
        }
        var snapshot: (peak: Int, calls: [String: Int]) { (peak, calls) }
    }

    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var _added: [String] = []; private var _batches: [Int] = []; private var _progress: [Int] = []
        var known: Set<String>
        init(known: Set<String> = []) { self.known = known }
        var added: [String] { lock.lock(); defer { lock.unlock() }; return _added }
        var batches: [Int] { lock.lock(); defer { lock.unlock() }; return _batches }
        var progress: [Int] { lock.lock(); defer { lock.unlock() }; return _progress }
        func commit(_ b: [PinFetched]) -> [PinCommit] {
            lock.lock(); defer { lock.unlock() }
            _batches.append(b.count)
            return b.map { f in
                if known.contains(f.pin.id) { return .duplicate }
                known.insert(f.pin.id); _added.append(f.pin.id); return .added
            }
        }
        func tick(_ n: Int) { lock.lock(); _progress.append(n); lock.unlock() }
    }

    private func pins(_ n: Int) -> [PinterestPin] {
        (1...max(n, 1)).prefix(n).map { PinterestPin(id: "\($0)", permalink: "https://www.pinterest.com/pin/\($0)/", image: "img\($0)") }
    }

    private func run(_ list: [PinterestPin], _ fake: Fake, _ sink: Sink, concurrency: Int = 5, batch: Int = 6,
                     streak: Int = 6) async -> PinImportResult {
        await runPinImport(pins: list, reader: fake, concurrency: concurrency, batchSize: batch, retryDelay: .zero, maxStreak: streak,
                           progress: { p, _ in sink.tick(p) }, commit: { sink.commit($0) })
    }

    // MARK: размеры досок

    @Test(arguments: [1, 6, 100])
    func wholeBoardLands(n: Int) async {
        let fake = Fake(), sink = Sink()
        let r = await run(pins(n), fake, sink)
        #expect(r.added == n && r.done && r.pending.isEmpty && r.total == n)
        #expect(Set(sink.added).count == n)
        #expect(sink.progress.last == n)
    }

    @Test func oneHundredFiftyArrivesAsTheFirstHundredWithTruncatedBoard() async throws {
        // Читалка режет доску на 100 и говорит об этом (`truncated`); клиент приносит 100 пинов и 150 в `pinCount`.
        let list = (1...100).map { """
            {"id":"\($0)","permalink":"https://www.pinterest.com/pin/\($0)/","image":"https://i.pinimg.com/736x/\($0).jpg"}
            """ }.joined(separator: ",")
        let body = #"{"name":"Большая","pinCount":150,"truncated":true,"pins":[\#(list)]}"#
        let c = PinterestClient(config: PinterestConfig(key: "k")) { req in
            (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let b = try await c.board(link: "https://pin.it/x")
        #expect(b.pins.count == 100 && b.pinCount == 150 && b.truncated)
    }

    @Test func concurrencyNeverExceedsTheLimit() async {
        let fake = Fake(delay: .milliseconds(20)), sink = Sink()
        _ = await run(pins(40), fake, sink, concurrency: 5)
        let s = await fake.snapshot
        #expect(s.peak <= 5 && s.peak >= 2)
    }

    @Test func batchesAreWrittenInGroupsNotOneByOne() async {
        let fake = Fake(), sink = Sink()
        _ = await run(pins(20), fake, sink, batch: 6)
        #expect(sink.batches.reduce(0, +) == 20)
        #expect(sink.batches.count <= 4 && sink.batches.max()! <= 6)
    }

    // MARK: повторный импорт

    @Test func importingTheSameBoardAgainAddsNothing() async {
        let fake = Fake(), sink = Sink()
        let first = await run(pins(10), fake, sink)
        let second = await run(pins(10), fake, sink)
        #expect(first.added == 10)
        #expect(second.added == 0 && second.duplicates == 10 && second.done)
        #expect(sink.added.count == 10)
    }

    @Test func samePinListedTwiceIsFetchedOnce() async {
        let fake = Fake(), sink = Sink()
        let r = await run(pins(5) + pins(5), fake, sink)
        #expect(r.added == 5 && r.total == 5)
        #expect(await fake.snapshot.calls.values.allSatisfy { $0 == 1 })
    }

    // MARK: сбои

    @Test func transientFailureIsRetriedOnce() async {
        let fake = Fake(script: ["img3": [.serverDown, nil]]), sink = Sink()
        let r = await run(pins(5), fake, sink)
        #expect(r.added == 5 && r.failed == 0)
        #expect(await fake.snapshot.calls["img3"] == 2)
    }

    @Test func persistentFailureIsReportedAndRetryableLater() async {
        let fake = Fake(script: ["img3": [.serverDown]]), sink = Sink()
        let r = await run(pins(5), fake, sink)
        #expect(r.added == 4 && r.failed == 1 && r.pending.map(\.id) == ["3"] && r.interrupted == nil)
        #expect(await fake.snapshot.calls["img3"] == 2)            // один повтор, не больше
        // «Повторить»: те же пины, что остались; добавленные не дублируются, упавший теперь отвечает.
        let fixed = Fake(), again = await run(r.pending, fixed, sink)
        #expect(again.added == 1 && again.done && sink.added.count == 5)
    }

    @Test func pinWithoutPictureDoesNotStopTheBoard() async {
        let fake = Fake(script: ["img2": [.notFound]]), sink = Sink()
        let r = await run(pins(6), fake, sink)
        #expect(r.added == 5 && r.failed == 1 && r.interrupted == nil)
        #expect(await fake.snapshot.calls["img2"] == 1)            // «нет картинки» не повторяется
    }

    @Test func networkDropInTheMiddleStopsTheQueueAndKeepsWhatCame() async {
        var script: [String: [PinterestFailure?]] = [:]
        for i in 21...40 { script["img\(i)"] = [.offline] }
        let fake = Fake(script: script), sink = Sink()
        let r = await run(pins(40), fake, sink, concurrency: 4)
        #expect(r.interrupted == .offline && !r.stopped)
        #expect(r.added >= 20 && r.added < 40)
        #expect(r.added + r.pending.count == 40)                    // каждый пин либо записан, либо ждёт повтора
        #expect(Set(sink.added).count == sink.added.count)
        let calls = await fake.snapshot.calls.count
        #expect(calls < 40)                                         // очередь не долбила оставшиеся
    }

    @Test func slowNetworkTimeoutsInARowStopTheQueue() async {
        var script: [String: [PinterestFailure?]] = [:]
        for i in 1...50 { script["img\(i)"] = [.timeout] }
        let fake = Fake(script: script), sink = Sink()
        let r = await run(pins(50), fake, sink, concurrency: 3, streak: 4)
        #expect(r.interrupted == .timeout && r.added == 0)
        #expect(await fake.snapshot.calls.count < 50)
    }

    @Test func missingKeyIsReportedBeforeAnything() async {
        let fake = Fake(script: ["img1": [.notConfigured]]), sink = Sink()
        let r = await run(pins(10), fake, sink, concurrency: 1)
        #expect(r.interrupted == .notConfigured && r.added == 0 && r.pending.count == 10)
    }

    // MARK: остановка

    @Test func stopInTheMiddleKeepsWhatArrivedAndDropsTheRest() async {
        let fake = Fake(delay: .milliseconds(15)), sink = Sink()
        let task = Task { await run(pins(100), fake, sink, concurrency: 4) }
        try? await Task.sleep(for: .milliseconds(120))
        task.cancel()
        let r = await task.value
        #expect(r.stopped && !r.done)
        #expect(r.added > 0 && r.added < 100)
        #expect(r.added + r.pending.count == 100)
        #expect(r.failed == 0)                                       // остановка не сбой
        #expect(Set(sink.added).count == sink.added.count)
        // Повтор после остановки доводит доску до конца без дублей.
        let rest = await run(r.pending, Fake(), sink)
        #expect(rest.done && sink.added.count == 100 && rest.duplicates == 0)
    }

    @Test func rejectedWritesStayPending() async {
        let fake = Fake()
        let r = await runPinImport(pins: pins(4), reader: fake, concurrency: 2, batchSize: 2, retryDelay: .zero,
                                   progress: { _, _ in }, commit: { $0.map { $0.pin.id == "3" ? .rejected : .added } })
        #expect(r.added == 3 && r.failed == 1 && r.pending.map(\.id) == ["3"])
    }
}
