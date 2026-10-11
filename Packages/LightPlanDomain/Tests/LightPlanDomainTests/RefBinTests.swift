import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Итерация 29б: корзина мудборда съёмки с самоочисткой (слова Алексея 07.10 и 11.10). Матрица «режим × возраст /
/// конец съёмки» → что уходит; кадр, лежащий ещё в подборке жанра, остаётся; «удалять сразу» не копит;
/// «не удалять» не трогает. Часы — число в аргументе: `Date()` в логике нет.
struct RefBinTests {
    private let t0: Double = 1_800_000_000_000          // момент «убрал»
    private let week = RefLibrary.binWeekMs
    private let second: Double = 1000

    /// Съёмка `S` с четырьмя кадрами; `f2` лежит и в наборе жанра `G` — он не «одинокий».
    private func library(mode: RefBinMode? = nil) -> RefLibrary {
        let shots = ["f1", "f2", "f3", "f4"].map { RefFrame(id: $0, kind: .img, im: $0 + ".jpg") }
        let s = RefBoard(id: "S", kind: .shoot, sid: "s1", genre: "wedding", items: ["f1", "f2", "f3", "f4"], binMode: mode)
        let g = RefBoard(id: "G", kind: .tpl, genre: "wedding", items: ["f2"])
        return RefLibrary(shots: shots, boards: [s, g])
    }

    private func bin(_ l: RefLibrary) -> [String] { l.board("S")?.bin.map(\.id) ?? [] }
    private func fund(_ l: RefLibrary) -> [String] { l.shots.map(\.id) }

    // MARK: убрать → в корзину

    @Test func removedFrameLandsInBinAndStaysInFund() {
        var l = library()
        let gone = l.discard(["f1"], from: "S", now: t0)
        #expect(gone.isEmpty)
        #expect(l.board("S")?.items == ["f2", "f3", "f4"])
        #expect(bin(l) == ["f1"])
        #expect(fund(l).contains("f1"))                 // файл и кадр целы, пока не вышел срок
        #expect(l.isUsed("f1"))                         // корзина держит кадр: чужая очистка его не тронет
        #expect(l.board("S")?.bin.first?.at == t0)
        #expect(l.board("S")?.bin.first?.pos == 0)      // стоял первым
    }

    @Test func genreFolderHasNoBin() {
        var l = library()
        l.discard(["f2"], from: "G", now: t0)           // обычная подборка: как раньше, ссылка снята, корзины нет
        #expect(l.board("G")?.items == [])
        #expect(l.board("G")?.bin.isEmpty == true)
        #expect(bin(l).isEmpty)
        #expect(fund(l).contains("f2"))                 // кадр лежит в съёмке — остаётся
    }

    @Test func nowModeDropsLoneFrameAtOnceAndDoesNotPile() {
        var l = library(mode: .now)
        let gone = l.discard(["f1", "f2"], from: "S", now: t0)
        #expect(gone == ["f1"])                         // «одинокий» — насовсем
        #expect(!fund(l).contains("f1"))
        #expect(fund(l).contains("f2"))                 // лежит ещё в жанре
        #expect(l.board("G")?.items == ["f2"])
        #expect(bin(l).isEmpty)                         // ничего не копится
    }

    // MARK: самоочистка по возрасту

    @Test(arguments: [
        (-1, false),        // через 7 суток минус секунда ещё лежит
        (0, true),          // ровно 7 суток — уходит
        (1, true),          // и секунда после
    ])
    func weekBoundary(offset: Int, expired: Bool) {
        var l = library()
        l.discard(["f1"], from: "S", now: t0)
        let gone = l.sweepBins(now: t0 + week + Double(offset) * second) { _ in false }
        #expect((gone == ["f1"]) == expired)
        #expect(bin(l).contains("f1") == !expired)
        #expect(fund(l).contains("f1") == !expired)
    }

    @Test func sharedFrameLeavesBinButStaysWhereItLies() {
        var l = library()
        l.discard(["f1", "f2"], from: "S", now: t0)
        let gone = l.sweepBins(now: t0 + week, shootEnded: { _ in false })
        #expect(gone == ["f1"])                         // одинокий — насовсем
        #expect(bin(l).isEmpty)
        #expect(fund(l).contains("f2"))                 // у жанра остался
        #expect(l.board("G")?.items == ["f2"])
        #expect(!(l.board("S")?.items.contains("f2") ?? true))   // в съёмку сам не возвращается
    }

