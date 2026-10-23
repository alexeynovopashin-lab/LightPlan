import Foundation
import LightPlanCore
import LightPlanDomain

/// Строка меню «как связаться»: подпись («Telegram»), что рядом (`@olga`, номер), адрес.
struct ReachItem: Equatable, Identifiable {
    /// `call`, `sms` или ключ мессенджера; у второго человека — с его номером (`1.telegram`).
    var id: String
    var title: String
    var detail: String
    var url: URL
}

/// Человек в меню: у пары и семьи — под своим именем, у персоны без подписи.
struct ReachSection: Equatable, Identifiable {
    var id: String
    var title: String
    var items: [ReachItem]
}

/// Кнопка мессенджера (шаг К4, справка `docs/clients_reference.md` § 7.1): нажатие открывает основной способ человека
/// «Пишем», долгое нажатие — меню всех способов.
struct ReachPlan: Equatable {
    var primary: ReachItem
    var sections: [ReachSection]
}

extension AppModel {

    // MARK: - Кнопка

    /// Кнопка карточки клиента: основной способ того, кому пишем; в меню — он первым, за ним остальные люди.
    func clientReach(_ c: Client) -> ReachPlan? {
        guard let w = ClientReach.writer(of: c, country: telCountry),
              let main = ClientReach.primary(of: c.people[w], country: telCountry) else { return nil }
        let many = c.people.count > 1
        let order = [w] + c.people.indices.filter { $0 != w }
        let sections = order.compactMap { i -> ReachSection? in
            let items = ClientReach.options(of: c.people[i], country: telCountry).map { reachItem($0, person: i == w ? nil : i) }
            guard !items.isEmpty else { return nil }
            let name = c.people[i].name.trimmingCharacters(in: .whitespaces)
            return ReachSection(id: "\(i)", title: many ? (name.isEmpty ? lexicon.t("clc.personN", ["n": "\(i + 1)"]) : name) : "",
                                items: items)
        }
        return ReachPlan(primary: reachItem(main, person: nil), sections: sections)
    }

    /// Кнопка в шапке карточки съёмки: у съёмки с клиентом — его кнопка; без клиента (или клиенту не написать) — SMS на
    /// номер шапки, в меню звонок и SMS. Номера нет — кнопки нет.
    func shootReach(_ s: Session) -> ReachPlan? {
        if let c = shootClient(s), let plan = clientReach(c) { return plan }
        return personReach(ClientPerson(phone: PlannerWords(lexicon: lexicon, orgs: orgs).firstPhone(s)))
    }

    /// Кнопка одного человека (у телефона в карточке клиента): его основной способ, в меню — только его способы.
    func personReach(_ p: ClientPerson) -> ReachPlan? {
        guard let main = ClientReach.primary(of: p, country: telCountry) else { return nil }
        let items = ClientReach.options(of: p, country: telCountry).map { reachItem($0, person: nil) }
        return ReachPlan(primary: reachItem(main, person: nil), sections: [ReachSection(id: "0", title: "", items: items)])
    }

    /// Способ словами экрана.
    private func reachItem(_ o: ClientReach.Option, person: Int?) -> ReachItem {
        let key: String, title: String
        switch o.way {
        case .call: key = "call"; title = lexicon.t("clc.call")
        case .sms: key = "sms"; title = lexicon.t("reach.sms")
        case .messenger(let k): key = k.rawValue; title = k.title
        }
        return ReachItem(id: person.map { "\($0).\(key)" } ?? key, title: title, detail: o.detail, url: o.url)
    }

    // MARK: - Правка мессенджеров (пишется сразу)

    /// «+ мессенджер» у человека: пустая строка вида; первый — сразу основной.
    func addClientMessenger(_ id: String, at i: Int, _ kind: MessengerKind) {
        editClient(id) { if $0.people.indices.contains(i) { ClientReach.addMessenger(kind, to: &$0.people[i]) } }
    }

    /// Поле мессенджера: вставленная ссылка профиля становится именем (`vk.com/id123` → `id123`), MAX — как есть.
    func setClientMessenger(_ id: String, at i: Int, _ kind: MessengerKind, _ raw: String) {
        editClient(id) { if $0.people.indices.contains(i) { ClientReach.setMessenger(kind, raw, in: &$0.people[i]) } }
    }

    func removeClientMessenger(_ id: String, at i: Int, _ kind: MessengerKind) {
        editClient(id) { if $0.people.indices.contains(i) { ClientReach.removeMessenger(kind, from: &$0.people[i]) } }
    }

    /// Звёздочка: этот мессенджер у человека основной — его открывает кнопка.
    func setClientPreferred(_ id: String, at i: Int, _ kind: MessengerKind) {
        editClient(id) { if $0.people.indices.contains(i) { $0.people[i].preferred = kind.rawValue } }
    }

    /// «Пишем»: кому из людей карточки пишет кнопка.
    func setClientMain(_ id: String, _ i: Int) {
        editClient(id) { if $0.people.indices.contains(i) { $0.main = i } }
    }

    /// Варианты «Пишем»: люди, с кем есть как связаться, — по имени (без имени — «Человек N»).
    func clientWriters(_ c: Client) -> [(label: String, value: Int)] {
        c.people.indices.compactMap { i in
            guard ClientReach.primary(of: c.people[i], country: telCountry) != nil else { return nil }
            let first = PhoneBook.firstName(c.people[i].name)
            return (first.isEmpty ? lexicon.t("clc.personN", ["n": "\(i + 1)"]) : first, i)
        }
    }
}
