import SwiftUI

/// Publishes the device's hinge as `\.duoPosture` for every view below.
///
/// The angle comes from SwiftUI's `onHingeChange`. Devices without a hinge, and OS versions
/// before 27.1, see `unavailable`, and nothing treats that as an error.
struct DuoRuntime: ViewModifier {
  @State private var state = DuoPostureState.unavailable

  /// How long the hinge must hold still before it counts as at rest.
  private static let motionWindow: Duration = .milliseconds(400)

  func body(content: Content) -> some View {
    #if os(iOS)
    if #available(iOS 27.1, *) {
      content
        .environment(\.duoPosture, state)
        .onHingeChange { _, context in
          state = Self.state(for: context)
        }
        // Each change restarts the wait, so `isAnimating` clears once the hinge settles
        .task(id: state.angleDegrees) {
          guard state.isAnimating else { return }
          try? await Task.sleep(for: Self.motionWindow)
          guard !Task.isCancelled else { return }
          state.isAnimating = false
        }
    } else {
      content.environment(\.duoPosture, .unavailable)
    }
    #else
    content.environment(\.duoPosture, .unavailable)
    #endif
  }

  #if os(iOS)
  @available(iOS 27.1, *)
  private static func state(for context: DeviceHingeContext) -> DuoPostureState {
    guard let hinge = context.hinge else { return .unavailable }
    let angle = min(max(hinge.angle.degrees, 0), 180)
    let posture: DuoPosture
    switch hinge.status {
    case .closed: posture = .closed
    case .fullyOpen: posture = .flat
    default: posture = (75...105).contains(angle) ? .tabletop : .partiallyOpen
    }
    return DuoPostureState(
      angleDegrees: angle,
      progress: angle / 180,
      isAnimating: true,
      isAvailable: true,
      posture: posture,
      // Hardware reports only the hinge, never a named pose
      pose: nil
    )
  }
  #endif
}
