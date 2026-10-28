import Testing
import Foundation

/// Курсив из календаря ушёл (Алексей 28.10: «не смог к нему привыкнуть»): занятость в клетке месяца отличается цветом
/// (`ink4`, без цветной точки погоды), а не наклоном. Пересмотр записи «Курсив ушёл из ленты, но остался в клетке месяца».
struct MonthLabelsNoItalicTests {
    @Test func plannerScreensDrawNoItalic() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LightPlanUI/Screens/Planner")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            #expect(!text.contains(".italic("), "\(f.lastPathComponent) рисует курсив")
        }
    }
}
