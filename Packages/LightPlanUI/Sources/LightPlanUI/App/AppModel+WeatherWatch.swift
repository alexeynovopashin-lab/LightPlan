import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData
#if os(iOS)
import UIKit
#endif

/// «Прогноз переменился» (шаг 30.6, итерация 30): фотограф узнаёт, что прогноз к ближайшей съёмке стал другим,
/// не открывая карточку. Два канала — баннер при запуске и возврате в приложение (веб `watchTick`, всегда) и
/// уведомление из фона (`BGAppRefreshTask`, когда разбудит iOS — по возможности). Правило одно
/// (`WeatherWatch.pass`), память одна — `wxTold`: что сказал один канал, второй не повторяет.
/// Отказ в праве уведомлять гасит только второй канал; баннеру разрешение не нужно.
extension AppModel {

    enum WeatherChannel { case banner, notification }

    /// Чаще получаса не спрашиваем: модель прогноза так часто и не обновляется (веб `WX_WATCH_GAP`).
    static let weatherWatchGap: TimeInterval = 30 * 60

    // MARK: - За кем следим

    /// Съёмки, за которыми стоит следить (веб `watchList` + `wxWatched`): работа, показывается, сегодня или впереди,
    /// ещё не прошла, день внутри окна прогноза и у якоря есть координаты. Встречи и чужие события отсеяны — у них
    /// нет ни света, ни замысла, ради которого стоило бы будить.
    func weatherWatched() -> [Session] {
        let t = today
        return snapshot.sessions.filter { s in
            !s.id.isEmpty && s.isShown(eventsLayer: eventsLayer) && s.kind.isWork && s.day.ordinal >= t.ordinal
                && phase(of: s) != .after && forecastReaches(s.day) && anchor(s) != nil
        }
    }

    /// Обход по тому прогнозу, что уже лежит у точек: решения без сети. Выключено — следить не за кем, но отметки
    /// ушедших записей чистятся всё равно.
    func weatherPass() -> WeatherWatch.Pass {
        let seen = WeatherMemory.read(WeatherMemory.seenKey, in: snapshot)
        let seenRaw = WeatherMemory.ids(WeatherMemory.seenKey, in: snapshot)
        // Отметка `wxSeen` есть, но эта версия её не читает (другой формат): съёмка не новая, и затирать отметку
        // молчаливым знакомством нельзя — пропускаем её до версии, которая поймёт (ревью GPT к 58e88fd).
        let items: [WeatherWatch.Item] = notifOn("wx")
            ? weatherWatched().filter { seen[$0.id] != nil || !seenRaw.contains($0.id) }
                .compactMap { s in cardSkySnap(s).map { .init(id: s.id, day: s.day, now: $0) } }
            : []
        let memory = seenRaw.union(WeatherMemory.ids(WeatherMemory.toldKey, in: snapshot))
        return WeatherWatch.pass(items: items, alive: Set(snapshot.sessions.map(\.id)),
                                 seen: seen,
                                 told: WeatherMemory.read(WeatherMemory.toldKey, in: snapshot),
                                 memoryIds: memory)
    }

    // MARK: - Обход

    /// Запуск (`force`) и возврат в приложение: свежий прогноз мест съёмок, затем баннер.
    public func watchWeather(force: Bool) {
        #if DEBUG
        // Замер фонового канала (`-LPWxBgRun 1`): на этом запуске баннер молчит, иначе он сказал бы первым.
        if UserDefaults.standard.bool(forKey: "LPWxBgRun") { return }
        #endif
        let prev = wxWatchTask
        wxWatchTask = Task { [weak self] in
            await prev?.value
            await self?.runWeatherWatch(force: force, channel: .banner)
        }
    }

    /// Обход целиком: спросить прогноз якорей, сравнить, сказать своим каналом, записать память.
    /// Возвращает то, о чём на самом деле сказано.
    @discardableResult
    func runWeatherWatch(force: Bool, channel: WeatherChannel) async -> [WeatherWatch.Say] {
        guard notifOn("wx") else { return [] }
        let t = now()
        // Получаса не прошло — в сеть не ходим, но сравниваем по тому прогнозу, что уже есть: фоновый проход мог
        // его обновить, а система — не принять уведомление; новость тогда несказанная (ревью GPT к 58e88fd).
        if !force, let last = wxWatchAt, t.timeIntervalSince(last) < Self.weatherWatchGap {
            return await announceWeather(channel)
        }
        wxWatchAt = t
        let list = weatherWatched()
        guard !list.isEmpty else { return [] }
        await pointWeather.refresh(list.compactMap { anchor($0).map(cardPlace) })
        return await announceWeather(channel)
    }

