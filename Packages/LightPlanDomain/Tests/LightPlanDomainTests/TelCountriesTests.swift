import Foundation
import Testing
import LightPlanDomain

/// Все страны мира (30ж.2, Алексей 06.11: «Любой мобильный номер должен учитываться»): 27 строк веба как были,
/// остальные — из данных Google libphonenumber. Номера — примеры Google (вымышленные), не настоящие.
@Suite struct TelCountriesTests {

    /// Мобильный и городской по примерам Google, по одной стране из каждой части света вне 27 веба.
    static let world: [(iso: String, mobile: String, landline: String)] = [
        ("AU", "412 345 678", "2 1234 5678"),      // Океания
        ("ZA", "71 123 4567", "10 123 4567"),      // Африка
        ("AR", "9 11 2345-6789", "11 2345-6789"),  // Южная Америка
        ("VN", "912 345 678", "210 123 4567"),     // Азия
        ("FI", "41 2345678", "13 1234567"),        // Европа
        ("PR", "787-234-5678", ""),                // Карибы, общий код +1
    ]

    @Test func tableHasEveryCountryOnceAndWebFirst() {
        #expect(Array(TelCountry.all.prefix(27)) == TelCountry.web)
        #expect(Set(TelCountry.all.map(\.iso)).count == TelCountry.all.count)
        #expect(TelCountry.googleTag == "v9.0.42")
        for iso in ["AU", "ZA", "AR", "VN", "FI", "PR", "NG", "EG", "KR", "CO", "SE", "CH", "NZ", "XK"] {
            #expect(TelCountry.of(iso) != nil, "\(iso)")
        }
        #expect(TelCountry.of("RU") == TelCountry.fallback)
    }

    /// Каждое правило мобильного собирается и принимает свой пример; пример встаёт в поле и даёт ID.
    @Test func everyMobileRuleCompilesAndTakesItsExample() {
        var bad: [String] = []
        for c in TelCountry.all {
            if (try? NSRegularExpression(pattern: c.mobile)) == nil { bad.append("\(c.iso): образец не собирается"); continue }
            let stored = TelFormat.join(national: c.example, country: c)
            if TelFormat.appId(stored, country: c) != "id" + c.cc + c.example { bad.append("\(c.iso): \(stored) без ID") }
            if TelFormat.digits(TelFormat.national(of: stored, country: c)) != c.example { bad.append("\(c.iso): поле \(stored)") }
        }
        #expect(bad.isEmpty, "\(bad.count): \(bad.prefix(8))")
    }

    @Test func aMobileOfEveryPartOfTheWorldOpensThePlanner() {
        for w in Self.world {
            let c = TelCountry.of(w.iso)!
            let stored = TelFormat.join(national: w.mobile, country: c)
            #expect(TelFormat.opensPlanner(stored, country: c), "\(w.iso) \(stored)")
            #expect(TelFormat.appId(stored, country: c) == "id" + c.cc + TelFormat.digits(w.mobile), "\(w.iso)")
            // Поле показывает номер по виду страны, как его пишет Google.
            #expect(TelFormat.national(of: stored, country: c) == w.mobile, "\(w.iso) \(stored)")
        }
    }

    @Test func aLandlineAndAFragmentAreRefused() {
        for w in Self.world where !w.landline.isEmpty {
            let c = TelCountry.of(w.iso)!
            let city = TelFormat.join(national: w.landline, country: c)
            #expect(!TelFormat.opensPlanner(city, country: c), "\(w.iso) городской \(city)")
            let cut = TelFormat.join(national: String(TelFormat.digits(w.mobile).prefix(3)), country: c)
            #expect(!TelFormat.opensPlanner(cut, country: c), "\(w.iso) обрывок \(cut)")
        }
    }

    /// Где Google не отличает мобильный от городского (США, Канада, Пуэрто-Рико …), номер принимается, как у США.
    @Test func fixedOrMobileCountriesTakeAnyNumberLikeTheUS() {
        let pr = TelCountry.of("PR")!, us = TelCountry.of("US")!
        #expect(TelFormat.opensPlanner("+1 787-234-5678", country: pr))
        #expect(TelFormat.opensPlanner("+1 212 555-0123", country: us))
        #expect(!TelFormat.opensPlanner("+1 787-234", country: pr), "обрывок")
    }

