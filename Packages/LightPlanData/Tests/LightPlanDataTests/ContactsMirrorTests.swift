import Foundation
import Testing
import LightPlanCore
import LightPlanDomain
@testable import LightPlanData

/// Клиенты в Контактах iPhone (шаг К7): проход по подставной книге `InMemoryContactsStore`. Настоящая книга —
/// `Tools/contacts_sim.py` на симуляторе.
@Suite struct ContactsMirrorTests {
    private let ru = TelCountry.of("RU")!

    private func client(_ id: String, _ kind: ClientKind = .person, _ people: [(String, String)]) -> Client {
        var c = Client(id: id, kind: kind)
        c.people = people.map { ClientPerson(name: $0.0, phone: $0.1) }
        return c
    }

    private func sync(_ m: ContactsMirror, _ clients: [Client], allowed: Set<String>? = nil,
                      annivs: [String: CivilDate] = [:]) async -> ContactsMirror.Outcome {
        await m.sync(clients: clients, allowed: allowed ?? Set(clients.map(\.id)), anniversaries: annivs, country: ru)
    }

    private func appEntries(_ s: InMemoryContactsStore) -> [InMemoryContactsStore.Entry] { s.entries.filter { $0.card != nil } }

    @Test func onePersonOneContactCoupleIsTwo() async {
        let store = InMemoryContactsStore(), memory = InMemoryContactsMemory()
        let m = ContactsMirror(store: store, memory: memory)
        let pair = client("p", .couple, [("Анна Петрова", "+7 903 111-22-33"), ("Иван Петров", "8 903 444-55-66")])
        let fam = client("f", .family, [("Мария", "8 913 222-33-44"), ("Петя", "")])
        let day = CivilDate(year: 2025, month: 6, day: 14)
        guard case .synced(let r) = await sync(m, [pair, fam], annivs: ["p": day]) else { Issue.record("нет прохода"); return }
        #expect(r.created == 3)
        let made = appEntries(store)
        #expect(made.map { $0.card!.phone }.sorted() == ["+79031112233", "+79034445566", "+79132223344"])
        #expect(made.filter { $0.card!.anniversary == day }.count == 2)
        #expect(Set(memory.record.links.keys) == ["p#0", "p#1", "f#0"])
        // Второй проход ничего не пишет.
        let before = store.writes
        _ = await sync(m, [pair, fam], annivs: ["p": day])
        #expect(store.writes == before)
    }

    @Test func numberAlreadyInTheBookIsNotWrittenTheirsIsOnlyRead() async {
        let store = InMemoryContactsStore(), memory = InMemoryContactsMemory()
        let mine = FoundContact(name: "Нина Своя", phones: ["8 (913) 000-00-01"], birthday: "1960-03-08",
                                messengers: [ClientMessenger(kind: "telegram", value: "nina")])
        let id = store.addOwn(mine)
        let m = ContactsMirror(store: store, memory: memory)
        guard case .synced(let r) = await sync(m, [client("n", .person, [("Нина", "+7 913 000-00-01")])]) else { Issue.record("нет прохода"); return }
        #expect(r.created == 0 && store.writes == 0)
        #expect(store.entries == [InMemoryContactsStore.Entry(id: id, card: nil, found: mine)])
        #expect(r.fills.map(\.found) == [mine])
        #expect(r.fills.first?.read == ClientContacts.Read(client: "n", person: 0, contactId: id))
    }

    @Test func editsGoOnlyToOwnContacts() async {
        let store = InMemoryContactsStore(), memory = InMemoryContactsMemory()
        let theirs = FoundContact(name: "Нина Своя", phones: ["+79130000001"])
        store.addOwn(theirs)
        let m = ContactsMirror(store: store, memory: memory)
        var olga = client("o", .person, [("Ольга Смирнова", "8 916 123-45-67")])
        let nina = client("n", .person, [("Нина", "8 913 000-00-01")])
        _ = await sync(m, [olga, nina])
        let id = memory.record.links["o#0"]!.id
        olga.people[0].name = "Ольга Петрова"
        guard case .synced(let r) = await sync(m, [olga, nina]) else { Issue.record("нет прохода"); return }
        #expect(r.updated == 1 && r.created == 0)
        #expect(appEntries(store).map(\.id) == [id])
        #expect(appEntries(store).first?.card?.family == "Петрова")
        #expect(store.entries.first { $0.card == nil }?.found == theirs)
    }

