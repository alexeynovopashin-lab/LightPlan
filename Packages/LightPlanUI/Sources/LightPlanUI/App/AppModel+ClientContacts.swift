import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Что последний проход привёл в книгу: те же клиенты и те же разрешённые — проход без силы молчит.
struct ContactsApplied: Equatable {
    var clients: [Client]
    var allowed: Set<String>
}

/// Клиенты в Контактах iPhone (шаг К7, справка `docs/clients_reference.md` § 5): iPhone показывает, кто звонит.
///
/// Алексей, 23.10: «пишем сами, тумблер, по умолчанию вкл» и три защиты от придуманных контактов в личной книге —
/// (1) тестовые сборки «LP …» не пишут никогда, (2) клиенты из прошлых съёмок — только по «Да», (3) «Убрать из Контактов
/// всё, что записало приложение». Как у календаря: правда в Light Plan, проход — функция данных (`persist`, запуск,
/// возврат в приложение); без полного права ничего не трогается и ничего не ломается.
extension AppModel {

    // MARK: - Что видит экран

    /// Есть ли смысл показывать часть «Контакты» под списком: живое приложение на iPhone (или подставка снимков).
    var contactsAvailable: Bool { contactsMirror != nil }

    /// Тумблер «вкл»: эта сборка пишет, человек хочет и право полное. Частичный доступ и отказ — «выкл» с подписью.
    public var contactsOn: Bool { contactsWrites && contactsWanted && contactsAuth == .full }

    /// Право не то, а спросить снова нельзя: строка ведёт в настройки iPhone.
    var contactsNeedsSettings: Bool { contactsAuth == .denied || contactsAuth == .limited }

    // MARK: - Подключение

    /// Живое приложение: книга телефона и память на устройстве. На Mac книги нет (шаг про iPhone).
    func attachContacts() {
        #if os(iOS)
        attachContacts(store: CNContactsStore(), memory: DeviceContactsMemory(),
                       writes: ClientContacts.writes(bundleID: Bundle.main.bundleIdentifier))
        #endif
    }

    /// Подставки (тесты, снимки). `writes` — эта сборка пишет в книгу (защита 1: только `Novopashin.LightPlan`).
    func attachContacts(store: any ContactsStoring, memory: any ContactsMemory, writes: Bool) {
        contactsStore = store
        contactsMemory = memory
        contactsWrites = writes
        contactsMirror = ContactsMirror(store: store, memory: memory)
        markPastClients()
        readContactsMemory()
        syncContacts(force: true)
    }

    /// Защита 2: первый запуск сборки с К7 (и «Убрать всё») отмечает всех клиентов, что уже есть, как прошлых —
    /// собранных разовым проходом из старых съёмок или заведённых, когда записи в книгу ещё не было. Они пишутся только
    /// после «Да»; клиенты, что заведутся дальше, — сами.
    private func markPastClients() {
        guard let memory = contactsMemory, !memory.record.baseline else { return }
        var r = memory.record
        r.baseline = true
        r.past = Set(snapshot.clients.map(\.id))
        r.pastAnswer = nil
        memory.record = r
    }

    /// Прошлые клиенты, которых вопрос предлагает записать: те, у кого есть хоть один номер.
    private func pastWaiting(_ r: ContactsRecord) -> Int {
        snapshot.clients.filter { r.past.contains($0.id) && !ClientContacts.cards(of: $0, anniversary: nil, country: telCountry).isEmpty }.count
    }

    private func readContactsMemory() {
        guard let r = contactsMemory?.record else { return }
        contactsWanted = r.wanted
        contactsPastAnswer = r.pastAnswer
        contactsPastWaiting = pastWaiting(r)
        contactsOwnCount = r.links.count
    }

    /// Кого проход может писать: ничего в тестовой сборке и при выключенном тумблере; прошлых — только после «Да».
    func contactsAllowed() -> Set<String> {
        guard contactsWrites, let r = contactsMemory?.record, r.wanted else { return [] }
        var ids = Set(snapshot.clients.map(\.id))
        if r.pastAnswer != true { ids.subtract(r.past) }
        return ids
    }

    // MARK: - Очередь и проход

    /// Всё, что идёт в книгу, встаёт в одну очередь: тумблер, вопрос, «Убрать всё» и проход друг друга не обгоняют.
    /// Тесты ждут её конец (`contactsChain`).
    func enqueueContacts(_ work: @escaping @MainActor (AppModel) async -> Void) {
        let prev = contactsChain
        contactsChain = Task { [weak self] in
            await prev?.value
            guard let self else { return }
            await work(self)
        }
    }

