import Foundation
import LightPlanCore
import LightPlanData

/// Состояние листа «Где снимаем» в режиме места приложения (`openLocSheet
/// ("app")` веба) — без вида, чтобы правила проверялись тестами.
///
/// Три пути веба, но с шапки «Света» и «Карты» веб показывает два: студия
/// месту приложения не нужна («свету нужны координаты, а не арендодатель»),
/// её путь откроется с формой съёмки (23–24). Справка:
/// `Light_Plan/docs/native_21v_loc_sheet_web_spec.md`.
struct PlaceSheetForm: Equatable {
    /// Путь листа (`locWay`): развилка или один из двух входов.
    enum Way: String, Equatable { case fork, addr, geo }

    var way: Way = .fork
    /// Поля широты и долготы — строкой, как их видит человек. На открытии —
    /// место приложения до четырёх знаков (`toFixed(4)`).
    var lat = ""
    var lon = ""
    var name = ""
    var address = ""
    /// «Сохранить в моих местах».
    var save = false
    /// Имя набрано рукой (`locNameTyped`) — поиск его больше не перебивает,
    /// правка чисел не стирает.
    private(set) var nameTyped = false
    /// Числа принёс поиск, а не рука (`locFromHit`): сохранённая точка
    /// получает полую булавку.
    private(set) var fromHit = false
    /// Ключ словаря строки ошибки над «Готово» (`#locErr`); `nil` — пусто.
    var errorKey: String?

    init(here: GeoCoordinate, way: Way = .fork) {
        lat = JSNumber.fixed(here.latitude, 4)
        lon = JSNumber.fixed(here.longitude, 4)
        self.way = way
    }

    /// Вход в путь и возврат на развилку (`setWay`): строка ошибки гаснет.
    mutating func open(_ w: Way) {
        way = w
        errorKey = nil
    }

    /// Тап по ответу поиска: числа в поля, имя — если его не набирали.
    mutating func pick(_ hit: PlaceHit) {
        lat = JSNumber.fixed(hit.coordinate.latitude, 4)
        lon = JSNumber.fixed(hit.coordinate.longitude, 4)
        fromHit = true
        if !nameTyped { name = hit.name }
        errorKey = nil
    }

    mutating func typeName(_ v: String) {
        name = v
        nameTyped = true
    }

    /// Числа поправили руками: они снова свои, а имя прежних координат новым
    /// не подходит — стирается, если его не набирали (веб: «Эльбрус» не
    /// остаётся подписан «Лобней»).
    mutating func typeCoords(lat la: String? = nil, lon lo: String? = nil) {
        if let la { lat = la }
        if let lo { lon = lo }
        fromHit = false
        if !nameTyped { name = "" }
    }

    /// Ответ «Готово» (`#locDone`): точка или ключ ошибки. Оба поля не
    /// читаются — место не выбрано (`loc.errNone`), а не «широта неверна».
    /// Разбор строже `parseFloat` веба: «56.4 abc» он не прочтёт как 56.4.
    func answer() -> Result<GeoCoordinate, AnswerError> {
        let laOK = if case .success = ManualCoordinates.parse(latitude: lat, longitude: "0") { true } else { false }
        let loOK = if case .success = ManualCoordinates.parse(latitude: "0", longitude: lon) { true } else { false }
        if !laOK && !loOK { return .failure(AnswerError(key: "loc.errNone")) }
        if !laOK { return .failure(AnswerError(key: "loc.errLat")) }
        if !loOK { return .failure(AnswerError(key: "loc.errLon")) }
        switch ManualCoordinates.parse(latitude: lat, longitude: lon) {
        case .success(let c): return .success(c)
        case .failure: return .failure(AnswerError(key: "loc.errNone"))
        }
    }

    struct AnswerError: Error, Equatable { let key: String }

    /// Заголовок и подпись: на развилке — вопрос листа, в пути — его слова.
    var titleKey: String {
        switch way { case .fork: "loc.title"; case .addr: "loc.wayAddr"; case .geo: "loc.wayGeo" }
    }
    var subKey: String {
        switch way { case .fork: "loc.sub"; case .addr: "loc.wayAddrSub"; case .geo: "loc.wayGeoSub" }
    }
}
