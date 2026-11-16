import Foundation
import LightPlanCore
import LightPlanData

// MARK: - Облако фотографа (итерация 31.1: Яндекс.Диск)
//
// Роль облака в нативе — дополнительная копия и шлюз выгрузки, не хранилище (DECISIONS «Курс на серверы», 23.08):
// главные данные остаются файлом на телефоне. Здесь — круг «подключить → сохранить копию → восстановить → отключить»
// для главы «Данные и облако». Сама работа с Диском — `CloudBackup` / `YandexDisk` (LightPlanData), окно входа —
// `CloudSignInPresenting` (системный `ASWebAuthenticationSession` в живом приложении, подделка в тестах).

/// Окно входа поставщика: открыть адрес, дождаться возврата на схему приложения.
@MainActor
protocol CloudSignInPresenting {
    func run(_ request: CloudSignInRequest) async throws -> URL
}

/// Что видно в блоке «Облако».
struct CloudState: Equatable {
    enum Busy: Equatable {
        case connecting
        case pushing(done: Int, total: Int?)
        case reading
        case pulling(done: Int, total: Int?)
    }
    /// Подключение, имя и последняя выгрузка — из памяти устройства (`CloudRecord`).
    var record = CloudRecord()
    var busy: Busy?
    /// Строка итога под кнопками — уже словами; `error` красит её как предупреждение.
    var line: String?
    var error = false
    /// Выбор на сегменте, пока подключения нет (Google/Dropbox «скоро», Яндекс до конца входа).
    var picked: CloudKind?
    /// Копия на Диске, о замене которой спрашиваем.
    var confirm: CloudItem?
    /// Копия уже легла в файл данных: приложение надо открыть заново (плашка на весь экран).
    var restored = false

    var connected: Bool { record.kind != nil }
}

/// Проводка облака — собирается в `live()`; тесты подставляют поддельные Диск, ключи и окно входа.
struct CloudWiring {
    /// `nil` — в сборке нет ClientID (`Tools/yandex_key.sh`): Яндекс «не настроен в этой сборке».
    var yandex: (any CloudProvider)?
    var tokens: any CloudTokenStore
    var records: any CloudRecordStore
    var presenter: any CloudSignInPresenting
}

extension AppModel {
    /// Подключить облако в живом приложении: ClientID из сборки, ключ в Keychain, окно — системное.
    func attachCloud() {
        let records = DefaultsCloudRecordStore()
        let tokens = KeychainCloudTokenStore()
        var record = records.load()
        // Ключ пропал (переустановка стирает Keychain с «только на этом устройстве» не всегда, а запись в UserDefaults — да,
        // и наоборот): подключение считается живым, только когда есть оба.
        if record.kind != nil, tokens.load() == nil { record = CloudRecord(); records.save(record) }
        cloudWiring = CloudWiring(yandex: YandexConfig.load().map { YandexDisk(config: $0) },
                                  tokens: tokens, records: records, presenter: SystemCloudSignIn())
        cloud.record = record
    }

    private var cloudBackup: CloudBackup? {
        guard let w = cloudWiring, let p = w.yandex else { return nil }
        return CloudBackup(provider: p, tokens: w.tokens)
    }

    /// Строка о причине — словами, для человека.
    func cloudWords(_ failure: CloudFailure) -> String {
        let t = lexicon
        switch failure {
        case .notConfigured: return t.t("cloud.n.notConfigured")
        case .cancelled: return t.t("cloud.n.errSignIn")
        case .revoked: return t.t("cloud.n.errRevoked")
        case .offline: return t.t("cloud.n.errOffline")
        case .noSpace: return t.t("cloud.n.errNoSpace")
        case .noCopy: return t.t("cloud.n.errNoCopy")
        case .badCopy: return t.t("cloud.n.errBadCopy")
        case .server(let code, let message):
            let head = t.t("cloud.n.errServer", ["code": String(code)])
            return message.map { head + " " + $0 } ?? head
        }
    }

