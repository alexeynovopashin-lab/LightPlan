import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Итерация 28, шаг 4: перенос кадров правкой ссылок, без копий; неизвестные поля не теряются.
struct RefLibraryTests {
    /// Замер беты 30.09: 19 кадров; «Свадьба» — 10, «На море» — 2 (`zz_3` там уже лежит).
    private func measured() -> RefLibrary {
        let ids = ["sd_sh_wedding"] + (0..<18).map { "zz_\($0)" }
        let wedding = RefBoard(id: "w", kind: .tpl, genre: "wedding", items: ["sd_sh_wedding"] + (0..<9).map { "zz_\($0)" })
        let sea = RefBoard(id: "sea", kind: .tpl, genre: "wedding", items: ["zz_3", "zz_9"], name: "На море")
        return RefLibrary(shots: ids.map { RefFrame(id: $0) }, boards: [wedding, sea])
    }

    @Test func moveKeepsOneCopyOfEachShot() {
        var lib = measured()
        #expect(lib.shots.count == 19)
        #expect(lib.board("w")?.items.count == 10 && lib.board("sea")?.items.count == 2)
        let added = lib.move(["zz_0", "zz_3"], from: "w", to: "sea", remove: true)
        #expect(added == ["zz_0"])                       // zz_3 уже лежал: дубля нет
        #expect(lib.shots.count == 19)                   // 19 → 19
        #expect(lib.board("w")?.items.count == 8)        // 10 → 8
        #expect(lib.board("sea")?.items.count == 3)      // 2 → 3
        #expect(Set(lib.board("sea")!.items).count == 3)
        #expect(lib.board("w")?.items.contains("zz_0") == false && lib.board("w")?.items.contains("zz_3") == false)
    }

    @Test func putRefusesDuplicateInOneBoard() {
        var lib = measured()
        let r29 = lib.put("zz_3", into: "sea")
        #expect(r29 == false)
        #expect(lib.board("sea")?.items == ["zz_3", "zz_9"])
        let r32 = lib.put("zz_0", into: "sea")
        #expect(r32)
        #expect(lib.board("sea")?.items == ["zz_3", "zz_9", "zz_0"])
        let r35 = lib.put("zz_1", into: "sea", at: 1)
        #expect(r35)
        #expect(lib.board("sea")?.items == ["zz_3", "zz_1", "zz_9", "zz_0"])
        let r38 = lib.put("zz_2", into: "нет")
        #expect(r38 == false)
    }

    @Test func moveIntoSameBoardIsNoOp() {
        var lib = measured()
        let before = lib
        let added = lib.move(["zz_0", "zz_1"], from: "w", to: "w", remove: true)
        #expect(added.isEmpty)
        #expect(lib == before)                           // кадры со своей подборки не сняты
    }

    @Test func addWithoutRemoveLeavesSource() {
        var lib = measured()
        lib.move(["zz_0"], from: "w", to: "sea", remove: false)
        #expect(lib.board("w")?.items.contains("zz_0") == true)
        #expect(lib.board("sea")?.items.contains("zz_0") == true)
        #expect(lib.shots.count == 19)
    }

    @Test func takeKeepsShotInFund() {
        var lib = measured()
        let r60 = lib.take("zz_0", from: "w")
        #expect(r60)
        let r62 = lib.take("zz_0", from: "w")
        #expect(r62 == false)
        #expect(lib.shot("zz_0") != nil)
        #expect(lib.isUsed("zz_0") == false)
    }

    @Test func pruneRemovesOnlyEmptyUnnamedShootBoards() {
        var lib = RefLibrary(shots: [RefFrame(id: "a")], boards: [
            RefBoard(id: "own", kind: .shoot, sid: "s1", items: ["a"]),
            RefBoard(id: "named", kind: .shoot, sid: "s2", name: "Имя"),
            RefBoard(id: "covered", kind: .shoot, sid: "s3", cover: "a"),
            RefBoard(id: "tpl", kind: .tpl, genre: "portrait"),
            RefBoard(id: "dst", kind: .tpl, genre: "wedding")])
        let p1 = lib.prune("named"), p2 = lib.prune("covered"), p3 = lib.prune("tpl")
        #expect(!p1 && !p2 && !p3)
        // Перенос опустошает съёмочную подборку — она исчезает, жанровая осталась бы.
        lib.move(["a"], from: "own", to: "dst", remove: true)
        #expect(lib.board("own") == nil)
        #expect(lib.board("dst")?.items == ["a"])
        #expect(lib.board("tpl") != nil)
    }

