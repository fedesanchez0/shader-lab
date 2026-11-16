import SwiftUI
import UIKit

/// The colour a photo would cast as light, for the cabin lights of Rain's plane window: the
/// average of its pixels, weighted toward the vivid ones, so a purple sky lights the cabin
/// purple rather than a muddy grey.
enum PhotoGlow {
  /// Rain's hidden parameter that carries it to the shader
  static let paramName = "Glow"
  /// Warm amber, until a photo has been read
  static let fallback = Color(red: 1.0, green: 0.58, blue: 0.28)

  static func color(of image: UIImage) -> Color? {
    guard let cgImage = image.cgImage,
          let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    // A 16 × 16 thumbnail is plenty to read a colour from
    let side = 16
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
      guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                    bytesPerRow: side * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.interpolationQuality = .medium
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
      return true
    }
    guard drawn else { return nil }
    var sum = SIMD3<Double>(repeating: 0)
    var total = 0.0
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let pixel = SIMD3(Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2])) / 255
      let brightest = pixel.max(), darkest = pixel.min()
      let saturation = brightest > 0 ? (brightest - darkest) / brightest : 0
      let weight = saturation * saturation * brightest + 0.01
      sum += pixel * weight
      total += weight
    }
    let average = sum / total
    return Color(red: average.x, green: average.y, blue: average.z)
  }
}

extension PlaygroundModel {
  /// Reads the photo's glow off the main thread, and keeps it unless a newer photo came along
  func updatePhotoGlow(for image: UIImage?) {
    guard let image else { return }
    Task { @MainActor in
      let glow = await Task.detached(priority: .utility) { PhotoGlow.color(of: image) }.value
      guard let glow, uploadedImage === image else { return }
      photoGlow = glow
    }
  }
}
