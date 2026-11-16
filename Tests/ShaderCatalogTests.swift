import Foundation
import Testing
@testable import Shader_Lab

@Suite("Shader catalog")
struct ShaderCatalogTests {
  @Test func identifiersAreUnique() {
    let ids = ShaderDefinition.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(ShaderDefinition.byID.count == ids.count)
  }

  @Test("Every default value sits inside its slider's range", arguments: ShaderDefinition.all)
  func defaultsAreInRange(_ shader: ShaderDefinition) {
    for param in shader.defaultParams where !param.isColor {
      #expect(param.range.contains(param.value), "\(shader.name) · \(param.name) = \(param.value) is outside \(param.range)")
    }
  }

  @Test("Every shader's Metal function is in the bundled source the code viewer shows", arguments: ShaderDefinition.all)
  func metalFunctionIsInViewerSource(_ shader: ShaderDefinition) throws {
    let url = try #require(Bundle.main.url(forResource: "ShaderSource", withExtension: "txt"))
    let source = try String(contentsOf: url, encoding: .utf8)
    #expect(source.contains(" \(shader.metalFunctionName)("), "\(shader.metalFunctionName) is missing from ShaderSource.txt")
  }

  /// Each control becomes one argument, in order, after the ones SwiftUI passes (the position,
  /// the colour or layer, the size and the time). With one missing, every later argument lands
  /// in the wrong slot. Dithering passes its label on top of its controls.
  @Test("Every shader takes an argument for each of its controls",
        arguments: ShaderDefinition.all.filter { $0.metalFunctionName != "dithering" })
  func controlsMatchTheMetalArguments(_ shader: ShaderDefinition) throws {
    let url = try #require(Bundle.main.url(forResource: "ShaderSource", withExtension: "txt"))
    let source = try String(contentsOf: url, encoding: .utf8)
    let declaration = try #require(source.range(of: " \(shader.metalFunctionName)("))
    let close = try #require(source[declaration.upperBound...].firstIndex(of: ")"))
    let arguments = source[declaration.upperBound..<close].split(separator: ",").count
    let passedBySwiftUI = shader.effectType == .distortion ? 3 : 4
    #expect(arguments - passedBySwiftUI == shader.defaultParams.count,
            "\(shader.metalFunctionName) takes \(arguments - passedBySwiftUI) values for \(shader.defaultParams.count) controls")
  }

  @Test("A choice's range is exactly its choices", arguments: ShaderDefinition.all)
  func choicesFillTheirRange(_ shader: ShaderDefinition) {
    for param in shader.defaultParams where param.isChoice {
      #expect(param.range == 0...Float(param.options.count - 1), "\(shader.name) · \(param.name)")
    }
  }

  @Test func rainStartsAtAHouseWindow() throws {
    let window = try #require(ShaderDefinition.byID["Rain"]?.defaultParams.first { $0.name == "Window" })
    #expect(window.options == ["House", "Car", "Plane"])
    #expect(window.displayString == "House")
  }

  @Test func rainStartsWithRainOnTheGlass() throws {
    let rain = try #require(ShaderDefinition.byID["Rain"]?.defaultParams.first { $0.name == "Rain" })
    #expect(rain.value > 0, "At 0% the glass is dry and Rain shows nothing")
  }

  @Test func photoSectionHoldsOnlyPhotoShaders() {
    for shader in ShaderDefinition.all where shader.showInPhotoSection {
      #expect(shader.needsPhoto)
      #expect(shader.fixedImageName == nil)
    }
  }

  @Test func fullQualityRendersEveryPixel() {
    for shader in ShaderDefinition.all {
      #expect(shader.renderScale(for: .full) == 1)
      #expect(shader.renderScale(for: .performance) <= shader.renderScale(for: .balanced))
    }
  }

  @Test func pointSizedParametersShrinkWithTheSurface() throws {
    let dithering = try #require(ShaderDefinition.byID["Dithering"])
    let scaled = dithering.renderParams(dithering.defaultParams, scale: 0.5)
    let pixelSize = try #require(dithering.defaultParams.first { $0.name == "Pixel Size" })
    let scaledPixelSize = try #require(scaled.first { $0.name == "Pixel Size" })
    #expect(scaledPixelSize.value == pixelSize.value * 0.5)
    // Relative parameters are left alone
    let zoom = try #require(scaled.first { $0.name == "Zoom" })
    #expect(zoom.value == dithering.defaultParams.first { $0.name == "Zoom" }?.value)
  }
}

