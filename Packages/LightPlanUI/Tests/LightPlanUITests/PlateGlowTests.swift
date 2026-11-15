import Foundation
import Testing
import LightPlanCore
@testable import LightPlanUI

/// 30з.3: свет из-под верхней кромки первой плашки «Света» — только пока солнце под горизонтом, цвет и сила по небу (`DomeSky`).
struct PlateGlowTests {
    private func sky(_ e: Double, light: Bool, palette: SkyPalette?) -> DomeSky {
        DomeSky(astro: true, elevation: e, morning: false, lightTheme: light, palette: palette)!
    }

    private func palette(score: Int) -> SkyPalette {
        let hour = HourRecord(cloud: 0, code: 0, temperature: 10, low: 5, mid: 40, high: 50,
                              humidity: 60, windSpeed: 0, windDirection: nil, windGusts: nil)
        return SkyPalette(weather: WeatherDay(quality: .good, cloud: 0, sunset: score, layers: hour,
                          temperatureBase: 10, wind: 0, windDirection: nil, gust: 0, trend: [], real: true))!
    }

    private func glow(_ e: Double, light: Bool, palette p: SkyPalette?) -> PlateGlowSpec? {
        PlateGlowSpec.make(sky: sky(e, light: light, palette: p), elevation: e, centre: 0.5, lightTheme: light)
    }

    @Test func noGlowWhileTheSunIsUp() {
        for light in [false, true] {
            for p in [nil, palette(score: 5), palette(score: 90)] {
                for e in stride(from: 0.0, through: 90, by: 1) {
                    #expect(glow(e, light: light, palette: p) == nil, "e=\(e) light=\(light)")
                }
            }
        }
        #expect(PlateGlowSpec.make(sky: nil, elevation: -5, centre: 0.5) == nil)
        #expect(PlateGlowSpec.make(sky: sky(-5, light: false, palette: nil), elevation: .nan, centre: 0.5) == nil)
    }

    @Test func glowComesWithTheSunUnderTheHorizon() {
        for light in [false, true] {
            #expect(glow(-0.3, light: light, palette: palette(score: 90))!.peak < glow(-2, light: light, palette: palette(score: 90))!.peak)
            for e in [-2.0, -4, -6, -9.5, -13] {
                let g = glow(e, light: light, palette: palette(score: 90))
                #expect(g != nil, "e=\(e) light=\(light)")
                #expect(g!.peak > 0 && g!.peak <= (light ? PlateGlowSpec.lightCap : PlateGlowSpec.peakCap))
            }
        }
    }

    /// Астрономическая ночь: зарево неба погасло (`DomeSky.glowOpacity` → 0 к −18°) — и света из-под плашки нет.
    @Test func noGlowAtAstronomicalNight() {
        for light in [false, true] {
            for e in [-18.0, -22, -30, -60] {
                #expect(glow(e, light: light, palette: palette(score: 90)) == nil, "e=\(e)")
            }
        }
    }

    /// «Цвет и сила по состоянию неба, не постоянный янтарь»: серый закат слабее и серее яркого, цвет — зарево неба.
    @Test func strengthAndColourFollowTheSky() {
        for light in [false, true] {
            for e in [-2.0, -5, -9.5] {
                let bright = glow(e, light: light, palette: palette(score: 95))!
                let lead = glow(e, light: light, palette: palette(score: 2))!
                #expect(lead.peak < bright.peak, "e=\(e) light=\(light)")
                #expect(lead.color != bright.color, "e=\(e) light=\(light)")
                if !light { #expect(bright.color == sky(e, light: light, palette: palette(score: 95)).glowColor) }
            }
        }
        // Без прогноза — цвет ступени высоты солнца, а не одно значение на все моменты.
        let a = glow(-2, light: false, palette: nil)!, b = glow(-9.5, light: false, palette: nil)!
        #expect(a.color != b.color)
    }

    /// Светлая тема: свет — не тень. Цвет света не темнее плашки больше чем на пятую часть яркости, непрозрачность в пределах потолка.
    @Test func lightThemeGlowIsNotAShadow() {
        for score in [2, 50, 95] {
            for e in [-2.0, -5, -9.5, -13] {
                let g = glow(e, light: true, palette: palette(score: score))!
                #expect(DomeSky.luminance(g.color) >= PlateGlowSpec.plateLuminanceLight * PlateGlowSpec.lightFloor - 0.01, "e=\(e) s=\(score)")
                #expect(g.peak <= PlateGlowSpec.lightCap)
            }
        }
        // Оранжевый закат остаётся оттенком: красный канал не ниже зелёного и синего.
        let warm = PlateGlowSpec.lifted(SkyColor(214, 83, 58), toLuminance: 0.71)
        #expect(warm.r >= warm.g && warm.g >= warm.b)
    }

    /// Пик макета — 0,33 при плотности зарева 0,156 (чистое небо, глубокие сумерки), и выше 0,55 свет не поднимается.
    @Test func calibratedOnTheMock() {
        let k = PlateGlowSpec.k
        #expect(abs(PlateGlowSpec.peakCap * (1 - exp(-k * PlateGlowSpec.mockGlow)) - PlateGlowSpec.peakMock) < 1e-9)
        #expect(PlateGlowSpec.peakCap * (1 - exp(-k * 100)) <= PlateGlowSpec.peakCap)
    }

    @Test func centreFollowsTheSunAndStaysOnThePlate() {
        let s = sky(-5, light: false, palette: nil)
        #expect(PlateGlowSpec.make(sky: s, elevation: -5, centre: -3)!.centre == 0)
        #expect(PlateGlowSpec.make(sky: s, elevation: -5, centre: 3)!.centre == 1)
        #expect(PlateGlowSpec.make(sky: s, elevation: -5, centre: 0.8)!.centre == 0.8)
    }

    /// Профили макета: полный свет на кромке, ноль к 80 pt; никогда не растёт вглубь и от центра.
    @Test func profilesFadeFromTheEdge() {
        #expect(PlateGlowSpec.sample(PlateGlowSpec.vertical, 0) == 1)
        #expect(PlateGlowSpec.sample(PlateGlowSpec.vertical, Double(PlateGlowSpec.reach)) == 0)
        #expect(PlateGlowSpec.sample(PlateGlowSpec.horizontal, 0) == 1)
        #expect(PlateGlowSpec.sample(PlateGlowSpec.horizontal, 0.7) == 0)
        var last = 1.0
        for i in 0...160 {
            let a = PlateGlowSpec.sample(PlateGlowSpec.vertical, Double(i) / 2)
            #expect(a <= last + 1e-12); last = a
        }
        last = 1.0
        for i in 0...100 {
            let a = PlateGlowSpec.sample(PlateGlowSpec.horizontal, Double(i) / 100)
            #expect(a <= last + 1e-12); last = a
        }
        // Симметрия вокруг центра.
        #expect(PlateGlowSpec.sample(PlateGlowSpec.horizontal, -0.23) == PlateGlowSpec.sample(PlateGlowSpec.horizontal, 0.23))
    }
}
