import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Состояние экранов организаций (веб `#orgOverlay`, `#orgCard`): список с двумя
/// половинами, карточка, выбранный вид бумаг. Новая организация живёт черновиком и
/// попадает в данные, когда в ней появилось хоть что-то (ошибка веба 24: «+ Организация»
/// клала пустую запись, и она оставалась «Без названия» навсегда).
struct OrgState: Equatable {
    enum Tab { case orgs, docs }
    var listOpen = false
    var tab: Tab = .orgs
    /// Открытая в слое карточка; у черновика — его id.
    var cardId: String?
    /// Новая организация, ещё не в данных.
    var draft: Org?
    /// Вид, что ставится новой бумаге организации и фильтрует список (`#oDocKinds`).
    var docKind: DocKind?
    /// Вид на общей полке (`#allDocKinds`).
    var shelfKind: DocKind?
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
        org.tab = .orgs
        org.listOpen = true
    }

    func closeOrgs() {
        org.listOpen = false
        org.tab = .orgs
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

    func addOrgDocLink(_ id: String, _ raw: String) {
        let kind = org.docKind
        editOrg(id) { OrgBook.addLink(raw, kind: kind, to: &$0) }
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
