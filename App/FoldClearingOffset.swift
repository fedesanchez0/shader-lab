import SwiftUI

/// Slides a horizontally centered control just clear of a vertical crease, moving it no
/// further than it has to. The slide follows `bookAmount`, so it tracks the hinge
/// continuously instead of jumping at an angle.
struct FoldClearingOffset: ViewModifier {
  var fold: FoldPosture
  var containerWidth: CGFloat
  @State private var width: CGFloat = 0

  private let gap: CGFloat = 16
  private let edgeMargin: CGFloat = 24

  private var clearedOffsetX: CGFloat {
    guard let division = fold.divisionRect, fold.crease == .vertical, width > 0 else { return 0 }
    let centerX = containerWidth / 2
    // Already clear of the crease: leave it alone
    guard centerX - width / 2 < division.maxX, centerX + width / 2 > division.minX else { return 0 }
    let shifted = division.maxX + gap + width / 2 - centerX
    let limit = containerWidth - edgeMargin - width / 2 - centerX
    return max(0, min(shifted, limit))
  }

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
      .offset(x: clearedOffsetX * fold.bookAmount)
  }
}

extension View {
  func clearsFold(_ fold: FoldPosture, containerWidth: CGFloat) -> some View {
    modifier(FoldClearingOffset(fold: fold, containerWidth: containerWidth))
  }
}
