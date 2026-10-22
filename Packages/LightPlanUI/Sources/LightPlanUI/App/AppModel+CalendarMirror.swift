import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Съёмки в Календаре iPhone (шаг 30.1–3, `docs/14`).
///
/// Правда в Light Plan, Календарь её показывает. Расписание — функция данных, как у студийного часа: после правки
/// записи, при запуске, при возврате в приложение и когда календарная база изменилась, календарь приводится к списку
/// событий (`CalendarPlan`). Обратно едет только то, что человек сделал в Календаре руками (шаг 30.4):
/// **время и место** подвинутого события возвращаются в съёмку, а событие, заведённое в календаре «Light Plan»,
/// становится черновиком съёмки; название и заметки обратно не едут. Отказ в праве ничего не ломает: зеркало
/// молчит, остальное работает как раньше.
extension AppModel {

    // MARK: - Что видит экран

    /// Что показывает тумблер: человек включил, право есть и календарь на месте. «Хочет, но права нет» — не
    /// «включено»: ничего не появится.
    public var calendarMirrorOn: Bool { calendarWanted && calendarAuth == .allowed && !calendarGoneAsk }

    /// Права нет, а оно нужно: строка ведёт в настройки iPhone, а не спрашивает снова (спросить можно один раз).
    public var calendarNeedsSettings: Bool { calendarAuth == .denied }

    /// Есть ли смысл показывать строку: живое приложение на iPhone.
    public var calendarAvailable: Bool { calendarMirror != nil }

    // MARK: - Подключение

    /// Живое приложение: настоящий календарь телефона и память на устройстве. На Mac зеркала нет (нужны права
    /// песочницы, а шаг про iPhone): строки в настройках тоже.
    func attachCalendar() {
        #if os(iOS)
        attachCalendar(store: EventKitCalendarStore(), memory: DeviceCalendarMemory(), watch: true)
        #endif
    }

    /// Подставки (тесты, снимки): календарь и память подаются снаружи. Слушать изменения базы (`watch`) — только живому
    /// приложению и тесту, который проверяет именно это: сверка по уведомлению идёт сама и мешала бы остальным
    /// ждать конца «своего» прохода.
    func attachCalendar(store: any CalendarStoring, memory: any CalendarMirrorMemory, watch: Bool = false) {
        calendarStore = store
        calendarMirror = CalendarMirror(store: store, memory: memory)
        calendarWanted = memory.record.wanted
        calendarWatch?.cancel()
        calendarWatch = nil
        if watch { watchCalendar(store) }
        syncCalendarMirror(force: true)
    }

    /// Календарная база изменилась (правка в Календаре, синхронизация, наша же запись): сверка через секунду тишины.
    /// Наша запись будит и нас самих — проход тогда находит всё на месте и ничего не пишет, так что цепочка гаснет.
    private func watchCalendar(_ store: any CalendarStoring) {
        calendarWatch = Task { [weak self] in
            for await _ in store.changes() {
                guard let self else { return }
                self.syncCalendarMirror(force: true, settle: self.calendarSettle)
            }
        }
    }

    // MARK: - Названия и события

