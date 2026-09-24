#if canImport(AudioToolbox) && os(iOS)
import AudioToolbox
#endif

/// Щелчок булавки (слово Алексея 24.09: «с щелчком звук + тактильная
/// отдача»). Системный щелчок клавиатуры — до итерации 29, где звуки
/// приложения станут своими; гасится переключателем «Без звука» и громкостью
/// звонка, как любой системный звук.
enum MapClick {
    static func play() {
        #if canImport(AudioToolbox) && os(iOS)
        AudioServicesPlaySystemSound(1104)
        #endif
    }
}
