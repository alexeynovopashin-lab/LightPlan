import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Студийный час зовёт и при закрытом приложении (шаг 30а, итерация 30).
///
/// Расписание — функция данных: каждая запись со студийной ячейкой даёт два
/// запроса (`StudioSchedule`), и после любой правки данных, при запуске и при
/// возврате в приложение система приводится к этому списку. Отдельного кода
/// «продлили — перепиши» нет и быть не может: ячейка ушла вперёд — тот же
/// запрос получил другой момент.
extension AppModel {

    // MARK: - Разрешено ли говорить

    /// Память «что приложению разрешено говорить» — `notif` снимка, тот же ключ и те же имена, что у веба
    /// (`notifPrefs`): `all` и `studio`, по умолчанию оба включены; остальные ключи объекта не трогаем.
    private static func notifFlag(_ key: String, _ fallback: Bool = true, in snapshot: Snapshot) -> Bool {
        if case .object(let o)? = snapshot.extra["notif"], case .bool(let v)? = o[key] { return v }
        return fallback
    }

    /// Хочет ли человек студийный час: `notifOn("studio")` веба — главное «Разрешить все» и своё значение.
    public var studioAlertsWanted: Bool {
        Self.notifFlag("all", in: snapshot) && Self.notifFlag("studio", in: snapshot)
    }

    /// Что показывает тумблер: хочет и система разрешила. «Хочет, но не разрешили» — не «включено»: ничего не придёт.
    public var studioAlertsOn: Bool { studioAlertsWanted && alertAuth == .allowed }

    /// Отказали в разрешении, а человек хочет сигнал: строка ведёт в настройки iPhone, а не спрашивает снова.
    public var studioAlertsNeedSettings: Bool { studioAlertsWanted && alertAuth == .denied }

    /// Плашка уже показывалась: память между запусками — `notif.studioAsked` в снимке (веб ключ не знает и не трогает).
    var studioAlertAsked: Bool { Self.notifFlag("studioAsked", false, in: snapshot) }

    // MARK: - Плашка перед системным окном (30а.2)

    /// После первого сохранения съёмки со студией и часами — своя плашка вместо молчаливого системного окна.
    /// Показывается только когда система ещё не спрашивала (`notDetermined`), человек не выключил студийный час
    /// сам и плашки раньше не было; разрешено или отказано в системе — плашка ни к чему (тумблер включится сам
    /// по правилу 30а / строка ведёт в настройки iPhone). Системное окно здесь не вызывается никогда.
    func offerStudioAlerts(after s: Session) {
        guard canOfferStudioAlerts(for: s.id), let center = alertCenter else { return }
        alertOfferTask = Task { [weak self] in
            let auth = await center.authorization()
            guard let self else { return }
            alertAuth = auth
            // Пока система отвечала, человек мог выключить студийный час, запись — уйти или смениться.
            guard auth == .notDetermined, canOfferStudioAlerts(for: s.id) else { return }
            studioAlertAsk = true
        }
    }

    /// Все условия показа плашки — их же проверяем заново после ожидания ответа системы.
    private func canOfferStudioAlerts(for sessionId: String) -> Bool {
        guard alertCenter != nil, !studioAlertAsked, !studioAlertAsk, studioAlertsWanted,
              let s = snapshot.sessions.first(where: { $0.id == sessionId }) else { return false }
        return RentWindow.of(s, studios: snapshot.studios, now: nil) != nil
    }

    #if DEBUG
    /// Снимки (`-LPStudioAsk 1`): плашка на экране сразу, без сохранения и без системы.
    func debugShowStudioAsk() {
        if UserDefaults.standard.bool(forKey: "LPStudioAsk") { studioAlertAsk = true }
    }
    #endif

    /// «Да»: плашка закрыта, дальше как нажатие на тумблер — системное окно, разрешили — тумблер включён.
    public func answerStudioAlertAsk(yes: Bool) {
        studioAlertAsk = false
        // «Спрашивали» — по ответу, не по показу: закрыли приложение при открытой плашке — спросим в следующий раз.
        writeNotif(["studioAsked": true])
        if yes { setStudioAlerts(true) }
    }

    func writeNotif(_ changes: [String: Bool]) {
        var o: [String: JSONValue] = [:]
        if case .object(let cur)? = snapshot.extra["notif"] { o = cur }
        for (k, v) in changes { o[k] = .bool(v) }
        snapshot.extra["notif"] = .object(o)
        persist()
    }

    /// Тумблер «Студийный час». Включение — первый и единственный момент, когда у системы просят право
    /// уведомлять (не на запуске). Отказ ничего не ломает: тумблер остаётся выключенным, расписания нет.
    public func setStudioAlerts(_ on: Bool) {
        alertWish += 1
        let wish = alertWish
        Task { [weak self] in
            guard let self else { return }
            if on, let center = alertCenter {
                var auth = await center.authorization()
                if auth == .notDetermined {
                    _ = await center.requestAuthorization()
                    auth = await center.authorization()
                }
                alertAuth = auth
                // Пока шёл системный вопрос, человек нажал ещё раз: действует последнее нажатие.
                guard wish == alertWish else { return syncAlerts(force: true) }
                // Своего «Разрешить все» у натива пока нет: включая студийный час руками, человек разрешает.
                writeNotif(["studio": true, "all": true])
            } else {
                writeNotif(["studio": on])
            }
            syncAlerts(force: true)
        }
    }

    // MARK: - Расписание

