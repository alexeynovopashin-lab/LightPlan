import Foundation
import LightPlanCore

/// Запись в общем списке: съёмка, встреча или событие из чужого календаря
/// (веб `sessions[]`, поля — те, что кладёт «Сохранить» в форме съёмки).
///
/// Имена в Swift свои, ключ снимка веба у каждого поля назван в комментарии:
/// формат снимка общий у веба и натива (`docs/17` § 6), и читатель итерации 12
/// ставит их в `CodingKeys` один к одному. Пустое поле — пустая строка, ложь
/// или пустой список, как у веба (`|| ""`, `|| false`, `|| []`): карточка не
/// показывает пустого, и различать «пусто» и «нет ключа» ей незачем. Где
/// различать нужно, тип это говорит сам (`DeadlineChoice`, `rate`).
public struct Session: Sendable, Hashable, Identifiable {
    /// `id` — знак записи: по нему находит съёмку опросник, ушедший клиенту.
    public var id: String
    /// `kind`.
    public var kind: RecordKind
    /// `date` — день начала, строкой «ГГГГ-ММ-ДД».
    public var day: CivilDate
    /// `min` — начало, минуты от полуночи дня.
    public var start: Int
    /// `end` — конец, минуты от полуночи **первого** дня: съёмка до утра — больше 1 440.
    public var end: Int?
    /// `dur` — длительность в минутах.
    public var duration: Int?
    /// `type` — жанр; незнакомый или пустой — `nil` (правила веба для него — `GenreProfile`).
    public var genre: Genre?
    /// `sub` — уточнение жанра; пустая строка — `nil`.
    public var subGenre: SubGenre?

    /// `contact` — клиент строкой. Остаётся и при паре, и при организации:
    /// на ней держатся поиск, список дня и неделя.
    public var contact: String = ""
    /// `clientTel`.
    public var clientPhone: String = ""
    /// `notes`.
    public var notes: String = ""
    /// `orgId` — ссылка на организацию, а не название (`docs/12`, «Организация как сущность»).
    public var orgId: String?
    /// `person` — контактное лицо заказчика.
    public var orderPerson: String = ""
    /// `phone` — телефон контактного лица.
    public var orderPhone: String = ""
    /// `persons` — пара поимённо: невеста и жених, виновник торжества.
    public var persons: [Person] = []

    /// `place` — имя точки съёмки.
    public var place: String = ""
    /// `placeTown` — город, когда точки нет или она названа без него.
    public var placeTown: String = ""
    /// `placeAddr`.
    public var placeAddress: String = ""
    /// `placeLat`.
    public var latitude: Double?
    /// `placeLon`.
    public var longitude: Double?
    /// `placeCity` — место в городе: засветка мешает звёздам.
    public var placeIsCity: Bool = false
    /// `studioId` — студия первой ячейки дня (у записи старого вида — место съёмки).
    public var studioId: String?
    /// `hallId`.
    public var hallId: String?
    /// `rentFrom` — начало аренды, минуты от полуночи первого дня.
    public var rentFrom: Int?
    /// `rentTo`.
    public var rentTo: Int?
    /// `bookingRef` — бронь в каталоге студий (BroniOS).
    public var bookingRef: String?
    /// `rentReq` — запрос продления аренды.
    public var rentRequest: RentRequest?

    /// `wish` — пожелания к погоде и свету.
    public var wishes: [Wish] = []
    /// `warn` — первое несбывшееся пожелание, записанное при сохранении.
    public var wishWarning: WishWarning?

    /// `deadlineChoice`.
    public var deadline: DeadlineChoice = .auto
    /// `delivered` — единственная отметка, которую ставит человек: «материал сдан».
    public var delivered: Bool = false
    /// `deliveredAt` — момент отметки (строка ISO в снимке).
    public var deliveredAt: Date?

    /// `pay` — способ оплаты; пустой — `nil`, дохода нет.
    public var pay: PayKind?
    /// `rate` — ставка, цена или сумма. `nil` у помесячной карточки значит
    /// «доля месяца», число (и ноль) — свой гонорар.
    public var rate: Decimal?
    /// `units` — количество у поштучной оплаты.
    public var units: Decimal = 0
    /// `expense`.
    public var expense: Decimal = 0
    /// `prepay` — не доход и не вычет: отвечает, сколько привезут в день съёмки.
    public var prepay: Decimal = 0
    /// `currency` — валюта сделки; `nil` — валюта из настроек.
    public var currency: Currency?

