import Foundation
import QuartzCore

/// Журнал драга блока карточки (27а.3, Debug): `-LPCardDragLog <файл>`. Строка на подъём, на отпускание,
/// на отмену и на смену «палец держит ручку» — по ней видно, в каком порядке приходят конец жеста и
/// сброс состояния и сколько pt прошёл палец. В Release — пустой вызов.
enum CardDragProbe {
    #if DEBUG
    private static let path = UserDefaults.standard.string(forKey: "LPCardDragLog")
    #endif

    static func log(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let path else { return }
        let data = Data(String(format: "%.3f ", CACurrentMediaTime()).utf8 + Data((line() + "\n").utf8))
        let url = URL(fileURLWithPath: path)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}
