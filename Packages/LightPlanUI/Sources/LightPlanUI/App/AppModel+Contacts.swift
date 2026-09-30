import Foundation
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// «Контакты» (веб `#phoneOverlay`, `openPhones`) и встреча → съёмка (`#cdGrow`); итерация 28, шаг 7.
/// Список считается на лету из снимка и не хранится (справка `docs/org_reference.md` § 2).
extension AppModel {

    // MARK: - Список

    /// Свои номера: нынешний ID и прежние — старая симка в чужой карточке остаётся «моей».
    var myKeys: Set<String> {
        PhoneBook.mineKeys(myPreviousIds.map(\.was) + [myAppId], country: telCountry)
    }

    /// Все номера из записей и организаций (веб `phoneIndex`).
    var contacts: [PhoneBook.Group] {
        PhoneBook.index(sessions: snapshot.sessions, orgs: snapshot.orgs, mine: myKeys, country: telCountry)
    }

    /// Строка «Контакты» в настройках: число номеров или «нет».
    var contactsValue: String {
        let n = contacts.count
        return n == 0 ? lexicon.t("card.none") : String(n)
    }

    func openContacts() { org.contactsOpen = true }
    func closeContacts() { org.contactsOpen = false }

    /// Чей номер в этой карточке словом: у пары — слово жанра (невеста, жених), иначе роль. Слова роли, а не
    /// подсказка поля «Имя клиента», как у веба (ошибка 25).
    func contactRole(_ r: PhoneBook.Row) -> String {
        switch r.field {
        case PhoneBook.Field.personOne, PhoneBook.Field.personTwo:
            if case .shoot(let id) = r.card, let g = snapshot.sessions.first(where: { $0.id == id })?.genre {
                let i = r.field == PhoneBook.Field.personOne ? 0 : 1
                if g.persons.indices.contains(i) { return lexicon.t("person." + g.persons[i].rawValue) }
            }
            return lexicon.t("form.person")
        case PhoneBook.Field.client: return lexicon.t("who.client")
        case PhoneBook.Field.org: return lexicon.t("org.one")
        default: return lexicon.t("form.person")
        }
    }

    /// Правая подпись строки: «роль · имя».
    func contactWho(_ r: PhoneBook.Row) -> String {
        [contactRole(r), PhoneBook.firstName(r.name)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Левый заголовок строки: у записи «жанр · день месяц год», у организации её название.
    func contactTitle(_ r: PhoneBook.Row) -> String {
        switch r.card {
        case .org(let id):
            return snapshot.orgs.first { $0.id == id }.map(orgTitle) ?? lexicon.t("org.noName")
        case .shoot(let id):
            guard let s = snapshot.sessions.first(where: { $0.id == id }) else { return "" }
            let facts = PlannerFacts(app: self, dark: true)
            return PlannerWords(lexicon: lexicon, orgs: orgs).typeName(s) + " · " + facts.dates.dMonYear(facts.date(s.day))
        }
    }

    /// Тап по строке: организация — её карточка в списке, запись — карточка записи.
    func openContact(_ r: PhoneBook.Row) {
        closeContacts()
        switch r.card {
        case .org(let id):
            openOrgs()
            openOrgCard(id: id)
        case .shoot(let id):
            closeOrgs()
            openCard(id: id)
        }
    }

    // MARK: - Ушедший номер (веб `telRetire`)

    private var retireStamp: String { ISO8601DateFormatter().string(from: now()) }

    /// Сверка организации при закрытии карточки и уходе в фон: номер, которого больше нет, ложится в её `telLog`.
    /// Правка ставит свежий `mt` — по нему сливаются устройства.
    func commitOrgTels() {
        guard let id = org.cardId, let i = snapshot.orgs.firstIndex(where: { $0.id == id }) else { return }
        let o = snapshot.orgs[i]
        let now = PhoneBook.tels(of: o, country: telCountry)
        let log = PhoneBook.retire(before: org.telSnap, after: now, log: o.telLog, at: retireStamp, country: telCountry)
        org.telSnap = now
        guard log != o.telLog else { return }
        snapshot.orgs[i].telLog = log
        snapshot.orgs[i].modifiedAt = nowMs
        persist()
    }

    /// Новый архив номеров записи при сохранении формы: номер, пропавший из записи, уходит в её `telLog`.
    func retireSessionTels(_ s: Session) -> [TelLogEntry] {
        let prev = snapshot.sessions.first { $0.id == s.id }
        return PhoneBook.retire(before: prev.map { PhoneBook.tels(of: $0, country: telCountry) } ?? [],
                                after: PhoneBook.tels(of: s, country: telCountry),
                                log: prev?.telLog ?? s.telLog, at: retireStamp, country: telCountry)
    }

    // MARK: - Встреча → съёмка

    /// «Назначить съёмку»: порождает съёмку на дату встречи + 30 дней (подсказка), встреча остаётся с пометкой,
    /// форма новой съёмки открывается сразу — дату называет фотограф. Повторное назначение ничего не создаёт.
    func growMeet(_ id: String) {
        guard let m = snapshot.sessions.first(where: { $0.id == id }), MeetGrow.canGrow(m) else { return }
        let when = m.day.adding(days: MeetGrow.suggestedDays)
        let genre = m.genre ?? lastFormGenre
        // Время и длительность — как подсказала бы форма для этого дня.
        let probe = EventForm.new(id: "", day: when, start: nil, fromLight: true, genre: genre, prefs: genrePrefs[genre],
                                  light: formLight(on: when), step: settings.timeStep, home: repeatHome,
                                  genreRate: genreRate(genre), currency: settings.currency)
        guard let r = MeetGrow.make(from: m, shootId: Self.newRecordId(now()), day: when, start: probe.start,
                                    duration: probe.duration, modifiedAt: nowMs),
              let i = snapshot.sessions.firstIndex(where: { $0.id == id }) else { return }
        snapshot.sessions[i] = r.meet
        snapshot.sessions.append(r.shoot)
        persist()
        closeCard()
        planner.goToday(when)
        openForm(editing: r.shoot.id)
    }

    /// Строка у встречи, ставшей съёмкой: «Съёмка назначена на {дата}».
    func grownLine(_ s: Session) -> String? {
        guard s.kind != .shoot, let grew = s.grewOn else { return nil }
        // Дату называет съёмка: фотограф правит её в открывшейся форме, а `grewOn` записан при назначении
        // (ревью GPT к 21fdb78). Съёмки больше нет — остаётся записанный день.
        let d = s.grewToId.flatMap { id in snapshot.sessions.first { $0.id == id }?.day } ?? grew
        let facts = PlannerFacts(app: self, dark: true)
        return lexicon.t("card.grownOn", ["d": facts.dates.dMon(facts.date(d))])
    }
}
