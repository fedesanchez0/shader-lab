#if os(tvOS)
import Foundation

extension PlaygroundModel {
  /// Puts the TV retuning (`TVShowcaseShader.tunedValues`) into the shared parameters.
  func applyTVTuning() {
    for shader in TVShowcaseShader.allCases {
      for (name, value) in shader.tunedValues {
        guard let index = shaderParams[shader.definitionID]?.firstIndex(where: { $0.name == name }) else { continue }
        shaderParams[shader.definitionID]?[index].value = value
      }
    }
  }

  func show(_ shader: TVShowcaseShader) {
    selectedShaderID = shader.definitionID
  }

  func show(_ photo: TVRainPhoto) {
    guard uploadedImageName != photo.imageName else { return }
    selectBundledPhoto(photo.imageName)
  }
}
#endif
