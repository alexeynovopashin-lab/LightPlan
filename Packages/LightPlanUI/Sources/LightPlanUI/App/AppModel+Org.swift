import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Состояние экранов организаций (веб `#orgOverlay`, `#orgCard`): список, карточка, выбранный вид бумаг. Новая организация живёт черновиком и
/// попадает в данные, когда в ней появилось хоть что-то (ошибка веба 24: «+ Организация»
/// клала пустую запись, и она оставалась «Без названия» навсегда).
struct OrgState: Equatable {
    var listOpen = false
    /// Открытая в слое карточка; у черновика — его id.
    var cardId: String?
    /// Новая организация, ещё не в данных.
    var draft: Org?
    /// Вид, что ставится новой бумаге организации и фильтрует список (`#oDocKinds`).
    var docKind: DocKind?
    /// Вид на общей полке (`#allDocKinds`).
    var shelfKind: DocKind?
    /// Вид раздела «Документы», группировка, сортировка, свёрнутые группы (итерация 28, шаг 12а).
    var docs = DocsPrefs()
    /// Слово в «Назад» списка.
    var backKey = "nav.settings"
    /// Открыт ли экран «Контакты» (настройки → профиль): слой стоит рядом со списком организаций.
    var contactsOpen = false
    /// Номера открытой карточки до правки — по ним при закрытии видно, какой ушёл (веб `orgTelSnap`).
    var telSnap: [PhoneBook.Tel] = []

    var isOpen: Bool { listOpen || cardId != nil || contactsOpen }
}

extension AppModel {

    // MARK: - Слои

    func openOrgs(backKey: String = "nav.settings") {
        org.backKey = backKey
        org.docs = DocsPrefs.from(docsPrefsStore.load())
        org.listOpen = true
    }

    /// Правка вида раздела «Документы»: сразу ложится на диск — вид и свёртки переживают запуск.
    func editDocsPrefs(_ change: (inout DocsPrefs) -> Void) {
        change(&org.docs)
        docsPrefsStore.save(org.docs.data())
    }

    /// Группы полки под выбранными чипами, группировкой и сортировкой.
    func docGroups() -> [DocShelf.Group] {
        let all = OrgBook.shelf(orgs: orgs, sessions: sessions)
        return DocShelf.groups(OrgBook.filtered(all, kind: org.shelfKind), prefs: org.docs,
                               practice: dealPractice, words: docShelfWords())
    }

    /// Вид Б: таблица одним списком, под выбранными чипами и сортировкой колонки.
    func docTable() -> [DocShelf.Row] {
        let all = OrgBook.shelf(orgs: orgs, sessions: sessions)
        return DocShelf.table(OrgBook.filtered(all, kind: org.shelfKind), prefs: org.docs, words: docShelfWords())
    }

    /// Вид В: месяцы под выбранными чипами.
    func docMonths() -> [DocShelf.Group] {
        let all = OrgBook.shelf(orgs: orgs, sessions: sessions)
        return DocShelf.months(OrgBook.filtered(all, kind: org.shelfKind), practice: dealPractice, words: docShelfWords())
    }

