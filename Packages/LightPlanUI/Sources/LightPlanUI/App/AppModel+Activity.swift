import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain
#if os(iOS)
import UIKit
#endif

/// Экран активности: плашка на заблокированном телефоне и в Dynamic Island, пока идёт съёмка (шаг 30б.3).
///
/// Что и когда — решает `ActivityRules` (Domain), как выглядит — `ActivityFrame` и `LightPlanWidget/Views/ActivityViews.swift`. Здесь
/// клей: сверка с данными в каждый миг, когда приложение что-то узнало (запуск, возврат на экран, запись данных, нажатие на
/// уведомление «Студийный час»), и приём ссылок кнопок. Запустить плашку можно только при открытом приложении (замер 30б.3а), поэтому
/// иного момента нет, и платного Push, который будил бы плашку сам, на бесплатной команде тоже нет.
extension AppModel {
    #if DEBUG
    static var activityDemoOn = false
    #endif

    /// Живое приложение: система экрана активности и открытие ссылок (звонок, плеер).
    func attachActivity() {
        #if os(iOS)
        activityDefaults = .standard
        useActivityHost(ActivityKitHost())
        activityOpen = { url in UIApplication.shared.open(url) }
        debugActivityDemo()
        #endif
    }

    /// Система экрана активности и память: смахнули плашку — это записывается и переживает перезапуск приложения.
    func useActivityHost(_ host: any ActivityHosting) {
        host.onDismissed = { [weak self] id in self?.activityDismissed[id] = self?.now().timeIntervalSince1970 }
        activityHost = host
        loadActivityMemory()
    }

    private static let dismissedKey = "lp.activity.dismissed", marksKey = "lp.activity.marks"
    /// Память держится трое суток: съёмка дольше не идёт.
    private static let memorySpan: Double = 3 * 86400

    func loadActivityMemory() {
        guard let d = activityDefaults else { return }
        let cut = now().timeIntervalSince1970 - Self.memorySpan
        let dismissed = (d.dictionary(forKey: Self.dismissedKey) as? [String: Double] ?? [:]).filter { $0.value > cut }
        let marks = (d.dictionary(forKey: Self.marksKey) as? [String: Double] ?? [:]).filter { $0.value > cut }
        // Присвоение одного словаря не должно записать поверх сохранённого другой, ещё пустой (ревью GPT к 8580014): пока читаем, записи нет.
        activityDefaults = nil
        activityDismissed = dismissed
        activityMarks = marks
        activityDefaults = d
        saveActivityMemory()
    }

    func saveActivityMemory() {
        activityDefaults?.set(activityDismissed, forKey: Self.dismissedKey)
        activityDefaults?.set(activityMarks, forKey: Self.marksKey)
    }

    /// Привести плашку к данным. Сверки идут по очереди: перезапуск — «закрыть, потом запросить» — не должен наложиться на соседнюю.
    func syncActivity(_ reason: ActivityRules.Reason = .change) {
        guard activityHost != nil else { return }
        #if DEBUG
        if Self.activityDemoOn { return }   // демонстрационная плашка живёт вне данных (`debugActivityDemo`)
        #endif
        let prev = activityChain
        activityChain = Task { [weak self] in
            await prev?.value
            await self?.runActivity(reason)
        }
    }

    /// Сверка закончена — для тестов: ждёт всю очередь.
    func settleActivity() async { await activityChain?.value }

    private func runActivity(_ reason: ActivityRules.Reason) async {
        guard let host = activityHost else { return }
        let nowDate = now()
        let feed = makeWidgetFeed()
        let shown = host.shown
        var dismissed = Set(activityDismissed.keys)
        // Плашки нет, хотя мы её запускали, сами не закрывали и срок системы не вышел, — человек смахнул её (событие системы могло
        // прийти позже этой сверки или не прийти вовсе, пока приложение было закрыто).
        if shown == nil {
            for (id, at) in activityMarks where nowDate.timeIntervalSince1970 - at < ActivityRules.systemLimit { dismissed.insert(id) }
        }
        let wanted = ActivityRules.wanted(in: feed, at: nowDate, dismissed: dismissed)
        // После перезапуска приложения студийный режим помнит сама плашка: в памяти он пуст, а аренда ещё идёт.
        if activityStudioFor == nil, let shown, shown.frame.mode == .studio, shown.shootId == wanted?.id { activityStudioFor = shown.shootId }
        let run = shown.map { ActivityRules.Run(shootId: $0.shootId, startedAt: $0.startedAt) }
        // Студийный режим держится за одну съёмку: другая плашка или конец съёмки сбрасывают его.
        if activityStudioFor != nil, activityStudioFor != wanted?.id { activityStudioFor = nil }
        let frame = wanted.map { activityFrame(feed, $0, at: nowDate) }
        switch ActivityRules.decide(run: run, wanted: wanted, reason: reason, now: nowDate) {
        case .none:
            break
        case .start:
            if let frame { begin(host, frame, at: nowDate) }
        case .update:
            // Тот же кадр, что уже показан, системе не шлём: правки данных идут пачками.
            if let frame, !Self.sameFrame(frame, shown?.frame) { await host.update(frame) }
        case .restart:
            await host.end()
            activityMarks = [:]
            if let frame { begin(host, frame, at: nowDate) }
        case .end:
            await host.end()
            activityMarks = [:]
            activityStudioFor = nil
        }
    }

    private func begin(_ host: any ActivityHosting, _ frame: ActivityFrame, at date: Date) {
        guard host.allowed else { return }
        // Отказ системы (нет места под активность, слишком большое состояние) молчит: съёмка идёт и без плашки; метки тогда нет.
        guard (try? host.start(frame, startedAt: date)) != nil else { return }
        activityMarks[frame.shootId] = date.timeIntervalSince1970
    }

