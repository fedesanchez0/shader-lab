import Foundation
import Testing
@testable import Shader_Lab

@MainActor
@Suite("Fractal Grow loop")
struct FractalGrowthTests {
  /// A model showing Fractal, with Grow switched to `grow`
  private func fractal(grow: Bool = true) -> PlaygroundModel {
    let model = PlaygroundModel()
    model.selectedShaderID = FractalGrowth.shaderID
    set(FractalGrowth.grow, to: grow ? 1 : 0, in: model)
    return model
  }

  private func value(_ name: String, in model: PlaygroundModel) -> Float? {
    model.shaderParams[FractalGrowth.shaderID]?.first { $0.name == name }?.value
  }

  private func set(_ name: String, to value: Float, in model: PlaygroundModel) {
    guard let index = model.shaderParams[FractalGrowth.shaderID]?.firstIndex(where: { $0.name == name }) else { return }
    model.shaderParams[FractalGrowth.shaderID]?[index].value = value
  }

  /// One cycle with the default switches: Organic Growth and Cyanotype Develops on
  private var cycle: Float { FractalGrowth.cycleSeconds(grows: true, develops: true) }

  @Test func switchingGrowOnStartsACycle() {
    let model = fractal()
    model.updateFractalGrowth(at: 40)
    #expect(value(FractalGrowth.growStart, in: model) == 40)
  }

  @Test func aFinishedCycleGrowsTheNextSeed() {
    let model = fractal()
    set("Seed", to: 21, in: model)
    model.updateFractalGrowth(at: 40)
    model.updateFractalGrowth(at: 40 + cycle - 0.1)
    #expect(value("Seed", in: model) == 21)
    model.updateFractalGrowth(at: 40 + cycle + 0.02)
    #expect(value("Seed", in: model) == 22)
    #expect(value(FractalGrowth.growStart, in: model) == 40 + cycle + 0.02)
  }

  @Test func theSeedWrapsAround() {
    let model = fractal()
    set("Seed", to: 99, in: model)
    model.updateFractalGrowth(at: 10)
    model.updateFractalGrowth(at: 10 + cycle)
    #expect(value("Seed", in: model) == 0)
  }

  @Test func switchingGrowOffClearsTheStart() {
    let model = fractal()
    model.updateFractalGrowth(at: 40)
    set(FractalGrowth.grow, to: 0, in: model)
    model.updateFractalGrowth(at: 41)
    #expect(value(FractalGrowth.growStart, in: model) == -1)
  }

  @Test func afterTheClockStoppedThePlantStartsOver() {
    let model = fractal()
    set("Seed", to: 5, in: model)
    model.updateFractalGrowth(at: 40)
    // The Code tab covered the canvas for a minute
    model.updateFractalGrowth(at: 100)
    #expect(value("Seed", in: model) == 5)
    #expect(value(FractalGrowth.growStart, in: model) == 100)
  }

  @Test func waitsWhileAnotherShaderIsOnScreen() {
    let model = fractal()
    model.selectedShaderID = "Wave"
    model.updateFractalGrowth(at: 40)
    #expect(value(FractalGrowth.growStart, in: model) == -1)
  }

  @Test func playPausesAndResumesWhereItWas() {
    let model = fractal(grow: false)
    #expect(model.fractalGrowthState == .stopped)
    model.toggleFractalGrowth(at: 40)
    #expect(model.fractalGrowthState == .playing)
    #expect(value(FractalGrowth.growStart, in: model) == 40)
    model.toggleFractalGrowth(at: 43)
    #expect(model.fractalGrowthState == .paused)
    #expect(value(FractalGrowth.growPaused, in: model) == 3)
    // Paused, the clock moving on changes nothing
    model.updateFractalGrowth(at: 400)
    #expect(value(FractalGrowth.growPaused, in: model) == 3)
    model.toggleFractalGrowth(at: 60)
    #expect(model.fractalGrowthState == .playing)
    #expect(value(FractalGrowth.growStart, in: model) == 57)
  }

  @Test func changingSpeedKeepsThePlantWhereItIs() {
    let model = fractal(grow: false)
    set("Seed", to: 21, in: model)
    model.toggleFractalGrowth(at: 40)
    model.stepFractalGrowthSpeed(at: 44)  // 1× to 2×, 4 seconds in
    #expect(value(FractalGrowth.growSpeed, in: model) == 2)
    #expect(value(FractalGrowth.growStart, in: model) == 42)
    // At 2× the cycle takes half as long
    model.updateFractalGrowth(at: 42 + cycle / 2 + 0.02)
    #expect(value("Seed", in: model) == 22)
  }

  @Test func speedGoesRoundTheThreeChoices() {
    let model = fractal(grow: false)
    let labels = (0..<3).map { _ in
      model.stepFractalGrowthSpeed(at: 0)
      return FractalGrowth.speeds[Int(value(FractalGrowth.growSpeed, in: model) ?? 0)]
    }
    #expect(labels == ["2×", "0.5×", "1×"])
  }

