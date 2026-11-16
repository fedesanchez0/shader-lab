import SwiftUI

/// A panel's share of the fold transition. Going to tabletop the panels drop into the lower
/// half, and they do it like the macOS genie: the top edge pinches in and tips away as it's
/// pulled down, blurred while it travels, then everything opens back out as it lands.
///
/// It's built from a perspective pinch rather than a mesh-warp shader, because SwiftUI can't
/// run shaders over views that contain scroll views, and the panels do.
struct FoldTransitionChrome: ViewModifier {
  /// 0 at rest, up to 1 mid-transition. Pass 0 for any move where the panel stays put.
  var energy: Double

  func body(content: Content) -> some View {
    let energy = min(max(energy, 0), 1)
    content
      .blur(radius: 9 * energy)
      .opacity(1 - 0.25 * energy)
      // Anchored at the bottom edge, where the panel is heading: the top narrows and recedes
      .rotation3DEffect(.degrees(30 * energy), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.9)
      .scaleEffect(x: 1 - 0.10 * energy, y: 1, anchor: .bottom)
  }
}
