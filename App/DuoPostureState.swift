import Foundation

/// One snapshot of the device hinge.
///
/// `unavailable` is the state on every device without a hinge, and nothing should treat it
/// as an error.
struct DuoPostureState: Equatable, Sendable {
  /// Continuous hinge angle, 0 (closed) through 180 (flat).
  var angleDegrees: Double
  /// Normalized hinge progress, 0 (closed) through 1 (flat). Drive continuous UI from this.
  var progress: Double
  /// True while the hinge is moving.
  var isAnimating: Bool
  /// Whether the device has a hinge and is reporting it.
  var isAvailable: Bool
  var posture: DuoPosture
  /// An explicitly selected preset, when something can name one. Hardware never does.
  var pose: DuoPose?

  static let unavailable = DuoPostureState(
    angleDegrees: 180, progress: 1, isAnimating: false, isAvailable: false, posture: .flat, pose: nil)
}
