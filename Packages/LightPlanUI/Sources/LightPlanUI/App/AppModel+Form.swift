import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Где лежит черновик формы между запусками. Веб держит его в `localStorage`
/// (`lightplan.beta.draft`), вне снимка: черновик не уходит в выгрузку и в облако.
/// Здесь — `UserDefaults`, тем же местом; тестам подставляется своё.
public protocol DraftStoring: Sendable {
    func load() -> Data?
    func save(_ data: Data?)
}

public struct DefaultsDraftStore: DraftStoring, @unchecked Sendable {
    let defaults: UserDefaults
    let key: String
    public init(defaults: UserDefaults = .standard, key: String = "lightplan.native.draft") {
        self.defaults = defaults
        self.key = key
    }
    public func load() -> Data? { defaults.data(forKey: key) }
    public func save(_ data: Data?) {
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

/// Черновик в памяти — для сценариев снимков: на диск они не пишут.
final class MemoryDraftStore: DraftStoring, @unchecked Sendable {
    private var data: Data?
    func load() -> Data? { data }
    func save(_ data: Data?) { self.data = data }
}

/// Форма записи (итерация 23): открыть, править, сохранить, черновик. Правила —
/// в `EventForm` (Domain); здесь — то, что связано с приложением: часы, место,
/// снимок, диск.
extension AppModel {

    // MARK: - Открытие

    /// Окно света дня в месте приложения — подсказка времени (веб `dayWindow`): вечернее,
    /// золотой час и до конца синего; в тумане — утреннее; «плохо» — окна нет. Без окна
    /// (полярная ночь и день) — `nil`.
    func formLight(on day: CivilDate) -> FormLightWindow? {
        let sun = SolarDay(date: day, place: place.place)
        switch light.weather.day(for: day).quality {
        case .poor:
            return FormLightWindow(start: 0, end: 0, poor: true)
        case .fog:
            guard let a = sun.blueA, let b = sun.goldenA, b > a else { return nil }
            return FormLightWindow(start: a, end: b, dawn: true)
        default:
            guard let a = sun.goldenB, let b = sun.blueB, b > a else { return nil }
            return FormLightWindow(start: a, end: b)
        }
    }

    /// Новая съёмка или встреча. Черновик, если он есть, поднимается **поверх**
    /// того, что просит кнопка: день и время черновика главнее (веб L30532–30543).
    public func openForm(day: CivilDate? = nil, start: Int? = nil, fromLight: Bool = true, mode: FormMode = .shoot) {
        let d = day ?? planner.selected
        if let data = draftStore.load(), let draft = EventForm.fromDraft(data), draft.hasTypedContent {
            formIsDraft = true
            form = draft
            return
        }
        formIsDraft = false
        let genre = lastFormGenre
        form = EventForm.new(id: Self.newRecordId(now()), day: d, start: start, fromLight: fromLight, mode: mode,
                             genre: genre, prefs: genrePrefs[genre], light: formLight(on: d), step: settings.timeStep)
    }

    /// Правка существующей записи: черновика у правки нет.
    public func openForm(editing id: String) {
        guard let s = snapshot.sessions.first(where: { $0.id == id }) else { return }
        formIsDraft = false
        form = EventForm.editing(s)
    }

    /// Жанры, включённые в «Моих жанрах». Пустой список снимка — включены все (веб: «изначально включены все»).
    public var enabledGenres: [Genre] {
        let on = snapshot.genres
        return on.isEmpty ? Genre.allCases : Genre.allCases.filter(on.contains)
    }

    /// Выбор жанра в форме: пресет пересобирается, последний жанр запоминается.
    public func pickFormGenre(_ g: Genre, sub: SubGenre? = nil) {
        guard var f = form else { return }
        f.pick(g, sub: sub, prefs: genrePrefs[g], light: formLight(on: f.day))
        lastFormGenre = g
        form = f
        formChanged()
    }

    /// Конец правят руками: длительность жанра запоминается сразу, до сохранения
    /// (веб `setEndFrom` → `rememberGenre("dur")`).
    public func setFormEnd(dayOffset: Int, minuteOfDay: Int) {
        guard var f = form else { return }
        f.setEnd(dayOffset: dayOffset, minuteOfDay: minuteOfDay)
        var prefs = snapshot.genrePrefs[f.genre] ?? GenrePrefs()
        prefs.duration = .some(f.duration)
        snapshot.genrePrefs[f.genre] = prefs
        form = f
        formChanged()
    }

    // MARK: - Черновик

    /// Форма правлена: черновик пишется, но не чаще, чем раз в 600 мс (веб `scheduleDraftSave`).
    public func formChanged() {
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.writeDraft()
        }
    }

    /// Черновик на диск сразу (веб `draftSaveNow`, крестик и уход в фон): пока
    /// руками ничего не набрано, черновика нет, а старый стирается.
    public func writeDraft() {
        draftTask?.cancel()
        guard let f = form, f.isNew else { return }
        draftStore.save(f.hasTypedContent ? f.draftData() : nil)
    }

    /// «Начать заново»: черновик стирается, форма открывается чистой на том же дне.
    public func resetDraft() {
        draftTask?.cancel()
        let day = form?.day
        draftStore.save(nil)
        formIsDraft = false
        form = nil
        openForm(day: day)
        formNote = lexicon.t("form.draftGone")
    }

    // MARK: - Закрытие и сохранение

    /// Крестик: правка не сохраняется, у новой записи набранное остаётся черновиком.
    public func closeForm() {
        writeDraft()
        form = nil
        formIsDraft = false
        formNote = nil
    }

    /// Галочка (веб `#fSave`): формы без обязательных полей — пустая тоже сохраняется.
    @discardableResult
    public func saveForm() -> Session? {
        guard let f = form else { return nil }
        let org = f.orgId.flatMap { id in snapshot.orgs.first { $0.id == id } }
        var s = f.session(orgName: org?.name, and: lexicon.t("card.and"), now: now())
        // Повтор: копии заводятся один раз, здесь, и дальше живут сами (веб `repMake`).
        var copies: [Session] = []
        if f.repeatOn, let rule = f.repeatRule {
            let clock = now()
            copies = Repeats.make(&s, rule: rule, count: f.repeatCount, blocks: f.repeatBlocks, home: repeatHome,
                                  group: Self.newRecordId(clock)) { Self.newRecordId(clock) }
        }
        if let i = snapshot.sessions.firstIndex(where: { $0.id == s.id }) {
            snapshot.sessions[i] = s
        } else {
            snapshot.sessions.append(s)
        }
        snapshot.sessions.append(contentsOf: copies)
        draftTask?.cancel()
        if f.isNew { draftStore.save(nil) }
        persist()
        form = nil
        formIsDraft = false
        formNote = nil
        return s
    }

    /// «Удалить» внизу формы — только у сохранённой записи (веб `#fDelete`): через
    /// корзину, как из ленты, с полосой «Вернуть»; форма закрывается.
    public func deleteFormRecord() {
        guard let f = form, !f.isNew else { return }
        draftTask?.cancel()
        form = nil
        formIsDraft = false
        formNote = nil
        trashSession(id: f.id)
    }

    // MARK: - Повтор

    /// Место приложения для копий без «Повторять место и маршрут» (веб `myCity()`, `LAT`, `LON`).
    var repeatHome: RepeatHome {
        let c = place.coordinate
        return RepeatHome(town: place.name?.city ?? "", latitude: c.latitude, longitude: c.longitude)
    }

    public func setFormRepeat(_ rule: RepeatRule?) { editForm { $0.repeatRule = rule } }
    public func setFormRepeatCount(_ n: Int) {
        editForm { $0.repeatCount = min(max(n, Repeats.minCount), Repeats.maxCount) }
    }
    public func setFormRepeat(block b: RepeatBlock, on: Bool) { editForm { $0.setRepeat(block: b, on: on) } }

    private func editForm(_ change: (inout EventForm) -> Void) {
        guard var f = form else { return }
        change(&f)
        form = f
        formChanged()
    }

    /// Строка карточки из группы (веб `repInfo`): «Каждую неделю · 3 из 7» по
    /// живым карточкам, по порядку дат. `nil` — запись не в группе.
    public func formRepeatInfo(_ f: EventForm) -> String? {
        guard f.mode == .shoot, let rep = f.base?.repeatInfo else { return nil }
        let rule = lexicon.t("rep." + rep.rule.rawValue)
        guard let at = Repeats.place(of: f.id, group: rep.group, in: snapshot.sessions) else { return rule }
        return lexicon.t("rep.info", ["rule": rule, "i": String(at.index), "n": String(at.count)])
    }

    /// Итог до сохранения (веб `renderRepSum`): сколько карточек, до какой даты и
    /// какие копии ложатся на занятое. Копии на занятые даты всё равно создаются —
    /// решает фотограф. Наложения — у будущих копий: место берётся таким, каким
    /// его выставит копия по переключателю «Повторять место и маршрут».
    public func formRepeatSummary(_ f: EventForm) -> String? {
        let dates = f.repeatDates
        guard dates.count > 0 else { return nil }
        let dt = DateText(language: language)
        let year = today.year
        func dm(_ d: CivilDate) -> String {
            var c = DateComponents()
            (c.year, c.month, c.day, c.hour) = (d.year, d.month, d.day, 12)
            let at = Calendar(identifier: .gregorian).date(from: c) ?? Date()
            return d.year == year ? dt.dMon(at) : dt.dMonYear(at)
        }
        var text = lexicon.t("rep.sum", ["n": lexicon.count("unit.shoot", dates.count), "k": String(dates.count),
                                         "last": dm(dates[dates.count - 1])])
        let own = f.repeatBlocks.contains(.route)
        let home = repeatHome
        let probe = f.session(orgName: nil, and: "", now: now())
        let point = own ? GeoPoint(probe.latitude, probe.longitude) : GeoPoint(home.latitude, home.longitude)
        var homeProbe = probe
        (homeProbe.place, homeProbe.placeTown) = ("", home.town)
        let placeKey = own ? probe.placeKey : homeProbe.placeKey
        let wishes = f.repeatBlocks.contains(.wish) ? probe.wishes : []
        let skip = snapshot.sessions.firstIndex { $0.id == f.id }
        let busy = Set(snapshot.sessions.map(\.day))
        let words = PlannerWords(lexicon: lexicon, orgs: orgs)
        var hits: [String] = []
        for d in dates.dropFirst() where busy.contains(d) || snapshot.blocks.contains(where: { $0.covers(d) }) {
            let c = ClashCandidate(day: d, start: f.start, end: f.start + f.duration, placeKey: placeKey, skipIndex: skip,
                                   wishes: wishes, point: point, trip: own && probe.trip, tripOff: own && probe.tripManual && !probe.trip)
            guard let first = Overlaps.clashes(for: c, sessions: snapshot.sessions, blocks: snapshot.blocks,
                                               context: clashContext).first else { continue }
            let name: String
            switch first.subject {
            case .block(let i):
                let b = snapshot.blocks[i]
                name = b.note.isEmpty ? lexicon.t("blkKind." + b.kind.rawValue) : b.note
            case .session(let i):
                let o = snapshot.sessions[i]
                name = o.contact.isEmpty ? words.typeName(o) : o.contact
            }
            hits.append(dm(d) + " — " + name)
        }
        if !hits.isEmpty {
            var list = hits.prefix(3).joined(separator: "; ")
            if hits.count > 3 { list += " " + lexicon.t("rep.more", ["n": String(hits.count - 3)]) }
            text += " " + lexicon.t("rep.clash", ["n": String(hits.count), "list": list])
        }
        return text
    }

    /// Что проверка наложений берёт снаружи. Дорогу приложение пока не спрашивает —
    /// «не знаем», и работает порог фотографа, как у веба до ответа сети.
    var clashContext: ClashContext {
        let offset = Double(TimeZone(identifier: place.zone.identifier)?.secondsFromGMT(for: now()) ?? 0) / 3600
        return ClashContext(zones: place.zones, appOffsetHours: offset, travel: { _, _ in .unavailable },
                            travelThreshold: settings.travelMin, eventsLayer: eventsLayer)
    }

    // MARK: - Мои жанры

    /// Тап по плитке листа включает и выключает жанр; последний не выключается
    /// (веб `renderGenreList`). Пустой список снимка значит «включены все».
    public func toggleGenre(_ g: Genre) {
        var on = enabledGenres
        if let i = on.firstIndex(of: g) {
            guard on.count > 1 else { return }
            on.remove(at: i)
        } else {
            on.append(g)
        }
        snapshot.genres = Genre.allCases.filter(on.contains)
        persist()
        // Жанр формы выключили — форма перестраивается под первый включённый;
        // сохранённой записи время не переписываем (веб `renderGenres`, `swapped`).
        if var f = form, !enabledGenres.contains(f.genre), let first = enabledGenres.first {
            f.pick(first, prefs: genrePrefs[first], light: formLight(on: f.day))
            form = f
            formChanged()
        }
    }

    /// Длительность, которую жанр подставляет новой съёмке; `nil` — «по свету» (веб `rememberGenre("dur")`).
    public func setGenreDuration(_ g: Genre, _ minutes: Int?) {
        var p = snapshot.genrePrefs[g] ?? GenrePrefs()
        p.duration = .some(minutes)
        snapshot.genrePrefs[g] = p
        persist()
    }

    /// Свой срок сдачи жанра в днях (веб `rememberGenre("delvDays")`).
    public func setGenreDeliveryDays(_ g: Genre, _ days: Int) {
        var p = snapshot.genrePrefs[g] ?? GenrePrefs()
        p.deliveryDays = days
        snapshot.genrePrefs[g] = p
        persist()
    }

    /// Длительность жанра сейчас (веб `genreDur`): своя, иначе заводская; `nil` — по свету.
    public func genreDuration(_ g: Genre) -> Int? {
        if let own = snapshot.genrePrefs[g]?.duration { return own }
        return GenreProfile(g).spec.duration
    }

    /// Срок сдачи жанра сейчас (веб `genreDeadline`).
    public func genreDeliveryDays(_ g: Genre) -> Int {
        snapshot.genrePrefs[g]?.deliveryDays ?? g.deliveryDays
    }

    // MARK: - Клиент, организация, телефон

    /// Страна номера фотографа (веб `telCountry`): записанная, иначе по поясу телефона и языку.
    public var telCountry: TelCountry {
        if case .string(let iso)? = snapshot.extra["telCountry"], let c = TelCountry.of(iso) { return c }
        let region = Locale(identifier: language).region?.identifier
        return TelCountry.guess(zoneId: TimeZone.current.identifier, region: region)
    }

    public func setFormOrg(_ org: Org?) {
        guard var f = form else { return }
        f.choose(org)
        form = f
        formChanged()
    }

    /// Новая организация из формы — только имя; карточка организации — итерация 28.
    public func addOrg(name: String) -> Org {
        let o = Org(id: Self.newRecordId(now()), name: name)
        snapshot.orgs.append(o)
        persist()
        return o
    }

    static func newRecordId(_ now: Date) -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String((0..<10).map { _ in chars.randomElement()! })
    }
}
