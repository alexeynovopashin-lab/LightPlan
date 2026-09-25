import Foundation
import LightPlanCore

/// Окно света дня для подсказки времени новой съёмки (веб `dayWindow`):
/// начало и конец в минутах от полуночи, «плохо» — небо не даёт света.
public struct FormLightWindow: Sendable, Hashable {
    public var start: Double
    public var end: Double
    public var poor: Bool
    public init(start: Double, end: Double, poor: Bool = false) {
        self.start = start
        self.end = end
        self.poor = poor
    }
}

/// Состояние формы записи без вида — чтобы состав, время, черновик и сохранение
/// проверялись тестами (веб: модульные `fDate`, `fMin`, `fDur`, поля `#formOverlay`).
///
/// Конец не хранится: `start + duration`, конец переваливает за полночь, когда
/// сумма больше 1 440 (веб `endDayOff`, `endDate`). Правка изменяет **запись**,
/// а не собирает новую: `base` — исходная запись, и всё, чего в форме нет
/// (`fromMeetId`, `questSent`, `grewToId`…), уходит обратно как было.
public struct EventForm: Equatable, Sendable {
    /// Предел длительности — неделя (веб `MAX_DUR`).
    public static let maxDuration = 10_080
    /// Минимальная длительность: конец раньше начала — описка, не сутки (веб `setEndFrom`, `d < 15`).
    public static let minDuration = 15
    /// Длительности, к которым округляется «по свету» (веб `DURS`).
    public static let roundDurations = [30, 60, 90, 120, 180]

    public var id: String
    public var mode: FormMode
    public var genre: Genre
    public var subGenre: SubGenre?
    public var day: CivilDate
    public var start: Int
    public var duration: Int
    /// Время предложил свет или правило и его можно двигать сменой жанра (веб `fAuto`).
    public var timeIsProposed: Bool
    /// Время взято у света и не округляется (веб `fLight`).
    public var timeFromLight: Bool

    public var contact = ""
    public var clientPhone = ""
    public var breed = ""
    public var orgId: String?
    public var orderPerson = ""
    public var orderPhone = ""
    /// Люди пары: у свадьбы двое, у праздника один, у остальных пусто. Всегда столько же, сколько мест у жанра.
    public var persons: [Person] = []
    public var guests = 0
    public var notes = ""
    public var brief = ""
    public var models = ""

    /// Исходная запись при правке; `nil` — новая.
    public var base: Session?
    public var isNew: Bool { base == nil }

    // MARK: - Открытие

    /// Новая запись (веб `openForm` + `applyGenrePreset`, L30471–30530, L26714–26776).
    /// - Parameters:
    ///   - start: минута, которую назвали кнопка или тап по часу; `nil` — выбрать светом.
    ///   - fromLight: минута — начало окна света и округляться не должна.
    ///   - genre: жанр — последний использованный, форма его не сбрасывает (веб `shootType`).
    public static func new(id: String, day: CivilDate, start: Int?, fromLight: Bool, mode: FormMode = .shoot,
                           genre: Genre, prefs: GenrePrefs? = nil, light: FormLightWindow?, step: Int = 5) -> EventForm {
        var f = EventForm(id: id, mode: mode, genre: genre, day: day,
                          start: start.map { fromLight ? $0 : snap($0, step: step) } ?? 720,
                          duration: 60,
                          timeIsProposed: start == nil || fromLight, timeFromLight: fromLight)
        f.applyPreset(prefs: prefs, light: light)
        return f
    }

    /// Правка существующей записи (веб `fillFormFrom`): ничего не предлагается.
    public static func editing(_ s: Session) -> EventForm {
        var f = EventForm(id: s.id, mode: s.kind == .meet ? .meet : .shoot, genre: s.genre ?? .portrait, day: s.day,
                          start: s.start, duration: s.duration ?? max(s.endMinute - s.start, minDuration),
                          timeIsProposed: false, timeFromLight: false)
        f.subGenre = s.subGenre
        f.contact = s.contact
        f.clientPhone = s.clientPhone
        f.breed = s.breed
        f.orgId = s.orgId
        f.orderPerson = s.orderPerson
        f.orderPhone = s.orderPhone
        f.persons = s.persons
        f.guests = s.guests
        f.notes = s.notes
        f.brief = s.brief
        f.models = s.models
        f.base = s
        f.fitPersons()
        return f
    }

    private init(id: String, mode: FormMode, genre: Genre, day: CivilDate, start: Int, duration: Int,
                 timeIsProposed: Bool, timeFromLight: Bool) {
        self.id = id
        self.mode = mode
        self.genre = genre
        self.day = day
        self.start = start
        self.duration = duration
        self.timeIsProposed = timeIsProposed
        self.timeFromLight = timeFromLight
        fitPersons()
    }

