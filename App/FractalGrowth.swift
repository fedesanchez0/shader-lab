import Foundation

/// The Fractal's Grow loop. Each cycle grows a plant from its holdfast, develops the print when
/// Cyanotype Develops is on while the book's title comes up when Title is, holds it, then fades
/// it (with Loss, gusts of wind shake it apart first, until only its main stem is left to
/// fade), and the next cycle grows the next seed. `fractalTree` draws a cycle from how far into it
/// the loop is: the seconds since Grow Start, times the speed, or, while paused, Grow Paused.
/// The model keeps those, and the Seed, moving.
enum FractalGrowth {
  static let shaderID = "Fractal"

  // The Fractal's growth controls
  static let grow = "Grow"
  static let growSpeed = "Grow Speed"
  static let organicGrowth = "Organic Growth"
  static let fractalLevels = "Fractal Levels"
  static let cyanotypeDevelops = "Cyanotype Develops"
  static let title = "Title"
  static let loss = "Loss"
  static let growStart = "Grow Start"
  static let growPaused = "Grow Paused"

  /// The Grow row's speed chip steps through these
  static let speeds = ["0.5×", "1×", "2×"]

  /// How many times faster than 1× a speed plays: the shader works it out the same way
  static func pace(forSpeed choice: Int) -> Float {
    exp2(Float(choice) - 1)
  }

  // How long each stage lasts at 1×, in seconds: the same as fractalTree's FT_GROW_SECONDS
  // and so on
  static let growSeconds: Float = 6
  static let developSeconds: Float = 3
  static let titleSeconds: Float = 3
  static let holdSeconds: Float = 3
  static let fallSeconds: Float = 6
  static let fadeSeconds: Float = 1.5

  /// The title's letters start coming up this far apart, at 1×
  static let titleStagger: Float = 0.1

  /// How long the print takes to settle once the plant has grown: it develops while the title
  /// comes up
  static func settleSeconds(develops: Bool, title: Bool) -> Float {
    max(develops ? developSeconds : 0, title ? titleSeconds : 0)
  }

  /// How long one cycle lasts at 1×. Without Organic Growth or Fractal Levels the plant is
  /// there from the start; without Cyanotype Develops the print is too.
  static func cycleSeconds(grows: Bool, develops: Bool, title: Bool = false, loss: Bool = false) -> Float {
    fadeFrom(grows: grows, develops: develops, title: title, loss: loss) + fadeSeconds
  }

  /// When the last of the plant starts to fade, at 1×: after the hold, or with Loss, once the
  /// gusts have left only its main stem
  static func fadeFrom(grows: Bool, develops: Bool, title: Bool, loss: Bool) -> Float {
    (grows ? growSeconds : 0) + settleSeconds(develops: develops, title: title) + holdSeconds
      + (loss ? fallSeconds : 0)
  }

  /// How much of each of the title's letters is printed, from 0 to 1, `age` seconds into a cycle
  /// at 1×: none while the plant grows, then one after another in reading order, each coming up
  /// out of the paper on the print's ease, the last as the title stage ends. They fade with the
  /// last of the plant.
  static func titleReveal(letters: Int, age: Float, grows: Bool, develops: Bool, loss: Bool) -> [Float] {
    let grown = grows ? growSeconds : 0
    let fading = fadeFrom(grows: grows, develops: develops, title: true, loss: loss)
    let faded = min(max((age - fading) / fadeSeconds, 0), 1)
    let each = titleSeconds - titleStagger * Float(max(letters - 1, 0))
    return (0..<letters).map { index in
      let x = min(max((age - grown - titleStagger * Float(index)) / each, 0), 1)
      return x * x * (3 - 2 * x) * (1 - faded)
    }
  }

  /// A tick this much past the end of a cycle means the clock stopped in between: the Code tab
  /// covered the canvas, or another shader was on screen.
  static let missedTickSeconds: Float = 0.5

  enum State {
    /// Not started: the whole plant, still
    case stopped
    case playing
    /// Held where it was when paused
    case paused
  }
}

extension PlaygroundModel {
  var fractalGrowthState: FractalGrowth.State {
    let params = shaderParams[FractalGrowth.shaderID] ?? []
    guard params.first(where: { $0.name == FractalGrowth.grow })?.isOn == true else { return .stopped }
    let paused = params.first { $0.name == FractalGrowth.growPaused }?.value ?? -1
    return paused >= 0 ? .paused : .playing
  }

  /// Play starts the loop from the holdfast, or carries on from where Pause held it. Pause
  /// holds the plant exactly where it is.
  func toggleFractalGrowth(at time: Float) {
    updateFractalParams { params, value in
      let pace = FractalGrowth.pace(forSpeed: Int(value(FractalGrowth.growSpeed).rounded()))
      switch fractalGrowthState {
      case .stopped:
        params.set(FractalGrowth.grow, to: 1)
        params.set(FractalGrowth.growStart, to: time)
        params.set(FractalGrowth.growPaused, to: -1)
      case .paused:
        params.set(FractalGrowth.growStart, to: time - value(FractalGrowth.growPaused) / pace)
        params.set(FractalGrowth.growPaused, to: -1)
      case .playing:
        params.set(FractalGrowth.growPaused, to: max(time - value(FractalGrowth.growStart), 0) * pace)
      }
    }
  }