    /// Номер с «+» знает свою страну: все подошедшие — одного кода, первая — та, что разбор поставит в блок кода.
    @Test func aNumberWithPlusNamesOneCountryCode() {
        var bad: [String] = []
        for c in TelCountry.all {
            let raw = "+" + c.cc + c.example
            let fit = TelFormat.countriesFitting(raw)
            if !fit.contains(c) || Set(fit.map(\.cc)) != [c.cc] { bad.append("\(c.iso): \(fit.map(\.iso))") }
            let r = TelFormat.natIn(raw, country: TelCountry.of("RU")!)
            if c.cc != "7", r.country?.cc != c.cc || r.national != c.example { bad.append("\(c.iso): поле \(String(describing: r.country?.iso)) \(r.national)") }
        }
        #expect(bad.isEmpty, "\(bad.count): \(bad.prefix(8))")
        // Вставка из российского приложения переставляет блок кода; общий код — главная страна кода.
        #expect(TelFormat.natIn("+61 412 345 678", country: TelCountry.of("RU")!).country?.iso == "AU")
        #expect(TelFormat.countriesFitting("+61 412 345 678").first?.iso == "AU")
        #expect(TelFormat.countriesFitting("+358 41 2345678").first?.iso == "FI")
    }

    /// Без «+» цифры не уводят в чужую страну: отвечают только 27 стран веба, как было до 30ж.2.
    @Test func digitsWithoutPlusDoNotLeadARussianUserAbroad() {
        for raw in ["8 916 123-45-67", "9161234567", "79161234567", "89161234567"] {
            let fit = TelFormat.countriesFitting(raw)
            #expect(fit.contains(TelCountry.of("RU")!), "\(raw): \(fit.map(\.iso))")
            #expect(fit.allSatisfy(TelCountry.web.contains), "\(raw): \(fit.map(\.iso))")
        }
        var abroad: [String] = []
        for c in TelCountry.all.dropFirst(27) {
            for raw in [c.example, c.trunk + c.example, c.cc + c.example] {
                let fit = TelFormat.countriesFitting(raw)
                if !fit.allSatisfy(TelCountry.web.contains) { abroad.append("\(c.iso) «\(raw)»: \(fit.map(\.iso))") }
            }
        }
        #expect(abroad.isEmpty, "\(abroad.count): \(abroad.prefix(8))")
        #expect(TelFormat.countriesFitting("8 701 123-45-67").map(\.iso) == ["KZ"], "казахстанский по-прежнему узнаётся")
    }

    /// Догадка по поясу для стран веба та же; новые страны — по региону, как все.
    @Test func zoneGuessIsTheWebOne() {
        let cases: [(String, String?, String)] = [
            ("Europe/Moscow", nil, "RU"), ("Asia/Tomsk", "AU", "RU"), ("Asia/Vladivostok", "US", "RU"), ("Europe/Kaliningrad", "DE", "RU"), ("Asia/Almaty", nil, "KZ"), ("Europe/Minsk", nil, "BY"),
            ("Europe/Kyiv", nil, "UA"), ("Asia/Tashkent", nil, "UZ"), ("Europe/London", nil, "GB"), ("Atlantic/Canary", nil, "ES"),
            ("America/Toronto", nil, "CA"), ("America/Chicago", nil, "US"), ("America/Sao_Paulo", nil, "BR"),
            ("Asia/Calcutta", nil, "IN"), ("Asia/Tokyo", nil, "JP"), ("Europe/Moscow", "AU", "RU"),
            ("Australia/Sydney", nil, "RU"), ("Australia/Sydney", "AU", "AU"), ("Africa/Johannesburg", "ZA", "ZA"),
            ("America/Bogota", "CO", "US"), ("Europe/Helsinki", "XX", "RU"),
        ]
        for (zone, region, iso) in cases {
            #expect(TelCountry.guess(zoneId: zone, region: region).iso == iso, "\(zone) \(region ?? "-")")
        }
    }

    /// Время разбора: число в отчёт; граница щедрая, чтобы не мигать на загруженной машине.
    @Test func parsingStaysCheap() {
        let n = 2000
        let raws = ["+1 787-234-5678", "+61 412 345 678", "8 916 123-45-67", "+44 7911 123456"]
        _ = TelFormat.countriesFitting(raws[0])
        let t0 = Date()
        for i in 0..<n { _ = TelFormat.countriesFitting(raws[i % raws.count]) }
        let fit = Date().timeIntervalSince(t0) / Double(n) * 1e6
        let ru = TelCountry.of("RU")!
        let t1 = Date()
        for i in 0..<n { _ = TelFormat.opensPlanner(raws[i % raws.count], country: ru) }
        let gate = Date().timeIntervalSince(t1) / Double(n) * 1e6
        print("tel-timing countriesFitting \(Int(fit)) µs, opensPlanner \(Int(gate)) µs (среднее из \(n))")
        #expect(fit < 5000 && gate < 1000)
    }
}