    static func snap(_ m: Int, step: Int) -> Int {
        step > 0 ? Int((Double(m) / Double(step)).rounded()) * step : m
    }

    // MARK: - Жанр и его пресет

    /// Пресет жанра новой записи: длительность и начало (веб `applyGenrePreset`).
    /// Встреча длится час и светом не двигается; событие дня и день без окна
    /// начинаются в полдень; остальное — с начала золотого часа.
    mutating func applyPreset(prefs: GenrePrefs?, light: FormLightWindow?) {
        let sp = GenreProfile(genre).spec
        if mode == .meet {
            duration = 60
        } else if let own = prefs?.duration {           // своя длительность жанра, в том числе «по свету»
            duration = own ?? Self.lightDuration(light)
        } else if let d = sp.duration {
            duration = d
        } else {
            duration = Self.lightDuration(light)
        }
        guard timeIsProposed, mode != .meet else { fitPersons(); return }
        let poor = light?.poor ?? true
        if GenreProfile(genre).hasRoute || poor || light == nil {
            start = 720
            timeFromLight = false
        } else if let w = light {
            start = Int(w.start.rounded())
            timeFromLight = true
            if Double(duration) > w.end - w.start, duration <= 1440 {
                start = ((Int(w.end.rounded()) - duration) % 1440 + 1440) % 1440
            }
        }
        fitPersons()
    }

    static func lightDuration(_ light: FormLightWindow?) -> Int {
        guard let w = light, !w.poor else { return 90 }
        let m = (w.end - w.start).rounded()
        return roundDurations.min { abs(Double($0) - m) < abs(Double($1) - m) } ?? 90
    }

    /// Выбор жанра и уточнения — один вход (веб `pickGenre`): пресет
    /// перестраивается ровно один раз, и только у новой записи.
    public mutating func pick(_ g: Genre, sub: SubGenre? = nil, prefs: GenrePrefs? = nil, light: FormLightWindow? = nil) {
        let changed = g != genre
        genre = g
        subGenre = sub.flatMap { g.subGenres.contains($0) ? $0 : nil }
        if changed {
            if isNew { applyPreset(prefs: prefs, light: light) } else { fitPersons() }
        }
    }

    /// У жанра свои места для людей: лишних не хранится, недостающие пусты.
    mutating func fitPersons() {
        let n = GenreProfile(genre).persons.count
        if persons.count > n { persons = Array(persons.prefix(n)) }
        while persons.count < n { persons.append(Person(name: "", phone: "")) }
    }

    // MARK: - Состав

    public var fields: [FormField] { FormShape.fields(genre: genre, mode: mode) }
    public func shows(_ f: FormField) -> Bool { FormShape.shows(f, genre: genre, mode: mode) }

    // MARK: - Время

    public var endDayOffset: Int { (start + duration) / 1440 }
    public var endMinuteOfDay: Int { ((start + duration) % 1440 + 1440) % 1440 }
    public var endDay: CivilDate { day.adding(days: endDayOffset) }

    /// Начало правят руками: предложенное светом перестаёт быть предложенным, длительность остаётся.
    public mutating func setStart(day d: CivilDate? = nil, minute m: Int? = nil) {
        if let d { day = d }
        if let m {
            start = m
            timeIsProposed = false
            timeFromLight = false
        }
    }

    /// Конец правят руками (веб `setEndFrom`): длительность из дня и минуты конца.
    /// Конец раньше начала — описка, сдвигается на следующие сутки.
    public mutating func setEnd(dayOffset: Int, minuteOfDay: Int) {
        var d = dayOffset * 1440 + minuteOfDay - start
        while d < Self.minDuration { d += 1440 }
        duration = min(d, Self.maxDuration)
    }

    // MARK: - Клиент, организация

