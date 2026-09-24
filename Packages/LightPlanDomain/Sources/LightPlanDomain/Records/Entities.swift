import Foundation
import LightPlanCore

/// Организация (веб `orgs[]`): отдельная запись с постоянным ключом. Название
/// правится, контактное лицо меняется, а история съёмок не рвётся
/// (`docs/12_CARD_ARCHITECTURE.md`, «Организация как сущность»).
public struct Org: Sendable, Hashable, Identifiable {
    /// `id`.
    public var id: String
    /// `name`.
    public var name: String = ""
    /// `person` — текущее контактное лицо.
    public var person: String = ""
    /// `phone`.
    public var phone: String = ""
    /// `req` — реквизиты одним полем, как их прислали: приложение их не разбирает.
    public var requisites: String = ""
    /// `reqFiles` — реквизиты файлом или снимком.
    public var requisiteFiles: [Attachment] = []
    /// `docs` — документы организации: договор на год кладётся сюда, акт по съёмке — в съёмку.
    public var docs: [Attachment] = []
    /// `telLog`.
    public var telLog: [TelLogEntry] = []
    /// `mt`.
    public var modifiedAt: Int64?

    public init(id: String, name: String = "") {
        self.id = id
        self.name = name
    }
}

/// Занятое время (веб `blocks[]`): выходной, дорога, перелёт, «занят». Не съёмка
/// без полей: у выходного нет ни клиента, ни жанра, ни сдачи, и в прибыль года
/// он попадать не должен.
public struct Block: Sendable, Hashable, Identifiable {
    /// `id`.
    public var id: String
    /// `k` — вид; незнакомый читается как «занят» (веб `blockKind`).
    public var kind: BlockKind
    /// `note` — заметка; пустая — занятость называется своим видом.
    public var note: String = ""
    /// `from` — первый день.
    public var from: CivilDate
    /// `allDay` — на весь день.
    public var allDay: Bool = false
    /// `days` — дней подряд от первого (только у «весь день»): отпуск «с 3 по 10»
    /// и «7 дней подряд» — одно и то же, но дням не разъехаться.
    public var days: Int = 1
    /// `min` — начало по часам.
    public var start: Int?
    /// `dur` — длительность; у дороги из формы — настоящее время в пути.
    public var duration: Int?
    /// `tzFrom` — смещение пояса вылета в часах: минуты такой занятости — часы билета.
    public var zoneFrom: Double?
    /// `tzTo` — смещение пояса прилёта.
    public var zoneTo: Double?
    /// `mt`.
    public var modifiedAt: Int64?

    public init(id: String, kind: BlockKind, from: CivilDate) {
        self.id = id
        self.kind = kind
        self.from = from
    }

    /// Сколько дней занято (веб `blockDays`): у «весь день» — `days`, не меньше
    /// одного; у занятости по часам — один.
    public var dayCount: Int { allDay ? max(1, days) : 1 }

    /// Последний занятый день (веб `blockLast`).
    public var lastDay: CivilDate { from.adding(days: dayCount - 1) }

    /// Занят ли этот день (веб `blockCovers`).
    public func covers(_ day: CivilDate) -> Bool {
        if !allDay { return from == day }
        return day >= from && day <= lastDay
    }
}

/// Сохранённое место съёмки (веб `spots[]`): парк, лофт, кафе, банкетный зал.
/// Список один на приложение — и закладка карты, и «Мои точки съёмки», и лист
/// «Где снимаем» смотрят сюда.
public struct Spot: Sendable, Hashable, Identifiable {
    /// `id`.
    public var id: String
    /// `name`.
    public var name: String = ""
    /// `address`.
    public var address: String = ""
    /// `town`.
    public var town: String = ""
    /// `sub` — уточнение места: подъезд, вход.
    public var sub: String = ""
    /// `lat`.
    public var latitude: Double?
    /// `lon`.
    public var longitude: Double?
    /// `mt`.
    public var modifiedAt: Int64?
    /// `pinned` — поставлена пальцем на карте (закладка шапки): координаты
    /// выбрал человек. Без него место назвал геокодер, и булавка полая.
    public var pinned: Bool?
    /// `named` — имя набрано рукой, а не взято у геокодера.
    public var named: Bool?
    /// `ic` — знак места в списке точек (`pin`, если пусто).
    public var icon: String?

