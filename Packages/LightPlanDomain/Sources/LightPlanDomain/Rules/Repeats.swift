import Foundation
import LightPlanCore

/// Блок записи, который повтор переносит в копии или оставляет пустым
/// (веб `REP_BLOCKS`, строки `.rep-blk` формы). По умолчанию переносится всё,
/// кроме заметок: заметка обычно про один день.
public enum RepeatBlock: String, CaseIterable, Sendable, Codable {
    case client, route, kit, refs, playlist, notes, brief, docs, wish, delivery

    public static let defaults: Set<RepeatBlock> = Set(allCases).subtracting([.notes])
}

/// Место приложения — им заполняется копия с выключенным «Повторять место и
/// маршрут» (веб `myCity()`, `LAT`, `LON`).
public struct RepeatHome: Sendable, Hashable {
    public var town: String
    public var latitude: Double
    public var longitude: Double
    public init(town: String, latitude: Double, longitude: Double) {
        self.town = town
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Повтор съёмки (веб «Повтор съёмки», L30845–31220). Копии заводятся один раз,
/// при сохранении формы, и дальше живут сами по себе: главной и зависимой
/// карточки нет, общее у них только ключ группы.
public enum Repeats {
    /// Барабан «Сколько раз»: у новой группы с двух — одна карточка не повтор (веб `REP_MIN`, `REP_MAX`, `REP_DEF_N`).
    public static let minCount = 2
    public static let maxCount = 100
    public static let defaultCount = 4

    /// Даты группы, первая — сама съёмка (веб `repDates`). Месяц без такого
    /// числа пропускается, а не сдвигается на последний день: 31 января → 31
    /// марта → 31 мая; так же год от 29 февраля. «Сколько раз» считает
    /// созданные карточки, пропуски в счёт не идут.
    public static func dates(from d0: CivilDate, rule: RepeatRule, count n: Int) -> [CivilDate] {
        var out = [d0]
        var k = 1
        // Предел — страховка от вечного цикла: 29 февраля бывает реже раза в четыре года.
        while out.count < n && k <= n * 5 {
            switch rule {
            case .day: out.append(d0.adding(days: k))
            case .week: out.append(d0.adding(days: 7 * k))
            case .week2: out.append(d0.adding(days: 14 * k))
            case .month, .year:
                let m0 = d0.year * 12 + (d0.month - 1) + (rule == .month ? k : 12 * k)
                let y = m0 >= 0 ? m0 / 12 : (m0 - 11) / 12
                let m = m0 - y * 12 + 1
                if d0.day <= daysIn(year: y, month: m) { out.append(CivilDate(year: y, month: m, day: d0.day)) }
            }
            k += 1
        }
        return out
    }

    static func daysIn(year y: Int, month m: Int) -> Int {
        switch m {
        case 2: return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Живые карточки группы по порядку дат (веб `repMates`). Одна дата и
    /// минута — по номеру в группе, а не по месту в списке: слияние и возврат
    /// из корзины его переставляют.
    public static func mates(of group: String, in sessions: [Session]) -> [Session] {
        sessions.filter { $0.repeatInfo?.group == group }.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.repeatInfo!.index < $1.repeatInfo!.index
        }
    }

    /// Живой номер карточки в группе и сколько их (веб `repInfo`): удалённая
    /// выпадает из счёта, номера за ней сдвигаются. Записанные при создании
    /// номер и счёт не читаются. `nil` — карточки в группе нет.
    public static func place(of id: String, group: String, in sessions: [Session]) -> (index: Int, count: Int)? {
        let m = mates(of: group, in: sessions)
        guard let i = m.firstIndex(where: { $0.id == id }) else { return nil }
        return (i + 1, m.count)
    }

    /// Копия записи на другой день (веб `repCopy`). Переносится всё, что
    /// записано, кроме фактов одной карточки: брони студии, предоплаты,
    /// «сдано», отправленного опросника, связей со встречей, архива номеров и
    /// следа сдвига. Выключенный блок уходит в копию пустым, как у новой съёмки.
    public static func copy(_ rec: Session, id: String, day: CivilDate, info: Repeat,
                            blocks on: Set<RepeatBlock>, home: RepeatHome) -> Session {
        var c = rec
        c.id = id
        c.day = day
        c.repeatInfo = info
        c.bookingRef = nil
        c.rentRequest = nil
        c.prepay = 0
        c.delivered = false
        c.deliveredAt = nil
        c.questSent = nil
        c.fromMeetOn = nil
        c.fromMeetId = nil
        c.grewOn = nil
        c.grewToId = nil
        c.telLog = []
        // Сдвигали эту карточку, а не её повторы: и след, и его строка в заметке остаются у неё одной.
        if let line = c.dayMoved?.line, !line.isEmpty, c.notes.hasSuffix(line) {
            c.notes = String(c.notes.dropLast(line.count))
            while c.notes.hasSuffix("\n") { c.notes.removeLast() }
        }
        c.dayMoved = nil
        if !on.contains(.client) {
            c.contact = ""; c.clientPhone = ""; c.orgId = nil; c.orderPerson = ""; c.orderPhone = ""
            c.persons = []; c.guests = 0; c.breed = ""
        }
        if !on.contains(.route) {
            c.route = []; c.place = ""; c.placeTown = home.town; c.placeAddress = ""
            c.latitude = home.latitude; c.longitude = home.longitude; c.placeIsCity = true
            c.studioId = nil; c.hallId = nil; c.rentFrom = nil; c.rentTo = nil
            c.trip = false; c.tripManual = false; c.tripPlace = ""
        }
        if !on.contains(.notes) { c.notes = "" }
        if !on.contains(.kit) { c.gear = [] }
        if !on.contains(.playlist) { c.playlist = nil }
        if !on.contains(.brief) { c.brief = ""; c.models = "" }
        if !on.contains(.docs) { c.docs = [] }
        if !on.contains(.wish) { c.wishes = [] }
        // Проверка «замысел против прогноза» у копии — своя, на её день: сюда её
        // принесёт форма с погодой (шаг итерации 24); чужая оценка не переносится.
        c.wishWarning = nil
        if !on.contains(.delivery) { c.deadline = .auto }
        return c
    }

    /// Новая группа (веб `repMake`): эта карточка первая, копии — по правилу.
    /// Помесячная сумма и начало месяцев — в сведениях каждой карточки: удаление
    /// первой не уносит их с собой.
    public static func make(_ rec: inout Session, rule: RepeatRule, count: Int, blocks: Set<RepeatBlock>,
                            home: RepeatHome, group: String, monthly: Decimal? = nil,
                            newId: () -> String) -> [Session] {
        let ds = dates(from: rec.day, rule: rule, count: count)
        var first = Repeat(group: group, rule: rule, index: 1, count: ds.count)
        if rec.pay == .monthly {
            first.monthly = monthly   // сумма месяца придёт с деньгами формы (шаг итерации 24)
            first.start = rec.day
            rec.rate = nil
        }
        rec.repeatInfo = first
        return ds.dropFirst().enumerated().map { k, d in
            var info = Repeat(group: group, rule: rule, index: k + 2, count: ds.count)
            info.monthly = first.monthly
            info.start = first.start
            return copy(rec, id: newId(), day: d, info: info, blocks: blocks, home: home)
        }
    }
}