    /// Строка клиента (веб `contactLine`): у пары — имена без фамилий через союз,
    /// у заказа — «организация · лицо · телефон», иначе набранная строка.
    public func contactLine(orgName: String?, and: String) -> String {
        let named = filledPersons
        if !named.isEmpty {
            return named.map { Self.firstName($0.name).isEmpty ? $0.phone : Self.firstName($0.name) }
                .filter { !$0.isEmpty }.joined(separator: and)
        }
        if !GenreProfile(genre).groupSpec.order { return contact.trimmingCharacters(in: .whitespaces) }
        return [orgName ?? "", orderPerson.trimmingCharacters(in: .whitespaces), orderPhone.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var filledPersons: [Person] {
        persons.map { Person(name: $0.name.trimmingCharacters(in: .whitespaces), phone: $0.phone.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.name.isEmpty || !$0.phone.isEmpty }
    }

    static func firstName(_ full: String) -> String {
        full.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
    }

    /// Выбрана организация: контактное лицо и телефон подставляются, только если пусты (веб L26319–26326).
    public mutating func choose(_ org: Org?) {
        orgId = org?.id
        guard let org else { return }
        if orderPerson.trimmingCharacters(in: .whitespaces).isEmpty { orderPerson = org.person }
        if orderPhone.trimmingCharacters(in: .whitespaces).isEmpty { orderPhone = org.phone }
    }

    // MARK: - Черновик

    /// Набрано ли руками (веб `draftHasContent`): жанр, день, время, длительность и
    /// место, подставленные самим приложением, черновика не делают.
    public var hasTypedContent: Bool {
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return ![contact, clientPhone, notes, orderPerson, orderPhone, brief, models, breed].allSatisfy(blank)
            || persons.contains { !blank($0.name) || !blank($0.phone) }
            || guests > 0
    }

    // MARK: - Сохранение

    /// Запись из формы (веб `#fSave`, L31753–31814). Валидации нет — пустая форма
    /// сохраняется; правка накладывается на исходную запись и не теряет чужих полей.
    public func session(orgName: String?, and: String, now: Date = Date()) -> Session {
        var s = base ?? Session(id: id, kind: mode == .meet ? .meet : .shoot, day: day, start: start)
        s.kind = mode == .meet ? .meet : (base?.kind ?? .shoot)
        s.day = day
        s.start = start
        s.duration = duration
        s.end = start + duration
        s.genre = genre
        s.subGenre = subGenre
        s.persons = filledPersons
        s.contact = contactLine(orgName: orgName, and: and)
        s.clientPhone = clientPhone.trimmingCharacters(in: .whitespaces)
        s.orgId = orgId
        s.orderPerson = orderPerson.trimmingCharacters(in: .whitespaces)
        s.orderPhone = orderPhone.trimmingCharacters(in: .whitespaces)
        s.breed = breed
        s.guests = max(0, min(guests, 2000))
        s.notes = notes
        s.brief = brief
        s.models = models
        s.modifiedAt = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        return s
    }
}

// MARK: - Черновик на диске

/// Черновик новой записи (веб `lightplan.beta.draft`): пишется через 600 мс после
/// правки, живёт, пока запись не сохранена, и поднимается при следующем открытии.
extension EventForm {
    private struct Draft: Codable {
        var id: String, mode: String, genre: String, sub: String?
        var y: Int, m: Int, d: Int, start: Int, duration: Int, proposed: Bool, light: Bool
        var contact: String, clientPhone: String, breed: String, orgId: String?
        var orderPerson: String, orderPhone: String, persons: [[String]], guests: Int
        var notes: String, brief: String, models: String
    }

    public func draftData() -> Data? {
        guard isNew else { return nil }
        let d = Draft(id: id, mode: mode.rawValue, genre: genre.rawValue, sub: subGenre?.rawValue,
                      y: day.year, m: day.month, d: day.day, start: start, duration: duration,
                      proposed: timeIsProposed, light: timeFromLight,
                      contact: contact, clientPhone: clientPhone, breed: breed, orgId: orgId,
                      orderPerson: orderPerson, orderPhone: orderPhone,
                      persons: persons.map { [$0.name, $0.phone] }, guests: guests,
                      notes: notes, brief: brief, models: models)
        return try? JSONEncoder().encode(d)
    }

    /// Черновик с диска; нечитаемый — `nil`, форма откроется чистой.
    public static func fromDraft(_ data: Data) -> EventForm? {
        guard let d = try? JSONDecoder().decode(Draft.self, from: data),
              let g = Genre(rawValue: d.genre) else { return nil }
        var f = EventForm(id: d.id, mode: FormMode(rawValue: d.mode) ?? .shoot, genre: g,
                          day: CivilDate(year: d.y, month: d.m, day: d.d), start: d.start, duration: d.duration,
                          timeIsProposed: d.proposed, timeFromLight: d.light)
        f.subGenre = d.sub.flatMap(SubGenre.init(rawValue:))
        f.contact = d.contact; f.clientPhone = d.clientPhone; f.breed = d.breed; f.orgId = d.orgId
        f.orderPerson = d.orderPerson; f.orderPhone = d.orderPhone; f.guests = d.guests
        f.notes = d.notes; f.brief = d.brief; f.models = d.models
        f.persons = d.persons.map { Person(name: $0.first ?? "", phone: $0.count > 1 ? $0[1] : "") }
        f.fitPersons()
        return f
    }
}
