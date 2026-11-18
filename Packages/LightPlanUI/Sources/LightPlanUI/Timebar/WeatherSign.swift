import LightPlanCore

/// Погодный знак ячейки барабана по категории дня — порт `skyIcon(q)` веба:
/// `excellent` — солнце, `good` — голое облако, `plain` — солнце с облаком, `fog` — линии тумана.
/// `poor` — по осадкам (`signIconName(_:)`). Веб рисовал каплями и `plain`: «Переменно» без единого миллиметра
/// выглядело дождём (Алексей 18.11, Томск, −7°: «прогноз показывает дождь») — 31.4: капли только у настоящего дождя.
///
/// Веб рисует эти знаки отдельной вручную набранной SVG-функцией, а не через
/// `icons.js` — но по смыслу это те же самые солнце, облако, дождь и туман,
/// что уже есть в библиотеке знаков (итерация 15), и заводить для них второй,
/// отдельно поддерживаемый набор путей незачем (`ws:CLAUDE.md` — «сперва
/// открыть лист знаков, потом рисовать»).
extension DayQuality {
    var signIconName: String {
        switch self {
        case .excellent: "clear"
        case .good: "cloud"
        case .plain: "part"
        case .poor: "rain"
        case .fog: "fog"
        }
    }
}

/// 31.2 «Погода по правде»: `.poor` — это и осадки, и просто низкий закатный балл (сплошные низкие облака). Словом «Дождь» и каплями
/// называется только дождь; снег (коды 71–77, 85–86) — «Снег» и снежинка; «плохо» без осадков — «Пасмурно» и облако.
extension DayQuality {
    /// Окончание ключа слова `qualCond.*` / `qualSky.*`.
    func wordKey(_ precip: Precip?) -> String {
        guard self == .poor else { return rawValue }
        switch precip {
        case .rain?: return rawValue
        case .snow?: return "snow"
        case nil: return "overcast"
        }
    }

    func signIconName(_ precip: Precip?) -> String {
        guard self == .poor else { return signIconName }
        switch precip {
        case .rain?: return "rain"
        case .snow?: return "snow"
        case nil: return "cloud"
        }
    }
}

extension WeatherDay {
    /// Слово дня («Облачно», «Дождь», «Снег», «Пасмурно»…) — по окну заката.
    var condKey: String { "qualCond." + quality.wordKey(precip) }
    /// Слово неба рассвета (31.5): категория и осадки окна у восхода.
    var dawnCondKey: String { "qualCond." + dawnQuality.wordKey(dawnPrecip) }
    /// Знак дня (барабан, лента, сводка) — по окну заката.
    var signIconName: String { quality.signIconName(precip) }
    /// Слово и знак на выбранную минуту — по окну вокруг неё (`WeatherDay.wetWindowHours`).
    func condKey(at minute: Double) -> String { "qualCond." + quality(at: minute).wordKey(precip(at: minute)) }
    func skyKey(at minute: Double) -> String { "qualSky." + quality(at: minute).wordKey(precip(at: minute)) }
    func signIconName(at minute: Double) -> String { quality(at: minute).signIconName(precip(at: minute)) }
}
