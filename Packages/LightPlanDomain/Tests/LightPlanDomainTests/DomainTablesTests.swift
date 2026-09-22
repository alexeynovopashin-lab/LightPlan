import Foundation
import Testing
import LightPlanCore
@testable import LightPlanDomain

/// Таблицы домена совпадают с бетой позиция в позицию: тот же состав и тот же
/// порядок. Риск итерации 11 — тихая потеря пункта из таблицы; эти тесты падают
/// с именем таблицы и позицией, когда бета поменяла таблицу, а Swift — нет.
struct DomainTablesTests {
    let t = DomainOracle.file["tables"]

    func pairs(_ name: String) -> [(String, J)] {
        t[name].array!.map { ($0[0].string!, $0[1]) }
    }

    @Test func genreListAndOrders() {
        #expect(Genre.allCases.map(\.rawValue) == t["allGenres"].strings!, "ALL_GENRES")
        #expect(Genre.specOrder.map(\.rawValue) == pairs("genre").map(\.0), "порядок ключей GENRE")
        #expect(Genre.groupOrder.map(\.rawValue) == pairs("genreGroup").map(\.0), "порядок ключей GENRE_GROUP")
        #expect(Genre.deadlineOrder.map(\.rawValue) == pairs("deadline").map(\.0), "порядок ключей GENRE_DEADLINE")
        #expect(Genre.refTagsOrder.map(\.rawValue) == pairs("refTags").map(\.0), "порядок ключей GENRE_TAGS")
        #expect(Genre.subGenreOrder.map(\.rawValue) == pairs("subGenre").map(\.0), "порядок ключей SUBGENRE")
        #expect(Set(Genre.specOrder) == Set(Genre.allCases))
    }

    @Test func genreSpecRows() {
        for (code, row) in pairs("genre") {
            let g = Genre(rawValue: code)!, sp = g.spec
            #expect(sp.delivery == row["delivery"].bool!, "\(code).delivery")
            #expect(sp.client == row["client"].bool!, "\(code).client")
            #expect(sp.duration == row["dur"].int, "\(code).dur")
            #expect(sp.pay.map(\.rawValue) == row["pay"].strings!, "\(code).pay")
            #expect(sp.explicitRoute == row["route"].bool, "\(code).route")
            #expect(sp.breed == (row["breed"].bool ?? false), "\(code).breed")
            #expect(sp.models == (row["models"].bool ?? false), "\(code).models")
        }
        #expect(pairs("genre").count == Genre.allCases.count)
    }

    @Test func groups() {
        for (code, group) in pairs("genreGroup") {
            #expect(Genre(rawValue: code)!.group.rawValue == group.string!, "GENRE_GROUP.\(code)")
        }
        #expect(GenreGroup.allCases.map(\.rawValue) == pairs("group").map(\.0), "порядок ключей GROUP")
        for (code, row) in pairs("group") {
            let sp = GenreGroup(rawValue: code)!.spec
            #expect(sp.route.rawValue == row["route"].string!, "\(code).route")
            #expect(sp.pack == (row["pack"].bool ?? false), "\(code).pack")
            #expect(sp.guests == (row["guests"].bool ?? false), "\(code).guests")
            #expect(sp.prepay == (row["prepay"].bool ?? false), "\(code).prepay")
            #expect(sp.org == (row["org"].bool ?? false), "\(code).org")
            #expect(sp.order == (row["order"].bool ?? false), "\(code).order")
        }
    }

    /// `genreSpec` веба с выводом маршрута от группы и незнакомым жанром «x».
    @Test func genreProfilesMatchGenreSpec() {
        for row in t["genreSpec"].array! {
            let code = row[0].string!, p = GenreProfile(Genre(rawValue: code))
            let sp = row[1]
            #expect(p.spec.delivery == sp["delivery"].bool!, "\(code)")
            #expect(p.spec.duration == sp["dur"].int, "\(code).dur")
            #expect(p.spec.pay.map(\.rawValue) == sp["pay"].strings!, "\(code).pay")
            #expect(p.hasRoute == (sp["route"].bool!), "\(code).route")
            #expect(p.routeOptional == sp["routeOpt"].bool!, "\(code).routeOpt")
            #expect(p.group.rawValue == row[2].string!, "\(code) group")
            #expect(p.groupSpec.route.rawValue == row[3]["route"].string!, "\(code) group route")
            #expect(p.hasRoute == row[4].bool!, "\(code) hasRoute")
        }
    }

    @Test func pay() {
        #expect(PayKind.allCases.map(\.rawValue) == pairs("pay").map(\.0), "порядок PAY")
        for (code, row) in pairs("pay") {
            let k = PayKind(rawValue: code)!
            #expect(k.mechanic.rawValue == row["m"].string!, "PAY.\(code).m")
            #expect(k.countsUnits == (row["unit"].bool ?? false), "PAY.\(code).unit")
        }
    }

    @Test func subGenres() {
        var seen = Set<SubGenre>()
        for (code, list) in pairs("subGenre") {
            let g = Genre(rawValue: code)!
            let rows = list.array!.map { ($0[0].string!, $0[1].string!) }
            #expect(g.subGenres.map(\.rawValue) == rows.map(\.0), "SUBGENRE.\(code)")
            for (sub, icon) in rows {
                #expect(SubGenre(rawValue: sub)?.iconName == icon, "SUBGENRE.\(code).\(sub)")
                seen.insert(SubGenre(rawValue: sub)!)
            }
        }
        #expect(Genre.street.subGenres.isEmpty, "у стрита уточнений нет")
        #expect(seen == Set(SubGenre.allCases), "в Swift нет лишних уточнений")
    }

