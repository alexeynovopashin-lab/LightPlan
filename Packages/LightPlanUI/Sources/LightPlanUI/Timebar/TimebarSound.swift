/// Звук срыва — взвод механического затвора дальномерного Canon, тот же сэмпл, что и в вебе (`SHUTTER_B64`,
/// DECISIONS «Звук спуска вместо вжуха», «Щелчок детента вместо трещотки, громкость спуска -30%»): 0,35 с,
/// 48 кГц, моно. Громкость — `SoundCue.shutter.gain` = 0,2695 (у беты 0,385 − 30 % ещё раз, 24.08; до 29.6
/// здесь стояло 0,385). Играет `SoundCenter`: категория ambient, тумблер «Щелчки слайдера».
@MainActor
final class TimebarSound {
    func playSnap() {
        SoundCenter.play(.shutter, event: "timebar.snap")
    }
}
