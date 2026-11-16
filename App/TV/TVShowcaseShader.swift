#if os(tvOS)
import Foundation

/// The shaders the TV app offers: the full-screen generators that read well from across a room,
/// plus Rain over a photo. Each maps to a `ShaderDefinition` and retunes a few of its defaults
/// for a large, glanceable screen.
enum TVShowcaseShader: String, CaseIterable, Identifiable {
  case rain, wave, mesh, grain, sphere, vortex, heatmap

  var id: String { rawValue }

  /// The `ShaderDefinition` this entry renders.
  var definitionID: String {
    switch self {
    case .rain: "Rain"
    case .wave: "Wave"
    case .mesh: "Mesh"
    case .grain: "Grain Grad"
    case .sphere: "Sphere"
    case .vortex: "Vortex"
    case .heatmap: "Heatmap"
    }
  }

  var title: String {
    switch self {
    case .grain: "Grain"
    default: definitionID
    }
  }

  var symbol: String {
    switch self {
    case .rain: "cloud.rain.fill"
    case .wave: "water.waves"
    case .mesh: "square.grid.3x3.fill"
    case .grain: "circle.dotted"
    case .sphere: "circle.circle.fill"
    case .vortex: "tornado"
    case .heatmap: "thermometer.sun.fill"
    }
  }

  /// Parameter values that differ from the phone and tablet defaults.
  var tunedValues: [String: Float] {
    switch self {
    case .wave: ["Speed": 1.8, "Bands": 5.0]
    default: [:]
    }
  }
}

/// The bundled photos Rain can fall on.
enum TVRainPhoto: String, CaseIterable, Identifiable {
  case clownfish = "fish.php"
  case yosemite = "10-10"
  case elCapitan = "10-11"
  case sierra = "10-12"
  case highSierra = "10-13"
  case snowLeopard = "10-6"
  case ventura = "13-dark"

  var id: String { rawValue }
  /// Name the image loads by (see `CanvasImageStore`).
  var imageName: String { rawValue }

  var title: String {
    switch self {
    case .clownfish: "Clownfish"
    case .yosemite: "Yosemite"
    case .elCapitan: "El Capitan"
    case .sierra: "Sierra"
    case .highSierra: "High Sierra"
    case .snowLeopard: "Snow Leopard"
    case .ventura: "Ventura"
    }
  }

  /// Short name used in `shaderlab://` links.
  var slug: String { String(describing: self).lowercased() }
}
#endif
