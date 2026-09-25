import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Форма записи: пресет жанра, время, клиент, сохранение и черновик.
@Suite struct EventFormTests {
    let day = CivilDate(year: 2026, month: 10, day: 3)
    let golden = FormLightWindow(start: 1178, end: 1230)          // 19:38 – 20:30

    func fresh(_ g: Genre, start: Int? = nil, fromLight: Bool = true, mode: FormMode = .shoot,
               light: FormLightWindow? = nil, prefs: GenrePrefs? = nil) -> EventForm {
        EventForm.new(id: "x1", day: day, start: start, fromLight: fromLight, mode: mode, genre: g,
                      prefs: prefs, light: light ?? golden)
    }

    // MARK: матрица полей — таблица § 1.1 описания веба

    @Test func matrixMatchesWebTable() {
        let expected: [Genre: Set<FormField>] = [
            .portrait: [.payment, .wishes, .references, .delivery, .who, .contactLine, .prepay],
            .animals: [.payment, .wishes, .references, .delivery, .who, .contactLine, .prepay, .breed],
            .wedding: [.payment, .wishes, .references, .delivery, .who, .firstPerson, .secondPerson, .organization, .guests, .prepay],
            .party: [.payment, .wishes, .references, .delivery, .who, .firstPerson, .organization, .guests, .prepay],
            .architecture: [.payment, .wishes, .references, .delivery, .who, .organization, .orderContact, .prepay, .order],
            .product: [.payment, .wishes, .references, .delivery, .who, .organization, .orderContact, .prepay, .order, .models],
            .landscape: [.payment, .wishes, .references, .prepay],
            .street: [.payment, .wishes, .references, .prepay],
        ]
        for (g, want) in expected {
            #expect(Set(fresh(g).fields) == want, "жанр \(g)")
        }
        // Встреча прячет всё про съёмку
        let meet = fresh(.wedding, mode: .meet)
        #expect(Set(meet.fields) == [.who, .firstPerson, .secondPerson, .organization])
        // Двенадцать жанров, у каждого форма считается
        #expect(Genre.allCases.count == 12)
    }

    // MARK: время и длительность

    @Test func presetDurationAndStart() {
        #expect(fresh(.portrait).duration == 60)
        // час (60) длиннее окна (52): окно заканчивает съёмку
        #expect(fresh(.portrait).start == 1170 && fresh(.portrait).timeFromLight)
        let long = FormLightWindow(start: 1100, end: 1230)
        #expect(fresh(.portrait, light: long).start == 1100)
        // событие дня — полдень, светом не двигается
        let w = fresh(.wedding)
        #expect(w.duration == 480 && w.start == 720 && !w.timeFromLight)
        // день без окна — тоже полдень
        let poor = fresh(.portrait, light: FormLightWindow(start: 0, end: 0, poor: true))
        #expect(poor.start == 720)
        // пейзаж: длина окна, округлённая до ряда (52 → 60), по плохому небу — 90
        #expect(fresh(.landscape).duration == 60)
        #expect(fresh(.landscape, light: FormLightWindow(start: 0, end: 0, poor: true)).duration == 90)
        // встреча: час, время названо кнопкой и светом не двигается
        let m = fresh(.portrait, start: 840, fromLight: false, mode: .meet)
        #expect(m.duration == 60 && m.start == 840)
        // названное руками время округляется к шагу, свет — нет
        #expect(EventForm.new(id: "a", day: day, start: 843, fromLight: false, genre: .portrait, light: nil, step: 5).start == 845)
    }

    @Test func longerThanLightEndsAtSunset() {
        // 180 минут длиннее окна: начало уезжает назад, чтобы окно закончило съёмку
        let f = fresh(.report)
        #expect(f.duration == 180 && f.start == 1230 - 180)
    }

    @Test func ownGenreDurationWinsAndAutoLightIsRemembered() {
        let f = fresh(.portrait, prefs: GenrePrefs(duration: .some(45)))
        #expect(f.duration == 45)
        let byLight = fresh(.portrait, prefs: GenrePrefs(duration: .some(nil)))
        #expect(byLight.duration == 60)
    }

    @Test func endIsDerivedAndClamped() {
        var f = fresh(.portrait, start: 1320, fromLight: false)
        f.duration = 180
        #expect(f.endDayOffset == 1 && f.endMinuteOfDay == 60)
        f.setEnd(dayOffset: 0, minuteOfDay: 1300)          // раньше начала — следующие сутки
        #expect(f.duration == 1300 + 1440 - 1320)
        f.setEnd(dayOffset: 30, minuteOfDay: 0)
        #expect(f.duration == EventForm.maxDuration)
        f.setStart(minute: 600)
        #expect(!f.timeIsProposed && !f.timeFromLight)
    }

