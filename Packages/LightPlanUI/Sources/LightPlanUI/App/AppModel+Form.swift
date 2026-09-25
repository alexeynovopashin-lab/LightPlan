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
        let s = f.session(orgName: org?.name, and: lexicon.t("card.and"), now: now())
        if let i = snapshot.sessions.firstIndex(where: { $0.id == s.id }) {
            snapshot.sessions[i] = s
        } else {
            snapshot.sessions.append(s)
        }
        draftTask?.cancel()
        if f.isNew { draftStore.save(nil) }
        persist()
        form = nil
        formIsDraft = false
        formNote = nil
        return s
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
