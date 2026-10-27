import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// «Напоминать о съёмке» (шаг «Напоминание-1», решение 27.10): за N минут до начала съёмки или встречи — уведомление с
/// именем клиента, временем, жанром, местом и телефоном; нажатие открывает карточку. Расписание — функция данных, как
/// студийный час и поздравления, и сверяется с ними одной сверкой (`syncAlerts`): перенос, правка и удаление записи
/// переписывают или снимают её напоминание сами.
extension AppModel {

    // MARK: - Настройка

    /// За сколько минут напоминать: `notif.remind` снимка (число; веб ключа не знает и при пересохранении теряет — тогда
    /// снова 15). Значение не из списка — как по умолчанию; сравнение числом, без `Int(v)`: огромное или `nan` из
    /// импорта обрушило бы приложение.
    public var remindMinutes: Int {
        if case .object(let o)? = snapshot.extra["notif"], case .number(let v)? = o["remind"],
           let m = ReminderSchedule.choices.first(where: { Double($0) == v }) { return m }
        return ReminderSchedule.defaultMinutes
    }

    /// Напоминать ли: только свой выбор, не «выкл». Главное «Разрешить все» веба (`notif.all`) напоминание не трогает и
    /// от него не зависит: веб напоминаний не знает, а своего главного переключателя у натива нет — выключенное на вебе
    /// «все» не глушит напоминание, и выбор напоминания не включает обратно погоду и студийный час.
    var remindWanted: Bool { remindMinutes > 0 }

    /// Выбор в настройках. Не «выкл» — момент спросить у системы право уведомлять, если ещё не спрашивали; отказ
    /// ничего не ломает: выбор стоит, строка под ним ведёт в настройки iPhone. Другие ключи `notif` не трогаются.
    public func setRemindMinutes(_ m: Int) {
        var o: [String: JSONValue] = [:]
        if case .object(let cur)? = snapshot.extra["notif"] { o = cur }
        o["remind"] = .number(Double(m))
        snapshot.extra["notif"] = .object(o)
        persist()
        guard m > 0, let center = alertCenter else { return }
        Task { [weak self] in
            if await center.authorization() == .notDetermined { _ = await center.requestAuthorization() }
            let auth = await center.authorization()
            guard let self else { return }
            alertAuth = auth
            syncAlerts(force: true)
        }
    }

    // MARK: - Расписание

    /// Напоминания с готовым текстом: 16 ближайших съёмок и встреч. `urgent` — дала ли система неотложные.
    func reminderAlertPlan(urgent: Bool = false) -> [ScheduledAlert] {
        guard remindWanted else { return [] }
        let notices = ReminderSchedule.plan(sessions: snapshot.sessions, minutes: remindMinutes, now: Moment(now()),
                                            offsetHours: { alertOffsetHours(of: $0) })
        let byId = Dictionary(snapshot.sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return notices.compactMap { n in byId[n.sessionId].map { ReminderAlertText.alert(n, $0, app: self, urgent: urgent) } }
    }
}

/// Слова напоминания — те же, что у шапки карточки (`CardHeadText`): кого снимаем, какой номер набирает кнопка звонка.
@MainActor
enum ReminderAlertText {
    /// Заголовок: «Кирилл · 12:00» — имя из шапки карточки (нет клиента — жанр) и начало по часам места съёмки.
    /// Текст: «Портрет · Томсон» и строкой ниже телефон, как в карточке («+7 961 887-80-78»); тот, кто на связи, —
    /// «на связи: Алёна, подруга · +7 …».
    static func alert(_ n: ReminderSchedule.Notice, _ s: Session, app: AppModel, urgent: Bool) -> ScheduledAlert {
        let t = app.lexicon
        let head = CardHeadText(s, phase: .before, app: app)
        let words = PlannerWords(lexicon: t, orgs: app.orgs)
        let clock = ClockText(language: app.language, preference: AppModel.clock(app.settings.clock))
        let title = t.t("remind.title", ["name": head.name, "time": clock.fmt(Double(s.start))])

        let what: String
        switch s.kind {
        case .meet: what = t.t("card.meetAbout", ["genre": words.shortType(s).lowercased()])
        default: what = words.typeName(s)
        }
        let stop = Stops.all(of: s, spots: app.snapshot.spots, studios: app.snapshot.studios).first
        let place = stop.map(\.name).flatMap { $0.isEmpty ? nil : $0 } ?? s.placeText
        // Нет клиента — жанр уже в заголовке, второй раз не повторяем.
        let first = [what == head.name ? "" : what, place].filter { !$0.isEmpty }.joined(separator: " · ")
        let tel = head.tel.map { tel in head.via.map { $0 + " · " + tel.shown } ?? tel.shown } ?? ""
        let body = [first, tel].filter { !$0.isEmpty }.joined(separator: "\n")

        var alert = ScheduledAlert(id: n.id, sessionId: n.sessionId, fire: n.fire, offsetHours: n.offsetHours,
                                   title: title, body: body)
        alert.urgent = urgent
        return alert
    }
}
