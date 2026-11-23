import Foundation
import Testing
@testable import LightPlanData

/// Подложное ядро: помнит вызовы, отвечает по сценарию.
final class FakeCore: CoreClient, @unchecked Sendable {
    let lock = NSLock()
    var calls: [String] = []
    var avatars: [Data] = []
    var down = false
    var badPassOnce = false
    var issued = 0

    func log(_ s: String) throws {
        try lock.withLock {
            calls.append(s)
            if down { throw CoreFailure.unavailable }
        }
    }
    func register(_ r: CoreRegistration) async throws -> CoreDevice {
        try log("register \(r.appId) \(r.country)")
        return lock.withLock { issued += 1; return CoreDevice(deviceId: "dv_\(issued)", pass: "p\(issued)", idState: "unconfirmed", home: CoreHome.of(country: r.country), appId: r.appId) }
    }
    func move(_ d: CoreDevice, to appId: String, at: Date) async throws { try log("move \(d.appId)>\(appId)") }
    func putAvatar(_ jpeg: Data, device: CoreDevice) async throws {
        try log("put \(device.pass)")
        try lock.withLock {
            if badPassOnce { badPassOnce = false; throw CoreFailure.badPass }
            avatars.append(jpeg)
        }
    }
    func deleteAvatar(device: CoreDevice) async throws { try log("delAvatar \(device.pass)") }
    func deleteMe(device: CoreDevice) async throws { try log("delMe \(device.pass)") }
}

@Suite("Связь с ядром (31.13)")
struct CoreLinkTests {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    func input(_ avatar: Data?, appId: String = "id79161234567", country: String = "RU") -> CoreSync.Input {
        CoreSync.Input(avatar: avatar, appId: appId, country: country, appVersion: "1.0 (1)", name: nil, now: Date(timeIntervalSince1970: 0))
    }

    @Test func homeFollowsTheNumbersCountry() {
        #expect(CoreHome.of(country: "RU") == .ru)
        #expect(CoreHome.of(country: "kz") == .ru)
        #expect(CoreHome.of(country: "BY") == .ru)
        #expect(CoreHome.of(country: "DE") == .world)
        #expect(CoreHome.of(country: "US") == .world)
    }

    @Test func firstPhotoRegistersAndUploads() async {
        let core = FakeCore(), passes = InMemoryCorePassStore()
        let q = await CoreSync.run(CoreQueue(avatar: true), input(jpeg), client: core, passes: passes)
        #expect(q.isEmpty)
        #expect(core.calls == ["register id79161234567 RU", "put p1"])
        #expect(core.avatars == [jpeg])
        #expect(passes.load()?.home == .ru)
    }

    @Test func noMobileNumberMeansNoRegistrationAndThePhotoWaits() async {
        let core = FakeCore()
        let q = await CoreSync.run(CoreQueue(avatar: true), input(jpeg, appId: ""), client: core, passes: InMemoryCorePassStore())
        #expect(q.avatar)
        #expect(core.calls.isEmpty)
    }

    @Test func absentServerKeepsEverythingQueuedWithoutCalls() async {
        let passes = InMemoryCorePassStore()
        let q = await CoreSync.run(CoreQueue(avatar: true, forget: false), input(jpeg), client: AbsentCoreClient(), passes: passes)
        #expect(q == CoreQueue(avatar: true))
        #expect(passes.load() == nil)
    }

    @Test func outageLeavesThePhotoQueued() async {
        let core = FakeCore(); core.down = true
        let q = await CoreSync.run(CoreQueue(avatar: true), input(jpeg), client: core, passes: InMemoryCorePassStore())
        #expect(q.avatar)
    }

    @Test func forgottenPassRegistersAgainOnce() async {
        let core = FakeCore(); core.badPassOnce = true
        let passes = InMemoryCorePassStore(CoreDevice(deviceId: "dv_old", pass: "old", idState: "unconfirmed", home: .ru, appId: "id79161234567"))
        let q = await CoreSync.run(CoreQueue(avatar: true), input(jpeg), client: core, passes: passes)
        #expect(q.isEmpty)
        #expect(core.calls == ["put old", "register id79161234567 RU", "put p1"])
    }

