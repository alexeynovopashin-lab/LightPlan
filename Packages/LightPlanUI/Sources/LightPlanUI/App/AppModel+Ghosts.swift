import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Лист призрака: одно событие или несколько (на ленте дня они схлопнулись в «+N», на неделе — «ещё N»).
public struct GhostSheetTarget: Identifiable, Equatable, Sendable {
    public let ghosts: [Ghost]
    public var id: String { ghosts.map(\.id).joined(separator: "|") }
}

/// Чужие календари призраками (шаг 30.5, `docs/14` «Чужие календари — призраками»).
///
/// Призрак видно, править нельзя; он не входит в данные приложения (`snapshot`), не пишется в Календарь и не уходит
/// из телефона: список живёт только в памяти запуска и пересчитывается из EventKit. Решение остаётся за
/// фотографом — «Занять» создаёт обычное занятое время, и только по нажатию.
extension AppModel {

    // MARK: - Что видит экран

    /// Что показывает тумблер: человек включил и право есть. «Хочет, но права нет» — не «включено».
    public var ghostsOn: Bool { ghostWanted && calendarAuth == .allowed }

    /// Выбранные календари есть, а событий в окне нет, — не повод говорить «пусто»: просто ничего не отмечено.
    public var ghostPicked: Int { ghostChoices.filter(\.shown).count }

    // MARK: - Подключение

    func attachGhosts(store: any CalendarStoring, mirrorMemory: any CalendarMirrorMemory, memory: any GhostMemory,
                      mode: GhostCalendarsDefault, watch: Bool) {
        ghostWatch?.cancel()
        ghostWatch = nil
        ghostLoad?.cancel()
        ghostMemory = memory
        ghostReader = GhostCalendars(store: store, mirrorMemory: mirrorMemory, memory: memory, mode: mode)
        ghostWanted = memory.record.on
        ghostList = []
        ghostWindow = nil
        if watch { watchGhosts(store) }
        ghostsEnsure(around: planner.selected)
    }

    /// Календарная база изменилась: через секунду тишины призраки читаются заново. Всплеск уведомлений склеивается
    /// по счётчику, а не цепочкой сна: десять уведомлений подряд — одно чтение.
    func watchGhosts(_ store: any CalendarStoring) {
        ghostWatch?.cancel()
        ghostWatch = Task { [weak self] in
            for await _ in store.changes() {
                guard let self else { return }
                self.scheduleGhostReload()
            }
        }
    }

    func scheduleGhostReload() {
        ghostGen += 1
        let gen = ghostGen
        let settle = calendarSettle
        ghostLoad = Task { [weak self] in
            try? await Task.sleep(for: settle)
            guard let self, gen == self.ghostGen, !Task.isCancelled else { return }
            await self.reloadGhosts()
        }
    }

    // MARK: - Чтение

    /// Окно дней, в котором призраки нужны экрану: выбранный день с запасом. Пока оно прочитано, ничего не читается.
    /// Читается шире нужного (месяц назад, три вперёд), чтобы листание не дёргало базу на каждый день.
    func ghostsEnsure(around day: CivilDate) {
        guard ghostReader != nil, ghostWanted else { return }
        let needFrom = day.adding(days: -10), needTo = day.adding(days: 45)
        if let w = ghostWindow, w.from <= needFrom, w.to >= needTo { return }
        let from = day.adding(days: -30), to = day.adding(days: 90)
        ghostLoadGen += 1
        let gen = ghostLoadGen
        ghostLoad = Task { [weak self] in await self?.loadGhosts(from: from, to: to, gen: gen) }
    }

    /// Перечитать заново (база изменилась, вернулись в приложение, сменили отметки).
    func reloadGhosts() async {
        guard let reader = ghostReader else { return }
        await reader.invalidate()
        ghostLoadGen += 1
        await loadGhosts(from: ghostWindow?.from ?? planner.selected.adding(days: -30),
                         to: ghostWindow?.to ?? planner.selected.adding(days: 90), gen: ghostLoadGen)
        await refreshGhostFacts()
    }

