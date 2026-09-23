import Foundation

/// Язык приложения — из iOS (DECISIONS, «Язык приложения — из iOS, строка в
/// настройках ведёт туда», 21 сентября 2026). Своего выбора внутри нет:
/// строка «Язык» в настройках открывает страницу приложения в настройках
/// iPhone, а iOS после смены перезапускает приложение.
public enum AppLanguage {

    /// Коды словаря веба (`LANG_ORDER`): `ru`, `en-GB`, `en-US`, `es`, `ja`, `zh`.
    public static let codes = ["ru", "en-GB", "en-US", "es", "ja", "zh"]

    /// Код словаря по языку iOS и региону телефона. Британский или
    /// американский английский — по региону: США дают `en-US`, прочие —
    /// `en-GB`. Язык, которого у словаря нет, — английский того же правила.
    public static func code(preferred: String?, region: String?) -> String {
        let p = (preferred ?? "").lowercased()
        let base = String(p.prefix { $0 != "-" && $0 != "_" })
        switch base {
        case "ru", "es", "ja", "zh": return base
        default: return region?.uppercased() == "US" ? "en-US" : "en-GB"
        }
    }

    /// Язык этого запуска. `Locale.preferredLanguages` уже учитывает язык,
    /// выбранный для приложения в настройках iPhone (iOS пишет его в
    /// `AppleLanguages` приложения).
    public static var current: String {
        code(preferred: Locale.preferredLanguages.first, region: Locale.current.region?.identifier)
    }
}
