import SwiftUI

/// The faint mirror image of the canvas on the half that lies flat in tabletop, like a
/// screen reflected in a dark window. The lower half is otherwise black.
///
/// It's deliberately cheap: the copy renders at 1/16 of the pixels, and the blur that a
/// reflection needs anyway hides the missing detail.
struct TabletopReflection: View {
  var model: PlaygroundModel
  /// Size of the live canvas above the crease; the reflection mirrors it one-to-one.
  var canvasSize: CGSize
  /// 0...1, how far the tabletop layout has taken over.
  var strength: Double

  private let downscale: CGFloat = 4
  private let maxOpacity = 0.32
  private let blurRadius: CGFloat = 12

  var body: some View {
    // Blurred and faint, so half the frame rate is invisible here
    CanvasView(model: model, usesSlowClock: true)
      .frame(width: canvasSize.width / downscale, height: canvasSize.height / downscale)
      // Blur while it's still small: the same softness for 1/16 of the work
      .blur(radius: blurRadius / downscale)
      // Rasterize at this size. Without it the scale below is only a transform and the
      // shader would still run for every pixel of the lower half.
      .drawingGroup(opaque: true)
      // Flipped, so the picture's bottom edge meets the crease
      .scaleEffect(x: downscale, y: -downscale)
      .frame(width: canvasSize.width, height: canvasSize.height)
      .opacity(maxOpacity * strength)
      // Strongest at the crease, gone about two thirds of the way down
      .mask {
        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7))
      }
      .clipped()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}