    /// Смещение пояса места съёмки на день записи, часы (веб `momentOf`): место записи — по тем же правилам,
    /// что часы карточки (`wallNow`), но на день записи, а не на сегодня — перевод часов не должен сдвигать
    /// будущую съёмку.
    func alertOffsetHours(of s: Session) -> Double {
        if let p = Stops.skyPoint(of: s, spots: snapshot.spots, studios: snapshot.studios) {
            return place.zones.utcOffsetHours(latitude: p.latitude, longitude: p.longitude, on: s.day)
        }
        return place.zone.utcOffsetHours(on: s.day)
    }

    /// Расписание целиком: ближайшие 64 сигнала с готовым текстом.
    func studioAlertPlan() -> [ScheduledAlert] {
        let clock = ClockText(language: language, preference: Self.clock(settings.clock))
        let notices = StudioSchedule.plan(
            sessions: snapshot.sessions, studios: snapshot.studios, now: Moment(now()),
            offsetHours: { alertOffsetHours(of: $0) }, finished: { phase(of: $0) == .after })
        return notices.map { StudioAlertText.alert($0, lexicon: lexicon, clock: clock) }
    }

    /// Привести систему к данным — напоминания о съёмке, студийный час и поздравления (К6) одной сверкой: 64 места делятся по таблице
    /// (`NotificationScheduler.lanes`), а не по тому, кто сверился последним. Правки идут пачками — запрос откладывается
    /// на треть секунды и склеивается; `force` (запуск, возврат в приложение, смена тумблера) опрашивает систему даже при
    /// тех же данных: разрешение могли выдать или отнять в настройках iPhone, а у поздравлений сменился «сегодня».
    func syncAlerts(force: Bool = false) {
        guard let center = alertCenter else { return }
        alertGen += 1
        if force { alertForce = true }
        let gen = alertGen
        let prev = alertChain
        alertChain = Task { [weak self] in
            await prev?.value
            if !force { try? await Task.sleep(for: .milliseconds(300)) }
            // Позже пришёл другой запрос — он и выполнит работу, унаследовав «принудительно».
            guard let self, gen == alertGen else { return }
            let force = alertForce
            alertForce = false
            let auth = await center.authorization()
            alertAuth = auth
            let scheduler = NotificationScheduler(center: center)
            let plan = auth == .allowed
                ? reminderAlertPlan() + (studioAlertsWanted ? studioAlertPlan() : []) + greetAlertPlan() : []
            guard !plan.isEmpty else {
                if alertApplied != nil || force { await scheduler.clear() }
                alertApplied = nil
                await alertLog("idle wanted=\(studioAlertsWanted) remind=\(remindWanted ? remindMinutes : 0) auth=\(auth)")
                return
            }
            let sig = plan.map { $0.id + "=" + $0.signature }
            if !force, alertApplied == sig { return }
            let report = await scheduler.sync(plan)
            // Система отказала в части запросов — план не считается применённым, следующая сверка попробует снова.
            alertApplied = report.failed.isEmpty ? sig : nil
            await alertLog("sync plan=\(plan.count) added=\(report.added.count) removed=\(report.removed.count) kept=\(report.kept.count) dropped=\(report.dropped.count) failed=\(report.failed.count)")
        }
    }

    /// `-LPAlertLog <файл>` (Debug): после каждой сверки — что система держит на самом деле. Замеры шага 30а.
    private func alertLog(_ head: String) async {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "LPAlertLog"),
              let system = alertCenter as? SystemNotificationCenter else { return }
        let stamp = ISO8601DateFormatter().string(from: now())
        var out = ["# \(stamp) \(head)"]
        out += await system.dump().map { "  " + $0 }
        let text = out.joined(separator: "\n") + "\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        #endif
    }

    /// Живое приложение: система уведомлений и правило показа при открытом приложении.
    func attachAlerts() {
        let system = SystemNotificationCenter()
        alertCenter = system
        wxPoster = system
        alertPresenter = .shared
        alertPresenter.setCardCheck { [weak self] sid in self?.cardId == sid }
        SystemNotificationCenter.install(delegate: alertPresenter)
        // Нажали на уведомление: «прогноз переменился» и напоминание — карточка записи (30.6), поздравление — клиент или «Клиенты» (К6).
        alertPresenter.setOpen { [weak self] tap in
            switch tap {
            case .card(let sid): self?.openFromNotice(sid)
            case .client(let cid): self?.openGreetClient(cid)
            }
        }
        #if DEBUG
        // Замеры (`-LPAlertToggle on|off`): то же, что нажатие на тумблер «Студийный час», без руки.
        if let v = UserDefaults.standard.string(forKey: "LPAlertToggle"), v == "on" || v == "off" {
            setStudioAlerts(v == "on"); return
        }
        #endif
        syncAlerts(force: true)
    }
}

/// Текст сигнала: слова беты один в один (`studio.sayT`, `studio.leaveIn`, `studio.leaveNow`).
enum StudioAlertText {
    /// Заголовок: час выхода и «студийный час» («19:25 · студийный час»), текст: «Выйти из зала через 10 минут.
    /// Томсон, Эдисон.» — по остатку минут, не по номеру ступени. Дошло до нуля — «Пора выходить из зала».
    static func alert(_ n: StudioSchedule.Notice, lexicon t: Lexicon, clock: ClockText) -> ScheduledAlert {
        let where_ = [n.studioName, n.hallName ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        let body = n.minutesLeft > 0
            ? t.t("studio.leaveIn", ["left": t.count("unit.min", n.minutesLeft), "where": where_])
            : t.t("studio.leaveNow", ["where": where_])
        let title = clock.fmt(Double(n.deadline)) + " · " + t.t("studio.sayT").lowercased()
        return ScheduledAlert(id: n.id, sessionId: n.sessionId, fire: n.fire, offsetHours: n.offsetHours,
                              title: title, body: body)
    }
}
