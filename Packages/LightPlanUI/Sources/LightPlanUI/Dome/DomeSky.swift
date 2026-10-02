import Foundation
import LightPlanCore

/// Presentation palette for the Astro dome, approved on 28 September 2026.
/// Solar elevation controls twilight depth; these are art-directed UI colours,
/// not a replacement for the physical light-state palette in Core.
struct DomeSky: Sendable, Equatable {
    let zenith: SkyColor
    let horizon: SkyColor
    let forecast: SkyPalette?
    let forecastOpacity: Double
    let glowColor: SkyColor
    let glowOpacity: Double

    init?(astro: Bool, elevation e: Degrees, morning: Bool, lightTheme: Bool, palette: SkyPalette?,
          moon: Bool = false) {
        guard astro, e.isFinite else { return nil }
        let stops = Self.stops
        var lower = stops[0], upper = stops[0]
        for stop in stops.dropFirst() {
            upper = stop
            if e <= stop.e { break }
            lower = stop
        }
        let k = upper.e == lower.e ? 0 : Self.clamp((e - lower.e) / (upper.e - lower.e))
        let a = lightTheme ? lower.light : lower.dark
        let b = lightTheme ? upper.light : upper.dark
        zenith = LightPalette.lerp(a.0, b.0, k)
        horizon = LightPalette.lerp(a.1, b.1, k)
        forecast = morning ? nil : palette
        let colourStart = lightTheme ? 6.0 : 12.0
        forecastOpacity = forecast == nil ? 0 : Self.clamp((colourStart - e) / colourStart) * Self.clamp((e + 12) / 8) * 0.62

        let state = LightState(elevation: e, morning: morning)
        let near = Self.clamp((8 - e) / 14)
        // Like `HorizonGlow.paint`: the forecast tints only the sun's glow, not the moon's.
        let pal = e < 8 && !moon ? forecast : nil
        glowColor = pal.map { LightPalette.lerp(state.color, $0.horizon, near * 0.75) } ?? state.color
        let themeGain = lightTheme ? 0.65 + 0.35 * Self.clamp((6 - e) / 12) : 1
        // Astronomical night is the screen's backing in both themes (28е). Fade the
        // residual horizon glow too, otherwise it still paints a patch over it.
        let nightFade = Self.clamp((e + 18) / 6)
        glowOpacity = state.glow * (pal.map { 0.35 + $0.life * 0.85 } ?? 1) * themeGain * nightFade
    }

    /// Centre-line sample of the same gradient and elliptical forecast mask as Canvas.
    func background(at fraction: Double) -> SkyColor {
        let k = Self.clamp(fraction)
        let base = LightPalette.lerp(zenith, horizon, k)
        guard let forecast, forecastOpacity > 0 else { return base }
        let stops: [(Double, SkyColor)] = [(0, forecast.zenith), (0.38, forecast.high),
                                          (0.72, forecast.mid), (1, forecast.horizon)]
        var colour = forecast.horizon
        for i in 1..<stops.count where k <= stops[i].0 {
            let a = stops[i - 1], b = stops[i]
            colour = LightPalette.lerp(a.1, b.1, (k - a.0) / (b.0 - a.0))
            break
        }
        let mask = Self.clamp((1 - (1 - k) * 148 / 158) / 0.65)
        return LightPalette.lerp(base, colour, forecastOpacity * mask)
    }

    /// Each readout row sits at a different height in the gradient. Black/white
    /// keeps the centre-line contrast >= 4.5 even during the twilight crossover.
    func ink(at fraction: Double) -> SkyColor {
        let l = Self.luminance(background(at: fraction))
        return (l + 0.05) / 0.05 >= 1.05 / (l + 0.05) ? SkyColor(0, 0, 0) : SkyColor(255, 255, 255)
    }

    static func luminance(_ c: SkyColor) -> Double {
        func linear(_ channel: Int) -> Double {
            let x = Double(channel) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// The screen's backing around the dome (`--surface` of the web: #0F0E0C dark,
    /// #FAF8F3 light, what `DomeView.surfaceColor` paints). The web paints no sky in
    /// Astro, so at night its dome inside IS this colour.
    static func surface(lightTheme: Bool) -> SkyColor {
        lightTheme ? SkyColor(250,248,243) : SkyColor(15,14,12)
    }

    /// Star and meteor ink: pale on a dark backing, deep navy on the light paper.
    static func starColor(lightTheme: Bool) -> SkyColor {
        lightTheme ? SkyColor(8,14,34) : SkyColor(203,215,234)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private struct Stop: Sendable {
        let e: Double
        let light: (SkyColor, SkyColor)
        let dark: (SkyColor, SkyColor)

        init(_ e: Double, _ light: (SkyColor, SkyColor), _ dark: (SkyColor, SkyColor), dimDark: Bool = true) {
            self.e = e
            self.light = light
            guard dimDark else { self.dark = dark; return }
            // Below the accepted sketch: “one tone darker” was ×0.85; on the phone
            // the day blue still read too bright (Alexey, 28.09). ×0.6 gives about
            // half the light of ×0.85 — close to one stop.
            func dim(_ c: SkyColor) -> SkyColor {
                SkyColor(Int((Double(c.r) * 0.6).rounded()), Int((Double(c.g) * 0.6).rounded()),
                         Int((Double(c.b) * 0.6).rounded()))
            }
            self.dark = (dim(dark.0), dim(dark.1))
        }
    }
    private static let surfaceLight = surface(lightTheme: true)
    private static let surfaceDark = surface(lightTheme: false)
    private static let stops: [Stop] = [
        // Astronomical night paints the screen's own backing (28е, Alexey 02.10: inside
        // the dome was darker than the screen). Measured before: dark (0,0,0) on
        // (15,14,12), light (19,36,67) on (250,248,243); the web paints no sky at all.
        Stop(-24, (surfaceLight, surfaceLight), (surfaceDark, surfaceDark), dimDark: false),
        Stop(-18, (surfaceLight, surfaceLight), (surfaceDark, surfaceDark), dimDark: false),
        Stop(-12, (SkyColor(38,65,110), SkyColor(68,100,141)), (SkyColor(8,16,36), SkyColor(18,30,55))),
        Stop(-6, (SkyColor(98,130,171), SkyColor(149,176,202)), (SkyColor(16,28,49), SkyColor(24,40,68))),
        Stop(0, (SkyColor(207,225,235), SkyColor(235,241,240)), (SkyColor(18,35,63), SkyColor(30,57,90))),
        Stop(6, (SkyColor(207,225,235), SkyColor(235,241,240)), (SkyColor(18,38,67), SkyColor(35,68,103))),
        Stop(40, (SkyColor(207,225,235), SkyColor(235,241,240)), (SkyColor(21,46,78), SkyColor(42,78,116)))
    ]
}