    /// Привести книгу к клиентам. Правки идут пачками — треть секунды тишины; `force` (запуск, возврат, тумблер) сверяет
    /// и при тех же данных: контакт могли удалить руками, право — выдать в настройках iPhone.
    func syncContacts(force: Bool = false) {
        guard contactsMirror != nil else { return }
        contactsGen += 1
        if force { contactsForce = true }
        let gen = contactsGen
        enqueueContacts { app in
            guard gen == app.contactsGen else { return }
            if !force { try? await Task.sleep(for: .milliseconds(300)) }
            guard gen == app.contactsGen else { return }
            let force = app.contactsForce
            app.contactsForce = false
            await app.runContactsSync(force: force)
        }
    }

    fileprivate func runContactsSync(force: Bool) async {
        guard let mirror = contactsMirror, let store = contactsStore else { return }
        contactsAuth = await store.authorization()
        readContactsMemory()
        let allowed = contactsAllowed()
        let applied = ContactsApplied(clients: snapshot.clients, allowed: allowed)
        guard !allowed.isEmpty else { contactsApplied = nil; return }
        if !force, contactsApplied == applied { return }
        let annivs = Dictionary(snapshot.clients.compactMap { c in
            Greetings.anniversary(of: c, in: snapshot.sessions).map { (c.id, $0) }
        }, uniquingKeysWith: { a, _ in a })
        switch await mirror.sync(clients: snapshot.clients, allowed: allowed, anniversaries: annivs, country: telCountry) {
        case .synced(let report):
            contactsFailed = report.failed > 0
            contactsApplied = report.failed == 0 ? applied : nil
            takeContactFills(report.fills)
        case .noAccess:
            contactsApplied = nil
        case .failed:
            contactsApplied = nil
            contactsFailed = true
        }
        readContactsMemory()
    }

    /// Номер уже был в книге (ты сам сохранил человека): из твоего контакта в клиента — только недостающее, день
    /// рождения и мессенджеры. Твой контакт не правится.
    private func takeContactFills(_ fills: [ContactsMirror.Fill]) {
        var changed = false
        for f in fills {
            guard let ci = snapshot.clients.firstIndex(where: { $0.id == f.read.client }),
                  snapshot.clients[ci].people.indices.contains(f.read.person) else { continue }
            if ClientContacts.fill(&snapshot.clients[ci].people[f.read.person], from: f.found) {
                snapshot.clients[ci].modifiedAt = nowMs
                changed = true
            }
        }
        if changed { persist() }
    }

    // MARK: - Экран «Клиенты»

    /// Открыли «Клиенты» (§ 5): здесь у системы просят доступ — в первый раз и только в сборке, что пишет, при
    /// включённом тумблере. Право полное и есть прошлые клиенты с номером — вопрос «Сохранить N…?».
    func contactsOpened() {
        guard contactsWrites, let store = contactsStore else { return }
        enqueueContacts { app in
            var auth = await store.authorization()
            if auth == .notDetermined, app.contactsMemory?.record.wanted == true { auth = await store.requestAccess() }
            app.contactsAuth = auth
            app.askPastIfDue()
            await app.runContactsSync(force: true)
        }
    }

    /// Вопрос о прошлых клиентах — один раз, пока на него не ответили; после «Нет» — только строкой под тумблером.
    private func askPastIfDue() {
        guard contactsWrites, contactsAuth == .full, let r = contactsMemory?.record, r.wanted, r.pastAnswer == nil else { return }
        let n = pastWaiting(r)
        if n > 0 { contactsPastAsk = n }
    }

    /// Тумблер «Сохранять клиентов в Контакты iPhone». Включили, а права ещё не спрашивали — системный вопрос.
    /// Выключили — новые клиенты в книгу не идут, уже записанные остаются.
    public func setContactsWanted(_ on: Bool) {
        guard contactsWrites, let store = contactsStore, let memory = contactsMemory else { return }
        memory.record.wanted = on
        contactsWanted = on
        if !on { contactsPastAsk = nil }
        enqueueContacts { app in
            var auth = await store.authorization()
            if on, auth == .notDetermined { auth = await store.requestAccess() }
            app.contactsAuth = auth
            if on { app.askPastIfDue() }
            await app.runContactsSync(force: true)
        }
    }

    /// «Да» / «Нет» на «Сохранить в Контакты N клиентов из прошлых съёмок?». «Нет» — они остаются только в приложении.
    public func answerPastClients(_ yes: Bool) {
        guard let memory = contactsMemory else { return }
        contactsPastAsk = nil
        memory.record.pastAnswer = yes
        contactsPastAnswer = yes
        syncContacts(force: true)
    }

    /// Строка под тумблером после «Нет»: спросить снова.
    public func askPastClientsAgain() {
        guard let r = contactsMemory?.record else { return }
        let n = pastWaiting(r)
        if n > 0 { contactsPastAsk = n }
    }

