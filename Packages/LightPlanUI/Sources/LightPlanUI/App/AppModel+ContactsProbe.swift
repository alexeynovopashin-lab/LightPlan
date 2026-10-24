import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain
#if DEBUG && os(iOS)
import Contacts

/// Замер на настоящей книге симулятора (шаг К7): `-LPContactsProbe <файл>` (Debug).
///
/// Приложение само проходит сценарий — заводит клиентов, открывает «Клиенты», правит клиента, отвечает «Да» на прошлых,
/// «удаляет руками» свой контакт вторым `CNContactStore` (как это сделали бы Контакты), «Убрать всё» — и после каждого
/// шага пишет в файл, что лежит в книге на самом деле: по строке JSON на шаг. Проверяет `Tools/contacts_sim.py`; право
/// выдаёт он же (`simctl privacy grant contacts`). Книга симулятора — не личные данные; на телефоне сценарий не идёт.
extension AppModel {

    static let probeHand = (given: "Нина", family: "Своя", phone: "8 (913) 000-00-01")

    func runContactsProbe(log path: String) {
        Task { [weak self] in
            guard let self, let memory = contactsMemory else { return }
            await contactsChain?.value
            // Чистый лист: свои контакты прошлого прогона и «твой» контакт сценария.
            let book = CNContactStore()
            Self.probeDelete(book) { c in memory.record.links.values.contains { $0.id == c.identifier }
                || (c.givenName == Self.probeHand.given && c.familyName == Self.probeHand.family) }
            // Прошлый клиент — «Сергей Прошлый»: был до сборки с К7, пишется только после «Да».
            var r = ContactsRecord()
            r.baseline = true
            r.past = ["probe-p"]
            memory.record = r
            Self.probeAddHand(book)

            func person(_ name: String, _ tel: String, bd: String? = nil, msg: [ClientMessenger] = []) -> ClientPerson {
                var p = ClientPerson(name: name, phone: tel)
                p.birthday = bd
                p.messengers = msg
                return p
            }
            var a = Client(id: "probe-a", kind: .person)
            a.people = [person("Ольга Смирнова", "8 916 123-45-67", bd: "1990-10-25", msg: [.init(kind: "telegram", value: "olga_s")])]
            var b = Client(id: "probe-b", kind: .couple)
            b.people = [person("Анна Петрова", "+7 903 111-22-33"), person("Иван Петров", "8 903 444-55-66")]
            b.anniversary = CivilDate(year: 2025, month: 6, day: 14)
            b.anniversaryManual = true
            var c = Client(id: "probe-c", kind: .family)
            c.people = [person("Мария Иванова", "8 913 222-33-44"), person("Петя", "")]
            var d = Client(id: "probe-d", kind: .person)
            d.people = [person("Нина", "+7 913 000-00-01")]
            var p = Client(id: "probe-p", kind: .person)
            p.people = [person("Сергей Прошлый", "8 999 555-66-77")]
            snapshot.clients = [a, b, c, d, p]
            snapshot.sessions = []
            snapshot.trashed = []

            @MainActor func dump(_ stage: String) async {
                await contactsChain?.value
                let rows = Self.probeRows()
                let clients: [[String: Any]] = snapshot.clients.map { c in
                    ["id": c.id, "people": c.people.map { ["n": $0.name, "tel": $0.phone, "bd": $0.birthday ?? "",
                                                           "msg": $0.messengers.map { $0.kind + ":" + $0.value }] }]
                }
                let rec = memory.record
                let line = (try? JSONSerialization.data(withJSONObject: [
                    "stage": stage, "auth": "\(contactsAuth)", "on": contactsOn, "writes": contactsWrites,
                    "pastAsk": contactsPastAsk ?? -1, "own": contactsOwnCount, "removed": contactsRemoved ?? -1,
                    "links": rec.links.mapValues(\.id), "dropped": Array(rec.dropped).sorted(), "wanted": rec.wanted,
                    "rows": rows, "clients": clients,
                ], options: [.sortedKeys])) ?? Data()
                let text = String(decoding: line, as: UTF8.self) + "\n"
                if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
                else { try? text.write(toFile: path, atomically: true, encoding: .utf8) }
            }
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
            await dump("start")

            // Первое открытие «Клиентов»: право, проход, вопрос о прошлых.
            contactsOpened(); await dump("opened")

            // Правка в приложении: имя и мессенджер уезжают в свой контакт, «твой» не трогается.
            snapshot.clients[0].people[0].name = "Ольга Петрова"
            snapshot.clients[0].people[0].messengers.append(.init(kind: "vk", value: "olga_p"))
            persist(); syncContacts(force: true); await dump("edited")

            // Пересохранение без правки: ничего не пишется заново.
            syncContacts(force: true); await dump("resaved")

            answerPastClients(true); await dump("past-yes")

            // Свой контакт удалили руками — заново не заводится.
            if let id = memory.record.links[ClientContacts.key(client: "probe-c", person: 0)]?.id {
                Self.probeDelete(book) { $0.identifier == id }
            }
            syncContacts(force: true); await dump("gone")

            removeAppContacts(); await dump("removed")
            await dump("done")
        }
    }

