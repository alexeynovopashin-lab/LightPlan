import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Оборудование и документы заказа в форме (итерация 24, шаг 4а).
@Suite struct FormKitTests {
    func fresh() -> EventForm {
        EventForm.new(id: "k1", day: CivilDate(year: 2026, month: 10, day: 3), start: 900, fromLight: false,
                      genre: .wedding, light: nil)
    }

    @Test func kitCountsOnlyWhatIsStillInTheList() {
        var f = fresh()
        var list = ["Вспышка", "85 мм"]
        #expect(!f.hasTypedContent)
        f.toggleGear("Вспышка")
        #expect(f.kitChecked(in: list) == 1 && f.hasTypedContent, "взятая техника — набранное: черновик её держит")
        Kit.add("  Штатив ", to: &list, form: &f)
        #expect(list == ["Вспышка", "85 мм", "Штатив"] && f.gear == ["Вспышка", "Штатив"], "новая позиция сразу взята")
        Kit.add("Штатив", to: &list, form: &f)
        #expect(list.count == 3 && f.gear.count == 2, "повтор имени не множится")
        Kit.remove(at: 0, from: &list, form: &f)
        #expect(list == ["85 мм", "Штатив"] && f.gear == ["Штатив"])
        f.toggleGear("Штатив")
        #expect(f.gear.isEmpty)
        var old = f; old.gear = ["Старая вспышка"]
        #expect(old.kitChecked(in: list) == 0, "убранная из списка позиция в счёт не идёт")
    }

    @Test func docLinksGuessKindAndFilter() {
        var f = fresh()
        f.addDocLink("disk.yandex.ru/i/dogovor-romashka", kind: nil)
        f.addDocLink("https://example.org/smeta", kind: .invoice)
        f.addDocLink("   ", kind: nil)
        #expect(f.docs.count == 2)
        #expect(f.docs[0].url == "https://disk.yandex.ru/i/dogovor-romashka" && f.docs[0].kind == .contract)
        #expect(f.docCount(.invoice) == 1 && f.docsShown(kind: .contract).map(\.index) == [0])
        #expect(f.docsShown(kind: nil).count == 2)
        let s = f.session(orgName: nil, and: " и ")
        #expect(s.docs == f.docs)
        let back = try! #require(EventForm.fromDraft(f.draftData()!))
        #expect(back.docs == f.docs, "черновик держит документы")
        f.removeDoc(at: 0)
        #expect(f.docs.map(\.kind) == [.invoice])
    }

    @Test func docCardWords() {
        let link = Attachment(source: .link, url: "https://www.disk.yandex.ru/d/Folder/%D0%A1%D0%BC%D0%B5%D1%82%D0%B0.pdf/")
        #expect(DocLabel.top(link, kindName: { $0.rawValue }, fileWord: "файл", linkWord: "Ссылка") == "disk.yandex.ru")
        #expect(DocLabel.sub(link, anyWord: "документ") == "документ", "сайт уже сверху, хвост адреса именем не бывает")
        let known = Attachment(source: .link, url: "https://www.disk.yandex.ru/d/4coXjmnBnE7p-g", kind: .contract)
        #expect(DocLabel.sub(known, anyWord: "документ") == "disk.yandex.ru", "вид сверху — снизу сайт")
        var named = known; named.title = "Договор с Ромашкой"
        #expect(DocLabel.sub(named, anyWord: "документ") == "Договор с Ромашкой", "своё название главнее")
        let bare = Attachment(source: .link, url: "https://example.org")
        #expect(DocLabel.sub(bare, anyWord: "") == "", "сверху сайт, снизу слова нет")
        let file = Attachment(source: .doc, path: "/LightPlan/docs/akt.PDF", name: "akt.PDF")
        #expect(DocLabel.top(file, kindName: { $0.rawValue }, fileWord: "файл", linkWord: "") == "PDF")
        #expect(DocLabel.top(Attachment(source: .doc, name: "scan"), kindName: { $0.rawValue }, fileWord: "файл", linkWord: "") == "файл")
        #expect(DocLabel.top(Attachment(source: .doc, name: "x.pdf", kind: .act), kindName: { "акт·" + $0.rawValue }, fileWord: "", linkWord: "") == "акт·act")
    }
}
