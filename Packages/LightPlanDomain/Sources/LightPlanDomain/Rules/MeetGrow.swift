import Foundation
import LightPlanCore

/// Встреча → съёмка: «Назначить съёмку» (веб `#cdGrow`, итерация 28, шаг 7; ответ Алексея 5-1).
/// Порождение, а не переименование: разговор в кафе был и остаётся в календаре, съёмка встаёт на свою
/// дату. Из встречи переезжают жанр, имена, телефоны, организация, место и заметки; встреча запоминает
/// день съёмки (`grewOn`) и её знак (`grewToId`) — по знаку, а не по дате: дату можно поправить.
public enum MeetGrow {

    /// Съёмку можно назначить, пока встреча (или событие) ещё ничем не кончилась. Второй раз — нельзя:
    /// иначе у одной встречи две съёмки, а в календаре — одна пометка.
    public static func canGrow(_ s: Session) -> Bool { s.kind != .shoot && s.grewOn == nil }

    /// Подсказка даты: разговор сегодня, съёмка позже (веб: +30 дней). Условная — фотограф называет свою
    /// (ошибка веба 30: форма показывала её как названную).
    public static let suggestedDays = 30

    public struct Result: Sendable {
        public var meet: Session
        public var shoot: Session
    }

    /// `nil` — назначить нельзя (уже назначена или это не встреча). `start` и `duration` — то, что
    /// подсказал бы свет для нового дня; съёмка встаёт на `day`.
    public static func make(from meet: Session, shootId: String, day: CivilDate, start: Int, duration: Int,
                            modifiedAt: Int64?) -> Result? {
        guard canGrow(meet) else { return nil }
        var s = Session(id: shootId, kind: .shoot, day: day, start: start, end: start + duration,
                        duration: duration, genre: meet.genre)
        s.contact = meet.contact
        // Телефон клиента переезжает вместе с именем: веб его терял (ошибка веба 31).
        s.clientPhone = meet.clientPhone
        s.notes = meet.notes
        s.persons = meet.persons
        s.orderPerson = meet.orderPerson
        s.orderPhone = meet.orderPhone
        s.orgId = meet.orgId
        s.place = meet.place
        s.placeTown = meet.placeTown
        s.placeAddress = meet.placeAddress
        s.latitude = meet.latitude
        s.longitude = meet.longitude
        s.placeIsCity = meet.placeIsCity
        s.studioId = meet.studioId
        s.hallId = meet.hallId
        s.rentFrom = meet.rentFrom
        s.rentTo = meet.rentTo
        // Отправленный опросник едет вместе с остальным, иначе на съёмке кнопка появится снова и клиенту уйдёт второй.
        s.questSent = meet.questSent
        s.fromMeetOn = meet.day
        s.fromMeetId = meet.id
        s.modifiedAt = modifiedAt
        var m = meet
        m.grewOn = day
        m.grewToId = shootId
        m.modifiedAt = modifiedAt
        return Result(meet: m, shoot: s)
    }
}
