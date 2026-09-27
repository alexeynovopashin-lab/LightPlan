import Foundation
import Testing
@testable import LightPlanData

/// Ответ шлюза студии на «Связать с бронью» (веб `#fLinkRow`).
@Suite struct BookingMatchTests {
    @Test func matchCarriesRefHallAndHours() {
        let j = #"{"match":true,"bookingRef":"B9","hallId":"h1","start":"15:10","end":"17:00"}"#
        #expect(HTTPBookingMatch.answer(Data(j.utf8)) == BookingAnswer(ref: "B9", hallId: "h1", start: "15:10", end: "17:00"))
    }

    @Test func noMatchOrGarbageIsNil() {
        #expect(HTTPBookingMatch.answer(Data(#"{"match":false}"#.utf8)) == nil)
        #expect(HTTPBookingMatch.answer(Data("oops".utf8)) == nil)
    }
}
