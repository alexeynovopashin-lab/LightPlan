import Testing
import Foundation
@testable import LightPlanData
import LightPlanDomain

/// Черновик ответа клиента переживает закрытую форму и перезапуск (итерация 28, шаг 8; ошибка веба А3).
struct QuestDraftStoreTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("light-plan-quest-\(UUID().uuidString)", isDirectory: true)
    }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func draftComesBackAfterRestart() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var drafts = QuestDrafts()
        drafts.hold(code: "eyJiIjoi0JXQu9C10L3QsCJ9", for: "k3x9", at: t0)
        drafts.hold(code: "e30", for: nil, at: t0)
        #expect(QuestDraftStore(directory: dir).save(drafts))
        // Другой экземпляр — как после нового запуска приложения.
        let back = QuestDraftStore(directory: dir).load()
        #expect(back == drafts)
        #expect(back.pending(for: "k3x9")?.code == "eyJiIjoi0JXQu9C10L3QsCJ9")
        #expect(back.pending(for: nil)?.savedAt == t0)
    }

    @Test func releasedDraftStaysGoneAfterRestart() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = QuestDraftStore(directory: dir)
        var drafts = QuestDrafts()
        drafts.hold(code: "AAA", for: "a", at: t0)
        drafts.hold(code: "BBB", for: "b", at: t0)
        store.save(drafts)
        drafts.release("a")
        store.save(drafts)
        let back = QuestDraftStore(directory: dir).load()
        #expect(back.pending(for: "a") == nil && back.pending(for: "b")?.code == "BBB")
    }

    @Test func missingOrBrokenFileIsEmptyNotACrash() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = QuestDraftStore(directory: dir)
        #expect(store.load() == QuestDrafts(), "файла нет")
        try Data("{это не json".utf8).write(to: store.file)
        #expect(store.load() == QuestDrafts(), "файл испорчен")
        try Data(#"{"items":{"a":{"code":5}}}"#.utf8).write(to: store.file)
        #expect(store.load() == QuestDrafts(), "не та форма")
    }

    @Test func writeIsAtomicAndLeavesNoTempFiles() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = QuestDraftStore(directory: dir)
        var drafts = QuestDrafts()
        for i in 0..<5 { drafts.hold(code: "c\(i)", for: "r\(i)", at: t0); store.save(drafts) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["quest-drafts.json"])
    }
}
