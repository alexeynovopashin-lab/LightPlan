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

    public struct Result: Sendable {
        public var meet: Session
        public var shoot: Session
    }

    /// Съёмка из данных встречи, ещё не названная датой: переезжают жанр, имена, телефоны, организация, место и заметки.
    /// `day` — якорь для подсказок света (день встречи), не дата съёмки: её называет фотограф в форме. Встречу
    /// не трогает — она остаётся встречей, пока съёмка не сохранена (`link`).
    public static func draft(from meet: Session, shootId: String, day: CivilDate, start: Int, duration: Int) -> Session {
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
        return s
    }

    /// Съёмка сохранена — встреча получает пометку: день съёмки и её знак (по знаку, а не по дате: дату можно поправить).
    public static func link(_ meet: Session, to shoot: Session, modifiedAt: Int64?) -> Session {
        var m = meet
        m.grewOn = shoot.day
        m.grewToId = shoot.id
        m.modifiedAt = modifiedAt
        return m
    }

    /// `nil` — назначить нельзя (уже назначена или это не встреча). Целиком, без формы: съёмка встаёт на `day`.
    public static func make(from meet: Session, shootId: String, day: CivilDate, start: Int, duration: Int,
                            modifiedAt: Int64?) -> Result? {
        guard canGrow(meet) else { return nil }
        var s = draft(from: meet, shootId: shootId, day: day, start: start, duration: duration)
        s.modifiedAt = modifiedAt
        return Result(meet: link(meet, to: s, modifiedAt: modifiedAt), shoot: s)
    }
}