    @Test func removeAllTakesOnlyWhatTheAppWrote() async {
        let store = InMemoryContactsStore(), memory = InMemoryContactsMemory()
        let theirs = FoundContact(name: "Нина Своя", phones: ["+79130000001"])
        let own = store.addOwn(theirs)
        let m = ContactsMirror(store: store, memory: memory)
        _ = await sync(m, [client("a", .person, [("Ольга", "8 916 123-45-67")]), client("b", .person, [("Олег", "8 916 765-43-21")])])
        #expect(appEntries(store).count == 2)
        let out = await m.removeAll()
        #expect(out?.removed == 2 && out?.failed == 0)
        #expect(store.entries.map(\.id) == [own])
        #expect(memory.record.links.isEmpty)
    }

    @Test func ownContactDeletedByHandIsNotRecreated() async {
        let store = InMemoryContactsStore(), memory = InMemoryContactsMemory()
        let m = ContactsMirror(store: store, memory: memory)
        let c = client("a", .person, [("Ольга", "8 916 123-45-67")])
        _ = await sync(m, [c])
        store.deleteByHand(memory.record.links["a#0"]!.id)
        guard case .synced(let r) = await sync(m, [c]) else { Issue.record("нет прохода"); return }
        #expect(r.gone == 1 && r.created == 0)
        _ = await sync(m, [c])
        #expect(store.entries.isEmpty && memory.record.dropped == ["a#tel:79161234567"])
    }

    /// Ревью GPT к d613efc: удалили первого человека семьи — его контакт остаётся своим (связь не затёрта), и «Убрать всё»
    /// убирает оба.
    @Test func shiftedPeopleKeepEveryOwnContactKnown() async {
        let store = InMemoryContactsStore(), memory = InMemoryContactsMemory()
        let m = ContactsMirror(store: store, memory: memory)
        var fam = client("f", .family, [("Мария", "8 913 222-33-44"), ("Иван", "8 913 555-66-77")])
        _ = await sync(m, [fam])
        let ids = Set(memory.record.links.values.map(\.id))
        fam.people.remove(at: 0)
        guard case .synced(let r) = await sync(m, [fam]) else { Issue.record("нет прохода"); return }
        #expect(r.updated == 1 && r.created == 0)
        #expect(Set(memory.record.links.values.map(\.id)) == ids)
        #expect(memory.record.links["f#0"]?.card.given == "Иван")
        #expect(await m.removeAll()?.removed == 2)
        #expect(store.entries.isEmpty)
    }

    @Test func partialOrNoAccessWritesNothing() async {
        for auth in [ContactsAuthorization.limited, .denied, .notDetermined] {
            let store = InMemoryContactsStore(auth: auth), memory = InMemoryContactsMemory()
            let m = ContactsMirror(store: store, memory: memory)
            #expect(await sync(m, [client("a", .person, [("Ольга", "8 916 123-45-67")])]) == .noAccess(auth))
            #expect(await m.removeAll() == nil)
            #expect(store.writes == 0 && store.entries.isEmpty)
        }
    }

    @Test func notAllowedClientsAreNotWritten() async {
        let store = InMemoryContactsStore(), memory = InMemoryContactsMemory()
        let m = ContactsMirror(store: store, memory: memory)
        _ = await sync(m, [client("old", .person, [("Сергей", "8 999 555-66-77")])], allowed: [])
        #expect(store.entries.isEmpty)
    }

    @Test func recordReadsOldAndDefaultsToOn() throws {
        #expect(ContactsRecord().wanted)
        let r = try JSONDecoder().decode(ContactsRecord.self, from: Data("{}".utf8))
        #expect(r.wanted && !r.baseline && r.pastAnswer == nil && r.links.isEmpty)
    }
}

#if canImport(Contacts)
import Contacts

