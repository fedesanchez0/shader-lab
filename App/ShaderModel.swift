import SwiftUI
#if !os(tvOS)
import PhotosUI
#endif

enum ParamUnit {
  case percent, decimal, integer, degrees, radians
  /// A multiple of the usual amount, shown as a percentage of it: 1 is 100%
  case factor
}

struct ShaderParam: Identifiable {
  var id: String { name }
  var name: String
  var isColor: Bool = false
  var isHue: Bool = false
  /// On (1) or off (0), shown as a switch
  var isToggle: Bool = false
  /// Kept by the app for the shader, such as when an animation started: never shown as a control
  var isHidden: Bool = false
  var value: Float = 0
  var range: ClosedRange<Float> = 0...1
  var unit: ParamUnit = .decimal
  var colorValue: Color = .white
  /// Names of the choices, when the control picks one of a few. The value is the chosen index.
  var options: [String] = []
  /// The control this one is shown in, instead of a row of its own (the Fractal's growth
  /// options live in the Grow row's menu)
  var shownIn: String? = nil

  var isOn: Bool {
    get { value > 0.5 }
    set { value = newValue ? 1 : 0 }
  }

  var isChoice: Bool { !options.isEmpty }

  /// A switch, a choice or a value kept for the shader: each value means something of its own,
  /// with nothing in between to ease through
  var isDiscrete: Bool { isToggle || isChoice || isHidden }

  /// The chosen index, kept within the choices
  var choice: Int {
    get { min(max(Int(value.rounded()), 0), max(options.count - 1, 0)) }
    set { value = Float(newValue) }
  }

  var displayString: String {
    guard !isColor else { return "" }
    if isToggle { return isOn ? "On" : "Off" }
    if isChoice { return options[choice] }
    switch unit {
    case .percent:
      let ratio = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
      return String(format: "%.0f%%", ratio * 100)
    case .decimal:
      return String(format: "%.2f", value)
    case .integer:
      return String(format: "%.0f", value)
    case .degrees:
      return String(format: "%.0f°", value)
    case .radians:
      return String(format: "%.0f°", value * 180 / .pi)
    case .factor:
      return String(format: "%.0f%%", value * 100)
    }
  }

  var shaderArgument: Shader.Argument {
    isColor ? .color(colorValue) : .float(value)
  }
}

enum ShaderEffectType {
  case color, distortion, layer
}

enum ContainerStyle: String, CaseIterable, Identifiable {
  case none      = "None"
  case ultraThin = "Ultra Thin"
  case thin      = "Thin"
  case regular   = "Regular"
  case thick     = "Thick"
  case glass      = "Glass"
  case clearGlass = "Clear Glass"
  case glassTint  = "Glass + Tint"
  var id: String { rawValue }
  var isGlass: Bool { self == .glass || self == .clearGlass || self == .glassTint }
  var isMaterial: Bool { self != .none && !isGlass }
}

enum OverlayFontStyle: String, CaseIterable, Identifiable {
  case system   = "Default"
  case serif    = "Serif"
  case mono     = "Mono"
  case rounded  = "Rounded"
  var id: String { rawValue }
  var design: Font.Design {
    switch self {
    case .system:   return .default
    case .serif:    return .serif
    case .mono:     return .monospaced
    case .rounded:  return .rounded
    }
  }
}

struct OverlayConfig {
  var showOverlay: Bool = false
  var text: String = "Make iPad apps\nwith Bitrig"
  var fontSize: CGFloat = 1.0
  var fontStyle: OverlayFontStyle = .system
  var textColor: Color = .white
  var showContainer: Bool = true
  var containerStyle: ContainerStyle = .glass
  var containerColor: Color = Color.white.opacity(0.15)
  var cornerRadius: CGFloat = 32
  var containerPadding: CGFloat = 32
}

enum CanvasShapeType {
  case circle, diamond, roundedSquare, triangle, hexagon, star, pentagon, shield
}

struct ShaderDefinition: Identifiable {
  var id: String { name }
  var name: String
  var icon: String
  var effectType: ShaderEffectType
  var canvasShape: CanvasShapeType = .diamond
  var defaultParams: [ShaderParam]
  var metalFunctionName: String
  var prefersLightUI: Bool = false
  /// If non-nil, the shader uses this bundled image instead of the user's uploaded photo.
  var fixedImageName: String? = nil