    public init(id: String, name: String = "", latitude: Double?, longitude: Double?) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Студия (веб `studios[]`): отдельная сущность, а не место с тумблером — у неё
/// есть кому ответить (DECISIONS, «Студия — сущность, а не почасовое место»).
public struct Studio: Sendable, Hashable, Identifiable {
    /// `id`.
    public var id: String
    /// `name` — без слова «студия»: его дописывает приложение.
    public var name: String = ""
    /// `address`.
    public var address: String = ""
    /// `tel` — администратор.
    public var phone: String = ""
    /// `town` — им список отделяет томские студии от московских.
    public var town: String = ""
    /// `lat`.
    public var latitude: Double?
    /// `lon`.
    public var longitude: Double?
    /// `halls` — залы.
    public var halls: [Hall] = []
    /// `key` — ключ студии в каталоге броней: с ним уходит запрос продления.
    public var key: String = ""
    /// `tomcohId` — адрес в каталоге студий (BroniOS), откуда карточка приедет сама.
    public var catalogId: String?
    /// `hourMin` — длина рабочего часа в минутах; `nil` — 55, как у веба (`STUDIO_HOUR_MIN`).
    public var hourMinutes: Int?
    /// `mt`.
    public var modifiedAt: Int64?

    public init(id: String, name: String = "", latitude: Double?, longitude: Double?) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Зал студии (веб `halls[]`: `id`, `name`).
    public struct Hall: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
}

/// Удалённая запись в корзине (веб `trashed[]`: `rec`, `at`, `del`): запись
/// помнит, где стояла и когда её убрали, — возвращать надо на место.
public struct TrashedItem: Sendable, Hashable {
    /// `rec`.
    public var record: Session
    /// `at` — место в списке.
    public var index: Int
    /// `del` — когда удалили (миллисекунды).
    public var deletedAt: Int64

    public init(record: Session, index: Int, deletedAt: Int64) {
        self.record = record
        self.index = index
        self.deletedAt = deletedAt
    }
}

/// Сведения о группе повтора у карточки (веб `rep`). Главной и зависимой
/// карточки нет: каждая несёт сведения сама, и удаление первой их не уносит.
public struct Repeat: Sendable, Hashable {
    /// `g` — знак группы.
    public var group: String
    /// `rule`.
    public var rule: RepeatRule
    /// `i` — номер при создании (живой номер считается по датам группы).
    public var index: Int
    /// `n` — сколько карточек было при создании.
    public var count: Int
    /// `monthly` — сумма месяца у помесячной оплаты.
    public var monthly: Decimal?
    /// `start` — первый день помесячной группы: от него считаются месяцы.
    public var start: CivilDate?
    /// `sums` — смены суммы месяца: «с месяца k — столько».
    public var sums: [MonthSum] = []
    /// `stop` — продление погашено.
    public var stopped: Bool = false

    public init(group: String, rule: RepeatRule, index: Int, count: Int,
                monthly: Decimal? = nil, start: CivilDate? = nil, sums: [MonthSum] = []) {
        self.group = group
        self.rule = rule
        self.index = index
        self.count = count
        self.monthly = monthly
        self.start = start
        self.sums = sums
    }
}

/// Правило повтора (веб `REP_RULES` без «never»: «никогда» в запись не пишется).
public enum RepeatRule: String, CaseIterable, Sendable {
    case day, week, week2, month, year
}

/// Смена суммы месяца (веб `rep.sums[]`: `k`, `sum`, `at`).
public struct MonthSum: Sendable, Hashable {
    /// `k` — с какого месяца группы.
    public var month: Int
    public var sum: Decimal
    /// `at` — когда сменили (миллисекунды): действует самая поздняя смена.
    public var at: Int64

    public init(month: Int, sum: Decimal, at: Int64) {
        self.month = month
        self.sum = sum
        self.at = at
    }
}
