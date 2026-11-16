import CoreGraphics

/// The size an export renders at, so it drops straight in as a Lock Screen or Home Screen
/// wallpaper: the screen's own shape, at its own pixel density.
enum WallpaperSize {
  /// - Parameters:
  ///   - screen: The full window, in points, safe areas included.
  ///   - isCompact: A phone-width layout. Phone wallpapers are always upright, so a landscape
  ///     phone still exports portrait; regular-width screens (iPad, the Duo's inner display)
  ///     keep the shape they have.
  static func points(for screen: CGSize, isCompact: Bool) -> CGSize {
    guard screen.width > 0, screen.height > 0 else { return CGSize(width: 1024, height: 1024) }
    if isCompact && screen.width > screen.height {
      return CGSize(width: screen.height, height: screen.width)
    }
    return screen
  }
}
