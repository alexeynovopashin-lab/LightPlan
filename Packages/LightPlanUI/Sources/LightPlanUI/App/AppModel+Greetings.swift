import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// «Поздравлять» (шаг К6, справка `docs/clients_reference.md` § 6): дни рождения людей клиента и годовщина пары. Одно
/// уведомление на день в 10:00 по часам телефона, 40 ближайших дней; расписание — функция данных, как студийный час, и
/// сверяется с ним одной сверкой (`syncAlerts`): при запуске, возврате в приложение и любой правке.
extension AppModel {

    // MARK: - Расписание

    /// Поздравления с готовым текстом: сегодня, пока не пробило 10:00, иначе с завтрашнего дня.
    func greetAlertPlan() -> [ScheduledAlert] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = deviceZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now())
        let today = CivilDate(year: c.year!, month: c.month!, day: c.day!)
        let start = Greetings.firstDay(today: today, minute: c.hour! * 60 + c.minute!)
        let days = Greetings.days(clients: snapshot.clients, sessions: snapshot.sessions, from: start,
                                  and: lexicon.t("card.and"))
        return days.compactMap { d in
            let wall = WallTime(day: d.date, minutes: Greetings.minute)
            guard let fire = cal.date(from: DateComponents(year: d.date.year, month: d.date.month, day: d.date.day,
                                                           hour: Greetings.minute / 60, minute: Greetings.minute % 60))
            else { return nil }
            return ScheduledAlert(id: GreetSchedule.id(d.date), wall: wall, fire: Moment(fire), clientId: d.clientId,
                                  title: lexicon.t("greet.title"), body: GreetAlertText.body(d, lexicon: lexicon))
        }
    }

    /// Годовщина из свадьбы — в снимок (для облака, § 2.4), один раз на запуске; экраны и расписание считают её сами.
    @discardableResult
    static func settleAnniversaries(in snapshot: inout Snapshot, now: Date) -> Bool {
        var changed = false
        for i in snapshot.clients.indices where Greetings.settleAnniversary(&snapshot.clients[i], in: snapshot.sessions) {
            snapshot.clients[i].modifiedAt = Self.ms(now)
            changed = true
        }
        return changed
    }

    // MARK: - Карточка

    /// Годовщина пары на экране: вписанная руками или из самой ранней свадьбы.
    func clientAnniversary(_ c: Client) -> CivilDate? { Greetings.anniversary(of: c, in: snapshot.sessions) }

    /// Годовщина пришла из свадьбы, руками не правлена — подпись «из свадьбы».
    func clientAnniversaryFromWedding(_ c: Client) -> Bool { !c.anniversaryManual && clientAnniversary(c) != nil }

    /// День рождения человека: `nil` — убрать. Первая вписанная дата включает «Поздравлять» (решение 23.10, № 4).
    func setClientBirthday(_ id: String, at i: Int, _ b: Birthday?) {
        editGreetDate(id) { if $0.people.indices.contains(i) { $0.people[i].birthday = b?.snapshotString } }
    }

    /// Годовщина руками: дальше свадьба её не двигает; `nil` — убрать (и свадьба её не вернёт).
    func setClientAnniversary(_ id: String, _ d: CivilDate?) {
        editGreetDate(id) { $0.anniversary = d; $0.anniversaryManual = true }
    }

    private func editGreetDate(_ id: String, _ body: (inout Client) -> Void) {
        guard let before = clientRecord(id) else { return }
        editClient(id) { c in
            body(&c)
            if Greetings.turnsGreetOn(before: before, after: c) { c.greet = true }
        }
        if !before.greet, clientRecord(id)?.greet == true { askGreetPermission() }
    }

    /// Тумблер «Поздравлять». Включение — момент спросить у системы право уведомлять, если ещё не спрашивали; отказ
    /// ничего не ломает: тумблер стоит, под ним строка ведёт в настройки iPhone.
    func setClientGreet(_ id: String, _ on: Bool) {
        editClient(id) { $0.greet = on }
        if on { askGreetPermission() }
    }

    /// Тот же системный вопрос, что у тумблера «Студийный час»: задаётся один раз, ответ — в `alertAuth`.
    func askGreetPermission() {
        guard let center = alertCenter else { return }
        Task { [weak self] in
            var auth = await center.authorization()
            if auth == .notDetermined {
                _ = await center.requestAuthorization()
                auth = await center.authorization()
            }
            guard let self else { return }
            alertAuth = auth
            syncAlerts(force: true)
        }
    }

    /// Поздравлять хочет, а система запретила уведомления: строка под тумблером ведёт в настройки iPhone.
    func greetNeedsSettings(_ c: Client) -> Bool { c.greet && alertAuth == .denied }

    // MARK: - Нажатие на уведомление

    /// Поздравление: праздники одного клиента — его карточка поверх «Клиентов», разных — сам список «Клиенты».
    func openGreetClient(_ clientId: String?) {
        if cardId != nil { closeCard() }
        if org.clientCardId != nil { closeClientCard() }
        openClients()
        if let clientId, snapshot.clients.contains(where: { $0.id == clientId }) { openClientCard(id: clientId) }
    }
}

/// Текст поздравления (§ 6): «Сегодня: годовщина — Анна и Иван; день рождения — Ольга». Годовщины раньше дней рождения,
/// несколько одного вида — через запятую.
enum GreetAlertText {
    static func body(_ d: Greetings.Day, lexicon t: Lexicon) -> String {
        var parts: [String] = []
        for (kind, one, many) in [(Greetings.Kind.anniversary, "greet.anniv", "greet.annivs"),
                                  (.birthday, "greet.bday", "greet.bdays")] {
            let names = d.occasions.filter { $0.kind == kind }.map(\.name)
            guard !names.isEmpty else { continue }
            parts.append(t.t(names.count > 1 ? many : one, ["names": names.joined(separator: t.t("greet.comma"))]))
        }
        return t.t("greet.today", ["list": parts.joined(separator: t.t("greet.semi"))])
    }
}
