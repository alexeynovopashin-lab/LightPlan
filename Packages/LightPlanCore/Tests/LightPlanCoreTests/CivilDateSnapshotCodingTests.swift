import Testing
import Foundation
@testable import LightPlanCore

/// Итерация 12, `docs/17` § 6: «день записи бывает и строкой ГГГГ-ММ-ДД, и
/// прежним моментом ISO — читать нужно оба».
struct CivilDateSnapshotCodingTests {
    @Test func plainDateString() {
        let d = CivilDate(snapshotString: "2026-09-21")
        #expect(d == CivilDate(year: 2026, month: 9, day: 21))
    }

    @Test func legacyISOInstantFallsBackToCalendarDay() {
        // Строка ISO без временнОй составляющей суток — только чтобы
        // разбор не бросил; сравнение с `dayOf` веба (браузерный пояс)
        // здесь не воспроизвести детерминированно, но парсинг не должен
        // ни бросать, ни возвращать `nil` (единственное, что натив может
        // обещать без браузера).
        let d = CivilDate(snapshotString: "2026-09-21T12:00:00.000Z")
        #expect(d != nil)
    }

    @Test func garbageStringIsNil() {
        #expect(CivilDate(snapshotString: "не дата") == nil)
        #expect(CivilDate(snapshotString: "") == nil)
    }

    @Test func snapshotStringRoundTrips() {
        let d = CivilDate(year: 2026, month: 1, day: 5)
        #expect(d.snapshotString == "2026-01-05")
        #expect(CivilDate(snapshotString: d.snapshotString) == d)
    }
}
