import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Люди в карточке организации (слово Алексея 01.10: «Директор, контактное лицо, добавить — маркетолог, секретарь»):
/// идут в «Контакты» со своей ролью.
@Suite struct OrgPeopleTests {
    static let ru = TelCountry.of("RU")!

    private func org() -> Org {
        var o = Org(id: "o1", name: "Агентство")
        o.person = "Ольга"; o.phone = "8 916 111-22-33"
        o.director = "Пётр Иванов"; o.directorPhone = "8 916 222-33-44"
        o.staff = [OrgPerson(role: "маркетолог", name: "Анна", phone: "8 916 333-44-55"),
                   OrgPerson(role: "секретарь", name: "Мария", phone: "8 916 444-55-66")]
        return o
    }

    @Test func everyPersonOfTheOrgIsInContactsWithOwnRole() {
        let g = PhoneBook.index(sessions: [], orgs: [org()], country: Self.ru)
        #expect(g.count == 4, "контактное лицо, директор, маркетолог, секретарь")
        func row(_ phone: String) -> PhoneBook.Row? {
            let k = TelFormat.full(phone, country: Self.ru)
            return g.first { $0.key == k }?.rows.first
        }
        #expect(row("8 916 111-22-33")?.field == PhoneBook.Field.org && row("8 916 111-22-33")?.name == "Ольга")
        #expect(row("8 916 222-33-44")?.field == PhoneBook.Field.director && row("8 916 222-33-44")?.name == "Пётр Иванов")
        #expect(PhoneBook.Field.staffRole(row("8 916 333-44-55")?.field ?? "") == "маркетолог")
        #expect(PhoneBook.Field.staffRole(row("8 916 444-55-66")?.field ?? "") == "секретарь")
        #expect(PhoneBook.Field.staffRole(PhoneBook.Field.director) == nil)
    }

    @Test func personWithoutRealNumberGivesNoContactAndRemovedPersonDisappears() {
        var o = org()
        o.staff[0].phone = "123"
        #expect(PhoneBook.index(sessions: [], orgs: [o], country: Self.ru).count == 3, "обрывок короче пяти цифр — не номер")
        OrgBook.removePerson(at: 0, from: &o)
        #expect(o.staff.map(\.role) == ["секретарь"])
    }

    @Test func removedDirectorNumberGoesToArchive() {
        let before = PhoneBook.tels(of: org(), country: Self.ru)
        var o = org(); o.directorPhone = ""
        let log = PhoneBook.retire(before: before, after: PhoneBook.tels(of: o, country: Self.ru), log: [], at: "2026-10-01", country: Self.ru)
        #expect(log.count == 1 && log[0].field == PhoneBook.Field.director && log[0].name == "Пётр Иванов")
    }

    @Test func blankRowsAreNotDataButTypedOnesKeepTheOrg() {
        var o = Org(id: "x")
        OrgBook.addPerson(to: &o)
        #expect(OrgBook.isBlank(o), "пустая строка «+ Добавить» организацию не создаёт")
        o.director = "Пётр"
        #expect(!OrgBook.isBlank(o))
        o.director = ""; o.staff[0].role = "секретарь"
        #expect(!OrgBook.isBlank(o), "роль набрана — это уже данные")
        OrgBook.addPerson(to: &o)
        OrgBook.pruneBlankPeople(&o)
        #expect(o.staff.count == 1)
    }

    @Test func peopleSurviveTheSnapshotAndAnOrgWithoutThemWritesAsBefore() throws {
        let back = try JSONDecoder().decode(Org.self, from: JSONEncoder().encode(org()))
        #expect(back == org())
        let plain = try JSONEncoder().encode(Org(id: "p", name: "ООО"))
        let text = String(decoding: plain, as: UTF8.self)
        #expect(!text.contains("dir") && !text.contains("staff"), "пустые новые поля не пишутся — запись как у веба")
    }
}