/// «Из Контактов» и чтение «твоего» контакта: что берётся из настоящего `CNContact` (выбор системы отдаёт именно его).
@Suite struct CNContactFoundTests {
    @Test func pickedContactBecomesNamePhonesBirthdayAndMessengers() {
        let c = CNMutableContact()
        c.givenName = "Ольга"; c.middleName = "Ивановна"; c.familyName = "Смирнова"
        c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "8 (916) 123-45-67")),
                          CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "+7 383 222-33-44"))]
        c.birthday = DateComponents(month: 2, day: 29)
        c.socialProfiles = [CNLabeledValue(label: nil, value: CNSocialProfile(urlString: "https://vk.com/id123", username: nil,
                                                                              userIdentifier: nil, service: "VK")),
                            CNLabeledValue(label: nil, value: CNSocialProfile(urlString: nil, username: "x", userIdentifier: nil,
                                                                              service: CNSocialProfileServiceFacebook))]
        c.instantMessageAddresses = [CNLabeledValue(label: nil, value: CNInstantMessageAddress(username: "@olga_s", service: "Telegram"))]
        let f = CNContactsStore.found(c)
        #expect(f.name == "Ольга Ивановна Смирнова")
        #expect(f.phones == ["8 (916) 123-45-67", "+7 383 222-33-44"])
        #expect(f.birthday == "02-29")
        #expect(f.messengers == [ClientMessenger(kind: "vk", value: "id123"), ClientMessenger(kind: "telegram", value: "olga_s")])
    }

    /// Ревью GPT к 3e34cb3: правка своего контакта не стирает то, что человек дописал в Контактах сам.
    @Test func updateKeepsWhatThePersonAddedByHand() {
        let was = ContactCard(given: "Ольга", family: "Смирнова", phone: "+79161234567", birthday: "1990-10-25",
                              anniversary: CivilDate(year: 2025, month: 6, day: 14),
                              messengers: [ClientMessenger(kind: "telegram", value: "olga_s")])
        let c = CNMutableContact()
        CNContactsStore.fill(c, was)
        c.phoneNumbers.append(CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "+7 383 222-33-44")))
        c.socialProfiles.append(CNLabeledValue(label: nil, value: CNSocialProfile(urlString: nil, username: "olga.ig", userIdentifier: nil, service: "Instagram")))
        let party = NSDateComponents(); party.month = 3; party.day = 1
        c.dates.append(CNLabeledValue(label: "праздник", value: party))
        var now = was
        now.family = "Петрова"
        now.phone = "+79035556677"
        now.messengers = [ClientMessenger(kind: "telegram", value: "olga_p")]
        now.anniversary = CivilDate(year: 2025, month: 6, day: 15)
        CNContactsStore.fill(c, now, was: was)
        #expect(c.familyName == "Петрова")
        #expect(c.phoneNumbers.map { $0.value.stringValue } == ["+79035556677", "+7 383 222-33-44"])
        #expect(c.socialProfiles.map { $0.value.service + ":" + $0.value.username }.sorted() == ["Instagram:olga.ig", "Telegram:olga_p"])
        #expect(c.dates.map { "\($0.label ?? ""):\($0.value.month)-\($0.value.day)" }.sorted() == ["_$!<Anniversary>!$_:6-15", "праздник:3-1"])
        // День рождения стёрли у клиента — уходит и записанный приложением; поставленный человеком другой — остаётся.
        // Исправил день рождения прямо в Контактах — правка клиента его не перезаписывает.
        c.birthday = DateComponents(year: 1990, month: 10, day: 26)
        var renamed = now
        renamed.family = "Сидорова"
        CNContactsStore.fill(c, renamed, was: now)
        #expect(c.familyName == "Сидорова" && c.birthday?.day == 26)
        c.birthday = DateComponents(year: 1990, month: 10, day: 25)
        var noBd = now
        noBd.birthday = nil
        CNContactsStore.fill(c, noBd, was: now)
        #expect(c.birthday == nil)
        c.birthday = DateComponents(month: 1, day: 2)
        CNContactsStore.fill(c, noBd, was: now)
        #expect(c.birthday?.month == 1)
    }

    @Test func cardWrittenByTheAppReadsBack() {
        let card = ContactCard(given: "Анна", family: "Петрова", phone: "+79031112233", birthday: "1994-04-05",
                               anniversary: CivilDate(year: 2025, month: 6, day: 14),
                               messengers: [ClientMessenger(kind: "telegram", value: "anna")])
        let c = CNMutableContact()
        CNContactsStore.fill(c, card)
        #expect(c.phoneNumbers.map { $0.value.stringValue } == ["+79031112233"])
        #expect(c.dates.count == 1 && c.dates[0].label == CNLabelDateAnniversary && c.dates[0].value.year == 2025)
        let f = CNContactsStore.found(c)
        #expect(f.name == "Анна Петрова" && f.birthday == "1994-04-05")
        #expect(f.messengers == [ClientMessenger(kind: "telegram", value: "anna")])
    }
}
#endif