    @Test func persons() {
        let rows = pairs("persons")
        #expect(rows.map(\.0) == ["wedding", "party"])
        for (code, list) in rows {
            #expect(Genre(rawValue: code)!.persons.map { "person." + $0.rawValue } == list.strings!, "GENRE_PERSONS.\(code)")
        }
        for g in Genre.allCases where !rows.map(\.0).contains(g.rawValue) { #expect(g.persons.isEmpty, "\(g)") }
    }

    @Test func refTags() {
        var used = Set<RefTag>()
        for (code, list) in pairs("refTags") {
            let tags = Genre(rawValue: code)!.refTags
            #expect(tags.map(\.rawValue) == list.strings!, "GENRE_TAGS.\(code)")
            used.formUnion(tags)
        }
        #expect(RefTag.defaults.map(\.rawValue) == t["refTagsDefault"].strings!, "REF_TAGS_DEFAULT")
        used.formUnion(RefTag.defaults)
        #expect(used == Set(RefTag.allCases), "в Swift нет лишних папок")
        let codes = pairs("tagCode")
        #expect(RefTag.russianNames.map(\.name) == codes.map(\.0), "TAG_CODE: имена")
        #expect(RefTag.russianNames.map(\.tag.rawValue) == codes.map { $0.1.string! }, "TAG_CODE: коды")
    }

    @Test func deadlines() {
        for (code, days) in pairs("deadline") {
            #expect(Genre(rawValue: code)!.deliveryDays == days.int!, "GENRE_DEADLINE.\(code)")
        }
        #expect(GenreProfile(nil).deliveryDays == 7, "незнакомый жанр — неделя")
        #expect(Delivery.dayChoices == t["delvDays"].array!.map { $0.int! }, "DELV_DAYS")
        let d = t["constants"]["defaultDelivery"]
        #expect(DeliverySetting.standard.mode.rawValue == d["mode"].string! && DeliverySetting.standard.days == d["days"].int!)
    }

    @Test func blockKindsWishesCurrencies() {
        let bk = t["blockKinds"].array!
        #expect(BlockKind.allCases.map(\.rawValue) == bk.map { $0["k"].string! }, "BLOCK_KINDS")
        #expect(BlockKind.allCases.map(\.iconName) == bk.map { $0["ic"].string! }, "BLOCK_KINDS: знаки")
        #expect(Wish.allCases.map(\.rawValue) == t["wishes"].strings!, "WISHES")
        #expect(Wish.light.map(\.rawValue) == t["lightWish"].strings!, "LIGHT_WISH")
        #expect(Wish.allCases.filter(\.asksLight) .count == Wish.light.count)
        #expect(Currency.allCases.map(\.rawValue) == t["currencies"].strings!, "CURRENCIES")
    }

    @Test func cardBlocks() {
        let cb = t["cardBlocks"].array!
        #expect(CardBlock.allCases.map(\.rawValue) == cb.map { $0["k"].string! }, "CARD_BLOCKS")
        #expect(CardBlock.allCases.map(\.iconName) == cb.map { $0["ic"].string! }, "CARD_BLOCKS: знаки")
        let go = pairs("groupOrder")
        #expect(go.map(\.0) == ["client"], "GROUP_ORDER: только у заказа")
        #expect(CardOrder.clientOrder.map(\.rawValue) == go[0].1.strings!, "GROUP_ORDER.client")
        #expect(CardOrder.afterFirst.map(\.rawValue) == t["afterFirst"].strings!, "AFTER_FIRST")
    }

    @Test func practices() {
        #expect(Practice.allCases.map(\.rawValue) == t["practices"].strings!, "PRACTICES")
        #expect(Practice.allCases.map(\.rawValue) == pairs("practice").map(\.0), "порядок PRACTICE")
        for (code, row) in pairs("practice") {
            let p = Practice(rawValue: code)!
            #expect(p.chain.map(\.rawValue) == row["chain"].strings!, "PRACTICE.\(code).chain")
            #expect(p.docKinds.map(\.rawValue) == row["docs"].strings!, "PRACTICE.\(code).docs")
            #expect(p.dealForAll == row["dealForAll"].bool!, "PRACTICE.\(code).dealForAll")
        }
    }

    @Test func docGuessPatterns() {
        let rows = t["docGuess"].array!
        #expect(DocKind.guessPatterns.map(\.pattern) == rows.map { $0[0].string! }, "DOC_GUESS: образцы")
        #expect(rows.allSatisfy { $0[1].string == "i" }, "DOC_GUESS: флаги — только i")
        #expect(DocKind.guessPatterns.map(\.kind.rawValue) == rows.map { $0[2].string! }, "DOC_GUESS: виды")
    }

    @Test func formFieldsRows() {
        #expect(FormField.allCases.count == t["formFields"].array!.count, "FORM_FIELDS: число строк")
    }

    @Test func constants() {
        let c = t["constants"]
        #expect(Overlaps.farTrip == c["farMin"].int!, "FAR_MIN")
        #expect(Overlaps.flight == c["flyMin"].int!, "FLY_MIN")
        #expect(LightCase.goldEarly == c["goldEarly"].double!, "GOLD_EARLY")
    }
}
