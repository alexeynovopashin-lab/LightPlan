import Foundation
import LightPlanCore
import LightPlanDomain

/// Плашка клиента под полем имени в форме, словами экрана.
struct FormClientPlate: Equatable {
    var clientId: String
    var way: ClientBook.Hint.Way
    /// «Это Анна и Иван? 3 съёмки» / «Это Анна и Иван · 3 съёмки» / «По номеру — Анна и Иван · 3 съёмки».
    var text: String
    /// Знак вида клиента: пара, семья, персона.
    var icon: String
}

/// Входы в клиента из съёмки (шаг К3, справка `docs/clients_reference.md` § 4.5): плашка в форме и имя в шапке карточки.
extension AppModel {

    // MARK: - Плашка в форме

    /// Плашка для того, что сейчас вписано в форму. Считается на лету, ничего не пишет: клиенты меняются только при
    /// «Сохранить» (`saveForm` → `bindClient`), отменённая форма клиентов не оставляет.
    func formClientPlate(_ f: EventForm) -> FormClientPlate? {
        let org = f.orgId.flatMap { id in snapshot.orgs.first { $0.id == id } }
        let s = f.session(orgName: org?.name, and: lexicon.t("card.and"), studios: snapshot.studios, spots: snapshot.spots,
                          homeCity: homeCityName, now: now())
        guard let h = ClientBook.hint(for: s, choice: f.clientChoice, clients: snapshot.clients, sessions: snapshot.sessions,
                                      mine: myKeys, country: telCountry),
              let c = snapshot.clients.first(where: { $0.id == h.clientId }) else { return nil }
        let n = ClientBook.shoots(of: c.id, in: snapshot.sessions).count
        let words = ["name": clientTitle(c), "n": n > 0 ? lexicon.count("unit.shoot", n) : lexicon.t("cl.noShoots")]
        let key = switch h.way {
        case .name: "clf.ask"
        case .bound: "clf.is"
        case .phone: "clf.tel"
        }
        return FormClientPlate(clientId: c.id, way: h.way, text: lexicon.t(key, words), icon: Self.clientIcon(c.kind))
    }

    /// «Да» / «Другой» на плашке: ответ живёт в форме до «Сохранить» (черновик его не держит).
    func answerFormClient(_ choice: ClientBook.Choice) {
        form?.clientChoice = choice
    }

    // MARK: - Имя в шапке карточки

    /// Клиент открытой съёмки, если он есть в данных: имя в шапке тогда ведёт в его карточку.
    func shootClient(_ s: Session) -> Client? {
        s.clientId.flatMap { id in snapshot.clients.first { $0.id == id } }
    }

    /// Имя в шапке карточки съёмки: карточка клиента слоем поверх неё, «Назад» возвращает в съёмку.
    func openShootClient(_ s: Session) {
        guard let c = shootClient(s) else { return }
        openClientCard(id: c.id, backKey: "nav.back")
    }
}
