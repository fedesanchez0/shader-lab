#if os(tvOS)
import Foundation

/// A `shaderlab://shader/<name>?photo=<photo>&chrome=hidden` link: opens the TV app on a shader,
/// optionally a Rain photo, optionally with the controls hidden. Used for scripted screenshots.
struct TVLaunchLink: Equatable {
  var shader: TVShowcaseShader?
  var photo: TVRainPhoto?
  var hidesChrome: Bool?

  init?(url: URL) {
    guard url.scheme == "shaderlab",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    let name = url.host == "shader"
      ? url.pathComponents.last { $0 != "/" }
      : components.queryItems?.first { $0.name == "name" }?.value
    shader = name.flatMap { TVShowcaseShader(rawValue: $0.lowercased()) }
    let photoName = components.queryItems?.first { $0.name == "photo" }?.value?.lowercased()
    photo = TVRainPhoto.allCases.first { $0.slug == photoName }
    switch components.queryItems?.first(where: { $0.name == "chrome" })?.value {
    case "hidden": hidesChrome = true
    case "shown": hidesChrome = false
    default: hidesChrome = nil
    }
  }
}
#endif