    @Test func removedPhotoIsErasedOnServerOnlyIfRegistered() async {
        let core = FakeCore()
        var q = await CoreSync.run(CoreQueue(avatar: true), input(nil), client: core, passes: InMemoryCorePassStore())
        #expect(q.isEmpty && core.calls.isEmpty)
        let passes = InMemoryCorePassStore(CoreDevice(deviceId: "d", pass: "p", idState: "unconfirmed", home: .world, appId: "id79161234567"))
        q = await CoreSync.run(CoreQueue(avatar: true), input(nil), client: core, passes: passes)
        #expect(q.isEmpty)
        #expect(core.calls == ["delAvatar p"])
    }

    @Test func forgetErasesEverythingThenDropsThePass() async {
        let core = FakeCore()
        let passes = InMemoryCorePassStore(CoreDevice(deviceId: "d", pass: "p", idState: "unconfirmed", home: .ru, appId: "id79161234567"))
        let q = await CoreSync.run(CoreQueue(forget: true), input(nil), client: core, passes: passes)
        #expect(q.isEmpty)
        #expect(core.calls == ["delMe p"])
        #expect(passes.load() == nil)
    }

    @Test func forgetWaitsWhileTheServerIsAbsentAndKeepsThePass() async {
        let dev = CoreDevice(deviceId: "d", pass: "p", idState: "unconfirmed", home: .ru, appId: "id79161234567")
        let passes = InMemoryCorePassStore(dev)
        let q = await CoreSync.run(CoreQueue(forget: true), input(nil), client: AbsentCoreClient(), passes: passes)
        #expect(q.forget)
        #expect(passes.load() == dev)
    }

    @Test func forgetWithoutRegistrationNeedsNoCall() async {
        let core = FakeCore()
        let q = await CoreSync.run(CoreQueue(forget: true), input(nil), client: core, passes: InMemoryCorePassStore())
        #expect(q.isEmpty && core.calls.isEmpty)
    }

    @Test func newNumberMovesTheDevice() async {
        let core = FakeCore()
        let passes = InMemoryCorePassStore(CoreDevice(deviceId: "d", pass: "p", idState: "unconfirmed", home: .ru, appId: "id79160000000"))
        _ = await CoreSync.run(CoreQueue(avatar: true), input(jpeg), client: core, passes: passes)
        #expect(core.calls == ["move id79160000000>id79161234567", "put p"])
        #expect(passes.load()?.appId == "id79161234567")
    }

    // MARK: HTTP по договору сервера (31.14: дом ru — `?op=…` и `X-Core-Pass`)

    /// Подложная сеть: `health` отвечает своим телом, прочие разделы — `reply`. Помнит всё отправленное.
    final class Wire: CloudTransport, @unchecked Sendable {
        let lock = NSLock()
        var sent: [URLRequest] = []
        var health: (Int, String) = (200, #"{"ok":true,"core":"0.1.0","home":"ru","time":"2026-11-24T10:00:00Z","api":["devices","avatar"]}"#)
        var reply: (Int, Data) = (204, Data())
        var offline = false
        func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let (code, body): (Int, Data) = try lock.withLock {
                sent.append(r)
                if offline { throw CloudFailure.offline }
                return Wire.op(r) == "health" ? (health.0, Data(health.1.utf8)) : reply
            }
            return (body, HTTPURLResponse(url: r.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
        static func op(_ r: URLRequest) -> String? {
            r.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == "op" }?.value
                ?? r.url?.path.components(separatedBy: "/v1/").last
        }
        var ops: [String] { lock.withLock { sent.map { "\($0.httpMethod ?? "") \(Wire.op($0) ?? "?")" } } }
    }

    static let fn = CoreAddress(url: URL(string: "https://ru.example.invalid/fn")!, routing: .op)
    func client(_ wire: Wire, clock: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1000) }) -> HTTPCoreClient {
        HTTPCoreClient(base: { $0 == .ru ? Self.fn : nil }, transport: wire, clock: clock)
    }
    let device = CoreDevice(deviceId: "dv_1", pass: "dv_1.secret", idState: "unconfirmed", home: .ru, appId: "id79161234567")