  /// Share of the canvas' resolution the shader is evaluated at, per axis.
  func renderScale(for quality: RenderQuality) -> CGFloat {
    // Soft gradients are indistinguishable at half size and fine for video at a third
    let isSoft = Self.softShaderNames.contains(metalFunctionName)
    switch quality {
    case .full: return 1
    case .balanced: return isSoft ? 0.5 : 1
    case .performance: return isSoft ? 1.0 / 3.0 : 0.5
    }
  }

  /// Parameters measured in points rather than relative to the canvas. They have to shrink
  /// with the render surface, or the effect would come out larger once it's scaled back up.
  private var pointUnitParamNames: Set<String> {
    Self.pointUnitParamNamesByShader[metalFunctionName] ?? []
  }

  // Static, because these are consulted for every frame of every canvas
  private static let softShaderNames: Set<String> =
    ["heatmap", "waveGradient", "meshGradient", "sphereShader", "vortexShader"]
  private static let pointUnitParamNamesByShader: [String: Set<String>] = [
    "dithering": ["Pixel Size"],
    "chromaticAberration": ["Amount"],
  ]

  /// `params` as the shader should receive them when rendering at `scale`.
  func renderParams(_ params: [ShaderParam], scale: CGFloat) -> [ShaderParam] {
    guard scale < 1, !pointUnitParamNames.isEmpty else { return params }
    return params.map { param in
      guard pointUnitParamNames.contains(param.name) else { return param }
      var scaled = param
      scaled.value *= Float(scale)
      return scaled
    }
  }

  /// Distortion and layer shaders operate on an image — they need a photo.
  var needsPhoto: Bool { effectType == .distortion || effectType == .layer }
  /// Shows in the Photo Effects section (needs user photo, not a bundled one).
  var showInPhotoSection: Bool { needsPhoto && fixedImageName == nil }
}

