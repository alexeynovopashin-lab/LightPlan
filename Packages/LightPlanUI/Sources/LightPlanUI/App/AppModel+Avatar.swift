import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Своя аватарка и «Удалить мои данные» (31.13). Решения Алексея: «Только своя» (19.11), «Все, кто знает номер» (19.11),
/// «по стране номера» (22.11), «Стирать сразу» (22.11), кнопка «Удалить мои данные · телефон, фото» и без слова «ядро»
/// (23.11), удаление стирает и фото на телефоне, фото — в копию на Яндекс.Диске, строка видна всегда (23.11),
/// заглушка — кошка, собака или человек, один раз на установку (23.11).
struct AvatarState: Equatable {
    /// Квадрат JPEG 512; `nil` — фото нет, показывается заглушка.
    var jpeg: Data?
    /// Заглушка этой установки; до первого показа — `nil` (выбирается в `attachAvatar` / `avatarStub`).
    var stub: AvatarStub?
    /// Что ещё не дошло до ядра.
    var queue = CoreQueue()
    /// Окно «Удалить мои данные?» открыто.
    var confirmForget = false
    /// Фото не открылось (не картинка, повреждено) — строка под кругом.
    var unreadable = false
    #if DEBUG
    /// Снимки: экран обрезки открыт сразу (`-LPShotAvatar crop`).
    var shotCrop = false
    #endif
}

/// Проводка: где файл, где память установки, кто ядро. По умолчанию — всё в памяти и ядра нет (тесты, снимки).
struct AvatarWiring {
    var store: AvatarStore?
    var records: any AvatarRecordStore = InMemoryAvatarRecordStore()
    var passes: any CorePassStore = InMemoryCorePassStore()
    var client: any CoreClient = AbsentCoreClient()
    var syncing = false
}

extension AppModel {

    /// Живая проводка: файл рядом со снимком, память в UserDefaults, пропуск в Keychain. Сервера ядра нет —
    /// `AbsentCoreClient`: ни одного запроса в сеть, очередь ждёт.
    func attachAvatar(_ dir: URL?) {
        avatarWiring.store = dir.map { AvatarStore(directory: $0) }
        avatarWiring.records = DefaultsAvatarRecordStore()
        avatarWiring.passes = KeychainCorePassStore()
        avatarWiring.client = AbsentCoreClient()
        loadAvatar()
    }

    /// Прочитать файл и память установки; заглушку выбрать, если её ещё нет.
    func loadAvatar() {
        var r = avatarWiring.records.load()
        if r.stub == nil {
            r.stub = AvatarStub.allCases.randomElement()
            avatarWiring.records.save(r)
        }
        avatar.stub = r.stub
        avatar.queue = r.queue
        avatar.jpeg = avatarWiring.store?.read()
    }

    /// Заглушка: запомненная, а до `loadAvatar` — всё равно одна на установку (выбрать и запомнить сразу).
    /// Наблюдаемое состояние здесь не трогается (читается из `body`): выбор ложится только в память установки.
    var avatarStub: AvatarStub {
        if let s = avatar.stub { return s }
        var r = avatarWiring.records.load()
        if let s = r.stub { return s }
        let s = AvatarStub.allCases.randomElement() ?? .cat
        r.stub = s
        avatarWiring.records.save(r)
        return s
    }

    /// Имя значка заглушки в библиотеке: кошка и собака — общие значки, человек — знак жанра «Портрет».
    nonisolated static func stubIcon(_ s: AvatarStub) -> (name: String, genre: Bool) {
        switch s {
        case .cat: ("cat", false)
        case .dog: ("dog", false)
        case .person: ("portrait", true)
        }
    }

    private func setQueue(_ q: CoreQueue) {
        avatar.queue = q
        var r = avatarWiring.records.load()
        r.queue = q
        r.stub = r.stub ?? avatar.stub
        avatarWiring.records.save(r)
    }

    /// Новое фото после обрезки. Старое стирается сразу (тот же файл заменяется атомарно); ядру — выгрузить текущее.
    func setAvatar(_ jpeg: Data) {
        avatar.unreadable = false
        avatarWiring.store?.save(jpeg)
        avatar.jpeg = jpeg
        var q = avatar.queue
        q.avatar = true
        setQueue(q)
        syncCore()
    }

    /// «Удалить фото»: снова заглушка; ядру — стереть.
    func removeAvatar() {
        avatarWiring.store?.remove()
        avatar.jpeg = nil
        var q = avatar.queue
        q.avatar = true
        setQueue(q)
        syncCore()
    }

    /// «Удалить мои данные»: телефон забывает фото и пропуск сразу, ядру — стереть всё о номере (`DELETE /v1/me`).
    /// Пропуск уходит из Keychain только после ответа ядра: без него просьбу не отправить. Съёмки, клиенты, номер — не трогаются.
    func forgetMe() {
        avatar.confirmForget = false
        avatar.unreadable = false
        avatarWiring.store?.remove()
        avatar.jpeg = nil
        setQueue(CoreQueue(avatar: false, forget: true))
        syncCore()
    }

    /// Один проход очереди; второй не запускается, пока идёт первый. Ошибок человеку не показывает.
    func syncCore() {
        guard !avatar.queue.isEmpty, !avatarWiring.syncing else { return }
        avatarWiring.syncing = true
        let q = avatar.queue, w = avatarWiring
        let input = CoreSync.Input(avatar: avatar.jpeg, appId: myAppId, country: telCountry.iso,
                                   appVersion: Self.appVersion, name: myName.isEmpty ? nil : myName, now: now())
        Task {
            let out = await CoreSync.run(q, input, client: w.client, passes: w.passes)
            avatarWiring.syncing = false
            // Пока шёл проход, человек мог снова что-то нажать: снимаем только то, что было и ушло.
            var cur = avatar.queue
            if q.forget, !out.forget { cur.forget = false }
            if q.avatar, !out.avatar, avatar.jpeg == input.avatar { cur.avatar = false }
            if cur != avatar.queue { setQueue(cur) }
        }
    }

    #if DEBUG
    func shotAvatar(_ raw: String) {
        avatarWiring.records = InMemoryAvatarRecordStore(AvatarRecord(stub: AvatarStub(rawValue: raw) ?? .cat))
        avatar.stub = avatarWiring.records.load().stub
        if ["photo", "crop", "forget"].contains(raw) { avatar.jpeg = AvatarImage.demoJpeg() }
        avatar.shotCrop = raw == "crop"
        avatar.confirmForget = raw == "forget"
    }
    #endif

    /// Ждать конца прохода (тесты).
    func waitCoreSync() async {
        while avatarWiring.syncing { await Task.yield() }
    }

    nonisolated static var appVersion: String {
        let b = Bundle.main
        let v = b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let n = b.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(n))"
    }
}
