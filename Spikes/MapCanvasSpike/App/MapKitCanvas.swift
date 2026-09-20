import SwiftUI
import MapKit

/// Путь А: MapKit со своим `.mapStyle`. Ключей и счёта нет, карта идёт с
/// платформой. Ручек ровно четыре: вид, высотность, набор точек интереса и
/// «приглушённость» (`emphasis`). Перекрасить отдельный слой нечем — ни воды,
/// ни домов, ни магистралей: описания слоёв у MapKit нет вовсе.
struct MapKitCanvas: View {
    let place: Place
    let dark: Bool
    /// `.muted` — единственная ручка MapKit в сторону холста: подписи и цвета
    /// приглушаются. Сравнивается с `.automatic`, чтобы разница была числом.
    let muted: Bool

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera) { }
            .mapStyle(.standard(elevation: .flat,
                                emphasis: muted ? .muted : .automatic,
                                // Точки интереса выключены целиком: холст — подложка
                                // прибора, а не путеводитель (тот же довод, что у
                                // `poi_` в `mapstyle.js`).
                                pointsOfInterest: .excludingAll,
                                showsTraffic: false))
            .mapControlVisibility(.hidden)
            // Тёмный холст у MapKit получается только тёмной темой всего окна:
            // своего описания слоёв нет.
            .environment(\.colorScheme, dark ? .dark : .light)
            .onAppear { camera = .region(region) }
            .onChange(of: place) { camera = .region(region) }
    }

    /// Ширина кадра берётся от MapLibre, чтобы крупность совпадала числом, а не
    /// на глаз: z14 на широте Томска — 2,639 м на пиксель (DECISIONS, «Карта на
    /// вектор»), экран iPhone 17 Pro — 402 пункта, отсюда 1061 м поперёк кадра.
    /// z12 (природа) вчетверо крупнее — 4244 м.
    private var region: MKCoordinateRegion {
        let across: CLLocationDistance = place.zoom == 14 ? 1061 : 4244
        return MKCoordinateRegion(center: .init(latitude: place.lat, longitude: place.lon),
                                  latitudinalMeters: across, longitudinalMeters: across)
    }
}
