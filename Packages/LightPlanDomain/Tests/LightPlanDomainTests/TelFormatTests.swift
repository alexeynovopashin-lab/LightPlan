import Foundation
import Testing
import LightPlanDomain

/// Телефон сверяется с вебом строка в строку: `Fixtures/tel.json` собирает
/// `Tools/parity/tel.js` (`make tel`), вырезая разбор номера из `beta/index.html`.
@Suite struct TelFormatTests {
    struct Row: Decodable { let c: String, v: String, f: String, p: String, full: String, mob: Bool, id: String }
    struct File: Decodable { let rows: [Row] }

    static let rows: [Row] = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let url = u.appendingPathComponent("Fixtures/tel.json")
        do { return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).rows }
        catch { fatalError("нет \(url.path): \(error). Собрать: make tel") }
    }()

    @Test func matchesWebOnEveryRow() {
        var bad: [String] = []
        for r in Self.rows {
            let sp = TelCountry.of(r.c)!
            let f = TelFormat.format(r.v, country: sp), p = TelFormat.format(r.v, country: sp, pasted: true)
            let full = TelFormat.full(r.v, country: sp), mob = TelFormat.isMobile(r.v, country: sp)
            let id = TelFormat.appId(r.v, country: sp)
            if f != r.f || p != r.p || full != r.full || mob != r.mob || id != r.id {
                bad.append("\(r.c) «\(r.v)»: web \(r.f)|\(r.p)|\(r.full)|\(r.mob)|\(r.id) swift \(f)|\(p)|\(full)|\(mob)|\(id)")
            }
        }
        #expect(bad.isEmpty, "\(bad.count) из \(Self.rows.count): \(bad.prefix(8))")
    }

    @Test func countriesCount() { #expect(TelCountry.all.count == 27) }

    @Test func iosAutofillDigitByDigit() {
        // Номер приходит по цифре без +7: на десятой цифре возвращается ведущая часть.
        let ru = TelCountry.of("RU")!
        var text = "", prev = 0
        for ch in "9618878078" {
            text = TelFormat.typed(text + String(ch), previousDigits: prev, country: ru)
            prev = text.filter(\.isNumber).count
        }
        #expect(text == "8 961 887-80-78")
    }
}
