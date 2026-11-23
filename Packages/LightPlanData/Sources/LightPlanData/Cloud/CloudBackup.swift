import Foundation

/// Круг копии через облако (итерация 31.1): выгрузить копию данных и картинки мудборда, забрать их обратно.
///
/// Раскладка в папке приложения (у Яндекса — «Приложения/Light Plan», та же, что у веба):
/// - `light-plan-iphone.json` — копия данных в конверте веба `{app, format: 1, exported, data}` (`BackupFile`):
///   веб читает её своим «Восстановить из копии». Своё имя, а не `light-plan.json` веба: натив не затирает копию веба.
/// - `iphone-images/<имя>` — картинки мудборда под теми же именами, что в папке вложений (`RefImageStore`).
///   Выгружается только то, чего на Диске нет или что там другого размера; забирается только недостающее.
public struct CloudBackup: Sendable {
    public static let copyName = "light-plan-iphone.json"
    public static let imagesFolder = "iphone-images"
    /// Своя аватарка (31.13, Алексей 23.11 «Да, класть»): квадрат JPEG рядом с копией. Нет фото на телефоне — файл на Диске
    /// не трогается (удалять файлы Диска приложение не умеет); восстановление кладёт его, только если на телефоне фото нет.
    public static let avatarName = "iphone-avatar.jpg"

    let provider: any CloudProvider
    let tokens: any CloudTokenStore

    public init(provider: any CloudProvider, tokens: any CloudTokenStore) {
        self.provider = provider; self.tokens = tokens
    }

    /// Что ушло: копия всегда, картинок — сколько выгружено и сколько уже лежало.
    public struct Pushed: Sendable, Equatable {
        public var images: Int
        public var alreadyThere: Int
    }

    /// Ход работы для строки под кнопками: «картинки 3 из 40».
    public typealias Progress = @Sendable (_ done: Int, _ total: Int) -> Void

    // MARK: Ключ

    /// Ключ, годный сейчас: протухающий — обновить заранее. Нет ключа — `.revoked` (подключение пропало).
    func token() async throws -> CloudToken {
        guard var t = tokens.load(), t.kind == provider.kind else { throw CloudFailure.revoked }
        if t.stale(now: Date()), t.refresh != nil {
            do { t = try await provider.refresh(t); tokens.save(t) } catch CloudFailure.revoked { tokens.clear(); throw CloudFailure.revoked }
        }
        return t
    }

    /// Вызов с ключом. Диск ответил «ключ не годен» — одна попытка обновить его и повторить; не вышло — ключ забыт,
    /// наружу `.revoked`: дальше только подключиться заново (веб: «токен протух или отозван — молча забываем»).
    func withToken<T: Sendable>(_ body: (CloudToken) async throws -> T) async throws -> T {
        let t = try await token()
        do {
            return try await body(t)
        } catch CloudFailure.revoked {
            guard t.refresh != nil, let fresh = try? await provider.refresh(t) else {
                tokens.clear(); throw CloudFailure.revoked
            }
            tokens.save(fresh)
            do { return try await body(fresh) } catch CloudFailure.revoked { tokens.clear(); throw CloudFailure.revoked }
        }
    }

    // MARK: Подключение

    public func account() async throws -> CloudAccount {
        try await withToken { try await provider.account($0) }
    }

    // MARK: Выгрузка

    public func push(copy: Data, images: RefImageStore?, avatar: Data? = nil, progress: Progress? = nil) async throws -> Pushed {
        try await withToken { t in
            let local = images.map { store in store.names().filter(RefImageStore.isSafe) } ?? []
            var remote: [String: Int64] = [:]
            if !local.isEmpty {
                for item in try await provider.list(Self.imagesFolder, token: t) { remote[item.name] = item.size }
            }
            let todo: [(String, Data)] = local.compactMap { name in
                guard let data = images?.read(name) else { return nil }
                return remote[name] == Int64(data.count) ? nil : (name, data)
            }
            // Места не хватит — сказать до начала, а не оборвать на середине. Неизвестно, сколько места, — не мешаем.
            let need = Int64(copy.count) + Int64(avatar?.count ?? 0) + todo.reduce(Int64(0)) { $0 + Int64($1.1.count) }
            if let free = try? await provider.account(t).freeBytes, free < need { throw CloudFailure.noSpace }
            // Копия первой: она важнее картинок, и сорвись выгрузка на кадре — данные уже на Диске.
            try await provider.upload(copy, to: Self.copyName, token: t)
            if let avatar { try await provider.upload(avatar, to: Self.avatarName, token: t) }
            if !todo.isEmpty { try await provider.ensureFolder(Self.imagesFolder, token: t) }
            progress?(0, todo.count)
            for (i, (name, data)) in todo.enumerated() {
                try await provider.upload(data, to: Self.imagesFolder + "/" + name, token: t)
                progress?(i + 1, todo.count)
            }
            return Pushed(images: todo.count, alreadyThere: local.count - todo.count)
        }
    }

    // MARK: Обратно

    /// Копия на Диске: когда записана и сколько весит — для вопроса «заменить данные на телефоне?». Нет — `nil`.
    public func remoteCopy() async throws -> CloudItem? {
        try await withToken { try await provider.item(Self.copyName, token: $0) }
    }

    /// Файл копии с Диска, проверенный разбором: не копия Light Plan — `.badCopy`, нет файла — `.noCopy`.
    public func pullCopy() async throws -> Data {
        let data = try await withToken { try await provider.download(Self.copyName, token: $0) }
        guard let data else { throw CloudFailure.noCopy }
        guard (try? ImportedFile.decode(data)) != nil else { throw CloudFailure.badCopy }
        return data
    }

    /// Аватарка с Диска; нет файла — `nil`.
    public func pullAvatar() async throws -> Data? {
        try await withToken { try await provider.download(Self.avatarName, token: $0) }
    }

    /// Картинки с Диска, которых нет на телефоне. Возвращает, сколько легло.
    public func pullImages(into store: RefImageStore, progress: Progress? = nil) async throws -> Int {
        try await withToken { t in
            let missing = try await provider.list(Self.imagesFolder, token: t)
                .map(\.name).filter { RefImageStore.isSafe($0) && !store.exists($0) }
            progress?(0, missing.count)
            var n = 0
            for (i, name) in missing.enumerated() {
                if let data = try await provider.download(Self.imagesFolder + "/" + name, token: t), store.save(data, as: name) { n += 1 }
                progress?(i + 1, missing.count)
            }
            return n
        }
    }
}