extension ShaderDefinition {
  /// Looked up on every frame, so not a linear search
  static let byID: [String: ShaderDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

  static let all: [ShaderDefinition] = [
    ShaderDefinition(
      name: "Heatmap",
      icon: "sun.max",
      effectType: .color,
      canvasShape: .triangle,
      defaultParams: [
        ShaderParam(name: "Speed", value: 0.6,  range: 0...3,   unit: .percent),
        ShaderParam(name: "Scale", value: 0.12, range: 0...3, unit: .percent),
        ShaderParam(name: "Bands", value: 3.0,  range: 1...8,  unit: .integer),
      ],
      metalFunctionName: "heatmap"
    ),
    ShaderDefinition(
      name: "Wave",
      icon: "water.waves",
      effectType: .color,
      canvasShape: .roundedSquare,
      defaultParams: [
        ShaderParam(name: "Color 1", isColor: true, colorValue: Color(red: 1.0,  green: 0.85, blue: 0.10)),
        ShaderParam(name: "Color 2", isColor: true, colorValue: Color(red: 1.0,  green: 0.45, blue: 0.05)),
        ShaderParam(name: "Color 3", isColor: true, colorValue: Color(red: 1.0,  green: 0.10, blue: 0.45)),
        ShaderParam(name: "Color 4", isColor: true, colorValue: Color(red: 1.0,  green: 0.60, blue: 0.00)),
        ShaderParam(name: "Speed",     value: 1.8,  range: 0...3,   unit: .percent),
        ShaderParam(name: "Bands",     value: 5.0,  range: 1...8,   unit: .decimal),
        ShaderParam(name: "Angle",     value: 35,   range: 0...360, unit: .degrees),
        ShaderParam(name: "Warp",      value: 0.6,  range: 0...1,   unit: .decimal),
        ShaderParam(name: "Smoothness",value: 0.7,  range: 0...1,   unit: .decimal),
        ShaderParam(name: "Radial",    value: 0.0,  range: 0...1,   unit: .decimal),
      ],
      metalFunctionName: "waveGradient",
      prefersLightUI: false
    ),
    ShaderDefinition(
      name: "Mesh",
      icon: "chart.line.uptrend.xyaxis",
      effectType: .color,
      canvasShape: .hexagon,
      defaultParams: [
        ShaderParam(name: "Speed", value: 0.6, range: 0...3, unit: .percent),
        ShaderParam(name: "Scale", value: 1.0, range: 0.1...3, unit: .percent),
        ShaderParam(name: "Hue Shift", value: 0.0, range: 0...1, unit: .decimal),
      ],
      metalFunctionName: "meshGradient"
    ),
    ShaderDefinition(
      name: "Grain Grad",
      icon: "square.3.layers.3d",
      effectType: .color,
      canvasShape: .circle,
      defaultParams: [
        ShaderParam(name: "Speed", value: 1.68,  range: 0...3,   unit: .percent),
        ShaderParam(name: "Scale", value: 2.449, range: 0.1...3, unit: .percent),
        ShaderParam(name: "Color Shift", value: 0.0, range: 0...1, unit: .decimal),
      ],
      metalFunctionName: "grainGradient"
    ),
    ShaderDefinition(
      name: "Dithering",
      icon: "circle.grid.3x3",
      effectType: .color,
      canvasShape: .diamond,
      defaultParams: [
        ShaderParam(name: "Pixel Size", value: 4.0,  range: 1...16,  unit: .integer),
        ShaderParam(name: "Zoom",       value: 1.0,  range: 0.1...3, unit: .decimal),
        ShaderParam(name: "Speed",      value: 0.5,  range: 0...3,   unit: .percent),
        ShaderParam(name: "Rotation",   value: 0.0,  range: 0...360, unit: .degrees),
        ShaderParam(name: "Tint",       isHue: true, value: 0.5, range: 0...1),
      ],
      metalFunctionName: "dithering"
    ),
    ShaderDefinition(
      name: "Grain",
      icon: "sparkles",
      effectType: .color,
      canvasShape: .star,
      defaultParams: [
        ShaderParam(name: "Intensity", value: 0.5, range: 0...1, unit: .percent),
        ShaderParam(name: "Speed", value: 24.0, range: 1...60, unit: .integer),
        ShaderParam(name: "Colorize", value: 0.0, range: 0...1, unit: .percent),
      ],
      metalFunctionName: "grain"
    ),
    ShaderDefinition(
      name: "Fractal",
      icon: "tree",
      effectType: .color,
      canvasShape: .pentagon,
      // In the order fractalTree takes them. The defaults print the seaweed of the Geometry of
      // Grief cover: cobalt paper, an icy white plant. The print takes its tint from the paper.
      // Speed and Sway set how fast and how far it sways. Grow plays the plant's life on a loop,
      // a new seed each time (see FractalGrowth); its speed and the options after it live in
      // its row. Title prints the book's title at the top left (FractalTitleView); Loss ends each
      // loop with gusts of wind that tear the plant apart down to its main stem.
      defaultParams: [
        ShaderParam(name: "Depth",   value: 11.0, range: 4...13,    unit: .integer),
        ShaderParam(name: "Angle",   value: 28.0, range: 8...55,    unit: .degrees),
        ShaderParam(name: "Ratio",   value: 0.68, range: 0.5...0.8, unit: .decimal),
        ShaderParam(name: "Organic", value: 1.0,  range: 0...1,     unit: .percent),
        ShaderParam(name: "Seed",    value: 21,   range: 0...99,    unit: .integer),
        ShaderParam(name: "Speed",   value: 1.0,  range: 0...3,     unit: .percent),
        ShaderParam(name: "Sway",    value: 1.0,  range: 0...3,     unit: .factor),
        ShaderParam(name: "Texture", value: 0.6,  range: 0...1,     unit: .percent),
        ShaderParam(name: "Paper",   isHue: true, value: 0.5714, range: 0...1),
        ShaderParam(name: FractalGrowth.grow, isToggle: true, value: 0),
        ShaderParam(name: FractalGrowth.growSpeed, value: 1, range: 0...2, unit: .integer,
                    options: FractalGrowth.speeds, shownIn: FractalGrowth.grow),
        ShaderParam(name: FractalGrowth.organicGrowth, isToggle: true, value: 1, shownIn: FractalGrowth.grow),
        ShaderParam(name: FractalGrowth.fractalLevels, isToggle: true, value: 0, shownIn: FractalGrowth.grow),
        ShaderParam(name: FractalGrowth.cyanotypeDevelops, isToggle: true, value: 1, shownIn: FractalGrowth.grow),
        ShaderParam(name: FractalGrowth.title, isToggle: true, value: 0, shownIn: FractalGrowth.grow),
        ShaderParam(name: FractalGrowth.loss, isToggle: true, value: 0, shownIn: FractalGrowth.grow),
        ShaderParam(name: FractalGrowth.growStart, isHidden: true, value: -1,
                    range: -1...Float.greatestFiniteMagnitude),
        ShaderParam(name: FractalGrowth.growPaused, isHidden: true, value: -1,
                    range: -1...Float.greatestFiniteMagnitude),
      ],
      metalFunctionName: "fractalTree"
    ),
    ShaderDefinition(
      name: "Sphere",
      icon: "globe",
      effectType: .color,
      canvasShape: .roundedSquare,
      defaultParams: [
        ShaderParam(name: "Speed",        value: 0.4,  range: 0...3,   unit: .percent),
        ShaderParam(name: "Roughness",    value: 0.25, range: 0...1,   unit: .decimal),
        ShaderParam(name: "Iridescence",  value: 0.7,  range: 0...1,   unit: .decimal),
        ShaderParam(name: "Hue",          value: 0.55, range: 0...1,   unit: .decimal),
      ],
      metalFunctionName: "sphereShader"
    ),
    ShaderDefinition(
      name: "Vortex",
      icon: "tornado",
      effectType: .color,
      canvasShape: .circle,
      defaultParams: [
        ShaderParam(name: "Speed",  value: 0.27, range: 0...3,  unit: .percent),
        ShaderParam(name: "Twist",  value: 0.03, range: 0...12, unit: .decimal),
        ShaderParam(name: "Scale",  value: 1.26, range: 0.5...4, unit: .decimal),
      ],
      metalFunctionName: "vortexShader"
    ),
    ShaderDefinition(
      name: "Warp",
      icon: "waveform",
      effectType: .distortion,
      canvasShape: .shield,
      defaultParams: [
        ShaderParam(name: "Amplitude", value: 2.0, range: 0...5, unit: .percent),
        ShaderParam(name: "Frequency", value: 3.0, range: 0.5...10, unit: .decimal),
        ShaderParam(name: "Speed", value: 1.5, range: 0...5, unit: .percent),
      ],
      metalFunctionName: "warpDistortion"
    ),
    ShaderDefinition(
      name: "Ripple",
      icon: "drop",
      effectType: .distortion,
      canvasShape: .diamond,
      defaultParams: [
        ShaderParam(name: "Amplitude", value: 2.0, range: 0...5, unit: .percent),
        ShaderParam(name: "Frequency", value: 8.0, range: 1...20, unit: .decimal),
        ShaderParam(name: "Speed", value: 4.0, range: 0...10, unit: .percent),
      ],
      metalFunctionName: "rippleDistortion"
    ),
    ShaderDefinition(
      name: "Pinch",
      icon: "arrow.up.left.and.down.right.magnifyingglass",
      effectType: .distortion,
      canvasShape: .star,
      defaultParams: [
        ShaderParam(name: "Strength", value: 0.7, range: 0...1.5, unit: .percent),
        ShaderParam(name: "Radius", value: 0.5, range: 0.1...1, unit: .percent),
        ShaderParam(name: "Speed", value: 1.0, range: 0...3, unit: .percent),
      ],
      metalFunctionName: "pinchDistortion"
    ),
    ShaderDefinition(
      name: "Fluted Glass",
      icon: "rectangle.split.3x1",
      effectType: .layer,
      canvasShape: .roundedSquare,
      defaultParams: [
        // shape: 0=Lines 1=Irregular 2=Wave 3=Zigzag 4=Pattern
        ShaderParam(name: "Shape",      value: 0.0,  range: 0...4,       unit: .integer),
        ShaderParam(name: "Size",       value: 0.05, range: 0.005...0.3, unit: .percent),
        ShaderParam(name: "Highlights", value: 0.1,  range: 0...1,       unit: .percent),
        ShaderParam(name: "Shadows",    value: 0.5,  range: 0...1,       unit: .percent),
        ShaderParam(name: "Angle",      value: 0.0,  range: 0...360,     unit: .degrees),
        ShaderParam(name: "Distortion", value: 0.6,  range: 0...1,       unit: .percent),
        ShaderParam(name: "Shift",      value: 0.0,  range: 0...1,       unit: .percent),
        ShaderParam(name: "Stretch",    value: 0.0,  range: 0...1,       unit: .percent),
        ShaderParam(name: "Blur",       value: 0.0,  range: 0...1,       unit: .percent),
        ShaderParam(name: "Edges",      value: 0.25, range: 0...1,       unit: .percent),
      ],
      metalFunctionName: "flutedGlass"
    ),
    ShaderDefinition(
      name: "Chromatic",
      icon: "rays",
      effectType: .layer,
      canvasShape: .pentagon,
      defaultParams: [
        ShaderParam(name: "Amount", value: 8.0, range: 0...40, unit: .percent),
        ShaderParam(name: "Angle", value: 0.0, range: 0...6.28318, unit: .radians),
      ],
      metalFunctionName: "chromaticAberration"
    ),
    ShaderDefinition(
      name: "Rain",
      icon: "cloud.rain",
      effectType: .layer,
      canvasShape: .roundedSquare,
      defaultParams: [
        // Some rain from the start: at 0% the glass is dry and the effect shows nothing
        ShaderParam(name: "Rain",  value: 0.7, range: 0...1, unit: .percent),
        ShaderParam(name: "Speed", value: 1.0, range: 0...3, unit: .percent),
        ShaderParam(name: "Zoom",  value: 0.12, range: 0...0.25, unit: .percent),
        // What you watch the rain through: a house window, where the drops slide down; a car's
        // windshield, where the wind pushes them up; or a plane's, where they streak back
        ShaderParam(name: "Window", value: 0, range: 0...2, unit: .integer, options: ["House", "Car", "Plane"]),
        // The plane cabin's lights take the photo's colour (filled in by currentParams)
        ShaderParam(name: PhotoGlow.paramName, isColor: true, isHidden: true, colorValue: PhotoGlow.fallback),
      ],
      metalFunctionName: "rainGlass"
    ),
  ]
}

struct DitheredLabel {
  var enabled: Bool = false
  var text: String = "BITRIG"
  var pixelSize: CGFloat = 6
  var rotation: Double = 0
  var scale: Double = 1.0
  var labelColor: Color = .white
}

@Observable
class PlaygroundModel {
  var selectedShaderID: String = "Wave"
  var renderQuality = RenderQuality.stored {
    didSet { renderQuality.store() }
  }
  /// Shader time. Lives on the model so every canvas shares it and the animation doesn't
  /// restart when a canvas is rebuilt, such as moving between the Duo's two displays.
  let clock = CanvasClock()
  var shaderParams: [String: [ShaderParam]] = Dictionary(
    uniqueKeysWithValues: ShaderDefinition.all.map { ($0.id, $0.defaultParams) }
  )
  var backgroundColor: Color = .black
  var overlay = OverlayConfig()
  var ditheredLabel = DitheredLabel()
  var currentParamOrder: [String] = ["Speed", "Angle", "Bands", "Color 1", "Color 2", "Color 3", "Color 4", "Warp", "Smoothness", "Radial"]
  /// Decoded off the main thread by `selectBundledPhoto` / `prewarmImages`; nil until then.
  var uploadedImage: UIImage? {
    didSet { updatePhotoGlow(for: uploadedImage) }
  }
  /// The colour of light the photo casts: Rain's cabin lights at the plane window (PhotoGlow)
  var photoGlow: Color = PhotoGlow.fallback
  /// Which bundled photo `uploadedImage` is, or nil for a photo from the library.
  var uploadedImageName: String? = "10-11"
  /// The photo a fixed-image shader draws on, when the user picks one. Nil means the shader's
  /// own `fixedImageName`, loaded only when such a shader is on screen (none is today).
  var waveImage: UIImage?
  #if !os(tvOS)
  var imageItem: PhotosPickerItem? = nil
  #endif