    private func cloudFail(_ error: Error) {
        let f = (error as? CloudFailure) ?? .server(code: 0, message: String(describing: error))
        cloud.busy = nil
        cloud.line = cloudWords(f)
        cloud.error = true
        // Ключ отозван — подключения больше нет: сегмент на «Выкл», запись устройства чистая (ключ `CloudBackup` уже забыл).
        if f == .revoked { setCloudRecord(CloudRecord()) ; cloud.picked = nil }
    }

    private func setCloudRecord(_ r: CloudRecord) {
        cloud.record = r
        cloudWiring?.records.save(r)
    }

    func cloudSay(_ line: String) {
        cloud.busy = nil
        cloud.line = line
        cloud.error = false
    }

    /// Сегмент «Выкл / Яндекс / Google / Dropbox».
    var cloudSegment: CloudKind? { cloud.record.kind ?? cloud.picked }

    func pickCloud(_ kind: CloudKind?) {
        guard cloud.busy == nil else { return }
        switch kind {
        case nil:
            cloud.picked = nil
            if cloud.connected { forgetCloud() } else { cloud.line = nil }
        case .yandex?:
            if cloud.record.kind == .yandex { return }
            cloud.picked = .yandex
            connectCloud()
        case let k?:
            // Google и Dropbox — позже (план 31): честное «скоро», подключение Яндекса не трогаем.
            if cloud.connected { return }
            cloud.picked = k
            cloudSay(lexicon.t("cloud.n.soon"))
        }
    }

    // MARK: Подключить

    func connectCloud() {
        guard cloud.busy == nil else { return }
        guard let w = cloudWiring, let provider = w.yandex else { return cloudFail(CloudFailure.notConfigured) }
        cloud.busy = .connecting
        cloud.line = lexicon.t("cloud.n.connecting")
        cloud.error = false
        Task {
            do {
                let req = try provider.signIn()
                let back = try await w.presenter.run(req)
                let token = try await provider.finishSignIn(back, request: req)
                w.tokens.save(token)
                let account = try? await CloudBackup(provider: provider, tokens: w.tokens).account()
                setCloudRecord(CloudRecord(kind: provider.kind, account: account?.label, lastUpload: nil))
                cloud.picked = nil
                cloudSay(lexicon.t("cloud.n.connected"))
            } catch {
                cloud.picked = nil
                cloudFail(error)
            }
        }
    }

    // MARK: Отключить

    /// Забыть ключ на этом телефоне. Отозвать его у Яндекса без секрета приложения нельзя (`/revoke_token` требует
    /// пару ClientID + секрет) — строка итога говорит, где это сделать.
    func forgetCloud() {
        guard cloud.busy == nil else { return }
        cloudWiring?.tokens.clear()
        setCloudRecord(CloudRecord())
        cloud.picked = nil
        cloudSay(lexicon.t("cloud.n.forgotten"))
    }

    // MARK: Сохранить копию

    func pushCloud() {
        guard cloud.busy == nil, cloud.connected else { return }
        guard let backup = cloudBackup else { return cloudFail(CloudFailure.notConfigured) }
        cloud.busy = .pushing(done: 0, total: nil)
        cloud.line = lexicon.t("cloud.n.pushing")
        cloud.error = false
        let snap = snapshot, images = refImages
        Task {
            do {
                // Тот же конверт, что пишет «Поделиться копией» (`Store.exportArchive`) и читает веб: из снимка в памяти —
                // он правдивее файла, в который отложенная запись могла ещё не дойти.
                let copy = try CloudBackup.copy(of: snap)
                let pushed = try await backup.push(copy: copy, images: images) { done, total in
                    Task { @MainActor in self.cloudProgress(.pushing(done: done, total: total)) }
                }
                var r = cloud.record
                r.lastUpload = now()
                setCloudRecord(r)
                cloudSay(lexicon.t("cloud.n.pushed", ["n": String(pushed.images), "m": String(pushed.alreadyThere)]))
            } catch {
                cloudFail(error)
            }
        }
    }

    func cloudProgress(_ b: CloudState.Busy) {
        guard cloud.busy != nil else { return }
        cloud.busy = b
        switch b {
        case .pushing(let d, let t?) where t > 0: cloud.line = lexicon.t("cloud.n.pushingImages", ["n": String(d), "total": String(t)])
        case .pulling(let d, let t?) where t > 0: cloud.line = lexicon.t("cloud.n.pullingImages", ["n": String(d), "total": String(t)])
        default: break
        }
    }

