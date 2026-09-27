import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Сохранение без потерь (итерация 24, шаг 4а): запись → форма → сохранение →
/// та же запись, поле в поле. Веб здесь терял поля — форма собирала запись
/// заново, и то, чего в ней нет, переносили руками (веб L16424).
@Suite struct FormRoundTripTests {
    let day = CivilDate(year: 2026, month: 10, day: 3)
    let lumen: Studio = {
        var s = Studio(id: "st1", name: "Люмен", latitude: 56.47, longitude: 84.97)
        s.address = "Нахимова, 8"; s.town = "Томск"
        s.halls = [Studio.Hall(id: "h1", name: "Белый")]
        return s
    }()

    /// Свадьба, у которой заполнено всё, что умеет хранить запись.
    func full() -> Session {
        var s = Session(id: "r1", kind: .shoot, day: day, start: 660, end: 1260, duration: 600, genre: .wedding)
        s.subGenre = .registry
        s.contact = "Анна и Илья"
        s.clientPhone = "+7 913 000-00-01"
        s.notes = "сборы в 9"
        s.orgId = "o1"
        s.orderPerson = "Мария"
        s.orderPhone = "+7 913 000-00-02"
        s.persons = [Person(name: "Анна", phone: "+7 913 000-00-01"), Person(name: "Илья", phone: "+7 913 000-00-03")]
        s.place = "Люмен, зал Белый"
        s.placeTown = "Томск"
        s.placeAddress = "Нахимова, 8"
        s.latitude = 56.47
        s.longitude = 84.97
        s.placeIsCity = true
        s.studioId = "st1"
        s.hallId = "h1"
        s.rentFrom = 660
        s.rentTo = 780
        s.bookingRef = "bk-42"
        s.rentRequest = RentRequest(id: "rq1", status: .requested, newEnd: "13:30")
        s.route = [RoutePoint(start: 660, end: 780, name: "Сборы", placeText: "Люмен, зал Белый", studioId: "st1", hallId: "h1"),
                   RoutePoint(start: 840, name: "Загс", placeText: "Дворец бракосочетаний")]
        s.wishes = [.sunset, .clear]
        s.wishWarning = WishWarning(title: "Закат под вопросом", message: "облачно к вечеру")
        s.deadline = .days(30)
        s.delivered = true
        s.deliveredAt = Date(timeIntervalSince1970: 1_790_000_000)
        s.pay = .pack
        s.rate = 60000
        s.units = 1
        s.expense = 5000
        s.prepay = 15000
        s.currency = .rub
        s.guests = 80
        s.trip = true
        s.tripManual = true
        s.tripPlace = "Томск"
        s.brief = "репортаж и прогулка"
        s.models = "Катя +7 913 000-00-04"
        s.breed = ""
        s.docs = [Attachment(source: .doc, path: "/LightPlan/r1/dogovor.pdf", name: "dogovor.pdf", size: 120_000, kind: .contract),
                  Attachment(source: .link, name: "Смета", url: "https://example.org/smeta", kind: .invoice)]
        s.gear = ["Вспышка", "85 мм"]
        s.playlist = "Вечер"
        s.questSent = Date(timeIntervalSince1970: 1_780_000_000)
        s.questOff = true
        s.fromMeetOn = CivilDate(year: 2026, month: 9, day: 1)
        s.fromMeetId = "m9"
        s.grewOn = CivilDate(year: 2026, month: 9, day: 2)
        s.grewToId = "s7"
        s.dayMoved = DayMoved(start: 600, end: 1200, line: "сдвинуто на час")
        s.calendar = .apple
        s.telLog = [TelLogEntry(field: "clientTel", phone: "+7 913 999-99-99", name: "Анна", retiredAt: "2026-09-10")]
        s.repeatInfo = nil
        s.doneAt = 1250
        s.icsSignature = "sig"
        s.icsImportedAt = 1_780_000_000_000
        s.modifiedAt = 1_780_000_000_000
        s.extra = ["future": .string("поле веба новее этой сборки")]
        return s
    }

    /// Поля, которые разошлись: имя и оба значения (для понятного отказа).
    func diff(_ a: Session, _ b: Session) -> [String] {
        zip(Mirror(reflecting: a).children, Mirror(reflecting: b).children).compactMap { x, y in
            String(describing: x.value) == String(describing: y.value) ? nil : "\(x.label ?? "?"): \(x.value) → \(y.value)"
        }
    }

    @Test func untouchedEditIsTheSameRecord() {
        let s = full()
        let f = EventForm.editing(s)
        var back = f.session(orgName: nil, and: " и ", studios: [lumen], warning: s.wishWarning,
                             now: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(back.modifiedAt == 1_790_000_000_000, "правка ставит свою метку")
        back.modifiedAt = s.modifiedAt
        #expect(diff(s, back) == [], "поле в поле")
    }

    @Test func unknownSnapshotKeysSurviveFormAndDisk() throws {
        var s = full()
        s.extra = [:]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        json["future"] = ["a": 1, "b": ["x"]]
        let read = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(read.extra["future"] != nil, "незнакомый ключ прочитан")
        let saved = EventForm.editing(read).session(orgName: nil, and: " и ", studios: [lumen], warning: read.wishWarning)
        let out = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        #expect((out["future"] as? [String: Any])?["a"] as? Int == 1, "и записан обратно")
    }

    @Test func fixtureFillsEveryField() {
        // Новое поле записи, забытое в `full()`, этот тест назовёт: круговой
        // тест выше иначе проверял бы его пустым.
        let bare = Session(id: "r1", day: day, start: 660)
        let same = zip(Mirror(reflecting: full()).children, Mirror(reflecting: bare).children)
            .filter { String(describing: $0.value) == String(describing: $1.value) }.compactMap(\.0.label)
        #expect(Set(same) == ["id", "kind", "day", "start", "breed", "repeatInfo"],
                "повтор — в тестах повтора, порода — не у свадьбы")
    }
}
