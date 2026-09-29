import Testing
@testable import LightPlanDomain

/// Итерация 27, шаг 3: кадры карточки — свои, потом набор жанра (веб `allRefs`).
struct RefSetTests {
    private let shots = ["a", "b", "c", "d", "e"].map { RefFrame(id: $0) }

    private func ids(_ f: [RefFrame]) -> [String] { f.map(\.id) }

    @Test func ownFirstThenGenreSet() {
        let boards = [RefBoard(kind: .tpl, genre: "wedding", items: ["c", "d"]),
                      RefBoard(kind: .shoot, sid: "s1", genre: "wedding", items: ["a", "b"])]
        let f = RefSet.compose(sessionId: "s1", genre: "wedding", shots: shots, boards: boards)
        #expect(ids(f) == ["a", "b", "c", "d"])
        #expect(f.map(\.own) == [true, true, false, false])
    }

    @Test func sharedFrameStaysOnceAsOwn() {
        let boards = [RefBoard(kind: .shoot, sid: "s1", items: ["a", "b"]),
                      RefBoard(kind: .tpl, genre: "wedding", items: ["b", "c"])]
        let f = RefSet.compose(sessionId: "s1", genre: "wedding", shots: shots, boards: boards)
        #expect(ids(f) == ["a", "b", "c"])
        #expect(f.first { $0.id == "b" }?.own == true)
    }

    @Test func allFoldersOfGenreInShelfOrderWithoutRepeats() {
        let boards = [RefBoard(kind: .tpl, genre: "wedding", items: ["c", "d"]),
                      RefBoard(kind: .tpl, genre: "wedding", items: ["d", "e"]),
                      RefBoard(kind: .tpl, genre: "portrait", items: ["a"])]
        let f = RefSet.compose(sessionId: "s1", genre: "wedding", shots: shots, boards: boards)
        #expect(ids(f) == ["c", "d", "e"])
    }

    @Test func emptyStates() {
        // Ни своей подборки, ни набора — кадров нет (блока нет).
        #expect(RefSet.compose(sessionId: "s1", genre: "wedding", shots: shots, boards: []).isEmpty)
        // Только набор: своих нет, раздел «Эта съёмка» не рисуется.
        let onlySet = RefSet.compose(sessionId: "s1", genre: "wedding", shots: shots,
                                     boards: [RefBoard(kind: .tpl, genre: "wedding", items: ["a"])])
        #expect(onlySet.map(\.own) == [false])
        // Только свои, а у записи жанра нет.
        let onlyOwn = RefSet.compose(sessionId: "s1", genre: nil, shots: shots,
                                     boards: [RefBoard(kind: .shoot, sid: "s1", items: ["a"]),
                                              RefBoard(kind: .tpl, genre: "wedding", items: ["b"])])
        #expect(ids(onlyOwn) == ["a"])
        // Чужая подборка съёмки и id без кадра не считаются.
        let foreign = RefSet.compose(sessionId: "s1", genre: nil, shots: shots,
                                     boards: [RefBoard(kind: .shoot, sid: "s2", items: ["a"]),
                                              RefBoard(kind: .shoot, sid: "s1", items: ["zzz"])])
        #expect(foreign.isEmpty)
    }
}
