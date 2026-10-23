import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Подсказка карточки «номер есть у другого клиента — объединить?» словами экрана.
struct ClientTwinRow: Equatable, Identifiable {
    var id: String { clientId }
    var clientId: String
    var title: String
    var phone: String
}

/// Карточка частного клиента (шаг К2, справка `docs/clients_reference.md` § 4.4): слой поверх «Клиентов», правки пишутся
/// сразу (как карточка организации). Съёмки и суммы считаются из съёмок с `clientId`, в клиенте не хранятся.
extension AppModel {

    // MARK: - Слой

    func openClientCard(id: String) {
        guard let c = clientRecord(id) else { return }
        org.clientTelSnap = PhoneBook.tels(of: c, country: telCountry)
        org.clientPick = false
        org.clientCardId = id
    }

    /// «+ Клиент»: черновик и его карточка — данные не трогаются, пока не вписано слово (как «+ Организация»).
    func newClient() {
        var c = Client(id: ClientBook.newId(at: nowMs), kind: .person)
        c.people = [ClientPerson()]
        org.clientDraft = c
        org.clientTelSnap = []
        org.clientPick = false
        org.clientCardId = c.id
    }

    /// «Назад»: пустые строки людей убираются, ушедший номер ложится в архив, пустой клиент без съёмок не остаётся.
    func closeClientCard() {
        guard let id = org.clientCardId else { return }
        if let c = clientRecord(id), c.people.contains(where: \.isBlank), snapshot.clients.contains(where: { $0.id == id }) {
            editClient(id) { ClientBook.pruneBlankPeople(&$0) }
        }
        commitClientTels()
        settleClient(id)
        org.clientCardId = nil
        org.clientTelSnap = []
        org.clientPick = false
    }

    /// Клиент по ключу: из данных или черновик.
    func clientRecord(_ id: String) -> Client? {
        snapshot.clients.first { $0.id == id } ?? (org.clientDraft?.id == id ? org.clientDraft : nil)
    }

    /// Пустого убирают из данных (черновик просто забывается); со съёмками — даже пустого держат.
    func settleClient(_ id: String) {
        if org.clientDraft?.id == id { org.clientDraft = nil }
        guard let i = snapshot.clients.firstIndex(where: { $0.id == id }),
              !ClientBook.keeps(snapshot.clients[i], in: snapshot.sessions, trashed: snapshot.trashed) else { return }
        snapshot.clients.remove(at: i)
        bury(id, now: now())
        persist()
    }

    // MARK: - Правка (пишется сразу)

    /// Одна правка клиента. Черновик, в котором что-то появилось, встаёт в данные; отметка правки свежая.
    func editClient(_ id: String, _ body: (inout Client) -> Void) {
        if let i = snapshot.clients.firstIndex(where: { $0.id == id }) {
            var c = snapshot.clients[i]
            body(&c)
            guard c != snapshot.clients[i] else { return }
            c.modifiedAt = nowMs
            snapshot.clients[i] = c
            persist()
        } else if var d = org.clientDraft, d.id == id {
            body(&d)
            if ClientBook.isBlank(d) { org.clientDraft = d; return }
            d.modifiedAt = nowMs
            snapshot.clients.append(d)
            org.clientDraft = nil
            persist()
        }
    }

    func setClientKind(_ id: String, _ kind: ClientKind) {
        editClient(id) { $0.kind = kind }
    }

    func setClientPersonName(_ id: String, at i: Int, _ name: String) {
        editClient(id) { if $0.people.indices.contains(i) { $0.people[i].name = name } }
    }

    /// Телефон человека: причёсывается на лету, как в форме («9234443322» → «8 923 444-33-22»). Новые съёмки с этим
    /// номером найдут клиента; прошлые свои номера не переписывают (§ 3.5). Ушедший номер ложится в архив при «Назад».
    func setClientPersonPhone(_ id: String, at i: Int, _ raw: String) {
        let old = (clientRecord(id)?.people[safe: i]?.phone ?? "").filter(\.isNumber).count
        let typed = TelFormat.typed(raw, previousDigits: old, country: telCountry)
        editClient(id) { if $0.people.indices.contains(i) { $0.people[i].phone = typed } }
    }

    func addClientPerson(_ id: String) {
        // Пустой человек данных не меняет — у черновика он живёт в черновике.
        if snapshot.clients.contains(where: { $0.id == id }) {
            if let i = snapshot.clients.firstIndex(where: { $0.id == id }) { ClientBook.addPerson(to: &snapshot.clients[i]) }
        } else if org.clientDraft?.id == id {
            ClientBook.addPerson(to: &org.clientDraft!)
        }
    }

    func removeClientPerson(_ id: String, at i: Int) {
        editClient(id) { ClientBook.removePerson(at: i, from: &$0) }
    }

    func addClientLink(_ id: String, _ raw: String, title: String? = nil, date: CivilDate? = nil) {
        editClient(id) { ClientBook.addLink(raw, title: title, date: date, to: &$0) }
    }

    func removeClientLink(_ id: String, linkId: String) {
        editClient(id) { ClientBook.removeLink(id: linkId, from: &$0) }
    }

    // MARK: - Ушедший номер