    /// Кадры равны, если отличаются только моментом сборки.
    static func sameFrame(_ a: ActivityFrame, _ b: ActivityFrame?) -> Bool {
        guard var b else { return false }
        b.asOf = a.asOf
        return a == b
    }

    /// Кадр съёмки: слова на языке приложения, кнопки студии — по тому, что есть у записи (номер администратора, плейлист).
    func activityFrame(_ feed: WidgetFeed, _ shoot: WidgetFeed.Shoot, at date: Date) -> ActivityFrame {
        let s = snapshot.sessions.first { $0.id == shoot.id }
        let reach = ActivityReach(
            admin: s.flatMap { StudioTileState.tel($0, app: self) } != nil,
            playlist: s.flatMap { musicButton(for: $0) } != nil)
        return ActivityFrame.make(feed: feed, shoot: shoot, now: date,
                                  mode: activityStudioFor == shoot.id ? .studio : .route,
                                  words: activityWords(), reach: reach)
    }

    func activityWords() -> ActivityWords {
        var w = ActivityWords()
        w.nowAt = lexicon.t("day.nowAt")
        w.soonAt = lexicon.t("day.soonAt")
        w.running = lexicon.t("day.running")
        w.done = lexicon.t("day.shootDone")
        w.untilName = lexicon.t("activity.untilName")
        w.untilGolden = lexicon.t("activity.untilGolden")
        w.exit = lexicon.t("activity.exit")
        w.callAdmin = lexicon.t("studio.callAdmin")
        w.playlist = lexicon.t("activity.playlist")
        w.hourShort = lexicon.t("widget.hourShort")
        w.minShort = lexicon.t("widget.minShort")
        return w
    }

    /// Нажатие на уведомление «Студийный час» (в начале аренды): плашка переходит в студийный режим — кнопки админа и плейлиста.
    /// Нет плашки, а съёмка идёт — она запускается сразу в студийном режиме (приложение открыто, значит можно).
    func switchActivityToStudio(sessionId: String) {
        activityStudioFor = sessionId
        syncActivity()
    }

    /// `lightplan://activity/admin|playlist`: кнопки плашки. Из плашки ссылка всегда ведёт в приложение (замер 30б.3а), поэтому
    /// набор номера и плеер открывает оно: звонок — администратору студии идущей съёмки, плеер — её плейлист.
    @discardableResult
    func openActivityLink(_ url: URL) -> Bool {
        guard let link = ActivityLink.of(url) else { return false }
        let id = activityHost?.shown?.shootId ?? ActivityRules.wanted(in: makeWidgetFeed(), at: now())?.id
        guard let id, let s = snapshot.sessions.first(where: { $0.id == id }) else { return true }
        switch link {
        case .admin:
            if let tel = StudioTileState.tel(s, app: self), let call = StudioTileState.callURL(tel) { activityOpen(call) }
        case .playlist:
            if let music = musicButton(for: s), let href = URL(string: music.href) { activityOpen(href) }
        }
        return true
    }
}

#if DEBUG
extension AppModel {
    /// Снимки и замеры (`-LPActivityDemo wedding|rent|studio|many`, `-LPActivityStyle full|icons|compact`, итог запроса — в файл `-LPActivityLog`): настоящая плашка на экране
    /// блокировки с кадром, собранным вне данных — съёмка «шла три часа назад»: Сборы, Церемония, Прогулка, Банкет; у `rent`/`studio`
    /// ещё идёт аренда студии с администратором и плейлистом. Сверка с данными, пока демонстрация включена, плашку не трогает.
    func debugActivityDemo() {
        let d = UserDefaults.standard
        guard let kind = d.string(forKey: "LPActivityDemo"), let host = activityHost else { return }
        Self.activityDemoOn = true
        if let style = d.string(forKey: "LPActivityStyle"), let id = Bundle.main.bundleIdentifier {
            UserDefaults(suiteName: WidgetFeed.groupID(bundleID: id))?.set(style, forKey: "lp.activity.studioStyle")
        }
        let nowDate = now()
        func at(_ minutes: Double) -> Int64 { Moment(nowDate.addingTimeInterval(minutes * 60)).milliseconds }
        let signs = ["makeup", "rings", "park", "feast"]
        var stops = ["Сборы жениха", "Церемония", "Прогулка", "Банкет"].enumerated().map { i, name in
            WidgetFeed.Stop(at: at([-180, -30, 60, 240][i]), name: name, place: "", sign: signs[i])
        }
        if kind == "many" {
            stops = (0..<16).map { WidgetFeed.Stop(at: at(Double($0) * 30 - 240), name: "Достопримечательность \($0 + 1)", place: "", sign: "camera") }
        }
        let rents = kind == "rent" || kind == "studio"
            ? [WidgetFeed.Rent(from: at(-40), to: at(80), deadline: at(75), studio: "Томсон")] : []
        let shoot = WidgetFeed.Shoot(id: "demo", start: at(-180), end: at(420), title: "Свадьба", place: "Томск", wantsSunset: false,
                                     rents: rents, stops: stops, genre: "wedding")
        var feed = makeWidgetFeed()
        feed.shoots = [shoot]
        let frame = ActivityFrame.make(feed: feed, shoot: shoot, now: nowDate, mode: kind == "studio" ? .studio : .route,
                                       words: activityWords(), reach: ActivityReach(admin: true, playlist: true))
        Task { [weak self] in
            await host.end()
            guard self != nil else { return }
            var note = "demo start ok"
            do { try host.start(frame, startedAt: nowDate) } catch { note = "demo start FAILED \(error)" }
            if let path = d.string(forKey: "LPActivityLog") {
                try? "\(note) allowed=\(host.allowed) shown=\(host.shown != nil)\n".write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }
}
#endif