    /// `guests` — гости, десятками.
    public var guests: Int = 0
    /// `trip` — выезд: день уходит на дорогу целиком.
    public var trip: Bool = false
    /// `tripManual` — выезд правили руками; снятый руками — ответ «успею».
    public var tripManual: Bool = false
    /// `tripPlace`.
    public var tripPlace: String = ""
    /// `brief` — техническое задание.
    public var brief: String = ""
    /// `models`.
    public var models: String = ""
    /// `breed` — порода или вид у животных.
    public var breed: String = ""
    /// `docs` — документы заказа.
    public var docs: [Attachment] = []
    /// `gear` — что из общего списка оборудования взято на эту съёмку.
    public var gear: [String] = []
    /// `playlist` — имя плейлиста.
    public var playlist: String?

    /// `questSent` — когда ушёл опросник (строка ISO в снимке).
    public var questSent: Date?
    /// `questOff` — строка опросника выключена у этой карточки.
    public var questOff: Bool = false
    /// `fromMeetOn` — день встречи, из которой выросла съёмка.
    public var fromMeetOn: CivilDate?
    /// `fromMeetId`.
    public var fromMeetId: String?
    /// `grewOn` — у встречи: день съёмки, которой она кончилась.
    public var grewOn: CivilDate?
    /// `grewToId`.
    public var grewToId: String?
    /// `dayMoved` — время сдвинуто на ленте: было и строка в заметке.
    public var dayMoved: DayMoved?

    /// `route` — точки дня, в порядке, в каком их составил фотограф.
    public var route: [RoutePoint] = []
    /// `synced` — календарь, куда уехала запись.
    public var calendar: CalendarService?
    /// `telLog` — прежние номера карточки: по ним узнаётся звонок.
    public var telLog: [TelLogEntry] = []
    /// `rep` — сведения о группе повтора.
    public var repeatInfo: Repeat?
    /// `doneAt` — съёмку завершили кнопкой: минута суток по часам телефона.
    public var doneAt: Int?
    /// `icsSig` — отпечаток события чужого календаря: по нему не ввозят дважды.
    public var icsSignature: String?
    /// `icsAt` — когда ввезли (миллисекунды).
    public var icsImportedAt: Int64?
    /// `mt` — когда запись правили последний раз (миллисекунды); нужна обмену устройств.
    public var modifiedAt: Int64?

    public init(id: String, kind: RecordKind = .shoot, day: CivilDate, start: Int,
                end: Int? = nil, duration: Int? = nil, genre: Genre? = nil) {
        self.id = id
        self.kind = kind
        self.day = day
        self.start = start
        self.end = end
        self.duration = duration
        self.genre = genre
    }

    /// Жанр со всем, что из него выводится.
    public var profile: GenreProfile { GenreProfile(genre) }

    /// Конец записи (веб `shootEnd`): записанный, иначе начало плюс
    /// длительность, иначе полтора часа. Нулевая длительность — тоже полтора
    /// часа: `s.dur || 90`.
    public var endMinute: Int {
        if let end { return end }
        if let duration, duration != 0 { return start + duration }
        return start + 90
    }

    /// Показывается ли запись (веб `shownRec`): слой чужих событий
    /// выключается целиком, как календарь-подписка.
    public func isShown(eventsLayer: Bool) -> Bool {
        eventsLayer || kind != .event
    }

    /// Место одной строкой (веб `placeText`): точка названа — она и есть
    /// ответ, иначе город.
    public var placeText: String { place.isEmpty ? placeTown : place }

    /// Ключ места для сравнения (веб `placeKey`): имя без уточнений —
    /// «Лобня, Московская область» и «Лобня» одно место.
    public var placeKey: String {
        let first = placeText.split(separator: ",", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return Session.jsTrim(first).lowercased()
    }

    /// Точки дня «что во сколько» (веб `routeOf`): со временем и именем, по
    /// часам. Точка без часа сюда не попадает. Равные часы — в порядке списка.
    public var timedRoute: [RoutePoint] {
        route.enumerated()
            .filter { $0.element.start != nil && !$0.element.name.isEmpty }
            .sorted { ($0.element.start!, $0.offset) < ($1.element.start!, $1.offset) }
            .map(\.element)
    }

    /// Дата суток съёмки номер `k` от дня начала (веб `shootDate`).
    public func date(ofDay k: Int) -> CivilDate { k == 0 ? day : day.adding(days: k) }

    /// `String.prototype.trim` веба: пробелы Unicode и переводы строк.
    static func jsTrim(_ s: String) -> String {
        let white: Set<Unicode.Scalar> = [
            "\u{09}", "\u{0A}", "\u{0B}", "\u{0C}", "\u{0D}", "\u{20}", "\u{A0}", "\u{1680}",
            "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}", "\u{2006}",
            "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}", "\u{2028}", "\u{2029}", "\u{202F}",
            "\u{205F}", "\u{3000}", "\u{FEFF}",
        ]
        let scalars = s.unicodeScalars
        guard let a = scalars.firstIndex(where: { !white.contains($0) }) else { return "" }
        let b = scalars.lastIndex(where: { !white.contains($0) })!
        return String(scalars[a...b])
    }
}

/// Срок сдачи у записи (веб `deadlineChoice`).
public enum DeadlineChoice: Hashable, Sendable {
    /// «Как заведено»: по настройке сдачи и жанру. В снимке — `"auto"` или ключа нет.
    case auto
    /// Свой срок в днях — сильнее всего.
    case days(Int)
    /// Без срока. В снимке — `null`.
    case none
}

/// Человек пары (веб `persons[]`: `n`, `tel`).
public struct Person: Sendable, Hashable {
    /// `n`.
    public var name: String
    /// `tel`.
    public var phone: String