    /// Сверка клиента при закрытии карточки и уходе в фон: номер, которого больше нет у людей, ложится в его `telLog`
    /// и продолжает узнаваться склейкой (§ 3.5).
    func commitClientTels() {
        guard let id = org.clientCardId, let i = snapshot.clients.firstIndex(where: { $0.id == id }) else { return }
        let c = snapshot.clients[i]
        let now = PhoneBook.tels(of: c, country: telCountry)
        let log = PhoneBook.retire(before: org.clientTelSnap, after: now, log: c.telLog,
                                   at: ISO8601DateFormatter().string(from: self.now()), country: telCountry)
        org.clientTelSnap = now
        guard log != c.telLog else { return }
        snapshot.clients[i].telLog = log
        snapshot.clients[i].modifiedAt = nowMs
        persist()
    }

    // MARK: - Строки карточки

    /// Имя клиента словами экрана: пара — «Анна и Иван», без имени — первый номер или «Без имени».
    func clientTitle(_ c: Client) -> String {
        let t = ClientBook.title(of: c, and: lexicon.t("card.and"))
        return t.isEmpty ? lexicon.t("cl.noName") : t
    }

    /// «3 съёмки · 145 000 ₽» — считается из съёмок; съёмок нет — «съёмок нет».
    func clientLine(_ id: String) -> String {
        let line = ClientBook.line(of: id, in: snapshot.sessions, home: settings.currency)
        guard line.shootCount > 0 else { return lexicon.t("cl.noShoots") }
        let nt = NumberText(language: language)
        return ([lexicon.count("unit.shoot", line.shootCount)]
                + line.sums.map { nt.money(NSDecimalNumber(decimal: $0.sum).doubleValue, $0.currency.rawValue) })
            .joined(separator: " · ")
    }

    /// Другие клиенты, чей номер назван в карточке или её съёмках (§ 3.4): «объединить?» решает фотограф.
    func clientTwins(_ id: String) -> [ClientTwinRow] {
        ClientBook.twins(of: id, clients: snapshot.clients, sessions: snapshot.sessions, mine: myKeys, country: telCountry)
            .compactMap { tw in
                snapshot.clients.first { $0.id == tw.clientId }.map {
                    ClientTwinRow(clientId: tw.clientId, title: clientTitle($0), phone: tw.phone)
                }
            }
    }

    /// Кого можно влить в этого клиента: все, кроме него самого, в порядке списка «Частные».
    func clientMergeCandidates(_ id: String) -> [Client] {
        ClientBook.list(snapshot.clients, sessions: snapshot.sessions).filter { $0.id != id }
    }

    // MARK: - Объединить, удалить

    /// «Объединить»: `source` вливается в открытого `target` (правило — `ClientBook.merge`); могила второго — в снимке,
    /// чтобы облако его не вернуло.
    func mergeClient(_ source: String, into target: String) {
        // Номер, сменённый в открытой карточке до объединения, сперва ложится в архив: снимок номеров ниже заменяется
        // объединённым, и иначе старый номер не узнался бы (ревью GPT к 718a182).
        if org.clientCardId == target { commitClientTels() }
        var clients = snapshot.clients, sessions = snapshot.sessions, bin = snapshot.trashed
        guard ClientBook.merge(source, into: target, clients: &clients, sessions: &sessions, trashed: &bin,
                               country: telCountry, nowMs: nowMs) else { return }
        snapshot.clients = clients
        snapshot.sessions = sessions
        snapshot.trashed = bin
        bury(source, now: now())
        persist()
        if org.clientCardId == target, let c = clientRecord(target) {
            // Пришедшие номера не «ушли»: сверка при «Назад» начинается с объединённой карточки.
            org.clientTelSnap = PhoneBook.tels(of: c, country: telCountry)
        }
        org.clientPick = false
    }

    /// Сколько съёмок числится за клиентом — с теми, что в корзине: удаление спрашивает и тогда, когда живых нет, а
    /// вернувшиеся из корзины останутся без клиента (ревью GPT к 718a182).
    func clientShootCount(_ id: String) -> Int {
        snapshot.sessions.filter { $0.clientId == id }.count + snapshot.trashed.filter { $0.record.clientId == id }.count
    }

    /// «Удалить клиента»: съёмки остаются без клиента (`ClientBook.delete`), в могилу ложится ключ.
    func deleteClient(_ id: String) {
        if org.clientDraft?.id == id { org.clientDraft = nil }
        var clients = snapshot.clients, sessions = snapshot.sessions, bin = snapshot.trashed
        if ClientBook.delete(id, clients: &clients, sessions: &sessions, trashed: &bin, nowMs: nowMs) {
            snapshot.clients = clients
            snapshot.sessions = sessions
            snapshot.trashed = bin
            bury(id, now: now())
            persist()
        }
        if org.clientCardId == id { org.clientCardId = nil; org.clientTelSnap = []; org.clientPick = false }
    }

    /// Тап по съёмке клиента: карточка клиента и «Клиенты» закрываются, открывается карточка съёмки (как у организации).
    func openClientShoot(_ sessionId: String) {
        closeClientCard()
        closeOrgs()
        openCard(id: sessionId)
    }
}