    @Test func neverTouchesAnything() {
        var l = library(mode: .never)
        l.discard(["f1", "f3"], from: "S", now: t0)
        let gone = l.sweepBins(now: t0 + 400 * RefLibrary.binDayMs, shootEnded: { _ in true })
        #expect(gone.isEmpty)
        #expect(bin(l) == ["f1", "f3"])
    }

    @Test func nowModeKeepsWhatWasBinnedBefore() {
        var l = library()                               // по умолчанию — неделя
        l.discard(["f1"], from: "S", now: t0)
        l.setBinMode(.now, of: "S", now: t0)            // смена режима ничего не стирает
        let gone = l.sweepBins(now: t0 + 30 * RefLibrary.binDayMs, shootEnded: { _ in true })
        #expect(gone.isEmpty)
        #expect(bin(l) == ["f1"])
    }

    // MARK: после окончания съёмки

    @Test func shootModeWaitsForEndOfShoot() {
        var l = library(mode: .shoot)
        l.discard(["f1"], from: "S", now: t0)
        #expect(l.sweepBins(now: t0 + 30 * RefLibrary.binDayMs) { _ in false }.isEmpty)   // сколько ни прошло — съёмка идёт
        #expect(bin(l) == ["f1"])
        #expect(l.sweepBins(now: t0 + 30 * RefLibrary.binDayMs) { $0.sid == "s1" } == ["f1"])
        #expect(bin(l).isEmpty)
    }

    @Test func shootModeAfterTheEndGoesAtOnce() {
        var l = library(mode: .shoot)
        let gone = l.discard(["f1"], from: "S", now: t0, shootEnded: true)
        #expect(gone == ["f1"])
        #expect(bin(l).isEmpty)
    }

    @Test func weekModeIgnoresShootEnd() {
        var l = library()
        l.discard(["f1"], from: "S", now: t0)
        #expect(l.sweepBins(now: t0 + week - second) { _ in true }.isEmpty)
    }

    // MARK: вернуть, очистить

    @Test func restoreGoesBackToItsPlace() {
        var l = library()
        l.discard(["f3"], from: "S", now: t0)
        #expect(l.board("S")?.items == ["f1", "f2", "f4"])
        #expect(l.restore(["f3"], into: "S", now: t0 + second) == ["f3"])
        #expect(l.board("S")?.items == ["f1", "f2", "f3", "f4"])
        #expect(bin(l).isEmpty)
    }

    @Test func restoreClampsPlaceToTheEnd() {
        var l = library()
        l.discard(["f4"], from: "S", now: t0)           // стоял на месте 3
        l.discard(["f1", "f2", "f3"], from: "S", now: t0)
        l.restore(["f4"], into: "S")
        #expect(l.board("S")?.items == ["f4"])
    }

    @Test func restoreWithoutBoardLeavesTheEntry() {
        var l = library()
        l.discard(["f1"], from: "S", now: t0)
        #expect(l.restore(["f1"], into: "нет такой").isEmpty)
        #expect(bin(l) == ["f1"])
    }

    @Test func purgeTakesOnlyWhatWasConfirmed() {
        var l = library()
        l.discard(["f1", "f3"], from: "S", now: t0)
        let asked = l.binned("S").filter { $0.id == "f1" }
        let gone = l.purgeBin(asked, of: "S")           // f3 убрали уже после вопроса — не трогаем
        #expect(gone == ["f1"])
        #expect(bin(l) == ["f3"])
        #expect(fund(l).contains("f3"))
    }

    @Test func purgeSkipsAFrameThatWasRestoredAndRemovedAgain() {
        var l = library()
        l.discard(["f1"], from: "S", now: t0)
        let asked = l.binned("S")                       // подтвердили очистку этой записи
        l.restore(["f1"], into: "S")
        l.discard(["f1"], from: "S", now: t0 + 5 * second)   // убрали снова — запись другая
        #expect(l.purgeBin(asked, of: "S").isEmpty)
        #expect(bin(l) == ["f1"] && fund(l).contains("f1"))
    }