    public init(name: String, phone: String) {
        self.name = name
        self.phone = phone
    }
}

/// Точка дня (веб `route[]`). Своих координат не хранит: место живёт в «Моих
/// местах» одной записью, а точка на него ссылается.
public struct RoutePoint: Sendable, Hashable {
    /// `t` — начало, минуты от полуночи первого дня; `nil` — точка без часа,
    /// она не привязана к скелету времени и оболочку не держит.
    public var start: Int?
    /// `t2` — конец этапа.
    public var end: Int?
    /// `n` — что это: «ЗАГС», «Прогулка».
    public var name: String
    /// `p` — место строкой («Томсон, зал Эдисон»).
    public var placeText: String
    /// `placeId` — ссылка на сохранённое место.
    public var spotId: String?
    /// `studioId` — ссылка на студию.
    public var studioId: String?
    /// `hallId`.
    public var hallId: String?
    /// `walk` — до этой точки идут пешком.
    public var walk: Bool

    public init(start: Int?, end: Int? = nil, name: String, placeText: String = "",
                spotId: String? = nil, studioId: String? = nil, hallId: String? = nil, walk: Bool = false) {
        self.start = start
        self.end = end
        self.name = name
        self.placeText = placeText
        self.spotId = spotId
        self.studioId = studioId
        self.hallId = hallId
        self.walk = walk
    }
}

/// Вложение: документ заказа, файл реквизитов (веб `docs[]`, `reqFiles[]`).
/// Байты живут в облаке фотографа или в папке вложений, в записи — путь.
public struct Attachment: Sendable, Hashable {
    /// Откуда (веб `k`).
    public enum Source: String, Sendable {
        /// Файл на Диске фотографа.
        case doc
        /// Картинка с миниатюрой.
        case img
        /// Ссылка на чужое облако.
        case link
    }

    /// `k`.
    public var source: Source
    /// `path` — путь в облаке фотографа.
    public var path: String?
    /// `name`.
    public var name: String?
    /// `size` — байты.
    public var size: Int?
    /// `url` — у ссылки.
    public var url: String?
    /// `kind` — вид документа; незнакомый — `nil`.
    public var kind: DocKind?

    public init(source: Source, path: String? = nil, name: String? = nil, size: Int? = nil,
                url: String? = nil, kind: DocKind? = nil) {
        self.source = source
        self.path = path
        self.name = name
        self.size = size
        self.url = url
        self.kind = kind
    }
}

/// Предупреждение о пожелании, записанное при сохранении (веб `warn`: `t`, `m`).
/// Хранится готовыми словами на языке той минуты — так пишет веб.
public struct WishWarning: Sendable, Hashable {
    public var title: String
    public var message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

/// Время сдвинуто на ленте (веб `dayMoved`: `a`, `b`, `line`): было до сдвига
/// и строка, дописанная в заметку. Гаснет только от крестика.
public struct DayMoved: Sendable, Hashable {
    public var start: Int
    public var end: Int
    public var line: String?

    public init(start: Int, end: Int, line: String? = nil) {
        self.start = start
        self.end = end
        self.line = line
    }
}

/// Прежний номер карточки (веб `telLog[]`: `f`, `tel`, `n`, `at`).
public struct TelLogEntry: Sendable, Hashable {
    /// `f` — чей это был номер: поле карточки.
    public var field: String?
    public var phone: String
    /// `n` — имя при номере.
    public var name: String?
    /// `at` — когда номер ушёл из карточки (строка ISO в снимке).
    public var retiredAt: String?

    public init(field: String?, phone: String, name: String?, retiredAt: String?) {
        self.field = field
        self.phone = phone
        self.name = name
        self.retiredAt = retiredAt
    }
}

/// Запрос продления аренды студии (веб `rentReq`: `id`, `status`, `newEnd`).
public struct RentRequest: Sendable, Hashable {
    public enum Status: String, Sendable {
        case requested, confirmed, declined, expired
    }

    public var id: String
    /// Незнакомый ответ студии — `nil`: запрос висит, пока не придёт понятный.
    public var status: Status?
    /// `newEnd` — новый конец «ЧЧ:ММ», когда студия подтвердила.
    public var newEnd: String?

    public init(id: String, status: Status?, newEnd: String?) {
        self.id = id
        self.status = status
        self.newEnd = newEnd
    }
}