    private static func probeAddHand(_ store: CNContactStore) {
        let c = CNMutableContact()
        c.givenName = probeHand.given
        c.familyName = probeHand.family
        c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: probeHand.phone))]
        c.birthday = DateComponents(year: 1960, month: 3, day: 8)
        c.socialProfiles = [CNLabeledValue(label: nil, value: CNSocialProfile(urlString: nil, username: "nina_own",
                                                                              userIdentifier: nil, service: "Telegram"))]
        let req = CNSaveRequest()
        req.add(c, toContainerWithIdentifier: nil)
        try? store.execute(req)
    }

    private static func probeDelete(_ store: CNContactStore, where match: (CNContact) -> Bool) {
        let req = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey]
            .map { $0 as NSString })
        req.unifyResults = false
        var gone: [CNMutableContact] = []
        try? store.enumerateContacts(with: req) { c, _ in
            if match(c), let m = c.mutableCopy() as? CNMutableContact { gone.append(m) }
        }
        guard !gone.isEmpty else { return }
        let save = CNSaveRequest()
        gone.forEach { save.delete($0) }
        try? store.execute(save)
    }

    /// Вся книга симулятора как есть: имя, номера, день рождения, годовщины, профили.
    private static func probeRows() -> [[String: Any]] {
        let keys = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey,
                    CNContactPhoneNumbersKey, CNContactBirthdayKey, CNContactDatesKey, CNContactSocialProfilesKey]
            .map { $0 as NSString }
        let req = CNContactFetchRequest(keysToFetch: keys)
        req.unifyResults = false
        var out: [[String: Any]] = []
        try? CNContactStore().enumerateContacts(with: req) { c, _ in
            let bd = c.birthday.map { b in [b.year.map { String($0) } ?? "", String(b.month ?? 0), String(b.day ?? 0)].joined(separator: "-") } ?? ""
            let annivs = c.dates.filter { $0.label == CNLabelDateAnniversary }
                .map { "\($0.value.year)-\($0.value.month)-\($0.value.day)" }
            out.append(["id": c.identifier, "name": [c.givenName, c.middleName, c.familyName].filter { !$0.isEmpty }.joined(separator: " "),
                        "phones": c.phoneNumbers.map { $0.value.stringValue }, "bd": bd, "anniv": annivs,
                        "social": c.socialProfiles.map { $0.value.service + ":" + $0.value.username }])
        }
        return out
    }

    /// Вызывается при запуске живого приложения.
    func debugContactsProbe() {
        if let path = UserDefaults.standard.string(forKey: "LPContactsProbe") { runContactsProbe(log: path) }
    }
}
#else
extension AppModel {
    func debugContactsProbe() {}
}
#endif
