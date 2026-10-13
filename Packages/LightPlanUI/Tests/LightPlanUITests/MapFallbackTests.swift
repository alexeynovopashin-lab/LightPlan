import Testing
import Foundation
@testable import LightPlanMapCanvas

/// Часы теста: время идёт, только когда тест сказал `advance`. Окна в 60–250 мс на настоящих таймерах краснели
/// в полном наборе: очередь главного актора стоит за долгими тестами, и сторож взлетал на 1,7 с позже `start()`
/// (замер 12.10: `timeout=80 мс`, взлёт через 1676 мс, пробуждение через 4729 мс).
private final class ManualGateClock: @unchecked Sendable {
    private struct Waiter { let id: UUID; let until: Duration; let cont: CheckedContinuation<Void, Error> }
    private let lock = NSLock()
    private var current: Duration = .zero
    private var waiters: [Waiter] = []
    private var cancelled = Set<UUID>()

    var gate: GateClock {
        GateClock(now: { [self] in lock.lock(); defer { lock.unlock() }; return current },
                  sleep: { [self] until in try await sleep(until: until) })
    }

    func advance(by d: Duration) {
        lock.lock()
        current += d
        let ready = waiters.filter { $0.until <= current }
        waiters.removeAll { $0.until <= current }
        lock.unlock()
        for w in ready { w.cont.resume() }
    }

    private func sleep(until: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.lock(); defer { lock.unlock() }
                if cancelled.contains(id) || Task.isCancelled { c.resume(throwing: CancellationError()); return }
                if current >= until { c.resume(); return }
                waiters.append(Waiter(id: id, until: until, cont: c))
            }
        } onCancel: {
            lock.lock()
            cancelled.insert(id)
            let w = waiters.first { $0.id == id }
            waiters.removeAll { $0.id == id }
            lock.unlock()
            w?.cont.resume(throwing: CancellationError())
        }
    }
}

/// 28л.3: ключ CARTO в адресах стиля и сторож первой плитки.
@MainActor
struct MapFallbackGateTests {
    /// Источник, который молчит: не зовёт `tileArrived` — сторож срабатывает ровно один раз.
    @Test func silentSourceTriggersFallbackOnce() async {
        var fired = 0
        let clock = ManualGateClock()
        let gate = MapFallbackGate(timeout: .milliseconds(60), clock: clock.gate) { fired += 1 }
        gate.start()
        gate.start()
        clock.advance(by: .milliseconds(59))   // срок ещё не вышел
        #expect(gate.outcome == .waiting && fired == 0)
        clock.advance(by: .milliseconds(1))
        await gate.settled()
        #expect(gate.outcome == .silent && fired == 1 && gate.firstTileMs == nil)
        gate.tileArrived()   // плитка после срока — поздно, исход не меняется
        #expect(gate.outcome == .silent)
    }

    @Test func tileInTimeKeepsCarto() async {
        var fired = 0
        let clock = ManualGateClock()
        let gate = MapFallbackGate(timeout: .seconds(2), clock: clock.gate) { fired += 1 }
        gate.start()
        clock.advance(by: .milliseconds(20))
        gate.tileArrived()
        clock.advance(by: .seconds(5))
        await gate.settled()
        #expect(gate.outcome == .arrived && fired == 0)
        #expect(gate.firstTileMs == 20)
    }

    @Test func cancelledGateStaysQuiet() async {
        var fired = 0
        let clock = ManualGateClock()
        let gate = MapFallbackGate(timeout: .milliseconds(40), clock: clock.gate) { fired += 1 }
        gate.start()
        gate.cancel()
        clock.advance(by: .seconds(1))
        await gate.settled()
        #expect(fired == 0 && gate.outcome == .waiting)
    }

    /// Молчащий источник по замеру 28л.3: стиль встал, дальше только неполные кадры — «карта загружена» не приходит.
    @Test func styleAndPartialFramesAreNotData() async {
        var fired = 0
        let clock = ManualGateClock()
        let gate = MapFallbackGate(timeout: .milliseconds(80), clock: clock.gate) { fired += 1 }
        gate.start()
        gate.receive(.styleLoaded)
        for _ in 0..<36 { gate.receive(.partialFrame) }
        #expect(gate.outcome == .waiting)
        clock.advance(by: .milliseconds(80))
        await gate.settled()
        #expect(gate.outcome == .silent && fired == 1)
    }

    /// Над морем и пустым местом объектов на кадре нет, но «карта загружена» пришла — это приход данных.
    @Test func mapLoadedCountsWithoutLookingAtFeatures() async {
        var fired = 0
        let clock = ManualGateClock()
        let gate = MapFallbackGate(timeout: .milliseconds(150), clock: clock.gate) { fired += 1 }
        gate.start()
        gate.receive(.styleLoaded)
        gate.receive(.mapLoaded)
        clock.advance(by: .milliseconds(300))
        await gate.settled()
        #expect(gate.outcome == .arrived && fired == 0 && gate.firstTileMs == 0)
    }