    private func loadGhosts(from: CivilDate, to: CivilDate, gen: Int) async {
        guard let reader = ghostReader else { return }
        let zone = place.zone
        let a = WallTime(day: from, minutes: 0).moment(in: zone).date
        let b = WallTime(day: to.adding(days: 1), minutes: 0).moment(in: zone).date
        let list = await reader.ghosts(from: a, to: b)
        // Позже пришёл другой запрос или тумблер выключили — этот ответ устарел.
        guard gen == ghostLoadGen, !Task.isCancelled else { return }
        ghostList = list
        ghostWindow = ghostWanted ? (from, to) : nil
        // Список календарей — после чтения, а не до: календарь, заведённый в другом приложении, система показывает не
        // сразу (поймано на настоящем EventKit: список в настройках отставал от событий).
        await refreshGhostFacts()
    }

    /// Тумблер, отметки и право, как их видит читатель.
    func refreshGhostFacts() async {
        guard let reader = ghostReader else { return }
        ghostWanted = await reader.record.on
        ghostChoices = await reader.choices()
        if !ghostsOn, !ghostList.isEmpty { ghostList = []; ghostWindow = nil }
    }

    // MARK: - Тумблер и галочки

    /// «Другие календари». Чужие календари читать нельзя без полного доступа к Календарю: если права ещё не
    /// спрашивали, сначала человеку объясняют, зачем (`ghostAsk`), и только потом показывают системный запрос.
    /// Отказали раньше — спросить второй раз нельзя; строка ведёт в настройки iPhone.
    public func setGhosts(_ on: Bool) {
        guard let reader = ghostReader, let store = calendarStore else { return }
        enqueueCalendar { app in
            if !on {
                await reader.setOn(false)
                app.ghostLoadGen += 1
                app.ghostList = []
                app.ghostWindow = nil
                await app.refreshGhostFacts()
                return
            }
            switch await store.authorization() {
            case .allowed:
                await reader.setOn(true)
                app.ghostWanted = true
                app.calendarAuth = .allowed
                await app.refreshGhostFacts()
                app.ghostsEnsure(around: app.planner.selected)
            case .notDetermined:
                app.ghostAsk = true
            case .denied:
                app.calendarAuth = .denied
            }
        }
    }

    /// Ответ на объяснение перед системным запросом.
    public func answerGhostAsk(yes: Bool) {
        ghostAsk = false
        guard yes, let reader = ghostReader, let store = calendarStore else { return }
        enqueueCalendar { app in
            let granted = await store.requestAccess()
            app.calendarAuth = await store.authorization()
            if granted {
                await reader.setOn(true)
                app.ghostWanted = true
                await app.refreshGhostFacts()
                app.ghostsEnsure(around: app.planner.selected)
            }
        }
    }

    /// Галочка у календаря в списке.
    public func setGhostCalendar(_ id: String, shown: Bool) {
        guard let reader = ghostReader else { return }
        // Отметка видна сразу, не дожидаясь чтения.
        ghostChoices = ghostChoices.map { $0.id == id ? GhostCalendars.Choice(calendar: $0.calendar, shown: shown, personal: $0.personal) : $0 }
        enqueueCalendar { app in
            await reader.setShown(id, shown)
            await app.reloadGhosts()
        }
    }

    // MARK: - «Занять» и наложение

    /// Занятое время такое же, как призрак, уже стоит (то же время и та же заметка): второй раз его не заводим.
    public func ghostIsTaken(_ g: Ghost) -> Bool {
        let want = g.busyBlock(id: "", zone: place.zone, now: 0)
        return snapshot.blocks.contains {
            $0.kind == want.kind && $0.note == want.note && $0.from == want.from && $0.allDay == want.allDay
                && $0.days == want.days && $0.start == want.start && $0.duration == want.duration
        }
    }

