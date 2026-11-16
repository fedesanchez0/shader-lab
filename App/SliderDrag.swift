#if !os(tvOS)
import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
  /// The drag for a slider that sits in a scroll view, such as the parameter panels. On iPhone
  /// and iPad it only starts when the finger moves more sideways than up or down, so a vertical
  /// swipe that starts on a slider still scrolls the panel, and a tap jumps the slider to where
  /// it landed. Both report the location in the view's own space.
  func sliderDrag(onChanged: @escaping (CGPoint) -> Void, onEnded: @escaping () -> Void = {}) -> some View {
    #if os(iOS)
    gesture(SidewaysPan(onChanged: onChanged, onEnded: onEnded))
      .onTapGesture(coordinateSpace: .local) { location in
        onChanged(location)
        onEnded()
      }
    #else
    gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { onChanged($0.location) }
        .onEnded { _ in onEnded() }
    )
    #endif
  }
}

#if os(iOS)
/// A pan that only begins when it sets off sideways, leaving vertical swipes to the scroll view
private struct SidewaysPan: UIGestureRecognizerRepresentable {
  var onChanged: (CGPoint) -> Void
  var onEnded: () -> Void

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
    Coordinator()
  }

  func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
    let pan = UIPanGestureRecognizer()
    pan.delegate = context.coordinator
    return pan
  }

  func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
    switch recognizer.state {
    case .began, .changed: onChanged(context.converter.localLocation)
    case .ended, .cancelled, .failed: onEnded()
    default: break
    }
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
      let velocity = pan.velocity(in: pan.view)
      return abs(velocity.x) > abs(velocity.y)
    }
  }
}
#endif
#endif
