import Testing
import SwiftUI
@testable import LightPlanUI

/// `PATH_STOPS`/`stopAt` веба — цвет рельса по высоте светила (итерация 19б).
/// Ожидания посчитаны рукой по таблице веба и его `Math.round`.
struct PathStopsTests {
    @Test func goldenBandIsFlatBrass() {
        for alt in [6.0, 3.0, 0.0] {
            let s = PathStops.at(alt)
            #expect(s.rgb == (226, 164, 76))
            #expect(abs(s.a - 0.95) < 1e-12)
        }
    }

    @Test func blueTurnIsInterpolated() {
        // −5° — середина между −4° (150,110,170 · 0,88) и −6° (124,156,196 · 0,85).
        let s = PathStops.at(-5)
        #expect(s.rgb == (137, 133, 183))
        #expect(abs(s.a - 0.865) < 1e-12)
        #expect(abs(s.w - 3.0) < 1e-12)
    }

    @Test func endsClampToTable() {
        #expect(PathStops.at(95).rgb == (138, 132, 120))
        #expect(PathStops.at(-40).rgb == (40, 54, 92))
        #expect(abs(PathStops.at(-40).a - 0.28) < 1e-12)
    }

    /// Половина канала округляется вверх, как `Math.round`: между 20° и 6°
    /// на 13° каналы 176→226 дают 201.
    @Test func roundsHalfUpLikeJavaScript() {
        #expect(PathStops.at(13).rgb.0 == 201)
    }
}