    /// Сказать и запомнить (веб `wxAnnounce`). Баннер — одна, самая тяжёлая и ближняя, остальные числом «И ещё N»;
    /// каждая при этом помечена сказанной — подробности лежат в своей карточке. Уведомление — по одному на съёмку;
    /// сказанной считается только та, что система приняла.
    @discardableResult
    func announceWeather(_ channel: WeatherChannel) async -> [WeatherWatch.Say] {
        let pass = weatherPass()
        var told: [WeatherWatch.Say] = []
        switch channel {
        case .banner:
            // Пока шёл прогноз, приложение ушло в фон: баннер уехал бы невиданным, а новость считалась бы
            // сказанной. Молчим — скажет возврат или фон (ревью GPT к 58e88fd).
            guard sceneActive else { break }
            told = pass.say
            if let top = pass.say.first, let words = weatherWords(top) {
                wxOfferPending = true
                pushNotice(NoticeQueue.Notice(title: words.title, text: words.text, sessionId: top.id),
                           more: pass.say.count - 1)
            }
        case .notification:
            if let poster = wxPoster {
                for say in pass.say {
                    guard let words = weatherWords(say) else { continue }
                    let a = InstantAlert(id: InstantAlert.weatherId(say.id), sessionId: say.id,
                                         title: words.title, body: words.text)
                    if await poster.deliver(a) { told.append(say) }
                }
            }
        }
        if pass.writes || !told.isEmpty {
            WeatherMemory.apply(pass, told: told, in: &snapshot)
            persist()
        }
        await wxLog(channel, pass: pass, told: told)
        return told
    }

    /// Слова беты (`wxShiftSay` с именем): заголовок «24 октября · прогноз испортился», текст — вариант «W»:
    /// «„Анна и Илья“: балл заката был 80 из 100, стал 30.» или «…: небо обещали — ясно, теперь дождь.»
    func weatherWords(_ say: WeatherWatch.Say) -> (title: String, text: String)? {
        guard let s = snapshot.sessions.first(where: { $0.id == say.id }) else { return nil }
        let key = say.isUp ? "wxs.upT" : say.gap == 3 ? "wxs.badT" : "wxs.downT"
        let words = PlannerWords(lexicon: lexicon, orgs: orgs)
        let name = words.clientName(s)
        let who = name.isEmpty ? words.typeName(s) : name
        let text: String
        if WeatherShift.saysScore(say.was, say.now) {
            text = lexicon.t("wxs.scoreW", ["a": "\(say.was.sunset ?? 0)", "b": "\(say.now.sunset ?? 0)", "who": who])
        } else {
            text = lexicon.t("wxs.skyW", ["a": lexicon.t("qualCond." + say.was.quality.rawValue).lowercased(),
                                          "b": lexicon.t("qualCond." + say.now.quality.rawValue).lowercased(),
                                          "who": who])
        }
        let title = DateText(language: language).dMon(Self.noon(s.day)) + " · " + lexicon.t(key).lowercased()
        return (title, text)
    }

