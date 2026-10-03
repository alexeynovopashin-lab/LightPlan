import Testing
import Foundation
@testable import LightPlanData

/// Живая проверка клиента против настоящей читалки (28м). Выключена по умолчанию: нужна сеть и ключ.
/// `LP_LIVE_OG=1 swift test --filter PinterestLive` (ключ — из `~/.config/lightplan/og_key`, нигде не печатается).
/// Тестовая публичная доска Алексея «Коллектив» — 6 пинов (`docs/pinterest_reference.md` § 1.1).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LP_LIVE_OG"] == "1"))
struct PinterestLiveTests {

    private func client(key: String? = nil) async throws -> PinterestClient {
        let k = try key ?? String(contentsOfFile: NSHomeDirectory() + "/.config/lightplan/og_key", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Первый запрос процесса на этом Mac иногда виснет ~8 с и кончается `timedOut` (curl так не делает; 2 из 7 запусков, 04.10):
        // прогреваем соединение, чтобы замер смотрел на читалку, а не на это.
        let c = PinterestClient(config: PinterestConfig(key: k))
        _ = try? await c.board(link: "https://example.com/a/b")
        return c
    }

    @Test func shortBoardLinkGivesSixPinsAndAllPicturesArrive() async throws {
        let c = try await client()
        let b = try await c.board(link: "https://pin.it/3qVvzLDZl")
        #expect(b.name == "Коллектив" && b.pins.count == 6 && b.pinCount == 6 && !b.truncated)
        let sizes = try await withThrowingTaskGroup(of: Int.self) { g in
            for p in b.pins { g.addTask { try await c.image(at: p.image).count } }
            return try await g.reduce(into: []) { $0.append($1) }
        }
        #expect(sizes.count == 6 && sizes.allSatisfy { $0 > 5_000 })
    }

    @Test func singlePinPreviewIsTheSamePictureAsInTheBoard() async throws {
        let c = try await client()
        let b = try await c.board(link: "https://pin.it/3qVvzLDZl")
        let viaBoard = try await c.image(at: b.pins[0].image)
        let viaPage = try await c.preview(of: b.pins[0].permalink)
        #expect(viaBoard == viaPage)
    }

    @Test func shortLinkOfAPinSaysBadLinkOnBoardAndNotFoundBoardIsNamed() async throws {
        let c = try await client()
        await #expect(throws: PinterestFailure.boardNotFound) { try await c.board(link: "https://www.pinterest.com/nobody-here-xyz/no-such-board-xyz/") }
        await #expect(throws: PinterestFailure.badLink) { try await c.board(link: "https://example.com/a/b/") }
    }

    @Test func deadShortLinkGivesNoPictureNotPinterestsPlaceholder() async throws {
        let c = try await client()
        await #expect(throws: PinterestFailure.badLink) { try await c.board(link: "https://pin.it/3qVvzLDZ") }
        await #expect(throws: PinterestFailure.notFound) { try await c.preview(of: "https://pin.it/3qVvzLDZ") }
        await #expect(throws: PinterestFailure.notFound) { try await c.preview(of: "https://www.pinterest.com/pin/99999999999999999/") }
    }

    @Test func missingPictureIs404NotAServerFailure() async throws {
        let c = try await client()
        await #expect(throws: PinterestFailure.notFound) {
            try await c.image(at: "https://i.pinimg.com/736x/00/00/00/0000000000000000000000000000dead.jpg")
        }
    }

    @Test func wrongKeyIsRejected() async throws {
        let c = try await client(key: "wrong-key")
        await #expect(throws: PinterestFailure.rejected) { try await c.board(link: "https://pin.it/3qVvzLDZl") }
    }
}
