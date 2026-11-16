import SwiftUI

/// The inner display's fold, in the terms layout cares about.
///
/// Layout blends by `foldAmount`, which is continuous, so nothing snaps at an angle.
struct FoldPosture: Equatable {
  /// Which way the crease runs across the display. This is hardware geometry (the crease
  /// always crosses the middle of the long side), not a named pose.
  enum Crease {
    case vertical    // two side-by-side halves
    case horizontal  // viewing half on top, controls below
  }

  var crease: Crease? = nil
  /// The crease itself, in full-screen coordinates.
  var divisionRect: CGRect? = nil
  /// The system's margins around the crease: extra room controls that straddle it should keep.
  var divisionMargins = EdgeInsets()
  /// 0 = lay out as one flat display, 1 = lay out as two halves.
  var foldAmount: Double = 0
  /// The system says the crease currently divides the display. Then the two-halves layout
  /// applies in full: fixed controls must be clear of `divisionRect`, not easing toward it.
  var isDivisionActive = false

  static let unhinged = FoldPosture()

  /// The same fold at an in-between amount, for animating toward it.
  func with(foldAmount: Double) -> FoldPosture {
    var copy = self
    // A spring can overshoot; the layout math expects 0...1
    copy.foldAmount = min(max(foldAmount, 0), 1)
    return copy
  }

  /// 0...1, how much of a layout change is in flight, from how far the animated amount still
  /// is from where it's heading. It peaks mid-move and is zero at rest at any hinge angle,
  /// so transition effects can never linger on a partly folded display.
  static func transitionEnergy(target: Double, current: Double) -> Double {
    let remaining = min(abs(target - current), 1)
    return min(4 * remaining * (1 - remaining), 1)
  }

  /// How far the two-halves layout applies across each axis.
  var bookAmount: Double { crease == .vertical ? foldAmount : 0 }
  var tableAmount: Double { crease == .horizontal ? foldAmount : 0 }

  private static let divisionThickness: CGFloat = 24

  /// Resolves the fold for a container spanning the inner display.
  /// - Parameter divisionRegion: the system's division reserved region (the crease) in the
  ///   container's coordinates, when the OS reports one. Otherwise the crease is taken to
  ///   cross the middle of the display's long side, which is where the hardware puts it.
  static func resolve(
    state: DuoPostureState, containerSize: CGSize, divisionRegion: CGRect? = nil,
    divisionMargins: EdgeInsets = EdgeInsets(), isDivisionActive: Bool = false
  ) -> FoldPosture {
    guard state.isAvailable else { return .unhinged }

    let crease: Crease
    let rect: CGRect
    if let divisionRegion, !divisionRegion.isEmpty {
      crease = divisionRegion.width < divisionRegion.height ? .vertical : .horizontal
      rect = divisionRegion
    } else {
      let t = divisionThickness
      crease = containerSize.width > containerSize.height ? .vertical : .horizontal
      rect = crease == .vertical
        ? CGRect(x: containerSize.width / 2 - t / 2, y: 0, width: t, height: containerSize.height)
        : CGRect(x: 0, y: containerSize.height / 2 - t / 2, width: containerSize.width, height: t)
    }

    return FoldPosture(
      crease: crease,
      divisionRect: rect,
      divisionMargins: divisionMargins,
      // An active division is the system's word that the display is folded; the angle-based
      // ramp only stands in when no region is reported
      foldAmount: isDivisionActive ? 1 : resolvedFoldAmount(for: state),
      isDivisionActive: isDivisionActive
    )
  }

  private static func resolvedFoldAmount(for state: DuoPostureState) -> Double {
    // A preset says what the person intends, whatever angle the hinge is passing through
    switch state.pose {
    case .book, .nintendoDS:
      return 1
    case .fullyOpen, .innerPortrait, .alarmClock, .outerPortrait, .outerLandscape:
      return 0
    case nil:
      // Free folding: ease the two-halves layout in across a wide stretch of the hinge's
      // travel (175° to 110°), so it keeps pace with the fold instead of finishing early
      let x = min(max((0.97 - state.progress) / 0.36, 0), 1)
      return x * x * (3 - 2 * x)
    }
  }
}
