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

    // MARK: HTTP по договору

    final class Wire: CloudTransport, @unchecked Sendable {
        var sent: [URLRequest] = []
        var reply: (Int, Data) = (204, Data())
        func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
            sent.append(r)
            return (reply.1, HTTPURLResponse(url: r.url!, statusCode: reply.0, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func httpClientSpeaksTheContract() async throws {
        let wire = Wire()
        let ru = URL(string: "https://ru.example.invalid")!, world = URL(string: "https://world.example.invalid")!
        let c = HTTPCoreClient(base: { $0 == .ru ? ru : world }, transport: wire)
        wire.reply = (201, Data(#"{"deviceId":"dv_1","pass":"s","idState":"unconfirmed","home":"ru"}"#.utf8))
        let d = try await c.register(CoreRegistration(appId: "id7916", country: "RU", appVersion: "1.0 (1)", name: nil))
        #expect(d == CoreDevice(deviceId: "dv_1", pass: "s", idState: "unconfirmed", home: .ru, appId: "id7916"))
        let reg = wire.sent[0]
        #expect(reg.httpMethod == "POST" && reg.url?.absoluteString == "https://ru.example.invalid/v1/devices")
        let body = try JSONSerialization.jsonObject(with: reg.httpBody ?? Data()) as? [String: String]
        #expect(body == ["app": "lightplan", "appId": "id7916", "country": "RU", "appVersion": "1.0 (1)"])   // имени и города нет

        wire.reply = (200, Data())
        try await c.putAvatar(jpeg, device: d)
        try await c.deleteAvatar(device: d)
        try await c.deleteMe(device: d)
        let tail = wire.sent.suffix(3)
        #expect(tail.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == ["PUT /v1/me/avatar", "DELETE /v1/me/avatar", "DELETE /v1/me"])
        #expect(tail.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer s" })
        #expect(tail.first?.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")

        wire.reply = (401, Data())
        await #expect(throws: CoreFailure.badPass) { try await c.deleteMe(device: d) }
        wire.reply = (503, Data())
        await #expect(throws: CoreFailure.unavailable) { try await c.deleteMe(device: d) }
        wire.reply = (413, Data())
        await #expect(throws: CoreFailure.rejected(413)) { try await c.putAvatar(jpeg, device: d) }
    }

    @Test func homeWithoutAddressMakesNoRequest() async {
        let wire = Wire()
        let c = HTTPCoreClient(base: { _ in nil }, transport: wire)
        await #expect(throws: CoreFailure.unavailable) {
            _ = try await c.register(CoreRegistration(appId: "id7", country: "DE", appVersion: "1", name: nil))
        }
        #expect(wire.sent.isEmpty)
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
