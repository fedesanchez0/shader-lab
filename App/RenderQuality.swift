import Foundation

/// How much of the canvas' resolution the shaders are evaluated at.
///
/// A screen recording for social media is scaled down to roughly a third of the Duo's
/// native pixels, so rendering every one of them is wasted work.
enum RenderQuality: String, CaseIterable, Identifiable {
  case full
  case balanced
  case performance

  var id: String { rawValue }

  var title: String {
    switch self {
    case .full: "Full"
    case .balanced: "Balanced"
    case .performance: "Fast"
    }
  }

  private static let defaultsKey = "renderQuality"

  static var stored: RenderQuality {
    UserDefaults.standard.string(forKey: defaultsKey).flatMap(RenderQuality.init) ?? .performance
  }

  func store() {
    UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
  }
}
