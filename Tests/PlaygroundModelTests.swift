import Testing
import UIKit
@testable import Shader_Lab

@MainActor
@Suite("Playground model")
struct PlaygroundModelTests {
  @Test func startsOnAKnownShader() {
    let model = PlaygroundModel()
    #expect(ShaderDefinition.byID[model.selectedShaderID] != nil)
    #expect(model.currentParams.map(\.name) == model.selectedShader.defaultParams.map(\.name))
  }

  @Test func paramOrderKeepsSharedNamesAndAppendsNewOnes() {
    let model = PlaygroundModel()
    model.currentParamOrder = ["Speed", "Angle", "Bands"]
    model.updateParamOrder(to: "Heatmap")
    #expect(model.currentParamOrder == ["Speed", "Bands", "Scale"])
  }

  @Test func carriesOverAMatchingControl() {
    let model = PlaygroundModel()
    model.selectedShaderID = "Heatmap"
    model.shaderParams["Heatmap"]?[0].value = 2.5  // Speed, 0...3 percent, as on Wave
    model.carryOverSharedParams(to: "Wave")
    #expect(model.shaderParams["Wave"]?.first { $0.name == "Speed" }?.value == 2.5)
  }

  @Test func leavesAControlWithAnotherRangeAlone() {
    let model = PlaygroundModel()
    model.selectedShaderID = "Grain"  // Speed is 1...60 frames a second here
    let waveSpeed = model.shaderParams["Wave"]?.first { $0.name == "Speed" }?.value
    model.carryOverSharedParams(to: "Wave")
    #expect(model.shaderParams["Wave"]?.first { $0.name == "Speed" }?.value == waveSpeed)
    // Wave's Angle is in degrees; Chromatic's is in radians
    model.selectedShaderID = "Wave"
    let chromaticAngle = model.shaderParams["Chromatic"]?.first { $0.name == "Angle" }?.value
    model.carryOverSharedParams(to: "Chromatic")
    #expect(model.shaderParams["Chromatic"]?.first { $0.name == "Angle" }?.value == chromaticAngle)
  }

  @Test func paramOrderIgnoresUnknownShaders() {
    let model = PlaygroundModel()
    let before = model.currentParamOrder
    model.updateParamOrder(to: "Not a shader")
    #expect(model.currentParamOrder == before)
  }

  @Test("Every bundled photo loads", arguments: PlaygroundModel.bundledImageNames)
  func bundledPhotoLoads(_ name: String) async {
    let model = PlaygroundModel()
    await model.selectBundledPhoto(name).value
    #expect(model.uploadedImageName == name)
    #expect(model.uploadedImage != nil)
  }

  @Test func theLatestPickWins() async throws {
    let model = PlaygroundModel()
    // Snow Leopard is a 9 MB PNG and the clownfish a small JPEG, so the first pick tends to
    // finish last; it must not replace the second
    let first = model.selectBundledPhoto("10-6")
    let second = model.selectBundledPhoto("fish.php")
    await first.value
    await second.value
    #expect(model.uploadedImageName == "fish.php")
    // The clownfish photo is mostly green anemone; Snow Leopard's aurora is purple and blue
    let image = try #require(model.uploadedImage)
    let (red, green, blue) = averageColor(of: image)
    #expect(green > red && green > blue)
  }

  private func averageColor(of image: UIImage) -> (Double, Double, Double) {
    var pixel = [UInt8](repeating: 0, count: 4)
    let space = CGColorSpaceCreateDeviceRGB()
    pixel.withUnsafeMutableBytes { buffer in
      guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let cgImage = image.cgImage else { return }
      context.interpolationQuality = .medium
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
  }

  @Test func prewarmLoadsThePhotoAndThumbnails() async {
    let model = PlaygroundModel()
    #expect(model.uploadedImage == nil)
    #expect(!model.areThumbnailsReady)
    await model.prewarmImages()
    #expect(model.uploadedImage != nil)
    #expect(model.areThumbnailsReady)
  }
}

@Suite("Image store")
struct CanvasImageStoreTests {
  private func image(width: CGFloat, height: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
      UIColor.orange.setFill()
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
  }

  @Test func shrinksTheLongSideToTheLimit() {
    let result = CanvasImageStore.downsampled(image(width: 4000, height: 2000), maxPixels: 1000)
    #expect(result.size.width * result.scale == 1000)
    #expect(result.size.height * result.scale == 500)
  }

  @Test func leavesSmallImagesAlone() {
    let small = image(width: 300, height: 200)
    #expect(CanvasImageStore.downsampled(small, maxPixels: 1000) === small)
  }

  @Test func decodesDataStraightToTheLimit() throws {
    let data = try #require(image(width: 4000, height: 3000).jpegData(compressionQuality: 0.8))
    let result = try #require(CanvasImageStore.downsampled(data: data, maxPixels: 800))
    #expect(max(result.size.width, result.size.height) * result.scale == 800)
  }

  @Test func thumbnailsAreSmall() throws {
    let thumbnail = try #require(CanvasImageStore.thumbnail(named: "10-11"))
    let longSide = max(thumbnail.size.width, thumbnail.size.height) * thumbnail.scale
    #expect(longSide <= CanvasImageStore.thumbnailMaxPixels)
  }
}

@Suite("Render quality", .serialized)
struct RenderQualityTests {
  @Test func persistsTheChoice() {
    let original = RenderQuality.stored
    defer { original.store() }
    RenderQuality.balanced.store()
    #expect(RenderQuality.stored == .balanced)
    RenderQuality.full.store()
    #expect(RenderQuality.stored == .full)
  }
}

@MainActor
@Suite("Code viewer")
struct ShaderCodeViewTests {
  @Test("The Code tab shows the selected shader's own function", arguments: ShaderDefinition.all)
  func showsTheSelectedFunction(_ shader: ShaderDefinition) throws {
    let model = PlaygroundModel()
    model.selectedShaderID = shader.id
    let source = ShaderCodeView.extractedSource(for: model)
    let declaration = try #require(source.components(separatedBy: "\n").first { $0.contains("[[stitchable]]") })
    #expect(declaration.contains(" \(shader.metalFunctionName)("), "\(shader.name) shows: \(declaration)")
  }
}

@MainActor
@Suite("Canvas clock")
struct CanvasClockTests {
  @Test func holdsStillWhilePaused() async throws {
    let clock = CanvasClock()
    let task = Task { await clock.run() }
    defer { task.cancel() }
    try await Task.sleep(for: .milliseconds(150))
    #expect(clock.time > 0)
    clock.isPaused = true
    try await Task.sleep(for: .milliseconds(100))
    let frozen = clock.time
    try await Task.sleep(for: .milliseconds(300))
    #expect(clock.time == frozen)
    clock.isPaused = false
    try await Task.sleep(for: .milliseconds(400))
    #expect(clock.time > frozen)
  }
}