    @Test func ruHomeChoosesSectionsByOpAndCarriesThePassInItsOwnHeader() async throws {
        let wire = Wire(), c = client(wire)
        wire.reply = (201, Data(#"{"deviceId":"dv_1","pass":"dv_1.secret","idState":"unconfirmed","home":"ru"}"#.utf8))
        let d = try await c.register(CoreRegistration(appId: "id79161234567", country: "RU", appVersion: "1.0 (1)", name: nil))
        #expect(d == device)
        wire.reply = (200, Data(#"{"sha256":"x","size":4}"#.utf8))
        try await c.move(d, to: "id79169999999", at: Date(timeIntervalSince1970: 0))
        try await c.putAvatar(jpeg, device: d)
        wire.reply = (204, Data())
        try await c.deleteAvatar(device: d)
        try await c.deleteMe(device: d)

        // Health спрошен один раз и первым; дальше — только разделы из `api`.
        #expect(wire.ops == ["GET health", "POST devices", "PATCH devices/me", "PUT me/avatar", "DELETE me/avatar", "DELETE me"])
        #expect(wire.sent.map { $0.url!.absoluteString } == [
            "https://ru.example.invalid/fn?op=health", "https://ru.example.invalid/fn?op=devices",
            "https://ru.example.invalid/fn?op=devices/me", "https://ru.example.invalid/fn?op=me/avatar",
            "https://ru.example.invalid/fn?op=me/avatar", "https://ru.example.invalid/fn?op=me"])
        // Пропуск — только в X-Core-Pass; Authorization не уходит никогда (шлюз Яндекса отвечает на него 403).
        #expect(wire.sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(wire.sent.prefix(2).allSatisfy { $0.value(forHTTPHeaderField: "X-Core-Pass") == nil })
        #expect(wire.sent.dropFirst(2).allSatisfy { $0.value(forHTTPHeaderField: "X-Core-Pass") == "dv_1.secret" })

        let reg = wire.sent[1]
        let body = try JSONSerialization.jsonObject(with: reg.httpBody ?? Data()) as? [String: String]
        #expect(body == ["app": "lightplan", "appId": "id79161234567", "country": "RU", "appVersion": "1.0 (1)"])   // имени и города нет
        #expect(reg.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let patch = try JSONSerialization.jsonObject(with: wire.sent[2].httpBody ?? Data()) as? [String: String]
        #expect(patch == ["appId": "id79169999999", "previous": "id79161234567", "at": "1970-01-01T00:00:00Z"])
        #expect(wire.sent[3].value(forHTTPHeaderField: "Content-Type") == "image/jpeg" && wire.sent[3].httpBody == jpeg)
    }

    @Test func otherHomesKeepThePathRouting() {
        let a = CoreAddress(url: URL(string: "https://world.example.invalid")!, routing: .path)
        #expect(a.url("devices/me").absoluteString == "https://world.example.invalid/v1/devices/me")
        #expect(Self.fn.url("me").absoluteString == "https://ru.example.invalid/fn?op=me")
    }

    @Test func liveBuildKnowsOnlyTheRussianHome() {
        #expect(CoreAddress.live(.ru) == CoreAddress.ru)
        #expect(CoreAddress.live(.world) == nil)
        #expect(CoreAddress.ru.routing == .op)
        #expect(CoreAddress.ru.url("health").absoluteString == "https://functions.yandexcloud.net/d4ehnv8imbagj1vn50dd?op=health")
    }

    @Test func sectionMissingFromHealthIsNotCalled() async {
        let wire = Wire(), c = client(wire)
        wire.health = (200, #"{"ok":true,"home":"ru","api":["devices"]}"#)
        await #expect(throws: CoreFailure.unavailable) { try await c.putAvatar(jpeg, device: device) }
        await #expect(throws: CoreFailure.unavailable) { try await c.deleteAvatar(device: device) }
        #expect(wire.ops == ["GET health"])
        try? await c.deleteMe(device: device)     // «devices» есть — этот раздел зовётся
        #expect(wire.ops == ["GET health", "DELETE me"])
    }

    @Test func healthThatFailsStopsEveryCallAndIsAskedAgainNextTime() async throws {
        let wire = Wire(), c = client(wire)
        for bad in [(503, #"{"ok":false,"error":"not_configured"}"#), (200, #"{"ok":false,"api":["devices","avatar"]}"#),
                    (200, "<html>"), (403, ""), (200, #"{"ok":true,"home":"world","api":["devices","avatar"]}"#)] {
            wire.health = bad
            await #expect(throws: CoreFailure.unavailable) { try await c.putAvatar(jpeg, device: device) }
        }
        wire.offline = true
        await #expect(throws: CoreFailure.unavailable) { try await c.putAvatar(jpeg, device: device) }
        #expect(wire.ops == Array(repeating: "GET health", count: 6))   // неудача не запоминается, раздел не звали
        wire.offline = false
        wire.health = Wire().health
        wire.reply = (200, Data())
        try await c.putAvatar(jpeg, device: device)
        #expect(wire.ops.suffix(2) == ["GET health", "PUT me/avatar"])
    }

    @Test func goodHealthIsTrustedForTenMinutes() async throws {
        let wire = Wire()
        final class Clock: @unchecked Sendable { var t = Date(timeIntervalSince1970: 1000) }
        let clock = Clock()
        let c = client(wire, clock: { clock.t })
        wire.reply = (204, Data())
        try await c.deleteAvatar(device: device)
        clock.t += HTTPCoreClient.healthTTL - 1
        try await c.deleteAvatar(device: device)
        clock.t += 2
        try await c.deleteAvatar(device: device)
        #expect(wire.ops == ["GET health", "DELETE me/avatar", "DELETE me/avatar", "GET health", "DELETE me/avatar"])
    }

    @Test func serverAnswersMapToQuietFailures() async {
        let wire = Wire(), c = client(wire)
        let reg = CoreRegistration(appId: "id73822000001", country: "RU", appVersion: "1", name: nil)
        wire.reply = (400, Data(#"{"error":"bad_id"}"#.utf8))
        await #expect(throws: CoreFailure.badId) { _ = try await c.register(reg) }
        wire.reply = (400, Data(#"{"error":"wrong_home"}"#.utf8))
        await #expect(throws: CoreFailure.rejected(400)) { _ = try await c.register(reg) }
        wire.reply = (401, Data(#"{"error":"bad_pass"}"#.utf8))
        await #expect(throws: CoreFailure.badPass) { try await c.deleteMe(device: device) }
        wire.reply = (429, Data(#"{"error":"rate_limited"}"#.utf8))
        await #expect(throws: CoreFailure.rateLimited) { try await c.deleteMe(device: device) }
        wire.reply = (503, Data())
        await #expect(throws: CoreFailure.unavailable) { try await c.deleteMe(device: device) }
        wire.reply = (403, Data())
        await #expect(throws: CoreFailure.rejected(403)) { try await c.deleteMe(device: device) }
        wire.reply = (413, Data(#"{"error":"too_large"}"#.utf8))
        await #expect(throws: CoreFailure.rejected(413)) { try await c.putAvatar(jpeg, device: device) }
        wire.reply = (201, Data("not json".utf8))
        await #expect(throws: CoreFailure.unavailable) { _ = try await c.register(reg) }
    }

    @Test func homeWithoutAddressMakesNoRequest() async {
        let wire = Wire(), c = client(wire)
        await #expect(throws: CoreFailure.unavailable) {
            _ = try await c.register(CoreRegistration(appId: "id4915112345678", country: "DE", appVersion: "1", name: nil))
        }
        await #expect(throws: CoreFailure.unavailable) { _ = try await c.health(.world) }
        #expect(wire.sent.isEmpty)
    }

    /// Номер не из РФ и СНГ при живом доме ru: фото ждёт в очереди, в сеть не уходит ни одного запроса, ошибок нет.
    @Test func numberOutsideTheRussianHomeWaitsQuietly() async {
        let wire = Wire(), passes = InMemoryCorePassStore()
        let q = await CoreSync.run(CoreQueue(avatar: true), input(jpeg, appId: "id4915112345678", country: "DE"),
                                   client: client(wire), passes: passes)
        #expect(q == CoreQueue(avatar: true))
        #expect(wire.sent.isEmpty && passes.load() == nil)
        let f = await CoreSync.run(CoreQueue(forget: true), input(nil, appId: "id4915112345678", country: "DE"),
                                   client: client(wire), passes: passes)
        #expect(f.isEmpty && wire.sent.isEmpty)   // не регистрировался — стирать нечего
    }

    /// Номер РФ: весь путь очереди через HTTP — регистрация, фото, затем «Удалить мои данные».
    @Test func russianNumberGoesThroughTheWholeQueueOverHTTP() async {
        let wire = Wire(), passes = InMemoryCorePassStore(), c = client(wire)
        wire.reply = (201, Data(#"{"deviceId":"dv_1","pass":"dv_1.secret","idState":"unconfirmed","home":"ru"}"#.utf8))
        // Регистрация отвечает 201, загрузка фото — тем же кодом: для клиента это «успех».
        let q = await CoreSync.run(CoreQueue(avatar: true), input(jpeg), client: c, passes: passes)
        #expect(q.isEmpty && passes.load() == device)
        wire.reply = (204, Data())
        let f = await CoreSync.run(CoreQueue(forget: true), input(nil), client: c, passes: passes)
        #expect(f.isEmpty && passes.load() == nil)
        #expect(wire.ops == ["GET health", "POST devices", "PUT me/avatar", "DELETE me"])
    }

    /// Сервер лёг между проходами: пункт остаётся, пропуск сохраняется, человеку ничего не показывается.
    @Test func outageOverHTTPKeepsTheQueueAndThePass() async {
        let wire = Wire(), passes = InMemoryCorePassStore(device)
        wire.offline = true
        let q = await CoreSync.run(CoreQueue(avatar: true, forget: false), input(jpeg), client: client(wire), passes: passes)
        #expect(q == CoreQueue(avatar: true) && passes.load() == device)
        wire.offline = false
        wire.health = (503, "")
        let f = await CoreSync.run(CoreQueue(forget: true), input(nil), client: client(wire), passes: passes)
        #expect(f == CoreQueue(forget: true) && passes.load() == device)
    }

    @Test func avatarFileIsReplacedAndRemoved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("av-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = AvatarStore(directory: dir)
        #expect(s.read() == nil)
        s.save(Data([1])); s.save(Data([2]))
        #expect(s.read() == Data([2]))
        s.remove()
        #expect(s.read() == nil)
    }
}

/// Настоящий дом ru (31.14) — только по флагу: `LP_CORE_LIVE=1 [LP_CORE_JPEG=<квадрат 512 JPEG>] swift test --filter CoreLiveTests`.
/// Номер выдуманный (+7 913 000-01-77 → +7 913 000-01-78); в конце `DELETE /v1/me` стирает всё, что записано.
@Suite("Ядро: живой дом ru (31.14)")
struct CoreLiveTests {
    /// Строка на запрос: метод, раздел, код, начало ответа; пропуск и тело запроса не печатаются.
    struct Log: CloudTransport {
        let real = URLSessionCloudTransport()
        func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let op = r.url?.query ?? r.url?.path ?? "?"
            do {
                let (d, resp) = try await real.send(r)
                let text = String(decoding: d.prefix(120), as: UTF8.self)
                print("core-live \(r.httpMethod ?? "") \(op) → \(resp.statusCode) \(text.contains("pass") ? "<ответ с пропуском>" : text)")
                return (d, resp)
            } catch { print("core-live \(r.httpMethod ?? "") \(op) → \(error)"); throw error }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LP_CORE_LIVE"] == "1"))
    func realRussianHomeAcceptsTheClient() async throws {
        let c = HTTPCoreClient(base: CoreAddress.live, transport: Log())
        let h = try await c.health(.ru)
        #expect(h.home == .ru && h.api.contains("devices") && h.api.contains("avatar"))
        var d = try await c.register(CoreRegistration(appId: "id79130000177", country: "RU", appVersion: "31.14 live test", name: nil))
        #expect(d.home == .ru && d.idState == "unconfirmed" && d.deviceId.hasPrefix("dv_"))
        do {
            if let path = ProcessInfo.processInfo.environment["LP_CORE_JPEG"] {
                try await c.putAvatar(try Data(contentsOf: URL(fileURLWithPath: path)), device: d)
                try await c.move(d, to: "id79130000178", at: Date())
                d.appId = "id79130000178"
                try await c.deleteAvatar(device: d)
            }
            await #expect(throws: CoreFailure.badId) {
                _ = try await c.register(CoreRegistration(appId: "id73822000001", country: "RU", appVersion: "31.14 live test", name: nil))
            }
        } catch {
            try? await c.deleteMe(device: d)
            throw error
        }
        try await c.deleteMe(device: d)
        try await c.deleteMe(device: d)   // повтор — 204
        await #expect(throws: CoreFailure.badPass) { try await c.deleteAvatar(device: d) }
    }
}
