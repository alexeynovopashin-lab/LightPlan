import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Съёмки в Календаре iPhone (шаг 30.1–3, `docs/14`).
///
/// Одно направление: правда в Light Plan, Календарь её показывает. Расписание — функция данных, как у студийного
/// часа: после правки записи, при запуске и при возврате в приложение календарь приводится к списку событий
/// (`CalendarPlan`). Отказ в праве ничего не ломает: зеркало молчит, остальное работает как раньше.
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
        attachCalendar(store: EventKitCalendarStore(), memory: DeviceCalendarMemory())
        #endif
    }

    /// Подставки (тесты, снимки): календарь и память подаются снаружи.
    func attachCalendar(store: any CalendarStoring, memory: any CalendarMirrorMemory) {
        calendarStore = store
        calendarMirror = CalendarMirror(store: store, memory: memory)
        calendarWanted = memory.record.wanted
        syncCalendarMirror(force: true)
    }

    // MARK: - Названия и события

    /// Название события: жанр и клиент, жанр первым — в недельной сетке видно первые слова («Свадьба · Ирина»).
    func calendarTitle(of s: Session) -> String {
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
        let titles = Dictionary(snapshot.sessions.map { ($0.id, calendarTitle(of: $0)) }, uniquingKeysWith: { a, _ in a })
        let blockTitles = Dictionary(snapshot.blocks.map { ($0.id, calendarTitle(of: $0)) }, uniquingKeysWith: { a, _ in a })
        let ctx = CalendarPlan.Context(
            studios: snapshot.studios, spots: snapshot.spots, zones: place.zones, homeZone: place.zone,
            title: { titles[$0.id] ?? "" }, blockTitle: { blockTitles[$0.id] ?? "" })
        return CalendarPlan.drafts(sessions: snapshot.sessions, blocks: snapshot.blocks, context: ctx)
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
        guard let mirror = calendarMirror, id != calendarSourceId else { return }
        enqueueCalendar { app in
            let out = await mirror.moveCalendar(to: id)
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
        calendarSourceTitle = cal?.sourceTitle
    }

    // MARK: - Проход

    /// Привести календарь к данным. Правки идут пачками — запрос откладывается на треть секунды и склеивается;
    /// `force` (запуск, возврат в приложение, смена тумблера) сверяет даже при тех же данных: событие могли удалить
    /// в Календаре, а право — выдать или отнять в настройках iPhone. По таймеру — никогда.
    func syncCalendarMirror(force: Bool = false) {
        guard calendarMirror != nil else { return }
        calendarGen += 1
        if force { calendarForce = true }
        let gen = calendarGen
        enqueueCalendar { app in
            // Позже пришёл другой запрос — он и выполнит работу, унаследовав «принудительно». Проверка до паузы:
            // очередь стоит друг за другом, и пачка правок без неё ждала бы по трети секунды на каждую.
            guard gen == app.calendarGen else { return }
            if !force { try? await Task.sleep(for: .milliseconds(300)) }
            guard gen == app.calendarGen else { return }
            let force = app.calendarForce
            app.calendarForce = false
            await app.runCalendarSync(force: force)
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
        let drafts = calendarDrafts()
        if !force, calendarApplied == drafts { return }
        switch await mirror.sync(drafts) {
        case .synced(let report):
            calendarApplied = report.failed == 0 ? drafts : nil
            calendarFailed = false
        case .noAccess:
            calendarApplied = nil
        case .calendarGone:
            calendarApplied = nil
            calendarGoneAsk = true
        case .failed:
            calendarApplied = nil
            calendarFailed = true
        }
        await refreshCalendarFacts()
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
