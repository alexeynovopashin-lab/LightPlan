import Foundation

/// Род записи в общем списке (веб `kind`). Отсутствие ключа — съёмка.
public enum RecordKind: String, CaseIterable, Sendable {
    /// Съёмка: деньги, сроки, свет, маршрут.
    case shoot
    /// Встреча: жанр, когда, с кем и заметки — съёмки ещё не назначено.
    case meet
    /// Событие из чужого календаря: занимает день и молчит.
    case event

    /// Работа ли это (веб `!notWork`): деньги, сроки, статистика года и
    /// маршрут спрашивают именно это, а не «съёмка ли».
    public var isWork: Bool { self == .shoot }
}

/// Способ оплаты (веб `PAY`). Название — для человека, механика — для счёта.
public enum PayKind: String, CaseIterable, Sendable {
    case hourly, flat, pack, object, item
    /// Только у повтора: сумма за месяц у группы, у карточки — доля месяца.
    case monthly

    public var mechanic: PayMechanic {
        switch self {
        case .hourly: .hourly
        case .flat, .pack: .flat
        case .object, .item: .unit
        case .monthly: .monthly
        }
    }

    /// Спрашивает ли способ количество (`unit: true`): за объект, за предмет.
    public var countsUnits: Bool { mechanic == .unit }
}

/// Механика оплаты под названиями способов.
public enum PayMechanic: String, Sendable {
    /// Ставка × часы.
    case hourly
    /// Плоская сумма: сдельно, пакет.
    case flat
    /// Цена × количество.
    case unit
    /// Доля месяца группы повтора.
    case monthly
}

/// Валюта съёмки (веб `CURRENCIES`): своя настройка, а не следствие языка.
public enum Currency: String, CaseIterable, Sendable {
    case rub = "RUB", usd = "USD", eur = "EUR", gbp = "GBP", jpy = "JPY", cny = "CNY"
}

/// Пожелание к погоде и свету (веб `WISHES` в форме).
public enum Wish: String, CaseIterable, Sendable {
    case any, clear, sunset, cloudy, fog, rain, moon, stars

    /// Заказан ли свет (`LIGHT_WISH`): только с ним карточка говорит о золотом часе.
    public var asksLight: Bool { Wish.light.contains(self) }

    /// Порядок ключей `LIGHT_WISH`.
    public static let light: [Wish] = [.sunset, .stars, .moon]
}

/// Вид занятости (веб `BLOCK_KINDS`): календарь отвечает «я свободен?», и
/// ответ не зависит от того, свадьба это или самолёт.
public enum BlockKind: String, CaseIterable, Sendable {
    case off, road, flight, busy

    /// Имя знака в общей библиотеке.
    public var iconName: String {
        switch self {
        case .off: "home"
        case .road: "car"
        case .flight: "plane"
        case .busy: "clock"
        }
    }
}

/// Вид документа заказа. Порядок — порядок сделки: чем открывают работу, тем
/// и начинается; набор, который предлагается человеку, задаёт практика.
public enum DocKind: String, CaseIterable, Sendable {
    case contract, invoice, receipt, act, brief, release, acceptance

    /// Вид по имени файла (веб `DOC_GUESS`, `guessDocKind`): файлы называют и
    /// кириллицей, и транслитом — «akt-vypolnennyh», «chek-2214». Угадали
    /// неверно — человек поправит одним нажатием.
    public static func guess(fileName: String) -> DocKind? {
        let range = NSRange(fileName.startIndex..., in: fileName)
        for rule in guessRules where rule.regex.firstMatch(in: fileName, range: range) != nil {
            return rule.kind
        }
        return nil
    }

    /// Правила угадывания в порядке веба: первое совпавшее выигрывает.
    /// Образцы те же, что в `DOC_GUESS`, флаг `i` веба — `.caseInsensitive`.
    public static let guessPatterns: [(pattern: String, kind: DocKind)] = [
        ("догов|contract|dogovor", .contract),
        ("чек|chek|check|cheque|receipt|kassa", .receipt),
        ("счёт|счет|invoice|schet|schyot", .invoice),
        ("акт(?![а-яё])|akt(?![a-z])|act(?![a-z])", .act),
        ("тз|бриф|brief|task|tz(?![a-z])", .brief),
        ("release|релиз|соглас(ие|ия)\\s*модел", .release),
        ("acceptance|protok|протокол|приём?к|приемк", .acceptance),
    ]

    private struct GuessRule: @unchecked Sendable {
        let regex: NSRegularExpression
        let kind: DocKind
    }

    private static let guessRules: [GuessRule] = guessPatterns.map {
        GuessRule(regex: try! NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]), kind: $0.kind)
    }
}

/// Куда запись уехала календарём (веб `synced`: `apple`, `google`; «off» — ключа нет).
public enum CalendarService: String, CaseIterable, Sendable {
    case apple, google
}