  /// The bundled photo, decoded once at canvas size (see `CanvasImageStore`).
  static func loadBundledImage(_ name: String) -> UIImage? {
    CanvasImageStore.canvasImage(named: name)
  }

  static let bundledImageNames = ["10-11", "10-12", "10-13", "10-10", "10-6", "fish.php", "13-dark"]

  /// A readable name for a bundled photo, for VoiceOver and the TV picker.
  static func bundledPhotoTitle(_ name: String) -> String {
    switch name {
    case "fish.php": "Clownfish"
    case "10-6": "Snow Leopard"
    case "10-10": "Yosemite"
    case "10-11": "El Capitan"
    case "10-12": "Sierra"
    case "10-13": "High Sierra"
    case "13-dark": "Ventura"
    case "val-toch-BHeQQmZM8jE-unsplash": "Orange"
    default: name
    }
  }

  /// True once the picker thumbnails are decoded (see `prewarmImages`). Views show a
  /// placeholder until then rather than decoding 15–20 MP photos in their body.
  var areThumbnailsReady = false

  /// Shows one of the bundled photos on the canvas. The photo is decoded off the main thread;
  /// the canvas keeps the previous photo until it's ready.
  @discardableResult
  func selectBundledPhoto(_ name: String) -> Task<Void, Never> {
    uploadedImageName = name
    return Task { @MainActor in
      let image = await Task.detached(priority: .userInitiated) { Self.loadBundledImage(name) }.value
      // A newer pick wins
      guard uploadedImageName == name else { return }
      uploadedImage = image
    }
  }

