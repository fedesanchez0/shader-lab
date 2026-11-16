import ImageIO
import UIKit

/// Decodes each photo once, at the size it's actually drawn.
///
/// The bundled photos are 15–20 megapixels. A photo effect pushes its image through a shader
/// on every frame, so a full-size source means resampling all of those pixels 30 times a
/// second for a canvas that can show about a quarter of them.
enum CanvasImageStore {
  /// Long side, in pixels, for an image on the canvas. About the inner display's native size.
  static let canvasMaxPixels: CGFloat = 2560
  /// Long side, in pixels, for a picker thumbnail.
  static let thumbnailMaxPixels: CGFloat = 320

  // NSCache is safe to use from any thread, and the model loads its defaults off the main actor
  private static let cache = NSCache<NSString, UIImage>()

  static func canvasImage(named name: String) -> UIImage? {
    image(named: name, maxPixels: canvasMaxPixels)
  }

  static func thumbnail(named name: String) -> UIImage? {
    image(named: name, maxPixels: thumbnailMaxPixels)
  }

  private static func image(named name: String, maxPixels: CGFloat) -> UIImage? {
    let key = "\(name)@\(Int(maxPixels))" as NSString
    if let cached = cache.object(forKey: key) { return cached }
    guard let source = loadOriginal(named: name) else { return nil }
    let image = downsampled(source, maxPixels: maxPixels)
    cache.setObject(image, forKey: key)
    return image
  }

  /// Returns `image` unchanged when it's already small enough.
  static func downsampled(_ image: UIImage, maxPixels: CGFloat) -> UIImage {
    let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    let longSide = max(pixelSize.width, pixelSize.height)
    guard longSide > maxPixels else { return image }
    let ratio = maxPixels / longSide
    let target = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())
    // The system's thumbnail path decodes at the target size where the format allows it,
    // rather than decoding all 15–20 MP and then drawing them smaller
    if let thumbnail = image.preparingThumbnail(of: target) { return thumbnail }
    // Scale 1 so the size above is in pixels; drawing also bakes in the image's orientation
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    // Photos have no alpha; skipping it saves memory and blending on every frame
    let alpha = image.cgImage?.alphaInfo
    format.opaque = alpha == nil || alpha == CGImageAlphaInfo.none || alpha == .noneSkipFirst || alpha == .noneSkipLast
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
  }

  /// Decodes encoded image data straight to at most `maxPixels` on the long side, applying its
  /// orientation, without first decoding it at full size. Safe off the main thread.
  static func downsampled(data: Data, maxPixels: CGFloat) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ] as CFDictionary
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
    return UIImage(cgImage: image)
  }

  private static func loadOriginal(named name: String) -> UIImage? {
    if let image = UIImage(named: name) { return image }
    for ext in ["jpg", "jpeg", "png", "heic"] {
      if let image = UIImage(named: "\(name).\(ext)") { return image }
      if let path = Bundle.main.path(forResource: name, ofType: ext),
         let image = UIImage(contentsOfFile: path) { return image }
    }
    return nil
  }
}
