import SwiftUI

/// Один экран: холст во весь кадр, прибор поверх, три переключателя сверху.
/// Снимки для решения — два пути × две темы × город и природа.
struct SpikeScreen: View {
    @State private var path: CanvasPath = .mapLibre
    @State private var dark = true
    @State private var place: Place = .city
    /// Час всемирного времени: светило ведут пальцем по пути, чтобы видеть,
    /// читается ли путь над застройкой и над лесом.
    @State private var hourUTC: Double = 6
    /// Приглушённый вид MapKit. У MapLibre ручки нет — там весь стиль наш.
    @State private var muted = true

    var body: some View {
        ZStack(alignment: .top) {
            canvas
                .ignoresSafeArea()
            InstrumentOverlay(lat: place.lat, lon: place.lon, dark: dark, hourUTC: hourUTC)
                .ignoresSafeArea()
            controls
        }
        .preferredColorScheme(dark ? .dark : .light)
    }

    @ViewBuilder private var canvas: some View {
        switch path {
        case .mapKit: MapKitCanvas(place: place, dark: dark, muted: muted)
        case .mapLibre: MapLibreCanvas(place: place, dark: dark)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Путь", selection: $path) {
                ForEach(CanvasPath.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                Picker("Место", selection: $place) {
                    ForEach(Place.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Тьма", isOn: $dark)
                    .labelsHidden()
                    .toggleStyle(.switch)
                if path == .mapKit {
                    Toggle("Тише", isOn: $muted)
                        .labelsHidden()
                        .toggleStyle(.button)
                }
            }
            Slider(value: $hourUTC, in: 0...24)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}