  /// Decodes the current photo and every picker thumbnail on a background task, once at launch.
  @MainActor
  func prewarmImages() async {
    if uploadedImage == nil, let name = uploadedImageName {
      await selectBundledPhoto(name).value
    }
    guard !areThumbnailsReady else { return }
    let names = Self.bundledImageNames
    await Task.detached(priority: .utility) {
      for name in names { _ = CanvasImageStore.thumbnail(named: name) }
    }.value
    areThumbnailsReady = true
  }
  var revealTapTime: Float = -100
  #if os(visionOS)
  /// Whether the immersive shader space is showing, kept by the space's own appear/disappear.
  var isImmersiveSpaceOpen = false
  #endif

  init() {
    // The Fractal's Grow loop moves on with the clock
    clock.onTick = { [weak self] time in self?.updateFractalGrowth(at: time) }
  }

  var selectedShader: ShaderDefinition {
    ShaderDefinition.byID[selectedShaderID]!
  }

  var currentParams: [ShaderParam] {
    var params = shaderParams[selectedShaderID] ?? selectedShader.defaultParams
    // A shader's Glow is always the photo's, whatever was stored or reset
    if let glow = params.firstIndex(where: { $0.name == PhotoGlow.paramName }) {
      params[glow].colorValue = photoGlow
    }
    return params
  }

