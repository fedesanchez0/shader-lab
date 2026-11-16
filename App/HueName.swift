import Foundation

/// Names a hue (0–1) for VoiceOver, so a color slider reads as "orange" rather than a number.
enum HueName {
  static func describe(_ hue: Double) -> String {
    let degrees = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 360
    switch degrees {
    case ..<15, 345...: return "Red"
    case ..<45: return "Orange"
    case ..<70: return "Yellow"
    case ..<160: return "Green"
    case ..<200: return "Cyan"
    case ..<255: return "Blue"
    case ..<290: return "Purple"
    default: return "Pink"
    }
  }
}