    /// Кнопка «Занять»: **одно** занятое время («Занят») на время призрака, с названием события в заметке. Призрак
    /// остаётся призраком; других записей кнопка не трогает. `false` — такое занятое время уже есть.
    @discardableResult
    public func occupy(_ g: Ghost) -> Bool {
        guard !ghostIsTaken(g) else { return false }
        saveBlock(g.busyBlock(id: Self.newBlockId(nowMs), zone: place.zone, now: nowMs))
        return true
    }

    /// Мягкая плашка формы (решение Алексея 22.10, «1А»): время съёмки пересекается с событием чужого календаря. Не
    /// запрет — сохранить можно. Сравниваются моменты, а не часы на стене: съёмка в Москве и матч в Томске пересекаются
    /// только тогда, когда это одно и то же мгновение.
    public func formGhostWarning(_ f: EventForm) -> WishWarning? {
        guard ghostsOn, !ghostList.isEmpty else { return nil }
        let probe = f.session(orgName: nil, and: "", studios: snapshot.studios, spots: snapshot.spots,
                              homeCity: homeCityName, now: now())
        let ctx = CalendarPlan.Context(studios: snapshot.studios, spots: snapshot.spots, zones: place.zones,
                                       homeZone: place.zone, title: { _ in "" }, blockTitle: { _ in "" })
        guard let span = CalendarPlan.span(of: probe, ctx) else { return nil }
        // Съёмка через полночь касается и следующих дней: событие «на весь день» любого из них — наложение.
        var endMinute = probe.endMinute
        if endMinute <= probe.start { endMinute = probe.start + 90 }
        let lastDay = f.day.adding(days: max(0, (endMinute - 1) / 1440))
        let hits = GhostOverlap.find(start: span.start, end: span.end, day: f.day, through: lastDay, in: ghostList)
        guard let first = hits.first else { return nil }
        let facts = PlannerFacts(app: self, dark: false)
        let name = first.title.isEmpty ? lexicon.t("ghost.untitled") : first.title
        var text: String
        if first.allDay {
            text = lexicon.t("ghost.noteDayM", ["cal": first.calendarTitle, "name": name])
        } else {
            let r = first.wallRange(in: place.zone)
            text = lexicon.t("ghost.noteM", ["cal": first.calendarTitle, "name": name,
                                             "when": facts.range(Double(r.start.minutes), Double(r.end.minutes))])
        }
        if hits.count > 1 { text += " " + lexicon.t("card.clashMore", ["n": "\(hits.count - 1)"]) }
        return WishWarning(title: lexicon.t("clash.overlapT"), message: text)
    }
}

#if DEBUG
extension AppModel {
    /// Снимки экранов с призраками (`-LPShotGhosts`): подставной календарь телефона, призраки включены. Пары без этого
    /// аргумента идут без читателя вовсе — как прежде.
    func debugShotGhosts(many: Bool) {
        let store = InMemoryCalendarStore()
        let son = store.userAddCalendar(title: "Сын", type: .account)
        let work = store.userAddCalendar(title: "Работа", type: .exchange, source: "Exchange")
        let day = planner.selected, zone = place.zone
        func at(_ m: Int) -> Date { WallTime(day: day, minutes: m).moment(in: zone).date }
        store.userAdd(title: "Матч", start: at(600), end: at(690), calendarId: son, location: "Стадион")
        store.userAdd(title: "Планёрка", start: at(630), end: at(660), calendarId: work)
        store.userAdd(title: "Кружок", start: at(1020), end: at(1080), calendarId: son)
        let a = Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day))!
        store.userAdd(title: "Каникулы", start: a, end: a.addingTimeInterval(86_399), calendarId: son, allDay: true)
        if many {
            for (i, t) in ["Созвон", "Ревью", "Демо", "Ретро"].enumerated() {
                store.userAdd(title: t, start: at(840 + i * 10), end: at(930), calendarId: work)
            }
        }
        attachCalendar(store: store, memory: InMemoryCalendarMemory(), ghosts: InMemoryGhostMemory(GhostRecord(on: true)))
    }
}
#endif