    @Test func dropWithShotsRemovesOnlyLoneShots() {
        var lib = measured()                             // zz_3 лежит в двух папках, zz_0 — только в «Свадьбе»
        let gone = lib.dropWithShots("w")
        #expect(lib.board("w") == nil)
        #expect(gone.contains("zz_0") && !gone.contains("zz_3"))
        #expect(lib.shot("zz_0") == nil)                 // насовсем
        #expect(lib.shot("zz_3") != nil)                 // жив в «На море»
        #expect(lib.shots.count == 19 - gone.count)
        #expect(gone.count == 9)                         // 10 в папке минус zz_3
    }

    @Test func dropShotRemovesFromEveryBoard() {
        var lib = measured()
        lib.put("zz_0", into: "sea")
        let r97 = lib.dropShot("zz_0")
        #expect(r97)
        #expect(lib.boards.allSatisfy { !$0.items.contains("zz_0") })
        let r100 = lib.dropShot("zz_0")
        #expect(r100 == false)
    }

    @Test func mergeMovesMissingAndDropsSource() {
        var lib = measured()
        let moved = lib.merge("w", into: "sea")
        #expect(lib.board("w") == nil)
        #expect(moved.count == 9)                        // zz_3 не дублируется
        #expect(lib.board("sea")?.items.count == 11)
        #expect(Set(lib.board("sea")!.items).count == 11)
        #expect(lib.shots.count == 19)                   // кадры из фонда не уходят
        let self1 = lib.merge("sea", into: "sea")
        #expect(self1.isEmpty && lib.board("sea") != nil)
    }

    @Test func editStampsMt() {
        var lib = measured()
        lib.put("zz_0", into: "sea", now: 111)
        #expect(lib.board("sea")?.mt == 111)
        lib.put("zz_0", into: "sea", now: 222)           // дубль — правки не было
        #expect(lib.board("sea")?.mt == 111)
    }

    // MARK: - Неизвестные поля

    private func obj(_ p: [String: JSONValue]) -> JSONValue { .object(p) }

    @Test func unknownFieldsSurviveReadWrite() {
        let shot = obj(["id": .string("a"), "k": .string("link"), "url": .string("https://x.y/p"),
                        "pending": .bool(true), "mt": .number(5), "future": obj(["n": .number(1)])])
        let board = obj(["id": .string("b"), "kind": .string("tpl"), "genre": .string("wedding"),
                         "items": .array([.string("a")]), "name": .null, "cover": .null, "hue": .number(3),
                         "keep": obj(["mode": .string("half"), "at": .number(9), "by": .string("x")]), "mt": .number(7)])
        let strangeBoard = obj(["id": .string("q"), "kind": .string("album"), "items": .array([])])
        let extra: [String: JSONValue] = ["shots": .array([shot, .string("сирота")]),
                                          "boards": .array([board, strangeBoard]), "zones": .string("не моё")]
        var out = extra
        RefLibrary(extra: extra).write(into: &out)
        #expect(out == extra)                            // слово в слово, включая чужие записи
        let lib = RefLibrary(extra: extra)
        #expect(lib.shots[0].extra["pending"] == .bool(true) && lib.shots[0].mt == 5)
        #expect(lib.boards[0].extra["hue"] == .number(3) && lib.boards[0].mt == 7)
    }

    @Test func keepIsStoredAndEditedFieldsWriteBack() {
        let board = obj(["id": .string("b"), "kind": .string("tpl"), "genre": .string("wedding"),
                         "items": .array([]), "keep": obj(["mode": .string("ever"), "at": .number(42)])])
        var lib = RefLibrary(extra: ["boards": .array([board])])
        #expect(lib.boards[0].keep == RefKeep(mode: "ever", at: 42))
        lib.boards[0].keep = RefKeep(mode: "day", at: 43)
        lib.boards[0].sort = 2
        var out: [String: JSONValue] = [:]
        lib.write(into: &out)
        let back = RefLibrary(extra: out)
        #expect(back.boards[0].keep == RefKeep(mode: "day", at: 43) && back.boards[0].sort == 2)
    }

    @Test func boardWithoutIdGetsStableId() {
        let b = obj(["kind": .string("shoot"), "sid": .string("s9"), "items": .array([])])
        let one = RefLibrary(extra: ["boards": .array([b])]).boards[0].id
        let two = RefLibrary(extra: ["boards": .array([b])]).boards[0].id
        #expect(!one.isEmpty && one == two)
    }

    // MARK: - Первый запуск

