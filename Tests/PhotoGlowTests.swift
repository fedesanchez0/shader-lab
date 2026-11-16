import SwiftUI
import Testing
import UIKit
@testable import Shader_Lab

@MainActor
@Suite("Photo glow")
struct PhotoGlowTests {
  /// An image that's mostly grey with a quarter of one vivid colour
  private func image(vivid: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
      UIColor(white: 0.45, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
      vivid.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
    }
  }

  private func components(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
    UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: nil)
    return (red, green, blue)
  }

  @Test func takesTheVividColourOverTheGrey() throws {
    let glow = components(try #require(PhotoGlow.color(of: image(vivid: .systemPurple))))
    #expect(glow.blue > glow.green + 0.2)
    #expect(glow.red > glow.green + 0.1)
  }

  @Test func rainsGlowIsAlwaysThePhotos() throws {
    let model = PlaygroundModel()
    model.selectedShaderID = "Rain"
    model.photoGlow = Color(red: 0.2, green: 0.9, blue: 0.3)
    let glow = try #require(model.currentParams.first { $0.name == PhotoGlow.paramName })
    #expect(glow.isHidden)
    let green = components(glow.colorValue)
    #expect(green.green > 0.8 && green.red < 0.3)
  }
}
