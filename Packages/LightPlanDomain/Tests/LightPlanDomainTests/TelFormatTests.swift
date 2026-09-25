import Foundation
import Testing
import LightPlanDomain

/// Телефон сверяется с вебом строка в строку: `Fixtures/tel.json` собирает
/// `Tools/parity/tel.js` (`make tel`), вырезая разбор номера из `beta/index.html`.
@Suite struct TelFormatTests {
    struct Row: Decodable { let c: String, v: String, f: String, p: String, full: String, mob: Bool, id: String, real: Bool, fit: [String], nat: String, join: String, `in`: NatIn }
    struct NatIn: Decodable { let cc: String?, nat: String }
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
            let fit = TelFormat.countriesFitting(r.v).map(\.iso), nat = TelFormat.national(of: r.v, country: sp)
            let join = TelFormat.join(national: r.v, country: sp), real = TelFormat.isReal(r.v, country: sp)
            let nin = TelFormat.natIn(r.v, country: sp)
            if fit != r.fit || nat != r.nat || join != r.join || real != r.real || nin.national != r.in.nat || nin.country?.iso != r.in.cc {
                bad.append("\(r.c) «\(r.v)» nat: web fit=\(r.fit) nat=\(r.nat) join=\(r.join) real=\(r.real) in=\(r.in) swift fit=\(fit) nat=\(nat) join=\(join) real=\(real) in=\(nin)")
            }
            if f != r.f || p != r.p || full != r.full || mob != r.mob || id != r.id {
                bad.append("\(r.c) «\(r.v)»: web \(r.f)|\(r.p)|\(r.full)|\(r.mob)|\(r.id) swift \(f)|\(p)|\(full)|\(mob)|\(id)")
            }
        }
        #expect(bad.isEmpty, "\(bad.count) из \(Self.rows.count): \(bad.prefix(8))")
    }

    @Test func idChain() {
        let ru = TelCountry.of("RU")!
        var (l, real) = MyIdChain.retire([], from: "8 916 111-11-11", to: "8 916 222-22-22", country: ru, at: "t1")
        #expect(real && l.map(\.was) == ["id79161111111"])
        (l, real) = MyIdChain.retire(l, from: "8 916 222-22-22", to: "8 916 333-33-33", country: ru, at: "t2")
        #expect(l.map(\.was) == ["id79161111111", "id79162222222"])
        // Вернулись к прежнему: цепочка срезается, кольца нет
        (l, real) = MyIdChain.retire(l, from: "8 916 333-33-33", to: "+7 916 111-11-11", country: ru, at: "t3")
        #expect(real && l.isEmpty)
        // Пустое поле и тот же номер иначе — не смена
        #expect(!MyIdChain.retire([], from: "8 916 111-11-11", to: "", country: ru, at: "t").real)
        #expect(!MyIdChain.retire([], from: "8 916 111-11-11", to: "+7 916 111-11-11", country: ru, at: "t").real)
        // Городской прежний номер: смена настоящая, хранить нечего
        let city = MyIdChain.retire([], from: "8 495 123-45-67", to: "8 916 111-11-11", country: ru, at: "t")
        #expect(city.real && city.list.isEmpty)
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
