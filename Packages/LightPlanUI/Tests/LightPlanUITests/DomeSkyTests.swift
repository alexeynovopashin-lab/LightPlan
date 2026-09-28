import Foundation
import Testing
import LightPlanCore
@testable import LightPlanUI

struct DomeSkyTests {
    private func sky(_ e: Double, light: Bool = true, morning: Bool = false, palette: SkyPalette? = nil) -> DomeSky {
        DomeSky(astro: true, elevation: e, morning: morning, lightTheme: light, palette: palette)!
    }

    private var bright: SkyPalette {
        let hour = HourRecord(cloud: 0, code: 0, temperature: 10, low: 10, mid: 40, high: 50,
                              humidity: 60, windSpeed: 0, windDirection: nil, windGusts: nil)
        return SkyPalette(weather: WeatherDay(quality: .good, cloud: 0, sunset: 80, layers: hour,
                          temperatureBase: 10, wind: 0, windDirection: nil, gust: 0, trend: [], real: true))!
    }

    @Test func ordinaryModeHasNoNewSky() {
        for light in [false, true] {
            for e in stride(from: -90.0, through: 90, by: 1) {
                #expect(DomeSky(astro: false, elevation: e, morning: false, lightTheme: light, palette: bright) == nil)
            }
        }
        #expect(DomeSky(astro: true, elevation: .nan, morning: false, lightTheme: true, palette: nil) == nil)
    }

    @Test func daylightStaysPaleIncludingSixPM() {
        for e in stride(from: 0.0, through: 90, by: 1) {
            #expect(sky(e).zenith == SkyColor(207,225,235))
            #expect(sky(e).horizon == SkyColor(235,241,240))
        }
        let sun = SolarDay(date: CivilDate(year: 2026, month: 9, day: 23), latitude: 53.35, longitude: 83.75, utcOffsetHours: 7)
        let e = sun.elevation(at: 1080)
        #expect(e > 6)
        #expect(sky(e, palette: bright).forecastOpacity == 0)
        #expect(DomeSky.luminance(sky(e).zenith) > 0.7)
        // Same civil hour in winter is not forced into the summer/day palette.
        let winter = SolarDay(date: CivilDate(year: 2026, month: 12, day: 21), latitude: 53.35, longitude: 83.75, utcOffsetHours: 7)
        #expect(DomeSky.luminance(sky(winter.elevation(at: 1080)).zenith) < 0.2)
    }

    @Test func approvedNavyNightAndDarkerDarkTheme() {
        #expect(sky(-24).zenith == SkyColor(18,35,66))
        #expect(sky(-24).horizon == SkyColor(28,50,84))
        #expect(sky(6, light: false).zenith == SkyColor(15,32,57))
        #expect(sky(-24, light: false).zenith == SkyColor(0,0,0))
        for e in [-18.0, -24, -90] {
            let light = sky(e), dark = sky(e, light: false)
            #expect(DomeSky.luminance(light.horizon) < 0.06)
            #expect(DomeSky.luminance(dark.horizon) < DomeSky.luminance(light.zenith))
            // The actual native star field stays visible without changing its opacity.
            let opacity = DomeStars.points.map(\.opacity).max()!
            let star = LightPalette.lerp(light.horizon, SkyColor(203,215,234), opacity)
            #expect((DomeSky.luminance(star) + 0.05) / (DomeSky.luminance(light.horizon) + 0.05) > 2.5)
        }
    }

    @Test func darkAstronomicalNightIsBlackIncludingHorizonGlow() {
        for morning in [true, false] {
            for palette in [nil, bright] {
                for e in stride(from: -90.0, through: -18, by: 0.5) {
                    let night = sky(e, light: false, morning: morning, palette: palette)
                    #expect(night.zenith == SkyColor(0,0,0))
                    #expect(night.horizon == SkyColor(0,0,0))
                    #expect(night.forecastOpacity == 0 && night.glowOpacity == 0)
                    for fraction in [0.0, 0.5, 1] {
                        #expect(night.background(at: fraction) == SkyColor(0,0,0))
                        #expect(night.ink(at: fraction) == SkyColor(255,255,255))
                    }
                }
            }
        }
        #expect(sky(-18 + 0.001, light: false).glowOpacity < 0.00002)
        #expect(sky(-18, light: true).glowOpacity > 0)
        #expect(sky(-24, light: true).zenith == SkyColor(18,35,66))
    }

    @Test func twilightIsContinuousAndMonotonicallyDarker() {
        for light in [true, false] {
            var previous = sky(90, light: light)
            for i in 1...1800 {
                let next = sky(90 - Double(i) / 10, light: light)
                #expect(DomeSky.luminance(next.zenith) <= DomeSky.luminance(previous.zenith))
                #expect(DomeSky.luminance(next.horizon) <= DomeSky.luminance(previous.horizon))
                previous = next
            }
            for e in [-24.0, -18, -12, -6, 0, 6, 40] {
                let a = sky(e - 0.001, light: light), b = sky(e + 0.001, light: light)
                for (x, y) in [(a.zenith,b.zenith), (a.horizon,b.horizon)] {
                    #expect(abs(x.r-y.r) <= 1 && abs(x.g-y.g) <= 1 && abs(x.b-y.b) <= 1)
                }
            }
        }
    }

    @Test func forecastColoursOnlyEveningAndFadesBeforeNight() {
        for light in [true, false] {
            for e in stride(from: -90.0, through: 90, by: 1) {
                #expect(sky(e, light: light).forecastOpacity == 0)
                let dawn = sky(e, light: light, morning: true, palette: bright)
                #expect(dawn.forecast == nil && dawn.forecastOpacity == 0)
                #expect(dawn.zenith == sky(e, light: light).zenith)
                #expect(dawn.glowColor == LightState(elevation: e, morning: true).color)
                if e <= -12 { #expect(sky(e, light: light, palette: bright).forecastOpacity == 0) }
            }
        }
        #expect(sky(6, palette: bright).forecastOpacity == 0)
        #expect(sky(0, palette: bright).forecastOpacity == 0.62)
        #expect(abs(sky(-6, palette: bright).forecastOpacity - 0.465) < 1e-12)
    }

    @Test func readoutInkFollowsEachRowsBackground() {
        for light in [true, false] {
            for palette in [nil, bright] {
                for e in stride(from: -30.0, through: 40, by: 0.1) {
                    let sky = sky(e, light: light, palette: palette)
                    for y in [0.38, 0.63, 0.76] {
                        let a = DomeSky.luminance(sky.ink(at: y)), b = DomeSky.luminance(sky.background(at: y))
                        #expect((max(a,b)+0.05)/(min(a,b)+0.05) >= 4.5)
                    }
                }
            }
        }
    }

    @Test func polarDaysUseElevationNotSunriseAvailability() {
        for month in [6,12] {
            let day = SolarDay(date: CivilDate(year: 2026, month: month, day: 21), latitude: 90, longitude: 0, utcOffsetHours: 0)
            for minute in stride(from: 0.0, through: 1440, by: 60) {
                let e = day.elevation(at: minute)
                let paint = sky(e)
                #expect(month == 6 ? paint.zenith == sky(40).zenith : DomeSky.luminance(paint.zenith) < 0.03)
            }
        }
    }
}
