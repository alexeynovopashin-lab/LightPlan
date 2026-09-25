import SwiftUI

/// Распознаватель светила пальцем (итерация 19в). Купол лежит в прокрутке
/// «Света», и жест делит её с ней: горизонталь — наша, вертикаль — прокрутке
/// (`DomeDrag.axis`).
///
/// На iOS это распознаватель UIKit (`DomePan`), а не `DragGesture`: прокрутка
/// страницы ждёт, пока купол откажется (`shouldBeRequiredToFailBy`), и
/// диагональный палец не двигает страницу и солнце разом. `DragGesture`
/// SwiftUI либо забирает касание у прокрутки целиком, либо (`simultaneous`)
/// отдаёт его обоим — в «Астро» страница ехала бы вместе с солнцем.
///
/// `accepts` — стартовая точка годится (над горизонтом, мимо показаний и
/// тумблера светила); `onMove` — палец сейчас здесь; точки — в координатах
/// рамки купола.
struct DomeDragGesture {
    var accepts: (CGPoint) -> Bool
    var onMove: (CGPoint) -> Void
}

#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

extension DomeDragGesture: UIGestureRecognizerRepresentable {

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter)
    }

    func makeUIGestureRecognizer(context: Context) -> DomePan {
        let pan = DomePan()
        pan.delegate = context.coordinator
        let coordinator = context.coordinator
        pan.accepts = { [weak coordinator] in
            guard let coordinator else { return false }
            return coordinator.accepts(coordinator.converter.localLocation)
        }
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: DomePan, context: Context) {
        context.coordinator.converter = context.converter
        context.coordinator.accepts = accepts
    }

    func handleUIGestureRecognizerAction(_ recognizer: DomePan, context: Context) {
        switch recognizer.state {
        case .began, .changed: onMove(context.converter.localLocation)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var converter: CoordinateSpaceConverter
        var accepts: (CGPoint) -> Bool = { _ in false }

        init(converter: CoordinateSpaceConverter) { self.converter = converter }

        /// Прокрутка страницы ждёт отказа купола: иначе горизонтальный палец
        /// с малой вертикалью брала бы она, кто первым набрал свой порог.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

/// Свой распознаватель вместо `UIPanGestureRecognizer`: тот, повешенный
/// через SwiftUI, спрашивает «начинать ли» на первом же сдвиге, когда его
/// собственный путь ещё 0 (замер 19в), и ось решить нечем. Этот копит путь
/// от касания сам и решает на 6 pt, как `pointermove` веба: горизонталь —
/// начинает, вертикаль или поровну — отказывает, и прокрутка берёт палец.
final class DomePan: UIGestureRecognizer {
    /// Стартовая точка наша (над горизонтом, мимо показаний и тумблера).
    var accepts: (() -> Bool)?
    private var start: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard start == nil, touches.count == 1, let t = touches.first else { state = .failed; return }
        start = t.location(in: view)
        if accepts?() != true { state = .failed }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let t = touches.first, let start else { return }
        let p = t.location(in: view)
        switch state {
        case .possible:
            switch DomeDrag.axis(dx: p.x - start.x, dy: p.y - start.y) {
            case .pending: break
            case .scroll: state = .failed
            case .drag: state = .began
            }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = state == .began || state == .changed ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = state == .began || state == .changed ? .cancelled : .failed
    }

    override func reset() {
        super.reset()
        start = nil
    }
}
#else

/// На Mac прокрутка страницы — колесом, а не пальцем, делить нечего:
/// обычная протяжка, ось решается на первом движении дальше порога.
@MainActor
extension DomeDragGesture {
    func gesture(axis: Binding<DomeDrag.Axis>) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if axis.wrappedValue == .pending {
                    guard accepts(v.startLocation) else { axis.wrappedValue = .scroll; return }
                    axis.wrappedValue = DomeDrag.axis(dx: v.translation.width, dy: v.translation.height)
                }
                if axis.wrappedValue == .drag { onMove(v.location) }
            }
            .onEnded { _ in axis.wrappedValue = .pending }
    }
}
#endif