    @Test func genreSwitchRebuildsPresetOnlyForNewRecords() {
        var f = fresh(.portrait)
        f.pick(.wedding)
        #expect(f.duration == 480 && f.persons.count == 2 && f.start == 720)
        f.pick(.portrait)
        #expect(f.persons.isEmpty)
        var e = EventForm.editing(f.session(orgName: nil, and: " и "))
        e.duration = 45
        e.pick(.wedding)
        #expect(e.duration == 45, "правка не переставляет длительность")
    }

    // MARK: клиент

    @Test func contactLine() {
        var f = fresh(.wedding)
        f.persons[0] = Person(name: "Елена Иванова", phone: "")
        f.persons[1] = Person(name: "Алексей Петров", phone: "+7 916 123-45-67")
        #expect(f.contactLine(orgName: nil, and: " и ") == "Елена и Алексей")
        var g = fresh(.report)
        g.orderPerson = "Мария"; g.orderPhone = "8 900 000-00-00"
        #expect(g.contactLine(orgName: "Вега", and: " и ") == "Вега · Мария · 8 900 000-00-00")
        var h = fresh(.portrait)
        h.contact = "  Ольга "
        #expect(h.contactLine(orgName: nil, and: " и ") == "Ольга")
    }

    @Test func chosenOrgFillsOnlyEmptyContact() {
        var org = Org(id: "o1", name: "Вега"); org.person = "Мария"; org.phone = "8 900 000-00-00"
        var f = fresh(.report)
        f.choose(org)
        #expect(f.orderPerson == "Мария" && f.orderPhone == "8 900 000-00-00")
        f.orderPerson = "Иван"
        f.choose(org)
        #expect(f.orderPerson == "Иван")
    }

    // MARK: сохранение и правка

    @Test func emptyFormSaves() {
        let s = fresh(.portrait).session(orgName: nil, and: " и ")
        #expect(s.id == "x1" && s.kind == .shoot && s.genre == .portrait && s.contact.isEmpty)
        #expect(s.end == s.start + 60)
    }

    @Test func editKeepsFieldsTheFormDoesNotKnow() {
        var base = Session(id: "r1", day: day, start: 600, duration: 90, genre: .portrait)
        base.questSent = Date(timeIntervalSince1970: 1_780_000_000)
        base.fromMeetId = "m9"
        base.grewToId = "s7"
        base.rate = 3000
        base.route = [RoutePoint(start: 600, name: "Сбор")]
        var f = EventForm.editing(base)
        f.contact = "Ольга"
        f.notes = "рано"
        let s = f.session(orgName: nil, and: " и ")
        #expect(s.contact == "Ольга" && s.notes == "рано")
        #expect(s.questSent == base.questSent && s.fromMeetId == "m9" && s.grewToId == "s7")
        #expect(s.rate == 3000 && s.route == base.route)
    }

    @Test func savedRecordReopensAsTheSameForm() {
        var f = fresh(.wedding)
        f.persons[0] = Person(name: "Елена", phone: "+7 916 000-00-00")
        f.guests = 80; f.notes = "сборы в 9"
        f.orgId = "o1"
        let s = f.session(orgName: "Организатор", and: " и ")
        let back = EventForm.editing(s)
        #expect(back.persons == f.persons.map { $0 } && back.guests == 80 && back.notes == "сборы в 9" && back.orgId == "o1")
        #expect(back.start == f.start && back.duration == f.duration && back.genre == .wedding)
    }

    // MARK: черновик

    @Test func draftIsOnlyWhatWasTyped() {
        var f = fresh(.wedding)
        #expect(!f.hasTypedContent, "жанр, время и засев не считаются")
        f.persons[0].name = "Е"
        #expect(f.hasTypedContent)
        var g = fresh(.portrait); g.guests = 0; g.notes = "  "
        #expect(!g.hasTypedContent)
    }

    @Test func draftSurvivesRestart() throws {
        var f = fresh(.wedding)
        f.persons[1] = Person(name: "Алексей", phone: "8 900 111-22-33")
        f.notes = "рано"; f.guests = 60; f.orgId = "o1"; f.subGenre = .engagement
        f.setStart(minute: 555)
        let data = try #require(f.draftData())
        let back = try #require(EventForm.fromDraft(data))
        #expect(back == f)
        #expect(EventForm.editing(back.session(orgName: nil, and: " и ")).draftData() == nil, "правка черновика не имеет")
        #expect(EventForm.fromDraft(Data("{}".utf8)) == nil)
    }
}