  /// Moves Grow on to its next speed, keeping the plant where it is
  func stepFractalGrowthSpeed(at time: Float) {
    updateFractalParams { params, value in
      let old = Int(value(FractalGrowth.growSpeed).rounded())
      let new = (old + 1) % FractalGrowth.speeds.count
      params.set(FractalGrowth.growSpeed, to: Float(new))
      if fractalGrowthState == .playing {
        let into = (time - value(FractalGrowth.growStart)) * FractalGrowth.pace(forSpeed: old)
        params.set(FractalGrowth.growStart, to: time - into / FractalGrowth.pace(forSpeed: new))
      }
    }
  }

  /// Keeps the Fractal's Grow loop going, on every tick of the clock: when a cycle ends, the
  /// Seed moves on and the next begins. Switching Grow off clears the loop, so Play starts from
  /// the holdfast again. If the clock stopped partway, the plant on screen starts over rather
  /// than skipping ahead. Paused, nothing moves.
  func updateFractalGrowth(at time: Float) {
    guard selectedShaderID == FractalGrowth.shaderID else { return }
    let state = fractalGrowthState
    updateFractalParams { params, value in
      let started = value(FractalGrowth.growStart)
      guard state != .stopped else {
        if started >= 0 || value(FractalGrowth.growPaused) >= 0 {
          params.set(FractalGrowth.growStart, to: -1)
          params.set(FractalGrowth.growPaused, to: -1)
        }
        return
      }
      guard state == .playing else { return }
      let pace = FractalGrowth.pace(forSpeed: Int(value(FractalGrowth.growSpeed).rounded()))
      let cycle = FractalGrowth.cycleSeconds(
        grows: value(FractalGrowth.organicGrowth) > 0.5 || value(FractalGrowth.fractalLevels) > 0.5,
        develops: value(FractalGrowth.cyanotypeDevelops) > 0.5,
        title: value(FractalGrowth.title) > 0.5,
        loss: value(FractalGrowth.loss) > 0.5) / pace
      let elapsed = time - started
      if started < 0 || elapsed < 0 || elapsed >= cycle + FractalGrowth.missedTickSeconds {
        params.set(FractalGrowth.growStart, to: time)
      } else if elapsed >= cycle {
        params.set(FractalGrowth.growStart, to: time)
        if let seed = params.firstIndex(where: { $0.name == "Seed" }) {
          let next = params[seed].value.rounded() + 1
          params[seed].value = next > params[seed].range.upperBound ? params[seed].range.lowerBound : next
        }
      }
    }
  }

  /// How much of each of the title's letters shows at `time`, or nil with Title off. Stopped,
  /// the whole title is printed with the whole plant.
  func fractalTitleReveal(letters: Int, at time: Float) -> [Float]? {
    let params = shaderParams[FractalGrowth.shaderID] ?? []
    func value(_ name: String) -> Float { params.first { $0.name == name }?.value ?? 0 }
    guard value(FractalGrowth.title) > 0.5 else { return nil }
    let start = value(FractalGrowth.growStart), paused = value(FractalGrowth.growPaused)
    // fractalTree draws the still plant until the loop has a start
    guard fractalGrowthState != .stopped, start >= 0 else { return Array(repeating: 1, count: letters) }
    let pace = FractalGrowth.pace(forSpeed: Int(value(FractalGrowth.growSpeed).rounded()))
    return FractalGrowth.titleReveal(
      letters: letters, age: paused >= 0 ? paused : max(time - start, 0) * pace,
      grows: value(FractalGrowth.organicGrowth) > 0.5 || value(FractalGrowth.fractalLevels) > 0.5,
      develops: value(FractalGrowth.cyanotypeDevelops) > 0.5,
      loss: value(FractalGrowth.loss) > 0.5)
  }

  /// Changes the Fractal's parameters in one go, and only stores them if something changed:
  /// the clock calls in 30 times a second, and every store redraws whatever reads them.
  private func updateFractalParams(_ change: (inout [ShaderParam], (String) -> Float) -> Void) {
    guard let before = shaderParams[FractalGrowth.shaderID] else { return }
    var params = before
    change(&params) { name in before.first { $0.name == name }?.value ?? 0 }
    if params.map(\.value) != before.map(\.value) {
      shaderParams[FractalGrowth.shaderID] = params
    }
  }
}

private extension [ShaderParam] {
  mutating func set(_ name: String, to value: Float) {
    guard let index = firstIndex(where: { $0.name == name }) else { return }
    self[index].value = value
  }
}
