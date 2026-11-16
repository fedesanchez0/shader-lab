import SwiftUI

extension EnvironmentValues {
  /// The latest hinge state. `unavailable` on every device without a hinge.
  @Entry var duoPosture: DuoPostureState = .unavailable
}

extension View {
  /// Installs the hinge runtime at the app root and publishes its state as `\.duoPosture`.
  func duoRuntime() -> some View {
    modifier(DuoRuntime())
  }
}
