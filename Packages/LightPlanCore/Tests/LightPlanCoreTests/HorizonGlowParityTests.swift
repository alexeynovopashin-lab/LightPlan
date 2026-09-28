import Foundation
import Testing
@testable import LightPlanCore

/// Зарево у горизонта купола против веба. Ожидания сняты прогоном
/// `skyPalette` и хвоста `renderToday` из `beta/index.html` в node
/// (28.09.2026): три неба — яркий закат, серый, свинец.
struct HorizonGlowParityTests {
    static func day(_ sunset: Int, low: Double, mid: Double, high: Double, hum: Double) -> WeatherDay {
        let hour = HourRecord(cloud: 0, code: 0, temperature: 10, low: low, mid: mid, high: high,
                              humidity: hum, windSpeed: 0, windDirection: nil, windGusts: nil)
        return WeatherDay(quality: .good, cloud: 0, sunset: sunset, layers: hour, temperatureBase: 10,
                          wind: 0, windDirection: nil, gust: 0, trend: [], real: true)
    }
    static let bright = day(80, low: 10, mid: 40, high: 50, hum: 60)
    static let grey = day(40, low: 50, mid: 20, high: 10, hum: 90)
    static let lead = day(5, low: 90, mid: 0, high: 0, hum: 95)

    @Test func paletteMatchesWeb() throws {
        let p = try #require(SkyPalette(weather: Self.bright))
        #expect(p.zenith == SkyColor(66, 70, 86))
        #expect(p.high == SkyColor(179, 115, 133))
        #expect(p.mid == SkyColor(169, 106, 83))
        #expect(p.horizon == SkyColor(214, 174, 113))
        #expect(abs(p.life - 0.7885714285714286) < 1e-12)
        #expect(try #require(SkyPalette(weather: Self.grey)).horizon == SkyColor(107, 102, 98))
        let dead = try #require(SkyPalette(weather: Self.lead))
        #expect(dead.horizon == SkyColor(92, 92, 96))
        #expect(dead.life == 0)
    }

    @Test func noForecastNoPalette() {
        #expect(SkyPalette(weather: nil) == nil)
        let noScore = WeatherDay(quality: .good, cloud: 0, sunset: nil, layers: nil, temperatureBase: 10,
                                 wind: 0, windDirection: nil, gust: 0, trend: [], real: true)
        #expect(SkyPalette(weather: noScore) == nil)
    }

    /// Без прогноза центр зарева — ровно `glow` состояния. Порт купола
    /// домножал его ещё на 0.32 (у веба это исходное значение стопа, которое
    /// код перезаписывает): золотой час давал 0.11 вместо 0.34.
    @Test func glowWithoutForecastIsStateGlow() {
        let golden = LightState(elevation: 2, morning: false)
        let dark = HorizonGlow.paint(state: golden, elevation: 2, palette: nil, moon: false, lightTheme: false)
        #expect(dark.opacity == 0.34)
        #expect(dark.color == golden.color)
        let light = HorizonGlow.paint(state: golden, elevation: 2, palette: nil, moon: false, lightTheme: true)
        #expect(light.opacity == 0.14)
    }

    @Test func glowTintedByForecast() {
        let golden = LightState(elevation: 2, morning: false)
        func g(_ w: WeatherDay, _ state: LightState, _ e: Double, light: Bool = false) -> (SkyColor, Double) {
            let r = HorizonGlow.paint(state: state, elevation: e, palette: SkyPalette(weather: w), moon: false, lightTheme: light)
            return (r.color, r.opacity)
        }
        #expect(g(Self.bright, golden, 2) == (SkyColor(222, 167, 88), 0.35))
        #expect(g(Self.bright, golden, 2, light: true) == (SkyColor(222, 167, 88), 0.15))
        #expect(g(Self.grey, golden, 2) == (SkyColor(188, 144, 83), 0.15))
        #expect(g(Self.lead, golden, 2) == (SkyColor(183, 141, 82), 0.12))

        let dusk = LightState(elevation: -3, morning: false)
        #expect(dusk.color == SkyColor(208, 94, 99))
        #expect(g(Self.bright, dusk, -3) == (SkyColor(212, 141, 107), 0.29))
        #expect(g(Self.grey, dusk, -3) == (SkyColor(148, 99, 98), 0.12))
        #expect(g(Self.lead, dusk, -3, light: true) == (SkyColor(140, 93, 97), 0.04))
    }

    /// Высоко в небе и в лунном режиме палитра не действует.
    @Test func paletteOnlyNearHorizonAndBySun() {
        let noon = LightState(elevation: 30, morning: false)
        let high = HorizonGlow.paint(state: noon, elevation: 30, palette: SkyPalette(weather: Self.bright),
                                     moon: false, lightTheme: false)
        #expect(high.color == noon.color && high.opacity == 0.08)
        let golden = LightState(elevation: 2, morning: false)
        let moon = HorizonGlow.paint(state: golden, elevation: 2, palette: SkyPalette(weather: Self.bright),
                                     moon: true, lightTheme: false)
        #expect(moon.color == golden.color && moon.opacity == 0.34)
    }
}