@Suite("Parameter display")
struct ShaderParamDisplayTests {
  @Test func percentIsRelativeToTheRange() {
    let param = ShaderParam(name: "Speed", value: 1.5, range: 0...3, unit: .percent)
    #expect(param.displayString == "50%")
  }

  @Test func formatsEachUnit() {
    #expect(ShaderParam(name: "a", value: 0.256, unit: .decimal).displayString == "0.26")
    #expect(ShaderParam(name: "b", value: 7.6, range: 0...10, unit: .integer).displayString == "8")
    #expect(ShaderParam(name: "c", value: 35, range: 0...360, unit: .degrees).displayString == "35°")
    #expect(ShaderParam(name: "d", value: .pi, range: 0...6.3, unit: .radians).displayString == "180°")
  }

  @Test func colorsHaveNoText() {
    #expect(ShaderParam(name: "Color 1", isColor: true).displayString.isEmpty)
  }

  @Test func factorsArePercentagesOfTheUsualAmount() {
    #expect(ShaderParam(name: "Sway", value: 1, range: 0...3, unit: .factor).displayString == "100%")
    #expect(ShaderParam(name: "Sway", value: 2.5, range: 0...3, unit: .factor).displayString == "250%")
  }

  @Test func switchesSayOnOrOff() {
    var grow = ShaderParam(name: "Grow", isToggle: true)
    #expect(grow.displayString == "Off")
    grow.isOn = true
    #expect(grow.value == 1)
    #expect(grow.displayString == "On")
  }

  @Test func choicesNameTheChosenOneAndStayInRange() {
    var window = ShaderParam(name: "Window", value: 1, range: 0...2, unit: .integer, options: ["House", "Car", "Plane"])
    #expect(window.displayString == "Car")
    window.value = 7
    #expect(window.choice == 2)
    #expect(window.displayString == "Plane")
  }
}

@Suite("Code viewer source")
struct ShaderSourceSyncTests {
  /// The Code tab shows `ShaderSource.txt`, a copy of `Shaders.metal` (the .metal file is
  /// compiled, so it isn't in the bundle as text). Simulator tests can read the project folder,
  /// so this catches the copy falling behind.
  @Test func viewerSourceMatchesTheShaders() throws {
    let projectFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let shaders = try String(contentsOf: projectFolder.appending(path: "App/Shaders.metal"), encoding: .utf8)
    let bundled = try #require(Bundle.main.url(forResource: "ShaderSource", withExtension: "txt"))
    let copy = try String(contentsOf: bundled, encoding: .utf8)
    #expect(copy == shaders, "Run: cp App/Shaders.metal App/ShaderSource.txt")
  }
}

@Suite("Wallpaper size")
struct WallpaperSizeTests {
  @Test func keepsAnUprightPhoneScreen() {
    #expect(WallpaperSize.points(for: CGSize(width: 402, height: 874), isCompact: true) == CGSize(width: 402, height: 874))
  }

  @Test func turnsALandscapePhoneUpright() {
    #expect(WallpaperSize.points(for: CGSize(width: 874, height: 402), isCompact: true) == CGSize(width: 402, height: 874))
  }

  @Test func keepsAWideRegularScreen() {
    #expect(WallpaperSize.points(for: CGSize(width: 1376, height: 1032), isCompact: false) == CGSize(width: 1376, height: 1032))
  }

  @Test func fallsBackToASquareBeforeLayout() {
    #expect(WallpaperSize.points(for: .zero, isCompact: true) == CGSize(width: 1024, height: 1024))
  }
}