    /// День как момент в полдень — словарю дат нужен `Date`.
    static func noon(_ d: CivilDate) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (d.year, d.month, d.day, 12)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: c) ?? Date()
    }

    // MARK: - Баннер

    /// Показ: 5,2 с на экране, следующий — через 5,6 с (веб `notify` / `notifNext`; `noticeTiming`). Очередь
    /// кончилась после баннера о прогнозе — тогда, а не поверх него, плашка «Сообщать и когда закрыто?» (30.6b).
    func pushNotice(_ n: NoticeQueue.Notice, more: Int) {
        guard notices.push(n, more: more) else { return }
        noticeTask = Task { [weak self] in
            while let self, self.notices.current != nil {
                self.noticeShown = true
                try? await Task.sleep(for: self.noticeTiming.onScreen)
                self.noticeShown = false
                try? await Task.sleep(for: self.noticeTiming.step)
                self.notices.advance()
            }
            self?.offerPendingWeatherAlerts()
        }
    }

    /// Баннер о прогнозе отыграл — предложить плашку. Приложение в фоне — ожидание доживает до возврата
    /// (`RootView` зовёт снова на `.active`), иначе свёрнутое во время баннера не спросило бы никогда
    /// (ревью GPT к 0b19747).
    func offerPendingWeatherAlerts() {
        guard wxOfferPending, notices.current == nil, sceneActive else { return }
        wxOfferPending = false
        offerWeatherAlerts()
    }

    // MARK: - Плашка «Сообщать и когда закрыто?» (30.6b)

    static let wxAskedKey = "lightplan.native.notify.wxAsked"

    /// Плашку уже показывали и на неё ответили — на этой установке больше не появится.
    var weatherAlertAsked: Bool { wxAskDefaults?.bool(forKey: Self.wxAskedKey) ?? wxAskedMemory }

    private func markWeatherAlertAsked() {
        wxAskedMemory = true
        wxAskDefaults?.set(true, forKey: Self.wxAskedKey)
    }

    /// Все условия, кроме ответа системы: их же проверяем заново после ожидания.
    private var canOfferWeatherAlerts: Bool {
        alertCenter != nil && notifOn("wx") && !weatherAlertAsked && !weatherAlertAsk && !studioAlertAsk && sceneActive
    }

    /// После первого баннера о прогнозе: система ещё не спрашивала — своя плашка. Разрешили или отказали раньше
    /// (здесь, в настройках или плашкой студийного часа) — не нужна. Системное окно здесь не зовётся никогда.
    func offerWeatherAlerts() {
        guard canOfferWeatherAlerts, let center = alertCenter else { return }
        wxOfferTask = Task { [weak self] in
            let auth = await center.authorization()
            guard let self else { return }
            alertAuth = auth
            guard auth == .notDetermined, canOfferWeatherAlerts else { return }
            weatherAlertAsk = true
        }
    }

    /// «Да» — системное окно (то же, что кнопка «Разрешить уведомления»); «Не сейчас» и касание мимо — плашка
    /// закрыта навсегда. «Спрашивали» — по ответу, не по показу: закрыли приложение с плашкой — спросим снова.
    public func answerWeatherAlertAsk(yes: Bool) {
        weatherAlertAsk = false
        markWeatherAlertAsked()
        if yes { allowWeatherAlerts() }
    }

    #if DEBUG
    /// Снимки (`-LPWxAsk 1`): плашка на экране сразу, без баннера и без системы.
    func debugShowWeatherAsk() {
        if UserDefaults.standard.bool(forKey: "LPWxAsk") { weatherAlertAsk = true }
    }
    #endif

    /// Текст на экране: «И ещё N» — у последнего из показанных (веб `notifTail`, ключ карточки `card.clashMore`).
    public var noticeText: String? {
        guard let n = notices.current else { return nil }
        let tail = notices.tail
        return tail > 0 ? n.text + " " + lexicon.t("card.clashMore", ["n": "\(tail)"]) : n.text
    }

    /// Нажали на баннер: он уезжает, открывается карточка съёмки.
    public func tapNotice() {
        let sid = notices.current?.sessionId
        noticeShown = false
        if let sid { openFromNotice(sid) }
    }

    /// Карточка записи из баннера или уведомления; другая открытая карточка закрывается как обычно (с `wxAck`).
    func openFromNotice(_ sid: String) {
        guard snapshot.sessions.contains(where: { $0.id == sid }) else { return }
        if let cur = cardId, cur != sid { closeCard() }
        openCard(id: sid)
    }

    // MARK: - Настройки

    /// Тумблер «Предупреждения о смене погоды» (веб `#notifWxToggle`): `notif.all` и `notif.wx`. Показывает желание,
    /// а не разрешение системы: баннеру при открытии разрешение не нужно.
    public var weatherAlertsWanted: Bool { notifOn("wx") }

    /// Включили — сразу обход (веб `watchTick(true)` из тумблера). Своего «Разрешить все» у натива нет: включая
    /// погоду руками, человек разрешает и его (так же делает студийный час). Остальные поля `notif` не трогаются.
    public func setWeatherAlerts(_ on: Bool) {
        writeNotif(on ? ["wx": true, "all": true] : ["wx": false])
        if on { watchWeather(force: true) } else { WeatherRefreshTask.cancel() }
    }

    /// «Разрешить уведомления» под тумблером: системный вопрос — по нажатию, не на запуске. Разрешение одно на
    /// приложение — студийный час сверяется с ним тоже.
    public func allowWeatherAlerts() {
        wxOfferTask = Task { [weak self] in
            guard let self, let center = alertCenter else { return }
            if await center.authorization() == .notDetermined { _ = await center.requestAuthorization() }
            alertAuth = await center.authorization()
            syncStudioAlerts(force: true)
        }
    }

    // MARK: - Фон

    /// Хотим ли будить себя: следить есть за кем, погода не выключена, система разрешила говорить.
    var weatherWakeWanted: Bool { notifOn("wx") && alertAuth == .allowed && !weatherWatched().isEmpty }

    /// Ушли в фон и после каждого фонового прохода: попросить следующее пробуждение или снять просьбу.
    func scheduleWeatherWake() {
        if weatherWakeWanted {
            let ok = WeatherRefreshTask.schedule(now: now())
            wxLogLine("schedule submitted=\(ok)")
        } else {
            WeatherRefreshTask.cancel()
            wxLogLine("schedule cancel wx=\(notifOn("wx")) auth=\(alertAuth) watched=\(weatherWatched().count)")
        }
    }

    /// Имя фоновой задачи для `.backgroundTask(.appRefresh(…))` таргета: таргет видит только этот пакет.
    public nonisolated static var weatherTaskIdentifier: String { WeatherRefreshTask.identifier }

    /// Делегат уведомлений — из `init` приложения, до конца запуска (нажатие при холодном запуске).
    public static func installNotificationDelegate() {
        SystemNotificationCenter.install(delegate: .shared)
    }

    /// Фоновый проход (`BGAppRefreshTask`): то же правило, свой канал. Модель — та же, что у экранов
    /// (`sharedLive`): живое приложение в памяти держит снимок, и запись мимо него затёрлась бы его следующей
    /// записью — вместе с отметкой «сказано», и баннер повторил бы уведомление.
    public static func backgroundWeather() async {
        let app = await sharedLive()
        if let center = app.alertCenter { app.alertAuth = await center.authorization() }
        await app.wxWatchTask?.value
        await app.runWeatherWatch(force: true, channel: .notification)
        await app.flush()
        app.scheduleWeatherWake()
    }

    /// Замер фонового канала в симуляторе (`-LPWxBgRun 1`, Debug): `BGTaskScheduler` там просьбу не принимает
    /// (`submit` — ошибка), и `_simulateLaunchForTaskWithIdentifier` из lldb проходит, но обработчик не зовёт (замер 22.10). Ушли на домашний экран — тот же обработчик, что зовёт
    /// `.backgroundTask(.appRefresh)`, под фоновым временем системы: уведомление приходит на закрытое приложение.
    func debugWeatherBackgroundRun() {
        #if DEBUG && os(iOS)
        guard UserDefaults.standard.bool(forKey: "LPWxBgRun") else { return }
        final class Ticket: @unchecked Sendable { var id = UIBackgroundTaskIdentifier.invalid }
        let ticket = Ticket()
        ticket.id = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(ticket.id) }
        Task { @MainActor in
            await Self.backgroundWeather()
            UIApplication.shared.endBackgroundTask(ticket.id)
        }
        #endif
    }

    /// `-LPWxLog <файл>` (Debug): по строке на обход — канал, кого знакомили, кому сказали. Замеры шага 30.6.
    private func wxLog(_ channel: WeatherChannel, pass: WeatherWatch.Pass, told: [WeatherWatch.Say]) async {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "LPWxLog") else { return }
        let stamp = ISO8601DateFormatter().string(from: now())
        let say = pass.say.map { "\($0.id):\($0.gap):\($0.was.quality.rawValue)/\($0.was.sunset.map(String.init) ?? "-")→\($0.now.quality.rawValue)/\($0.now.sunset.map(String.init) ?? "-")" }
        var line = "# \(stamp) \(channel) seed=\(pass.seed.keys.sorted()) say=\(say) told=\(told.map(\.id)) dead=\(pass.dead)\n"
        if channel == .notification, let system = alertCenter as? SystemNotificationCenter {
            try? await Task.sleep(for: .milliseconds(300))
            line += (await system.dump()).filter { $0.contains(InstantAlert.weatherPrefix) }.map { "  " + $0 + "\n" }.joined()
        }
        wxLogLine(line, raw: true)
        #endif
    }

    private func wxLogLine(_ text: String, raw: Bool = false) {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "LPWxLog") else { return }
        let line = raw ? text : "# \(ISO8601DateFormatter().string(from: now())) \(text)\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
        #endif
    }
}

// MARK: - Одна модель на приложение

extension AppModel {
    @MainActor private static var liveOnce: Task<AppModel, Never>?

    /// Живая модель, одна на процесс: экраны и фоновая задача берут одну и ту же. iOS может поднять приложение
    /// в фоне ради обновления раньше любого экрана — тогда экран потом получает уже собранную.
    public static func sharedLive() async -> AppModel {
        if let t = liveOnce { return await t.value }
        let t = Task { @MainActor in await live() }
        liveOnce = t
        return await t.value
    }
}
