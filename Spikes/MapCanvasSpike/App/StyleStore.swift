import Foundation

/// Описание холста — тот же самый style JSON, что рисует бета в браузере:
/// `beta/mapstyle.js` собирает его из снимка CARTO Voyager и перекрашивает по
/// именам слоёв. Здесь лежат два готовых результата (`build({dark:…})`),
/// снятые тем же кодом, чтобы холст песочницы и холст беты были одним холстом,
/// а не похожими.
enum StyleStore {
    static func url(dark: Bool) -> URL? {
        Bundle.main.url(forResource: dark ? "style_dark" : "style_light", withExtension: "json")
    }
}