  /// Carries the current shader's values over to `newID` where both have the same control:
  /// same name, range and unit. Speed on Wave (0–3) and Speed on Grain (1–60 fps) share a name
  /// but not a meaning, so they're left alone.
  func carryOverSharedParams(to newID: String) {
    guard newID != selectedShaderID, var target = shaderParams[newID] else { return }
    for param in currentParams where !param.isColor && !param.isHidden {
      guard let index = target.firstIndex(where: {
        $0.name == param.name && $0.range == param.range && $0.unit == param.unit && !$0.isColor
          && !$0.isHidden
      }) else { continue }
      target[index].value = param.value
    }
    shaderParams[newID] = target
  }

  func updateParamOrder(to newID: String) {
    guard let newParamNames = shaderParams[newID]?.map(\.name) else { return }
    let newSet = Set(newParamNames)
    var result = currentParamOrder.filter { newSet.contains($0) }
    let seen = Set(result)
    result += newParamNames.filter { !seen.contains($0) }
    currentParamOrder = result
  }

  #if !os(tvOS)
  /// Loads the photo picked from the library. The canvas reads `uploadedImage` on the main
  /// actor every frame, so it's only ever set there.
  @MainActor
  func loadImage() async {
    guard let item = imageItem else { return }
    // Cleared so picking the same photo again (after a bundled one) loads it again
    defer { imageItem = nil }
    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
    // A camera photo is 12–48 MP. Decode it straight to canvas size, off the main actor,
    // instead of decoding every pixel first
    let image = await Task.detached(priority: .userInitiated) {
      CanvasImageStore.downsampled(data: data, maxPixels: CanvasImageStore.canvasMaxPixels)
    }.value
    guard let image else { return }
    uploadedImage = image
    uploadedImageName = nil
  }
  #endif
}
