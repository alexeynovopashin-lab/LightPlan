import Foundation
import LightPlanDomain

/// Файл черновиков ответов клиента (`QuestDrafts`) в песочнице приложения. Запись атомарная; нет файла или он
/// испорчен — пустые черновики, а не ошибка: потерять черновик хуже, чем открыть форму без него, но падение хуже
/// обоих (итерация 28, шаг 8; ошибка веба А3).
public struct QuestDraftStore: Sendable {
    public let file: URL

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.file = directory.appendingPathComponent("quest-drafts.json")
    }

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(), d = JSONDecoder()
        e.dateEncodingStrategy = .iso8601; d.dateDecodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return (e, d)
    }

    public func load() -> QuestDrafts {
        guard let data = try? Data(contentsOf: file),
              let drafts = try? Self.coder().1.decode(QuestDrafts.self, from: data) else { return QuestDrafts() }
        return drafts
    }

    @discardableResult
    public func save(_ drafts: QuestDrafts) -> Bool {
        guard let data = try? Self.coder().0.encode(drafts) else { return false }
        return (try? data.write(to: file, options: .atomic)) != nil
    }
}