    /// Срок считается от `start()`: задача сторожа может взлететь позже (очередь главного актора занята),
    /// но времени ей это не прибавляет.
    @Test func deadlineCountsFromStartNotFromWhenTheTaskGotToRun() async {
        var fired = 0
        let clock = ManualGateClock()
        let gate = MapFallbackGate(timeout: .milliseconds(100), clock: clock.gate) { fired += 1 }
        gate.start()
        clock.advance(by: .milliseconds(100))   // срок вышел, пока задача ещё не взлетела (мы не отдавали актор)
        #expect(fired == 0)
        await gate.settled()
        #expect(gate.outcome == .silent && fired == 1)
    }

    /// Боевые часы: срок настоящий, но тест ждёт события «сторож отработал», а не миллисекунды.
    @Test func realClockFiresAndMeasuresWithoutAWindow() async {
        var fired = 0
        let gate = MapFallbackGate(timeout: .milliseconds(10), clock: .real) { fired += 1 }
        gate.start()
        await gate.settled()
        #expect(gate.outcome == .silent && fired == 1)

        let quick = MapFallbackGate(timeout: .seconds(60), clock: .real) { fired += 1 }
        quick.start()
        quick.tileArrived()
        #expect(quick.outcome == .arrived && (quick.firstTileMs ?? -1) >= 0 && (quick.firstTileMs ?? Int.max) < 60_000 && fired == 1)
    }

    @Test func realTimeoutIsFourSeconds() { #expect(MapFallbackGate.timeout == .seconds(4)) }
}

struct CartoKeyTests {
    private let style = #"""
    {"glyphs":"https://tiles.basemaps.cartocdn.com/fonts/{fontstack}/{range}.pbf",
     "sprite":"https://tiles.basemaps.cartocdn.com/gl/voyager-gl-style/sprite",
     "sources":{"carto":{"type":"vector","tiles":["https://tiles-a.basemaps.cartocdn.com/vectortiles/carto.streets/v1/{z}/{x}/{y}.mvt","https://other.example/{z}.mvt"]}},
     "layers":[]}
    """#

    @Test func keyGoesToTilesAndGlyphsOnly() throws {
        let out = try #require(MapStyle.keyed(Data(style.utf8), key: "AB 12&x"))
        let obj = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect((obj["glyphs"] as? String)?.hasSuffix(".pbf?key=AB%2012%26x") == true)
        #expect(obj["sprite"] as? String == "https://tiles.basemaps.cartocdn.com/gl/voyager-gl-style/sprite")
        let tiles = try #require(((obj["sources"] as? [String: Any])?["carto"] as? [String: Any])?["tiles"] as? [String])
        #expect(tiles[0].hasSuffix("{y}.mvt?key=AB%2012%26x"))
        #expect(tiles[1] == "https://other.example/{z}.mvt")
    }

    @Test func bundledStylesKeepWorkingWithAndWithoutKey() throws {
        for dark in [false, true] {
            let plain = try #require(MapStyle.url(dark: dark, cartoKey: nil))
            #expect(!(try String(contentsOf: plain, encoding: .utf8)).contains("key="))
            let keyed = try #require(MapStyle.url(dark: dark, labels: true, cartoKey: "K1"))
            let text = try String(contentsOf: keyed, encoding: .utf8)
            #expect(text.contains("{y}.mvt?key=K1") && text.contains(".pbf?key=K1"))
        }
    }

    @Test func cacheNameFollowsKeyWithoutContainingIt() {
        func name(_ k: String?) -> String { MapStyle.cacheName(dark: true, nameKey: "name:ru", labels: true, cartoKey: k, silent: false) }
        #expect(name("secretKeyOne") != name("secretKeyTwo"))
        #expect(name("secretKeyOne") == name("secretKeyOne"))
        #expect(name(nil) != name("secretKeyOne"))
        #expect(!name("secretKeyOne").contains("secretKeyOne"))
        #expect(MapStyle.fingerprint("a").count == 8)
    }

    @Test func missingOrEmptyKeyFileMeansNoKeyNoCrash() throws {
        #expect(CartoKey.load(bundle: Bundle(for: Probe.self)) == nil)
        // Своя папка на случай: Bundle запоминает содержимое папки при первом обращении.
        func bundle(_ plist: String?) throws -> (Bundle, URL) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-carto-\(UUID().uuidString).bundle")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let plist {
                try Data("""
                <?xml version="1.0"?><plist version="1.0"><dict><key>LPCartoKey</key><string>\(plist)</string></dict></plist>
                """.utf8).write(to: dir.appendingPathComponent("carto.plist"))
            }
            return (try #require(Bundle(url: dir)), dir)
        }
        for (plist, want) in [(nil, nil), ("  ", nil), (" k9 ", "k9")] as [(String?, String?)] {
            let (b, dir) = try bundle(plist)
            defer { try? FileManager.default.removeItem(at: dir) }
            #expect(CartoKey.load(bundle: b) == want)
        }
    }

    private final class Probe {}
}