    /// Название события: жанр и клиент, жанр первым — в недельной сетке видно первые слова («Свадьба · Ирина»).
    func calendarTitle(of s: Session) -> String {
        // Черновик из Календаря зовётся так, как его назвал человек: переименовывать его событие нечем.
        if s.isCalendarDraft { return s.fromCalendar ?? "" }
        let w = PlannerWords(lexicon: lexicon, orgs: snapshot.orgs)
        let who = w.clientName(s)
        let head: String
        if s.kind == .meet {
            head = s.genre == nil ? lexicon.t("plan.meet")
                : lexicon.t("week.meetWith", ["genre": w.shortType(s).lowercased()])
        } else {
            let type = w.typeName(s)
            head = type.isEmpty ? lexicon.t("plan.shortShoot") : type
        }
        return [head, who].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Название занятости: заметка, а без неё — вид («Дорога»).
    func calendarTitle(of b: Block) -> String {
        b.note.isEmpty ? lexicon.t("blkKind." + b.kind.rawValue) : b.note
    }

    /// Всё, что должно стоять в календаре. Пояс — места съёмки; без точки — место приложения (`alertOffsetHours`).
    func calendarDrafts() -> [EventDraft] {
        CalendarPlan.drafts(sessions: snapshot.sessions, blocks: snapshot.blocks, context: calendarContext())
    }

    /// Названия, заметки и пояса, по которым записи становятся событиями и события — записями.
    func calendarContext() -> CalendarPlan.Context {
        let titles = Dictionary(snapshot.sessions.map { ($0.id, calendarTitle(of: $0)) }, uniquingKeysWith: { a, _ in a })
        let blockTitles = Dictionary(snapshot.blocks.map { ($0.id, calendarTitle(of: $0)) }, uniquingKeysWith: { a, _ in a })
        let words = CalendarNotes.Words(client: lexicon.t("calm.noteClient"), contact: lexicon.t("calm.noteContact"),
                                        phone: lexicon.t("calm.notePhone"))
        let country = telCountry
        return CalendarPlan.Context(
            studios: snapshot.studios, spots: snapshot.spots, zones: place.zones, homeZone: place.zone,
            title: { titles[$0.id] ?? "" }, blockTitle: { blockTitles[$0.id] ?? "" },
            notes: { CalendarNotes.text(of: $0, country: country, words: words) })
    }

    // MARK: - Тумблер и выбор учётной записи

    /// Всё, что идёт в Календарь, встаёт в одну очередь: включение, переезд, ответ на вопрос и проход друг друга не
    /// обгоняют. Тесты ждут её конец (`calendarChain`).
    private func enqueueCalendar(_ work: @escaping @MainActor (AppModel) async -> Void) {
        let prev = calendarChain
        calendarChain = Task { [weak self] in
            await prev?.value
            guard let self else { return }
            await work(self)
        }
    }

    /// «Съёмки в Календаре». Включение — первый и единственный момент, когда у системы просят доступ; отказ
    /// ничего не ломает: тумблер остаётся выключенным и строка говорит, где доступ выдаётся.
    public func setCalendarMirror(_ on: Bool) {
        guard let mirror = calendarMirror else { return }
        enqueueCalendar { app in
            app.calendarOffFailed = false
            if on {
                let out = await mirror.enable()
                app.calendarFailed = false
                if case .failed = out { app.calendarFailed = true }
                if case .calendarGone = out { app.calendarGoneAsk = true }
            } else {
                // Не вышло убрать — зеркало остаётся включённым, строка под тумблером говорит почему.
                if case .failed = await mirror.disable() { app.calendarOffFailed = true }
                app.calendarFailed = false
                app.calendarGoneAsk = false
            }
            app.calendarApplied = nil
            await app.runCalendarSync(force: true)
        }
    }

    /// «Куда класть»: календарь переезжает в другую учётную запись, события ложатся в него заново.
    public func setCalendarSource(_ id: String) {
        guard let mirror = calendarMirror, id != calendarSourceId || !calendarMirrorOn else { return }
        enqueueCalendar { app in
            // Календаря ещё нет (зеркало не завелось) — выбор учётной записи и есть включение.
            let hasCalendar = await mirror.record.calendarId != nil
            let out = hasCalendar ? await mirror.moveCalendar(to: id) : await mirror.enable(sourceId: id)
            app.calendarFailed = false
            if case .failed = out { app.calendarFailed = true }
            app.calendarApplied = nil
            await app.runCalendarSync(force: true)
        }
    }

    /// Ответ на «календарь удалён, завести заново?».
    public func answerCalendarGone(yes: Bool) {
        guard let mirror = calendarMirror else { return }
        calendarGoneAsk = false
        enqueueCalendar { app in
            if yes { _ = await mirror.recreateCalendar() } else { _ = await mirror.disable() }
            app.calendarApplied = nil
            await app.runCalendarSync(force: true)
        }
    }

    /// Открыта глава с календарём: список учётных записей и то, где календарь лежит сейчас.
    public func refreshCalendarSources() {
        enqueueCalendar { app in await app.refreshCalendarFacts() }
    }

    private func refreshCalendarFacts() async {
        guard let mirror = calendarMirror, let store = calendarStore else { return }
        calendarAuth = await store.authorization()
        let rec = await mirror.record
        calendarWanted = rec.wanted
        calendarSources = await store.sources()
        let cal = await mirror.calendar()
        calendarSourceId = cal?.sourceId ?? calendarSources.first { $0.id == rec.sourceId }?.id
        // Календаря ещё нет — называем учётную запись, куда его пытались завести (по умолчанию телефона).
        let defaultSource = await store.defaultSourceId()
        let tried = rec.sourceId ?? defaultSource
        calendarSourceTitle = cal?.sourceTitle ?? calendarSources.first { $0.id == tried }?.title
    }

    // MARK: - Проход

    /// Привести календарь к данным. Правки идут пачками — запрос откладывается на треть секунды и склеивается;
    /// `force` (запуск, возврат в приложение, смена тумблера) сверяет даже при тех же данных: событие могли удалить
    /// в Календаре, а право — выдать или отнять в настройках iPhone. По таймеру — никогда.
    func syncCalendarMirror(force: Bool = false, settle: Duration? = nil) {
        guard calendarMirror != nil else { return }
        calendarGen += 1
        if force { calendarForce = true }
        let gen = calendarGen
        enqueueCalendar { app in
            // Позже пришёл другой запрос — он и выполнит работу, унаследовав «принудительно». Проверка до паузы:
            // очередь стоит друг за другом, и пачка правок без неё ждала бы по трети секунды на каждую.
            guard gen == app.calendarGen else { return }
            if let settle { try? await Task.sleep(for: settle) }
            else if !force { try? await Task.sleep(for: .milliseconds(300)) }
            guard gen == app.calendarGen else { return }
            let force = app.calendarForce
            app.calendarForce = false
            // Уведомления базы не гоняют по кругу: после трёх записывающих проходов подряд они ждут человека.
            let fromWatch = settle != nil
            if fromWatch, Date().timeIntervalSince(app.calendarWatchLast) > app.calendarStreakWindow { app.calendarWatchStreak = 0 }
            if fromWatch, app.calendarWatchStreak >= 3 { return }
            app.calendarPassWrote = false
            await app.runCalendarSync(force: force)
            app.calendarWatchStreak = fromWatch && app.calendarPassWrote ? app.calendarWatchStreak + 1 : 0
            if app.calendarPassWrote { app.calendarWatchLast = Date() }
        }
    }

    fileprivate func runCalendarSync(force: Bool) async {
        guard let mirror = calendarMirror, let store = calendarStore else { return }
        calendarAuth = await store.authorization()
        let rec = await mirror.record
        calendarWanted = rec.wanted
        guard rec.wanted else {
            calendarApplied = nil
            await refreshCalendarFacts()
            return
        }
        await learnCalendarZones()
        var drafts = calendarDrafts()
        if !force, calendarApplied == drafts { return }
        // Правки из Календаря возвращаются в записи, и проход повторяется на новых данных; три круга — с запасом
        // (первый принимает, второй дописывает ссылку и заметки, третий убеждается, что всё сошлось).
        var round = 0
        loop: while true {
            switch await mirror.sync(drafts) {
            case .synced(let report):
                if !report.incoming.isEmpty, round < 3, await takeCalendarIncoming(report.incoming, mirror) {
                    round += 1
                    drafts = calendarDrafts()
                    continue loop
                }
                // Пока в календаре есть то, что не принято, «всё привели» не говорим: следующий проход посмотрит снова.
                calendarApplied = report.failed == 0 && report.incoming.isEmpty ? drafts : nil
                calendarFailed = false
                if report.changed || round > 0 { calendarPassWrote = true }
            case .noAccess:
                calendarApplied = nil
            case .calendarGone:
                calendarApplied = nil
                calendarGoneAsk = true
            case .failed:
                calendarApplied = nil
                calendarFailed = true
            }
            break loop
        }
        await refreshCalendarFacts()
    }

    // MARK: - Из Календаря в записи (30.4)

    /// Принять то, что человек сделал в Календаре. `true` — данные изменились (и уже записаны на диск), проход надо
    /// повторить.
    ///
    /// Время и место подвинутого события ложатся в съёмку с меткой правки (`mt`), как любая правка — так обмен
    /// устройств увидит её. Новое событие становится черновиком съёмки; его связывают с записью только **после** записи
    /// на диск: пока связи нет, событие никто не уберёт, а потеряйся запись — оно просто станет черновиком снова.
    private func takeCalendarIncoming(_ incoming: [CalendarMirror.Incoming], _ mirror: CalendarMirror) async -> Bool {
        var changed = false
        var adopt: [(event: String, key: String)] = []
        for item in incoming {
            switch item {
            case .moved(let key, let event):
                // Место могло переехать в другой пояс: его часы нужны до пересчёта времени.
                if let la = event.latitude, let lo = event.longitude {
                    await learnCalendarZone(at: GeoCoordinate(latitude: la, longitude: lo))
                }
                guard let url = URL(string: key) else { continue }
                if let id = CalendarPlan.shootId(in: url) {
                    if takeShootMove(id: id, event: event) { changed = true } else { await mirror.dismiss(key: key, event: event) }
                } else if let id = CalendarPlan.blockId(in: url) {
                    if takeBlockMove(id: id, event: event) { changed = true } else { await mirror.dismiss(key: key, event: event) }
                }
            case .created(let event):
                // Пояс места нужен до того, как часы события станут часами съёмки: оценка по долготе ошибается на час.
                if let la = event.latitude, let lo = event.longitude {
                    await learnCalendarZone(at: GeoCoordinate(latitude: la, longitude: lo))
                }
                let id = Self.newRecordId(now())
                guard let draft = CalendarPlan.newDraft(from: event, id: id, modifiedAt: nowMs, calendarContext()) else { continue }
                snapshot.sessions.append(draft)
                adopt.append((event.id, CalendarPlan.url(shoot: id).absoluteString))
                changed = true
            }
        }
        guard changed else { return false }
        persist()
        await flush()
        for a in adopt { await mirror.adopt(eventId: a.event, key: a.key) }
        return true
    }

    /// Съёмку подвинули в Календаре: время и место ложатся в запись, и ставится та же отметка «Время сдвинуто в календаре:
    /// было → стало» с крестиком, что и от пальца на ленте дня (`DayDrag.commit`): «было» остаётся исходным при повторных
    /// сдвигах, вернули как было — отметка гаснет. Сдвиг самим приложением (форма) отметки не ставит.
    /// `false` — принять нечего (записи нет, студия не меняется строкой, ничего не изменилось).
    private func takeShootMove(id: String, event: StoredEvent) -> Bool {
        guard let i = snapshot.sessions.firstIndex(where: { $0.id == id }),
              let moved = CalendarPlan.applying(event, to: snapshot.sessions[i], calendarContext()) else { return false }
        var s = snapshot.sessions[i]
        s.place = moved.place; s.placeAddress = moved.placeAddress
        s.latitude = moved.latitude; s.longitude = moved.longitude
        let f = PlannerFacts(app: self, dark: false)
        let when = f.dates.dMonShort(f.date(today)) + " " + f.fmt(Double(nowMinute))
        let originDay = s.dayMoved?.day ?? s.day
        func text(_ t: (Int, Int), day: CivilDate) -> String {
            (day == originDay && moved.day == originDay ? "" : f.dates.dMonShort(f.date(day)) + " ") + f.range(Double(t.0), Double(t.1))
        }
        DayDrag.commit(&s, day: moved.day, start: moved.start, end: moved.endMinute) { was, now in
            lexicon.t("day.movedNote", ["when": when, "from": text(was, day: originDay), "to": text(now, day: moved.day)])
        }
        s.modifiedAt = nowMs
        snapshot.sessions[i] = s
        return true
    }

    /// То же для занятого времени: у блока нет карточки и нет ленты для пальца, поэтому «каким был» лежит в самом блоке
    /// (`Block.movedFrom`), а строка живёт в ленте дня и в листе блока (`blockMovedText`).
    private func takeBlockMove(id: String, event: StoredEvent) -> Bool {
        guard let i = snapshot.blocks.firstIndex(where: { $0.id == id }),
              var moved = CalendarPlan.applying(event, to: snapshot.blocks[i], calendarContext()) else { return false }
        let old = snapshot.blocks[i]
        let was = old.movedFrom ?? BlockMoved(from: old.from, allDay: old.allDay, days: old.days, start: old.start, duration: old.duration)
        moved.movedFrom = was.matches(moved) ? nil : was
        moved.modifiedAt = nowMs
        snapshot.blocks[i] = moved
        return true
    }

    // MARK: - Пояса (30.4)

    /// Пояс точки у геокодера, пока тот не известен: событие считается по часам места, а без настоящего пояса место
    /// даёт оценку по долготе (Томск +6 вместо +7, событие на час раньше). Каждую клетку в полградуса спрашиваем один
    /// раз за запуск и не больше шести за проход; нет сети — остаётся оценка, как и было.
    private func learnCalendarZones() async {
        var cells: [(day: CivilDate, key: String, point: GeoCoordinate)] = []
        var seen = Set<String>()
        let from = today.adding(days: -14)
        for s in snapshot.sessions where (s.kind == .shoot || s.kind == .meet) && s.day >= from {
            guard let p = Stops.skyPoint(of: s, spots: snapshot.spots, studios: snapshot.studios) else { continue }
            let c = GeoCoordinate(latitude: p.latitude, longitude: p.longitude)
            let key = ZoneEstimate.cacheKey(c)
            guard place.zones.zone(at: c) == nil, !calendarZonesTried.contains(key), seen.insert(key).inserted else { continue }
            cells.append((s.day, key, c))
        }
        for cell in cells.sorted(by: { ($0.day, $0.key) < ($1.day, $1.key) }).prefix(6) {
            await learnCalendarZone(at: cell.point)
        }
    }

    private func learnCalendarZone(at c: GeoCoordinate) async {
        let key = ZoneEstimate.cacheKey(c)
        guard place.zones.zone(at: c) == nil, calendarZonesTried.insert(key).inserted else { return }
        guard await place.learnZone(at: c) else { return }
        snapshot.extra["zones"] = .object(place.zones.entries.mapValues { .string($0) })
        persist()
    }

    // MARK: - Ссылка из события

    /// `lightplan://shoot/<id>`: тап по событию в Календаре открывает съёмку. Чужую ссылку или запись, которой
    /// уже нет, не трогаем.
    @discardableResult
    func openShootLink(_ url: URL) -> Bool {
        guard let id = CalendarPlan.shootId(in: url), snapshot.sessions.contains(where: { $0.id == id }) else { return false }
        openCard(id: id)
        return true
    }
}