    @Test func frameHeldByAnUnreadBoardStaysInTheFund() {
        let raw: JSONValue = .object(["id": .string("X"), "kind": .string("mystery"), "items": .array([.string("f1")])])
        var extra: [String: JSONValue] = [:]
        library().write(into: &extra)
        guard case .array(var bs)? = extra["boards"] else { Issue.record("нет подборок"); return }
        bs.append(raw)
        extra["boards"] = .array(bs)
        var l = RefLibrary(extra: extra)
        l.discard(["f1"], from: "S", now: t0)
        #expect(l.liveShots.map(\.id).contains("f1"))   // чужая подборка держит кадр на виду
    }

    @Test func emptyBoardWithBinIsKept() {
        var l = library()
        l.discard(["f1", "f2", "f3", "f4"], from: "S", now: t0)
        #expect(l.board("S")?.items.isEmpty == true)
        #expect(l.board("S") != nil)                    // подборку держит корзина
        l.purgeBin(l.binned("S"), of: "S")
        #expect(l.board("S") == nil)                    // пустая и без корзины — исчезает, как раньше
    }

    @Test func deletingTheBoardTakesItsBinWithIt() {
        var l = library()
        l.discard(["f1", "f2"], from: "S", now: t0)
        #expect(l.loneCount("S") == 2)                  // подпись листа считает то, что на глазах: f3, f4 (f2 — и в жанре)
        let gone = l.dropWithShots("S")
        #expect(Set(gone) == ["f1", "f3", "f4"])
        #expect(fund(l) == ["f2"])
    }

    // MARK: чужие читатели

    @Test func binOnlyFramesAreHiddenFromFundSearch() {
        var l = library()
        l.discard(["f1", "f2"], from: "S", now: t0)
        #expect(Set(l.liveShots.map(\.id)) == ["f2", "f3", "f4"])   // f2 лежит в жанре, f1 — только в корзине
    }

    @Test func shootBoardWithOnlyBinStaysOnTheStrip() {
        var l = library()
        l.discard(["f1", "f2", "f3", "f4"], from: "S", now: t0)
        let session = Session(id: "s1", day: CivilDate(year: 2026, month: 10, day: 20), start: 600)
        let tiles = Moodboard.folders(library: l, sessions: [session], genresOn: [])
        #expect(tiles.contains { $0.boardId == "S" })
    }

    // MARK: файл

    @Test func binSurvivesTheRoundTrip() {
        var l = library(mode: .never)
        l.discard(["f1", "f3"], from: "S", now: t0)
        var extra: [String: JSONValue] = [:]
        l.write(into: &extra)
        let back = RefLibrary(extra: extra)
        #expect(back.board("S")?.bin == l.board("S")?.bin)
        #expect(back.board("S")?.binMode == .never)
        var again: [String: JSONValue] = [:]
        back.write(into: &again)
        #expect(again == extra)                         // чтение-запись ничего не меняет
    }

    @Test func unknownBinModeAndForeignEntriesComeBackAsTheyWere() {
        let raw: JSONValue = .object([
            "id": .string("S"), "kind": .string("shoot"), "sid": .string("s1"), "items": .array([]),
            "binMode": .string("monthly"),
            "bin": .array([.object(["id": .string("f1"), "at": .number(5)]), .string("чужое")]),
        ])
        var extra: [String: JSONValue] = ["boards": .array([raw]), "shots": .array([])]
        let l = RefLibrary(extra: extra)
        #expect(l.board("S")?.binMode == nil)
        #expect(l.board("S")?.effectiveBinMode == .week)
        #expect(l.board("S")?.bin.count == 1)
        l.write(into: &extra)
        guard case .array(let bs)? = extra["boards"], case .object(let o) = bs[0] else { Issue.record("нет подборки"); return }
        #expect(o["binMode"] == .string("monthly"))
        guard case .array(let b)? = o["bin"] else { Issue.record("нет корзины"); return }
        #expect(b.count == 2 && b.contains(.string("чужое")))
    }

    @Test func defaultModeIsWeek() {
        #expect(RefBinMode.standard == .week)
        #expect(library().board("S")?.effectiveBinMode == .week)
    }
}
