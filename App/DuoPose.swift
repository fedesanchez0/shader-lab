import Foundation

/// A named device pose. Hardware only reports a hinge angle, so this is nil in normal use;
/// it stays so a preset (a demo mode, a test) can still ask for a specific layout.
enum DuoPose: String, CaseIterable, Sendable {
  case outerPortrait
  case book
  case fullyOpen
  case nintendoDS
  case outerLandscape
  case alarmClock
  case innerPortrait
}
