import Foundation
import AVFAudio

/// Звуки приложения (29.6, 29.7). Три сэмпла беты, один плеер, один выключатель.
///
/// Бета (`initAudio`, `tickClick`, `swoosh`): щелчок детента `CLICK_B64` (48 кГц моно 16 бит, 44 мс) и затвор
/// `SHUTTER_B64` (0,35 с); смятие бумаги `TRASH_B64` (1,30 с, `trashSound`, 29.7). Все гасятся тумблером «Щелчки слайдера» (`#soundToggle`, по умолчанию включён).
///
/// Источник один — отдача: щелчок звучит из `Haptics.play` (у события в карте есть `sound`) и из
/// `TimebarHaptics.detent`, в тот же вызов, что и тик. Своих мест со звуком у экранов нет.
///
/// Системная часть: категория `ambient` — звук подчиняется переключателю «Без звука» и не прерывает чужую
/// музыку. Буферы грузятся один раз; узлы живут в одном `AVAudioEngine`.
enum SoundCue: String, CaseIterable, Sendable {
    case click, shutter, trash

    /// Громкость: у затвора — число беты (`swoosh`, 0,385 − 30 %), у смятия — `trashSound` (0,165), у щелчка её
    /// задаёт `SoundCenter.clickVariation`.
    var gain: Double {
        switch self {
        case .click: 0.02
        case .shutter: 0.2695
        case .trash: 0.165
        }
    }
}

/// Один щелчок: тон (`playbackRate` беты) и громкость.
struct ClickVariation: Equatable, Sendable {
    var rate: Double
    var gain: Double
}

/// Запись о воспроизведении — журнал отладки и тесты.
struct SoundPlay: Equatable, Sendable {
    var event: String
    var cue: SoundCue
    var gain: Double
    var rate: Double
}

@MainActor
enum SoundCenter {
    /// Ключ тумблера «Щелчки слайдера» (устройство, не данные съёмок: в снимок и облако не уходит).
    static let enabledKey = "lp.soundClicks"

