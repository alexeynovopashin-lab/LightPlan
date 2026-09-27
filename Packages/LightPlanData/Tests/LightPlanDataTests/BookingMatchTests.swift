import Foundation
import Testing
@testable import LightPlanData

/// Ответ шлюза студии на «Связать с бронью» (веб `#fLinkRow`).
@Suite struct BookingMatchTests {
    @Test func matchCarriesRefHallAndHours() throws {
        let j = #"{"match":true,"bookingRef":"B9","hallId":"h1","start":"15:10","end":"17:00"}"#
        #expect(try HTTPBookingMatch.answer(Data(j.utf8)) == BookingAnswer(ref: "B9", hallId: "h1", start: "15:10", end: "17:00"))
    }

    @Test func noMatchIsNilButGarbageIsAFailure() throws {
        #expect(try HTTPBookingMatch.answer(Data(#"{"match":false}"#.utf8)) == nil)
        #expect(throws: (any Error).self) { try HTTPBookingMatch.answer(Data("oops".utf8)) }
    }
}
