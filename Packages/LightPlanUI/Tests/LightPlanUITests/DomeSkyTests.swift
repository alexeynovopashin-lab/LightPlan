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

    /// Ревью GPT к `8c8c280`: у Луны зарево без прогнозной палитры, как у
    /// `HorizonGlow.paint(moon: true)`; ночное затухание «Астро» остаётся.
    @Test func moonGlowIgnoresSunsetForecast() {
        for light in [false, true] {
            for e in stride(from: -20.0, through: 7, by: 1) {
                let moon = DomeSky(astro: true, elevation: e, morning: false, lightTheme: light, palette: bright, moon: true)!
                let plain = sky(e, light: light)
                #expect(moon.glowColor == LightState(elevation: e, morning: false).color)
                #expect(moon.glowOpacity == plain.glowOpacity)
                #expect(moon.forecastOpacity == sky(e, light: light, palette: bright).forecastOpacity)
            }
        }
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

    /// Alexey on the phone, 02.10 (28е): at night the dome's inside must match the
    /// screen's backing — measured before: black (0,0,0) on (15,14,12) in the dark
    /// theme, navy (19,36,67) on (250,248,243) in the light one. The web paints
    /// no sky at all, so its night inside IS the backing.
    @Test func nightInsideMatchesTheScreenBacking() {
        for e in [-18.0, -20, -24, -90] {
            for (light, backing) in [(true, DomeSky.surface(lightTheme: true)), (false, DomeSky.surface(lightTheme: false))] {
                let night = sky(e, light: light)
                #expect(night.zenith == backing && night.horizon == backing)
                for fraction in [0.0, 0.35, 0.63, 1] { #expect(night.background(at: fraction) == backing) }
            }
        }
        #expect(DomeSky.surface(lightTheme: false) == SkyColor(15,14,12))
        #expect(DomeSky.surface(lightTheme: true) == SkyColor(250,248,243))
        #expect(sky(6, light: false).zenith == SkyColor(11,23,40))
        // The twilight above the night keeps its approved navy.
        #expect(sky(-12).zenith == SkyColor(38,65,110))
        #expect(sky(-12, light: false).zenith == SkyColor(5,10,22))
    }

    @Test func starsStayVisibleOnTheNightBacking() {
        let opacity = DomeStars.points.map(\.opacity).max()!
        for light in [false, true] {
            let back = DomeSky.surface(lightTheme: light)
            let star = LightPalette.lerp(back, DomeSky.starColor(lightTheme: light), opacity)
            #expect((max(DomeSky.luminance(star), DomeSky.luminance(back)) + 0.05)
                    / (min(DomeSky.luminance(star), DomeSky.luminance(back)) + 0.05) > 2.5)
        }
    }

    /// Alexey on the phone, 28.09: the dark theme's day blue was still too bright
    /// after "one tone darker". It now gives about half the light of that build.
    @Test func darkThemeDayBlueIsMutedAboutOneStop() {
        let day = sky(40, light: false)
        #expect(day.zenith == SkyColor(13,28,47))
        #expect(day.horizon == SkyColor(25,47,70))
        // What fc78cbd painted at +40°, judged too bright.
        let seen = (zenith: SkyColor(18,39,66), horizon: SkyColor(36,66,99))
        for ratio in [DomeSky.luminance(day.zenith) / DomeSky.luminance(seen.zenith),
                      DomeSky.luminance(day.horizon) / DomeSky.luminance(seen.horizon)] {
            #expect(ratio > 0.45 && ratio < 0.6)
        }
        #expect(sky(40).zenith == SkyColor(207,225,235))
    }

    @Test func astronomicalNightIsTheBackingIncludingHorizonGlow() {
        for light in [false, true] {
            let backing = DomeSky.surface(lightTheme: light)
            for morning in [true, false] {
                for palette in [nil, bright] {
                    for e in stride(from: -90.0, through: -18, by: 0.5) {
                        let night = sky(e, light: light, morning: morning, palette: palette)
                        #expect(night.zenith == backing && night.horizon == backing)
                        #expect(night.forecastOpacity == 0 && night.glowOpacity == 0)
                        for fraction in [0.0, 0.5, 1] { #expect(night.background(at: fraction) == backing) }
                    }
                }
            }
        }
        #expect(sky(-18 + 0.001, light: false).glowOpacity < 0.00002)
    }

    /// The sky darkens with the sun down to -12°; from there it eases into the
    /// backing, which is not darker, so the monotone run stops at -12°.
    @Test func twilightIsContinuousAndMonotonicallyDarker() {
        for light in [true, false] {
            var previous = sky(90, light: light)
            for i in 1...1020 {
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
                #expect(month == 6 ? paint.zenith == sky(40).zenith : paint.zenith == DomeSky.surface(lightTheme: true))
            }
        }
    }
}
