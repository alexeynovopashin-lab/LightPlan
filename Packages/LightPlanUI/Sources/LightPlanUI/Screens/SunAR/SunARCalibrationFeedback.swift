import Foundation
#if os(iOS)
import UIKit
import AudioToolbox
#endif

/// Отклик калибровки (шаг 29.8в.8а): щелчок на процент шкалы и сигнал «движение закончено». Когда отдавать —
/// решает `CalibrationPacer` (ядро); здесь только как. Слой отдачи приложения (`Haptics`, `HapticEvent`) не трогаем:
/// его перечень сверяется с бетой, а у калибровки беты нет.
@MainActor
protocol CalibrationFeedback: AnyObject {
    /// Прогреть движок до первого щелчка.
    func prepare()
    /// Шкала прибавила процент.
    func tick()
    /// Движение закончено: звук и короткая вибрация.
    func completed()
}

/// Тишина: Mac, тесты без записи.
@MainActor
final class SilentCalibrationFeedback: CalibrationFeedback {
    func prepare() {}
    func tick() {}
    func completed() {}
}

#if os(iOS)
/// Живой отклик. Щелчок — один лёгкий транзиент (`UIImpactFeedbackGenerator.light`, сила 0,7): один транзиент
/// ощущается щелчком, а не гудением. Конец — системное «успех» (`UINotificationFeedbackGenerator.success`, короткая
/// двойная отдача) и системный звук. Журнал отдачи (`-LPHapticLog`) видит и то, и другое.
///
/// Звук идёт через `AudioServicesPlaySystemSound`: подчиняется переключателю «Без звука» и не прерывает музыку.
/// Тумблер «Щелчки слайдера» его не гасит: он про щелчки слайдера, а этот сигнал — сообщение «хватит водить».
@MainActor
final class DeviceCalibrationFeedback: CalibrationFeedback {
    private let tickGenerator = UIImpactFeedbackGenerator(style: .light)
    private let doneGenerator = UINotificationFeedbackGenerator()

    func prepare() {
        tickGenerator.prepare()
        doneGenerator.prepare()
    }

    func tick() {
        HapticsLog.note("calib.tick light 0.7")
        tickGenerator.impactOccurred(intensity: 0.7)
        tickGenerator.prepare()
    }

    func completed() {
        HapticsLog.note("calib.done success")
        doneGenerator.notificationOccurred(.success)
        doneGenerator.prepare()
        Self.chime()
    }

    /// Системные файлы по порядку предпочтения («сканирование завершено», «подтверждение»); нет ни одного на этой
    /// версии iOS — системный номер 1054 («SIMToolkitPositiveACK»). Грузится один раз.
    private static let chimeID: SystemSoundID = {
        let dir = "/System/Library/Audio/UISounds/"
        for name in ["access_scan_complete.caf", "jbl_confirm.caf", "SIMToolkitPositiveACK.caf"] {
            let url = URL(fileURLWithPath: dir + name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError { return id }
        }
        return 1054
    }()

    private static func chime() { AudioServicesPlaySystemSound(chimeID) }
}
#endif
