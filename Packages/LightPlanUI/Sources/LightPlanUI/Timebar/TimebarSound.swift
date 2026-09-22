import AVFAudio

/// Звук срыва — взвод механического затвора дальномерного Canon, тот же
/// сэмпл, что и в вебе (`SHUTTER_B64`, DECISIONS «Звук спуска вместо вжуха»,
/// «Щелчок детента вместо трещотки, громкость спуска -30%»): 0,35 с, 48 кГц,
/// моно, громкость `gain 0.385`. Детент таймбара звучит только отдачей —
/// щелчок детента (`tickClick`) остаётся вебу до отдельной итерации звука.
@MainActor
final class TimebarSound {
    private static let gain: Float = 0.385

    private var player: AVAudioPlayer?

    init() {
        guard let url = Bundle.module.url(forResource: "shutter", withExtension: "wav", subdirectory: "Sound")
            ?? Bundle.module.url(forResource: "shutter", withExtension: "wav")
        else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = Self.gain
        player?.prepareToPlay()
    }

    /// Проигрывает готовый буфер с начала — срыв повторяется чаще, чем один
    /// раз в жизни экрана.
    func playSnap() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}
