import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Вкладка экрана «Клиенты»: «Частные» или «Компании» (нынешние «Организации»).
enum ClientsTab: Equatable { case privates, companies }

/// Строка списка «Частные»: всё, что нужно показать, посчитано из клиента и его съёмок.
struct ClientRow: Equatable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    /// Знак из библиотеки по виду: пара, семья, персона.
    var icon: String
}

/// Частные клиенты (шаг К1, справка `docs/clients_reference.md`): склейка при сохранении съёмки, разовый проход на
/// старте, строки экрана «Клиенты».
extension AppModel {

    var clients: [Client] { snapshot.clients }

    // MARK: - Склейка (§ 3)

    /// Съёмка при «Сохранить»: клиент находится по номеру или заводится (`ClientBook.bind`). Ничего не изменилось —
    /// клиенты не тронуты, отметка правки прежняя.
    func bindClient(_ s: inout Session) {
        var list = snapshot.clients
        let ms = nowMs
        ClientBook.bind(&s, among: &list, mine: myKeys, country: telCountry, nowMs: ms,
                        retiredAt: ISO8601DateFormatter().string(from: now())) { ClientBook.newId(at: ms) }
        if list != snapshot.clients { snapshot.clients = list }
    }

    /// Свои номера по снимку, ещё до сборки модели (нынешний ID и прежние — как `myKeys`).
    static func myKeys(of snapshot: Snapshot, country: TelCountry) -> Set<String> {
        guard case .object(let me)? = snapshot.extra["me"] else { return [] }
        var ids: [String] = []
        if case .array(let a)? = me["ids"] {
            for v in a { if case .object(let o) = v, case .string(let was)? = o["was"] { ids.append(was) } }
        }
        if case .string(let phone)? = me["phone"] { ids.append(TelFormat.appId(phone, country: country)) }
        return PhoneBook.mineKeys(ids, country: country)
    }

    /// Разовый проход по уже записанным съёмкам (§ 3.8): первый запуск сборки с клиентами раскладывает их тем же
    /// правилом, что и сохранение. Сделан — больше не идёт, пока файл не потеряет флаг (веб пересохранил его без
    /// раздела `clients`): тогда съёмки без своего клиента получают его заново. `true` — снимок изменился.
    @discardableResult
    static func assembleClients(into snapshot: inout Snapshot, language: String, now: Date) -> Bool {
        guard !snapshot.clientsAssembled else { return false }
        let country = telCountry(of: snapshot, language: language)
        let ms = Self.ms(now)
        ClientBook.assemble(sessions: &snapshot.sessions, clients: &snapshot.clients,
                            mine: myKeys(of: snapshot, country: country), country: country, nowMs: ms,
                            retiredAt: ISO8601DateFormatter().string(from: now)) { ClientBook.newId(at: ms) }
        snapshot.clientsAssembled = true
        return true
    }

    // MARK: - Экран «Клиенты»

    /// «Клиенты» в настройках: слой поверх вкладок, как «Организации» до К1 (§ 4).
    func openClients(backKey: String = "nav.settings") {
        openOrgs(backKey: backKey)
        org.clientsTab = .privates
    }

    /// Справа в строке главы «Клиенты»: сколько частных клиентов (§ 4.1) или «нет».
    var clientsValue: String { clients.isEmpty ? lexicon.t("card.none") : String(clients.count) }

    /// Строки вкладки «Частные» под выбранным фильтром, свежие сверху.
    func clientRows() -> [ClientRow] {
        ClientBook.list(snapshot.clients, sessions: snapshot.sessions, filter: org.clientsFilter).map { c in
            ClientRow(id: c.id, title: clientTitle(c), subtitle: clientLine(c.id), icon: Self.clientIcon(c.kind))
        }
    }

    static func clientIcon(_ kind: ClientKind) -> String {
        switch kind {
        case .couple: "couple"
        case .family: "family"
        case .person: "partner"
        }
    }

    /// Строка клиента ведёт в его карточку (К2): слой поверх «Клиентов», «Назад» возвращает в список.
    func openClient(_ row: ClientRow) {
        openClientCard(id: row.id)
    }
}