    /// «Убрать из Контактов всё, что записало приложение» (защита 3) — после подтверждения. Убираются только контакты
    /// по связи этого телефона; твои не трогаются. Тумблер выключается (иначе следующий проход записал бы их снова),
    /// а все клиенты снова становятся «прошлыми»: включишь тумблер — массовая запись снова только по «Да».
    public func removeAppContacts() {
        guard let mirror = contactsMirror, let memory = contactsMemory else { return }
        contactsRemoveAsk = false
        enqueueContacts { app in
            guard let out = await mirror.removeAll() else { app.contactsFailed = true; return }
            var r = memory.record
            r.wanted = false
            r.past = Set(app.snapshot.clients.map(\.id))
            r.pastAnswer = nil
            r.baseline = true
            memory.record = r
            app.contactsRemoved = out.removed
            app.contactsFailed = out.failed > 0
            app.contactsPastAsk = nil
            app.contactsApplied = nil
            app.readContactsMemory()
        }
    }

    // MARK: - «Из Контактов» (системный выбор, без разрешения)

    /// Человек в карточке клиента взял контакт из книги: номер и имя — выбранные, день рождения и мессенджеры —
    /// недостающие.
    public func takeClientContact(_ clientId: String, at i: Int, _ f: FoundContact) {
        guard let ci = snapshot.clients.firstIndex(where: { $0.id == clientId }),
              snapshot.clients[ci].people.indices.contains(i) else { return }
        if let phone = Self.pickedPhone(f, country: telCountry) { setClientPersonPhone(clientId, at: i, phone) }
        if !f.name.isEmpty { setClientPersonName(clientId, at: i, f.name) }
        guard let cj = snapshot.clients.firstIndex(where: { $0.id == clientId }) else { return }
        var c = snapshot.clients[cj]
        if ClientContacts.fill(&c.people[i], from: f) {
            c.modifiedAt = nowMs
            snapshot.clients[cj] = c
            persist()
        }
    }

    /// Номер из контакта: выбранный в системном листе — он один; иначе первый мобильный, а нет мобильного — первый.
    static func pickedPhone(_ f: FoundContact, country: TelCountry) -> String? {
        let real = f.phones.filter { TelFormat.isReal($0, country: country) }
        let p = real.first { TelFormat.isMobile($0, country: country) } ?? real.first
        return p.map { TelFormat.format($0, country: country, pasted: true) }
    }

    /// Форма: контакт подставляет имя и номер в поле, остальное ждёт «Сохранить» (`takeFormPicked`).
    func pickForForm(_ f: FoundContact, name: (inout EventForm, String) -> Void, phone: (inout EventForm, String) -> Void) {
        guard form != nil else { return }
        let tel = Self.pickedPhone(f, country: telCountry)
        editForm { e in
            if !f.name.isEmpty { name(&e, f.name) }
            if let tel { phone(&e, tel) }
        }
        formPicked.append(f)
    }

    /// После «Сохранить»: клиенту записи — день рождения и мессенджеры выбранных контактов, у человека с тем же номером,
    /// если у него этого нет.
    func takeFormPicked(_ s: Session) {
        defer { formPicked = [] }
        guard !formPicked.isEmpty, let id = s.clientId, let ci = snapshot.clients.firstIndex(where: { $0.id == id }) else { return }
        var c = snapshot.clients[ci]
        var changed = false
        for f in formPicked {
            let keys = Set(f.phones.map { ClientContacts.phoneKey($0, country: telCountry) }.filter { !$0.isEmpty })
            guard let i = c.people.firstIndex(where: { keys.contains(ClientContacts.phoneKey($0.phone, country: telCountry)) }) else { continue }
            if ClientContacts.fill(&c.people[i], from: f) { changed = true }
        }
        if changed {
            c.modifiedAt = nowMs
            snapshot.clients[ci] = c
        }
    }

    // MARK: - Снимки

    /// Часть «Контакты» для снимков (`-LPShotContacts`): `past` — первое открытие, вопрос о прошлых; `on` — все клиенты
    /// записаны, видна кнопка «Убрать всё»; `no` — на вопрос ответили «Нет», строка «спросить снова»; `limited` —
    /// частичный доступ; `test` — тестовая сборка, тумблера нет.
    func shotContacts(_ kind: String) {
        let store = InMemoryContactsStore(auth: kind == "limited" ? .limited : .full)
        var r = ContactsRecord()
        switch kind {
        case "on":
            r.baseline = true
        case "no":
            r.baseline = true
            r.past = Set(snapshot.clients.map(\.id))
            r.pastAnswer = false
        default:
            break
        }
        attachContacts(store: store, memory: InMemoryContactsMemory(r), writes: kind != "test")
    }
}
