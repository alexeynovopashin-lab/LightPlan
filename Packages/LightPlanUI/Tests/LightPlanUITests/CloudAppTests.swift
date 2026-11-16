import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
@testable import LightPlanData
@testable import LightPlanUI

/// Облако в памяти: поставщик, которому всё равно, Яндекс он или нет. Ключ «ok» годен, пока не `revoked`.
private final class MemoryCloud: CloudProvider, @unchecked Sendable {
    let kind = CloudKind.yandex
    private let lock = NSLock()
    var files: [String: Data] = [:]
    var revoked = false
    var modified = Date(timeIntervalSince1970: 1_794_825_600)

    func signIn() throws -> CloudSignInRequest {
        CloudSignInRequest(url: URL(string: "https://oauth.test/authorize")!, callbackScheme: "lightplan-oauth", verifier: "v", state: "s1")
    }
    func finishSignIn(_ callback: URL, request: CloudSignInRequest) async throws -> CloudToken {
        guard callback.absoluteString.contains("code=ok"), callback.absoluteString.contains("state=\(request.state)") else { throw CloudFailure.cancelled }
        return CloudToken(kind: .yandex, access: "ok", refresh: nil, expires: nil)
    }
    func refresh(_ token: CloudToken) async throws -> CloudToken { throw CloudFailure.revoked }
    private func check(_ t: CloudToken) throws { if lock.withLock({ revoked }) || t.access != "ok" { throw CloudFailure.revoked } }
    func account(_ token: CloudToken) async throws -> CloudAccount { try check(token); return CloudAccount(login: "a.photo", name: "Алексей") }
    func ensureFolder(_ path: String, token: CloudToken) async throws { try check(token) }
    func upload(_ data: Data, to path: String, token: CloudToken) async throws { try check(token); lock.withLock { files[path] = data } }
    func download(_ path: String, token: CloudToken) async throws -> Data? { try check(token); return lock.withLock { files[path] } }
    func item(_ path: String, token: CloudToken) async throws -> CloudItem? {
        try check(token)
        return lock.withLock { files[path].map { CloudItem(name: path, size: Int64($0.count), modified: modified) } }
    }
    func list(_ folder: String, token: CloudToken) async throws -> [CloudItem] {
        try check(token)
        return lock.withLock { files.filter { $0.key.hasPrefix(folder + "/") }
            .map { CloudItem(name: String($0.key.dropFirst(folder.count + 1)), size: Int64($0.value.count)) } }
    }
}

/// Окно входа «нажали Разрешить» (или «Отмена»).
@MainActor
private struct FakeSignIn: CloudSignInPresenting {
    var answer: String?
    func run(_ request: CloudSignInRequest) async throws -> URL {
        guard let answer else { throw CloudFailure.cancelled }
        return URL(string: answer)!
    }
}