    // MARK: Восстановить

    /// Шаг 1: узнать, есть ли копия и от какого она числа, — и спросить.
    func askRestoreCloud() {
        guard cloud.busy == nil, cloud.connected else { return }
        guard let backup = cloudBackup else { return cloudFail(CloudFailure.notConfigured) }
        cloud.busy = .reading
        cloud.line = lexicon.t("cloud.reading")
        cloud.error = false
        Task {
            do {
                guard let item = try await backup.remoteCopy() else { throw CloudFailure.noCopy }
                cloud.busy = nil
                cloud.line = nil
                cloud.confirm = item
            } catch {
                cloudFail(error)
            }
        }
    }

    func cancelRestoreCloud() { cloud.confirm = nil }

    /// Шаг 2: забрать копию и картинки, положить копию в файл данных. Свой снимок `Store` сперва убирает в `backups/`.
    /// После этого модель больше не пишет файл (`storeFrozen`): в памяти — прежние данные, и любая правка затёрла бы
    /// только что положенную копию. Приложение надо открыть заново — об этом плашка на весь экран.
    func restoreCloud() {
        guard cloud.busy == nil, cloud.confirm != nil else { return }
        cloud.confirm = nil
        guard let backup = cloudBackup else { return cloudFail(CloudFailure.notConfigured) }
        cloud.busy = .pulling(done: 0, total: nil)
        cloud.line = lexicon.t("cloud.reading")
        cloud.error = false
        let images = refImages
        Task {
            do {
                let data = try await backup.pullCopy()
                if let images {
                    _ = try await backup.pullImages(into: images) { done, total in
                        Task { @MainActor in self.cloudProgress(.pulling(done: done, total: total)) }
                    }
                }
                storeFrozen = true
                await flush()
                if let store {
                    do { _ = try await store.importArchive(data: data) } catch { storeFrozen = false; throw error }
                }
                cloud.restored = true
                cloudSay(lexicon.t("cloud.n.restored"))
            } catch {
                cloudFail(error)
            }
        }
    }

    /// «16.11 14:20» — время последней выгрузки и копии на Диске.
    func cloudWhen(_ d: Date) -> String {
        let dt = DateText(language: language)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.hour, .minute], from: d)
        return dt.dNum(d) + " " + ClockText(language: language, preference: Self.clock(settings.clock))
            .fmt(Double(c.hour! * 60 + c.minute!))
    }
}

extension AppModel {
    /// Снимки экрана (`-LPShotCloud`): состояние блока «Облако» напрямую, без Диска и окна входа.
    func shotCloud(_ kind: String) {
        let on = CloudRecord(kind: .yandex, account: "Алексей", lastUpload: now().addingTimeInterval(-3600))
        switch kind {
        case "on": cloud.record = on
        case "pushing": cloud.record = on; cloud.busy = .pushing(done: 3, total: 12); cloudProgress(.pushing(done: 3, total: 12))
        case "pushed": cloud.record = on; cloudSay(lexicon.t("cloud.n.pushed", ["n": "12", "m": "30"]))
        case "error": cloud.record = on; cloud.line = cloudWords(.noSpace); cloud.error = true
        case "ask":
            // Вопрос — после того как глава открылась: поставленный до перехода, он не показывается.
            cloud.record = on
            let item = CloudItem(name: CloudBackup.copyName, size: 1, modified: now().addingTimeInterval(-7200))
            Task { try? await Task.sleep(for: .milliseconds(1500)); cloud.confirm = item }
        case "soon": cloud.picked = .google; cloudSay(lexicon.t("cloud.n.soon"))
        case "restored": cloud.record = on; cloud.restored = true
        default: break
        }
    }
}

extension CloudBackup {
    /// Конверт копии из снимка в памяти — то же, что `Store.exportArchive` пишет из файла.
    static func copy(of snapshot: Snapshot) throws -> Data { try Store.archive(snapshot) }
}