    @Test func seedMakesOneEmptyFolderPerGenreOnce() {
        var n = 0
        var extra: [String: JSONValue] = ["boards": .array([RefBoard(id: "old", kind: .tpl, genre: "wedding", items: ["a"]).json])]
        let changed = RefLibrary.seedGenreFolders(in: &extra, genres: ["wedding", "portrait", "family"],
                                                  newId: { n += 1; return "n\(n)" })
        #expect(changed)
        let lib = RefLibrary(extra: extra)
        #expect(lib.boards.count == 3)                   // у «Свадьбы» своя папка уже есть
        #expect(lib.folders(ofGenre: "wedding").map(\.id) == ["old"])
        #expect(lib.folders(ofGenre: "portrait").first?.items.isEmpty == true)
        #expect(extra["mbSeeded"] == .bool(true))
        // Второй запуск: убранную человеком папку не возвращаем.
        var lib2 = RefLibrary(extra: extra)
        lib2.boards.removeAll { $0.genre == "family" }
        lib2.write(into: &extra)
        #expect(RefLibrary.seedGenreFolders(in: &extra, genres: ["wedding", "portrait", "family"],
                                            newId: { "x" }) == false)
        #expect(RefLibrary(extra: extra).boards.count == 2)
    }

    // MARK: - Ревью GPT к 1f449e1

    @Test func oddFieldsSurviveReadWrite() {
        let shot = obj(["id": .string("a"), "k": .string("video"), "tags": .array([.string("x"), .number(3)]),
                        "w": .string("широко")])
        let board = obj(["id": .string("b"), "kind": .string("tpl"), "genre": .string("wedding"),
                         "items": .array([.string("a"), .null]), "sort": .number(1e300),
                         "keep": obj(["at": .number(1)]), "name": .number(5), "cover": .null])
        let extra: [String: JSONValue] = ["shots": .array([shot]), "boards": .array([board])]
        var out = extra
        RefLibrary(extra: extra).write(into: &out)
        #expect(out == extra)                            // неизвестный k, чужие элементы, sort 1e300, keep без mode
        #expect(RefLibrary(extra: extra).boards[0].sort == 0)
    }

    @Test func unknownBoardHoldsShotAgainstDrop() {
        let strange = obj(["id": .string("q"), "kind": .string("album"), "items": .array([.string("zz_0")])])
        var extra: [String: JSONValue] = ["boards": .array([strange])]
        var lib = measured()
        lib.write(into: &extra)
        extra["boards"] = .array(RefLibrary(extra: extra).boards.map(\.json) + [strange])
        var back = RefLibrary(extra: extra)
        #expect(back.isUsed("zz_0"))
        let gone = back.dropWithShots("w")
        #expect(!gone.contains("zz_0") && back.shot("zz_0") != nil)
    }

    @Test func moveToSameBoardDoesNotAddForeignShot() {
        var lib = measured()
        let added = lib.move(["zz_15"], from: "w", to: "w", remove: true)   // zz_15 в «Свадьбе» не лежит
        #expect(added.isEmpty && lib.board("w")?.items.contains("zz_15") == false)
    }

    @Test func editingListKeepsForeignElementsAndHonoursRemoval() {
        let board = obj(["id": .string("b"), "kind": .string("tpl"), "genre": .string("wedding"),
                         "items": .array([.string("a"), .null, .string("c")])])
        let shot = obj(["id": .string("a"), "tags": .array([.string("x"), .number(3)])])
        var lib = RefLibrary(extra: ["boards": .array([board]), "shots": .array([shot])])
        lib.put("d", into: "b")
        lib.take("a", from: "b")
        lib.shots[0].tags = []                           // последний тег снят — он не возвращается
        var out: [String: JSONValue] = [:]
        lib.write(into: &out)
        guard case .array(let bs)? = out["boards"], case .object(let bo) = bs[0], case .array(let items)? = bo["items"],
              case .array(let ss)? = out["shots"], case .object(let so) = ss[0], case .array(let tags)? = so["tags"]
        else { Issue.record("нет полей"); return }
        #expect(items == [.string("c"), .null, .string("d")])
        #expect(tags == [.number(3)])
    }

    @Test func reorderIsWrittenInListOrder() {
        let board = obj(["id": .string("b"), "kind": .string("tpl"), "genre": .string("wedding"),
                         "items": .array([.string("a"), .null, .string("b"), .string("c")])])
        var lib = RefLibrary(extra: ["boards": .array([board])])
        lib.boards[0].items = ["c", "a", "b"]            // перестановка пальцем (29)
        var out: [String: JSONValue] = [:]
        lib.write(into: &out)
        guard case .array(let bs)? = out["boards"], case .object(let bo) = bs[0], case .array(let items)? = bo["items"]
        else { Issue.record("нет items"); return }
        #expect(items == [.string("c"), .null, .string("a"), .string("b")])   // чужой элемент на своём индексе
        var plain = RefLibrary(shots: [], boards: [RefBoard(id: "p", kind: .tpl, genre: "x", items: ["a", "b"])])
        plain.boards[0].items = ["b", "a"]
        var out2: [String: JSONValue] = [:]
        plain.write(into: &out2)
        #expect(RefLibrary(extra: out2).boards[0].items == ["b", "a"])
    }
}