    /// Слова полки: вид словарём, организация или клиент съёмки, дата и месяц на языке приложения.
    func docShelfWords() -> DocShelfWords {
        let words = PlannerWords(lexicon: lexicon, orgs: orgs)
        let facts = PlannerFacts(app: self, dark: true)
        let byId = Dictionary(snapshot.sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return DocShelfWords(
            kindName: { self.docKindName($0) },
            requisite: lexicon.t("doc.req"), fileWord: lexicon.t("doc.file"),
            privateClients: lexicon.t("doc.private"), noDate: lexicon.t("doc.noDate"),
            owner: { d in
                if let sid = d.sessionId, let s = byId[sid] {
                    if let id = s.orgId, let o = self.orgRecord(id) { return .init(key: id, label: self.orgTitle(o)) }
                    let c = words.clientName(s)
                    return c.isEmpty ? nil : .init(key: "c:" + c.lowercased(), label: c)
                }
                if let id = d.orgId, let o = self.orgRecord(id) { return .init(key: id, label: self.orgTitle(o)) }
                return nil
            },
            dateText: { facts.dates.dMonShortYear(facts.date($0)) },
            monthLabel: { y, m in
                facts.dates.monthTitle(facts.date(CivilDate(year: y, month: m, day: 1))) + " " + String(y)
            })
    }

    func closeOrgs() {
        org.listOpen = false
        org.shelfKind = nil
    }

    /// «+ Организация»: черновик и его карточка — данные не трогаются, пока не введено слово.
    func newOrg() {
        let o = Org(id: Self.newRecordId(now()))
        org.draft = o
        org.docKind = nil
        org.telSnap = []
        org.cardId = o.id
    }

    func openOrgCard(id: String) {
        guard let o = orgRecord(id) else { return }
        org.docKind = nil
        org.telSnap = PhoneBook.tels(of: o, country: telCountry)
        org.cardId = id
    }

    /// «Назад» из карточки: пустая организация без съёмок не остаётся (ошибка веба 24).
    func closeOrgCard() {
        if let id = org.cardId, orgRecord(id)?.staff.contains(where: \.isBlank) == true {
            editOrg(id) { OrgBook.pruneBlankPeople(&$0) }
        }
        commitOrgTels()
        if let id = org.cardId { settleOrg(id) }
        org.cardId = nil
        org.docKind = nil
        org.telSnap = []
    }

    /// Организация по ключу: из данных или черновик.
    func orgRecord(_ id: String) -> Org? {
        snapshot.orgs.first { $0.id == id } ?? (org.draft?.id == id ? org.draft : nil)
    }

    /// Пустую убирают из данных (черновик просто забывается), полную оставляют.
    func settleOrg(_ id: String) {
        org.docKind = nil
        if org.draft?.id == id { org.draft = nil }
        guard let i = snapshot.orgs.firstIndex(where: { $0.id == id }),
              !OrgBook.keeps(snapshot.orgs[i], in: snapshot.sessions) else { return }
        snapshot.orgs.remove(at: i)
        bury(id, now: now())
        dropFormOrg(id)
        persist()
    }

    /// Открытая форма не должна держать выбор удалённой организации: сохранение записало бы
    /// её ключ в съёмку заново (ревью GPT к a456d3d).
    private func dropFormOrg(_ id: String) {
        if form?.orgId == id { setFormOrg(nil) }
    }

    // MARK: - Правка (пишется сразу, кнопки «Сохранить» нет)

    /// Одна правка организации. Черновик, в котором что-то появилось, встаёт в данные;
    /// отметка правки свежая — по ней сливаются устройства.
    func editOrg(_ id: String, _ body: (inout Org) -> Void) {
        if let i = snapshot.orgs.firstIndex(where: { $0.id == id }) {
            body(&snapshot.orgs[i])
            snapshot.orgs[i].modifiedAt = nowMs
            persist()
        } else if var d = org.draft, d.id == id {
            body(&d)
            if OrgBook.isBlank(d) { org.draft = d; return }
            d.modifiedAt = nowMs
            snapshot.orgs.append(d)
            org.draft = nil
            persist()
        }
    }

    /// Телефон: причёсывается на лету, как в форме («9234443322» → «8 923 444-33-22»).
    func setOrgPhone(_ id: String, _ raw: String) {
        let old = (orgRecord(id)?.phone ?? "").filter(\.isNumber).count
        // Страна читает снимок — до правки, не внутри неё (два доступа к `snapshot` разом).
        let typed = TelFormat.typed(raw, previousDigits: old, country: telCountry)
        editOrg(id) { $0.phone = typed }
    }

    /// Телефон директора: причёсывается, как остальные.
    func setDirectorPhone(_ id: String, _ raw: String) {
        let old = (orgRecord(id)?.directorPhone ?? "").filter(\.isNumber).count
        let typed = TelFormat.typed(raw, previousDigits: old, country: telCountry)
        editOrg(id) { $0.directorPhone = typed }
    }

    /// «+ Добавить»: новая строка человека; роль набирает фотограф («маркетолог», «секретарь»).
    func addOrgPerson(_ id: String) {
        editOrg(id) { OrgBook.addPerson(to: &$0) }
    }

    func editOrgPerson(_ id: String, at i: Int, _ body: (inout OrgPerson) -> Void) {
        editOrg(id) { if $0.staff.indices.contains(i) { body(&$0.staff[i]) } }
    }

    func setOrgPersonPhone(_ id: String, at i: Int, _ raw: String) {
        let old = (orgRecord(id)?.staff[safe: i]?.phone ?? "").filter(\.isNumber).count
        let typed = TelFormat.typed(raw, previousDigits: old, country: telCountry)
        editOrgPerson(id, at: i) { $0.phone = typed }
    }

    func removeOrgPerson(_ id: String, at i: Int) {
        editOrg(id) { OrgBook.removePerson(at: i, from: &$0) }
    }

    func addOrgDocLink(_ id: String, _ raw: String, title: String? = nil, date: CivilDate? = nil) {
        let kind = org.docKind
        editOrg(id) { OrgBook.addLink(raw, kind: kind, title: title, date: date, to: &$0) }
    }

    func removeOrgDoc(_ id: String, at i: Int) {
        editOrg(id) { OrgBook.removeDoc(at: i, from: &$0) }
    }

    /// Сколько съёмок числится за организацией.
    func orgShootCount(_ id: String) -> Int { snapshot.sessions.filter { $0.orgId == id }.count }

    /// Удаление: съёмки остаются без заказчика, в могилу ложится ключ (веб `oDelete`).
    func deleteOrg(_ id: String) {
        snapshot.sessions = OrgBook.detach(id, from: snapshot.sessions, at: nowMs)
        snapshot.orgs.removeAll { $0.id == id }
        if org.draft?.id == id { org.draft = nil }
        bury(id, now: now())
        dropFormOrg(id)
        persist()
        if org.cardId == id { org.cardId = nil; org.docKind = nil; org.telSnap = [] }
    }

    /// Тап по съёмке организации: карточка организации и список закрываются, открывается
    /// карточка съёмки (веб L23826).
    func openOrgShoot(_ sessionId: String) {
        closeOrgCard()
        closeOrgs()
        openCard(id: sessionId)
    }

    // MARK: - Строки

    /// Вторая строка списка: лицо · «N съёмок» · суммы по валютам; ничего нет — «реквизиты не заполнены».
    func orgSubtitle(_ o: Org) -> String {
        let line = OrgBook.line(of: o.id, in: snapshot.sessions, home: settings.currency)
        let nt = NumberText(language: language)
        var parts: [String] = []
        if !o.person.isEmpty { parts.append(o.person) }
        if line.shootCount > 0 { parts.append(lexicon.count("unit.shoot", line.shootCount)) }
        parts += line.sums.map { nt.money(NSDecimalNumber(decimal: $0.sum).doubleValue, $0.currency.rawValue) }
        return parts.isEmpty ? lexicon.t("org.noReq") : parts.joined(separator: " · ")
    }

    func orgTitle(_ o: Org) -> String { o.name.isEmpty ? lexicon.t("org.noName") : o.name }
}