    static var enabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: enabledKey) == nil ? true : d.bool(forKey: enabledKey)
    }

    // MARK: - Разброс щелчка (бета: `PI_D`, `piTick`)

    /// Дробная часть π, 192 знака — слово в слово таблица беты (`PI_D`). Щелчок берёт по две цифры за шаг.
    nonisolated static let piDigits: [Int] = Array(
        ("141592653589793238462643383279502884197169399375"
         + "105820974944592307816406286208998628034825342117"
         + "067982148086513282306647093844609550582231725359"
         + "408128481117450284102701938521105559644622948954").utf8
    ).map { Int($0) - 48 }

    /// Формулы `tickClick`: тон гуляет ±2 %, громкость ±18 % — читают разные цифры.
    nonisolated static func clickVariation(pa: Int, pb: Int) -> ClickVariation {
        ClickVariation(rate: 0.8 * (1 + (Double(pa) / 9 - 0.5) * 0.04),
                       gain: 0.02 * (1 + (Double(pb) / 9 - 0.5) * 0.36))
    }

    /// Указатель в таблице: по две цифры за щелчок, по кругу. Значимый тип — тест гоняет свой, не трогая общий.
    struct PiCursor: Sendable {
        var tick = 0
        /// Шаг вперёд — только на сыгранном щелчке, как у беты (молчавший не сдвигает).
        mutating func next() -> ClickVariation {
            let v = SoundCenter.clickVariation(pa: SoundCenter.piDigits[tick], pb: SoundCenter.piDigits[tick + 1])
            tick = (tick + 2) % SoundCenter.piDigits.count
            return v
        }
    }

    private static var cursor = PiCursor()

    // MARK: - Воспроизведение

    /// Звук `cue` по событию `event`. Выключенный тумблер — тишина и ничего в журнале.
    static func play(_ cue: SoundCue, event: String) {
        guard enabled else { return }
        let rate: Double, gain: Double
        switch cue {
        case .click:
            let v = cursor.next()
            rate = v.rate; gain = v.gain
        case .shutter, .trash:
            rate = 1; gain = cue.gain
        }
        SoundLog.note(SoundPlay(event: event, cue: cue, gain: gain, rate: rate))
        output.play(cue, gain: Float(gain), rate: Float(rate))
    }

    /// Тумблер в «Настройках»: включение сопровождается одним щелчком (`soundToggle`: `initAudio(); tickClick()`).
    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: enabledKey)
        if on { play(.click, event: "soundToggle") }
    }

    /// Поднять сессию и движок до первого касания: иначе первый щелчок приходит с запозданием.
    static func prepare() { output.prepare() }

    private static let output = Output()

    // MARK: - Движок

    @MainActor
    private final class Output {
        private let engine = AVAudioEngine()
        private let clickNode = AVAudioPlayerNode()
        private let clickPitch = AVAudioUnitVarispeed()
        private let shutterNode = AVAudioPlayerNode()
        private let trashNode = AVAudioPlayerNode()
        private var buffers: [SoundCue: AVAudioPCMBuffer] = [:]
        private var built = false

        private func build() {
            guard !built else { return }
            built = true
            #if os(iOS)
            // `ambient`: переключатель «Без звука» гасит, чужая музыка не прерывается.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, mode: .default, options: [])
            try? session.setActive(true)
            #endif
            for cue in SoundCue.allCases {
                guard let url = Bundle.module.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Sound")
                    ?? Bundle.module.url(forResource: cue.rawValue, withExtension: "wav"),
                      let file = try? AVAudioFile(forReading: url),
                      let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                 frameCapacity: AVAudioFrameCount(file.length)),
                      (try? file.read(into: buf)) != nil
                else { continue }
                buffers[cue] = buf
            }
            engine.attach(clickNode); engine.attach(clickPitch); engine.attach(shutterNode); engine.attach(trashNode)
            // Подключение — по формату сэмпла: узел знает его до первого буфера. Тон щелчка идёт через
            // varispeed — он, как `playbackRate` беты, двигает тон и длину вместе.
            if let f = buffers[.click]?.format {
                engine.connect(clickNode, to: clickPitch, format: f)
                engine.connect(clickPitch, to: engine.mainMixerNode, format: f)
            }
            if let f = buffers[.shutter]?.format {
                engine.connect(shutterNode, to: engine.mainMixerNode, format: f)
            }
            if let f = buffers[.trash]?.format {
                engine.connect(trashNode, to: engine.mainMixerNode, format: f)
            }
            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.restart() }
            }
            engine.prepare()
        }

        private func restart() {
            guard !engine.isRunning else { return }
            try? engine.start()
        }

        func prepare() {
            build()
            restart()
        }

        func play(_ cue: SoundCue, gain: Float, rate: Float) {
            prepare()
            guard let buf = buffers[cue], engine.isRunning else { return }
            let node: AVAudioPlayerNode
            switch cue {
            case .click: node = clickNode
            case .shutter: node = shutterNode
            case .trash: node = trashNode
            }
            if cue == .click { clickPitch.rate = rate }
            node.volume = gain
            // `.interrupts`: быстрый ряд щелчков не копится в очереди — каждый обрывает хвост предыдущего.
            node.scheduleBuffer(buf, at: nil, options: .interrupts)
            if !node.isPlaying { node.play() }
        }
    }

    // MARK: - Журнал для тестов

    #if DEBUG
    /// Последние воспроизведения (до 400): тесты читают, приложение не трогает.
    private(set) static var journal: [SoundPlay] = []
    static func resetJournal() { journal.removeAll() }
    #endif
}

/// Журнал звуков (Debug, `-LPSoundLog <файл>`; имя без «/» — файл в `Documents`): строка на воспроизведение —
/// время, событие, звук, gain, rate. На симуляторе слуха нет — меряем журнал.
enum SoundLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPSoundLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    #endif
    @MainActor static func note(_ p: SoundPlay) {
        #if DEBUG
        SoundCenter.noteForTests(p)
        guard let url else { return }
        let line = String(format: "%.3f %@ %@ gain=%.5f rate=%.5f\n", ProcessInfo.processInfo.systemUptime,
                          p.event, p.cue.rawValue, p.gain, p.rate)
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}

#if DEBUG
extension SoundCenter {
    fileprivate static func noteForTests(_ p: SoundPlay) {
        journal.append(p)
        if journal.count > 400 { journal.removeFirst(journal.count - 400) }
    }
}
#endif