@MainActor
@Suite("Облако в настройках (31.1)")
struct CloudAppTests {
    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func dir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cloudapp-\(UUID().uuidString)", isDirectory: true)
    }

    private func probe(_ s: Snapshot) -> JSONValue? { s.extra["probe"] }

    private func model(_ snap: Snapshot, store: Store?, cloud: MemoryCloud, tokens: InMemoryCloudTokenStore,
                       answer: String? = "lightplan-oauth://yandex?code=ok&state=s1") -> AppModel {
        let app = AppModel(snapshot: snap, store: store, language: "ru", locator: NoLocator(),
                           geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
        app.cloudWiring = CloudWiring(yandex: cloud, tokens: tokens, records: InMemoryCloudRecordStore(),
                                      presenter: FakeSignIn(answer: answer))
        return app
    }

    private func settle(_ app: AppModel) async throws {
        for _ in 0..<400 where app.cloud.busy != nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(app.cloud.busy == nil)
    }

    @Test("Круг: подключить → сохранить копию → восстановить на другом телефоне → отключить")
    func roundTrip() async throws {
        let cloud = MemoryCloud()
        let tokens = InMemoryCloudTokenStore()

        // Телефон А: данные «A» и одна картинка мудборда.
        var snapA = Snapshot(); snapA.extra["probe"] = .string("A")
        let a = model(snapA, store: nil, cloud: cloud, tokens: tokens)
        let picsA = RefImageStore(directory: dir())
        picsA.save(Data(repeating: 7, count: 300), as: "f1.jpg")
        a.refImages = picsA

        a.pickCloud(.yandex)
        try await settle(a)
        #expect(a.cloud.record.kind == .yandex)
        #expect(a.cloud.record.account == "Алексей")
        #expect(a.cloud.line == a.lexicon.t("cloud.n.connected"))

        a.pushCloud()
        try await settle(a)
        #expect(a.cloud.record.lastUpload != nil)
        #expect(cloud.files[CloudBackup.copyName] != nil)
        #expect(cloud.files["iphone-images/f1.jpg"]?.count == 300)
        #expect(!a.cloud.error, "\(a.cloud.line ?? "")")

        // Телефон Б: свои данные «B» на диске; забираем копию с Диска.
        let dirB = dir()
        let storeB = Store(directory: dirB)
        var snapB = Snapshot(); snapB.extra["probe"] = .string("B")
        try await storeB.saveNow(snapB)
        let b = model(snapB, store: storeB, cloud: cloud, tokens: tokens)
        let picsB = RefImageStore(directory: dirB.appendingPathComponent("attachments"))
        b.refImages = picsB
        b.cloud.record = CloudRecord(kind: .yandex)

        b.askRestoreCloud()
        try await settle(b)
        #expect(b.cloud.confirm != nil, "сначала вопрос «заменить?», данные не тронуты")
        #expect(probe(try await storeB.load()) == .string("B"))
        b.restoreCloud()
        try await settle(b)
        #expect(b.cloud.restored)
        #expect(probe(try await storeB.load()) == .string("A"))
        #expect(picsB.read("f1.jpg") == picsA.read("f1.jpg"))
        let kept = try FileManager.default.contentsOfDirectory(atPath: dirB.appendingPathComponent("backups").path)
        #expect(kept.contains { $0.hasPrefix("before-import-") }, "прежние данные Б сохранены файлом")

        // Правка после восстановления не затирает легшую копию прежними данными из памяти.
        b.persist()
        await b.flush()
        #expect(probe(try await storeB.load()) == .string("A"))

        // Отключить: ключ забыт, на Диске всё осталось.
        a.forgetCloud()
        #expect(a.cloud.record.kind == nil)
        #expect(tokens.load() == nil)
        #expect(a.cloud.line == a.lexicon.t("cloud.n.forgotten"))
        #expect(cloud.files[CloudBackup.copyName] != nil)
    }

    @Test("Доступ отозван: строка «подключите заново», подключение снято")
    func revoked() async throws {
        let cloud = MemoryCloud()
        let tokens = InMemoryCloudTokenStore()
        let app = model(Snapshot(), store: nil, cloud: cloud, tokens: tokens)
        app.pickCloud(.yandex)
        try await settle(app)
        cloud.revoked = true
        app.pushCloud()
        try await settle(app)
        #expect(app.cloud.error)
        #expect(app.cloud.line == app.lexicon.t("cloud.n.errRevoked"))
        #expect(app.cloud.record.kind == nil)
        #expect(app.cloudSegment == nil)
        #expect(tokens.load() == nil)
    }

    @Test("Нет копии, отмена входа, Google «скоро», нет ClientID")
    func honestLines() async throws {
        let cloud = MemoryCloud()
        let tokens = InMemoryCloudTokenStore()
        let app = model(Snapshot(), store: nil, cloud: cloud, tokens: tokens)
        app.pickCloud(.google)
        #expect(app.cloud.record.kind == nil)
        #expect(app.cloudSegment == .google)
        #expect(app.cloud.line == app.lexicon.t("cloud.n.soon"))

        app.pickCloud(.yandex)
        try await settle(app)
        app.askRestoreCloud()
        try await settle(app)
        #expect(app.cloud.confirm == nil)
        #expect(app.cloud.line == app.lexicon.t("cloud.n.errNoCopy"))
        #expect(app.cloud.record.kind == .yandex, "нет копии — подключение остаётся")

        let cancelled = model(Snapshot(), store: nil, cloud: cloud, tokens: InMemoryCloudTokenStore(), answer: nil)
        cancelled.pickCloud(.yandex)
        try await settle(cancelled)
        #expect(cancelled.cloud.record.kind == nil)
        #expect(cancelled.cloud.line == cancelled.lexicon.t("cloud.n.errSignIn"))

        let bare = model(Snapshot(), store: nil, cloud: cloud, tokens: tokens)
        bare.cloudWiring?.yandex = nil
        bare.pickCloud(.yandex)
        #expect(bare.cloud.line == bare.lexicon.t("cloud.n.notConfigured"))
    }
}
