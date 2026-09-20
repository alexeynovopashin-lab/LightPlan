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
    /// Замер маршрутов Apple — отдельный вопрос итерации 4: если MKDirections
    /// закрывает и машину, и тропы, путь MapKit становится дешевле вдвойне.
    @State private var probe = RouteProbe()
    @State private var showProbe = false

    var body: some View {
        ZStack(alignment: .top) {
            canvas
                .ignoresSafeArea()
            InstrumentOverlay(lat: place.lat, lon: place.lon, dark: dark, hourUTC: hourUTC)
                .ignoresSafeArea()
            controls
            if showProbe { probeSheet }
        }
        .preferredColorScheme(dark ? .dark : .light)
    }

    @ViewBuilder private var canvas: some View {
        switch path {
        case .mapKit: MapKitCanvas(place: place, dark: dark, muted: muted)
        case .mapLibre: MapLibreCanvas(place: place, dark: dark)
        }
    }

    /// Числа замера поверх холста: иначе их пришлось бы вылавливать из лога.
    private var probeSheet: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(probe.legs) { leg in
                HStack {
                    Text("\(leg.mode) · \(leg.name)").font(.system(size: 11))
                    Spacer()
                    if let km = leg.km, let min = leg.min {
                        Text(String(format: "%.1f км · %d мин", km, min))
                            .font(.system(size: 11, weight: .semibold))
                    } else {
                        Text(leg.error ?? "—").font(.system(size: 10)).foregroundStyle(.red)
                    }
                }
            }
            if !probe.running && !probe.legs.isEmpty {
                Text(String(format: "всего %.2f с на %d запросов", probe.elapsed, probe.legs.count))
                    .font(.system(size: 11)).padding(.top, 2)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 10)
        .padding(.top, 230)
        .onTapGesture { showProbe = false }
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
            Button(probe.running ? "считаю…" : "Маршруты Apple") {
                showProbe = true
                Task { await probe.run() }
            }
            .disabled(probe.running)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}
