import Foundation

/// The hinge's general geometric classification, from its angle and status.
enum DuoPosture: Sendable {
  case closed
  case partiallyOpen
  case tabletop
  case flat
}
