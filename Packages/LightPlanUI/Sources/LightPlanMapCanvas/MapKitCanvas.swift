import SwiftUI
import MapKit

/// Путь А итерации 4: MapKit. Своего цвета слоям не даёт, тёмный холст —
/// только тёмной темой окна (DECISIONS, «Холст карты в нативе»).
struct MapKitCanvas: View {
    let center: MapCanvasCenter
    let zoom: Double
    let dark: Bool
    let panEnabled: Bool
    let focusShift: CGFloat
    let onMove: (MapCanvasCenter) -> Void
    let onCamera: (MapCanvasCamera) -> Void
    let onTap: (CGPoint) -> Void

    @State private var camera: MapCameraPosition = .automatic
    @State private var width: CGFloat = 440
    @State private var placed: MapCanvasCenter?

    var body: some View {
        Map(position: $camera, interactionModes: panEnabled ? [.pan, .zoom] : [.zoom]) { }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll,
                                showsTraffic: false))
            .mapControlVisibility(.hidden)
            .safeAreaPadding(.top, max(0, -focusShift))
            .safeAreaPadding(.bottom, max(0, focusShift))
            .environment(\.colorScheme, dark ? .dark : .light)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // Тап без сдвига (`click` веба); пан и щипок остаются у карты.
            .onTapGesture { onTap($0) }
            // Камера на каждом кадре — булавки едут за картой. Крупность — из
            // ширины кадра в градусах долготы: плитка 512, как у MapLibre.
            // Из кода, не мерено: у MapKit сдвиг центра полями не сверен.
            .onMapCameraChange(frequency: .continuous) { ctx in
                let c = ctx.camera.centerCoordinate
                let span = max(1e-9, ctx.region.span.longitudeDelta)
                let z = log2(Double(width) * 360 / (512 * span))
                let moved = MapCanvasCenter(latitude: c.latitude, longitude: c.longitude)
                onCamera(MapCanvasCamera(center: moved, zoom: z, byHand: moved != placed))
            }
            .onAppear { place() }
            .onChange(of: center) { if center != placed { place() } }
            .onMapCameraChange(frequency: .onEnd) { ctx in
                let c = ctx.region.center
                let moved = MapCanvasCenter(latitude: c.latitude, longitude: c.longitude)
                guard let placed, abs(moved.latitude - placed.latitude) + abs(moved.longitude - placed.longitude) > 1e-6
                else { return }
                self.placed = moved
                onMove(moved)
            }
    }

    /// Ширина кадра в метрах — от уровня веба, чтобы крупность совпала с
    /// MapLibre числом, а не на глаз.
    private func place() {
        placed = center
        let across = Double(width) * MapCanvasView.metersPerPoint(zoom: zoom, latitude: center.latitude)
        camera = .region(MKCoordinateRegion(center: .init(latitude: center.latitude, longitude: center.longitude),
                                            latitudinalMeters: across, longitudinalMeters: across))
    }
}
