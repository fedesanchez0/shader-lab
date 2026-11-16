#if !os(tvOS)
import Photos
import UIKit

/// Saves rendered images to the photo library and says whether that worked.
enum PhotoLibrarySaver {
  enum Failure: Error {
    case notAllowed
    case saveFailed

    var message: String {
      switch self {
      case .notAllowed: "Shader Lab isn't allowed to add photos. You can allow it in Settings › Privacy & Security › Photos."
      case .saveFailed: "The image couldn't be added to your photo library. Try again."
      }
    }
  }

  static func save(_ image: UIImage) async throws(Failure) {
    // Add-only access is all an export needs
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else { throw .notAllowed }
    do {
      try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAsset(from: image)
      }
    } catch {
      throw .saveFailed
    }
  }
}
#endif