  @Test func cyclesAreShorterWithoutGrowingOrDeveloping() {
    #expect(FractalGrowth.cycleSeconds(grows: false, develops: false)
            == FractalGrowth.holdSeconds + FractalGrowth.fadeSeconds)
    #expect(FractalGrowth.cycleSeconds(grows: true, develops: false)
            < FractalGrowth.cycleSeconds(grows: true, develops: true))
  }

  @Test func growStartIsNeitherShownNorListed() throws {
    let start = try #require(ShaderDefinition.byID[FractalGrowth.shaderID]?.defaultParams.first { $0.name == FractalGrowth.growStart })
    #expect(start.isHidden)
    // The Code tab lists the current values as "  // Name  value" lines
    let model = fractal()
    let source = ShaderCodeView.extractedSource(for: model)
    #expect(source.contains("// \(FractalGrowth.grow) "))
    #expect(!source.contains("// \(FractalGrowth.growStart) "))
  }

  @Test func theTitleComesUpLetterByLetterOnceThePlantHasGrown() {
    let grown = FractalGrowth.growSeconds
    func reveal(at age: Float) -> [Float] {
      FractalGrowth.titleReveal(letters: 15, age: age, grows: true, develops: false, loss: false)
    }
    #expect(reveal(at: grown).allSatisfy { $0 == 0 })
    let partway = reveal(at: grown + 1)
    #expect(partway[0] > 0 && partway[0] > partway[14])
    #expect(partway == partway.sorted(by: >))
    #expect(reveal(at: grown + FractalGrowth.titleSeconds).allSatisfy { $0 == 1 })
    let gone = grown + FractalGrowth.titleSeconds + FractalGrowth.holdSeconds + FractalGrowth.fadeSeconds
    #expect(reveal(at: gone).allSatisfy { $0 == 0 })
  }

  @Test func withLossTheTitleStaysUntilTheLastStemFades() {
    let fadeFrom = FractalGrowth.fadeFrom(grows: true, develops: false, title: true, loss: true)
    #expect(fadeFrom == FractalGrowth.growSeconds + FractalGrowth.titleSeconds + FractalGrowth.holdSeconds
            + FractalGrowth.fallSeconds)
    func reveal(at age: Float) -> [Float] {
      FractalGrowth.titleReveal(letters: 15, age: age, grows: true, develops: false, loss: true)
    }
    #expect(reveal(at: fadeFrom - 0.1).allSatisfy { $0 == 1 })
    #expect(reveal(at: fadeFrom + FractalGrowth.fadeSeconds).allSatisfy { $0 == 0 })
  }

  @Test func theTitleIsWholeWhileStoppedAndAbsentWhenOff() throws {
    let model = fractal(grow: false)
    #expect(model.fractalTitleReveal(letters: 15, at: 3) == nil)
    set(FractalGrowth.title, to: 1, in: model)
    let reveal = try #require(model.fractalTitleReveal(letters: 15, at: 3))
    #expect(reveal.allSatisfy { $0 == 1 })
  }

  @Test func theTitleWaitsForTheGrowingPlant() throws {
    let model = fractal(grow: false)
    set(FractalGrowth.title, to: 1, in: model)
    set(FractalGrowth.cyanotypeDevelops, to: 0, in: model)
    model.toggleFractalGrowth(at: 40)
    let growing = try #require(model.fractalTitleReveal(letters: 15, at: 43))
    #expect(growing.allSatisfy { $0 == 0 })
    let printed = try #require(model.fractalTitleReveal(letters: 15, at: 40 + FractalGrowth.growSeconds + FractalGrowth.titleSeconds))
    #expect(printed.allSatisfy { $0 == 1 })
  }

  @Test func lossLengthensTheCycle() {
    let model = fractal()
    set("Seed", to: 83, in: model)
    set(FractalGrowth.cyanotypeDevelops, to: 0, in: model)
    set(FractalGrowth.title, to: 1, in: model)
    set(FractalGrowth.loss, to: 1, in: model)
    let cycle = FractalGrowth.cycleSeconds(grows: true, develops: false, title: true, loss: true)
    #expect(cycle == 6 + 3 + 3 + 6 + 1.5)
    model.updateFractalGrowth(at: 10)
    model.updateFractalGrowth(at: 10 + cycle - FractalGrowth.fallSeconds)
    #expect(value("Seed", in: model) == 83)
    model.updateFractalGrowth(at: 10 + cycle)
    #expect(value("Seed", in: model) == 84)
  }

  /// The shader draws the stages from its own copy of their lengths
  @Test func theShaderTimesTheStagesTheSame() throws {
    let url = try #require(Bundle.main.url(forResource: "ShaderSource", withExtension: "txt"))
    let source = try String(contentsOf: url, encoding: .utf8)
    let stages: [(String, Float)] = [
      ("FT_GROW_SECONDS", FractalGrowth.growSeconds), ("FT_DEVELOP_SECONDS", FractalGrowth.developSeconds),
      ("FT_TITLE_SECONDS", FractalGrowth.titleSeconds), ("FT_HOLD_SECONDS", FractalGrowth.holdSeconds),
      ("FT_FALL_SECONDS", FractalGrowth.fallSeconds), ("FT_FADE_SECONDS", FractalGrowth.fadeSeconds),
    ]
    for (name, seconds) in stages {
      let line = try #require(source.components(separatedBy: "\n").first { $0.contains("float \(name) =") })
      let number = line.split(separator: "=")[1].trimmingCharacters(in: CharacterSet(charactersIn: " f;"))
      #expect(Float(number) == seconds, "\(name) is \(number) in the shader, \(seconds) in FractalGrowth")
    }
  }
}
