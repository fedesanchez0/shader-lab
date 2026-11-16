import Foundation
import Observation

/// The one clock every canvas draws from.
///
/// Each `CanvasView` used to own a timer, so the main canvas, the tabletop reflection and the
/// magnifier ticked separately and out of step. Now whichever canvas is alive drives this
/// clock, the rest just read it, and a canvas that doesn't need 30 fps can read `slowTime`.
@Observable
final class CanvasClock {
  /// Seconds since launch, refreshed ~30 times a second.
  private(set) var time: Float = 0
  /// The same clock at half the rate, for soft secondary passes such as the reflection.
  private(set) var slowTime: Float = 0

  /// While true the clock holds still, so nothing that reads it redraws: set while an opaque
  /// screen (the Code or Nodes tab) covers the canvas.
  @ObservationIgnored var isPaused = false

  /// Called with the time on every tick, for things that move on with the animation, such as
  /// the Fractal's Grow loop.
  @ObservationIgnored var onTick: ((Float) -> Void)?

  @ObservationIgnored private let epoch = Date()
  @ObservationIgnored private var driver: UUID?
  @ObservationIgnored private var tickCount = 0

  private static let interval: Duration = .milliseconds(33)
  private static let pausedInterval: Duration = .milliseconds(250)

  /// Keeps the clock running until the calling task is cancelled. Safe to call from every
  /// canvas: only one caller ticks at a time, and another takes over if that one goes away.
  @MainActor
  func run() async {
    let id = UUID()
    defer { if driver == id { driver = nil } }

    while !Task.isCancelled {
      if driver == nil { driver = id }
      if driver == id && !isPaused { tick() }
      // Paused, there's nothing to tick; just check back now and then
      try? await Task.sleep(for: isPaused ? Self.pausedInterval : Self.interval)
    }
  }

  @MainActor
  private func tick() {
    let now = Float(Date().timeIntervalSince(epoch))
    time = now
    tickCount += 1
    if tickCount.isMultiple(of: 2) { slowTime = now }
    onTick?(now)
  }
}
