import SwiftUI

// MARK: - Canvas Shapes

struct Diamond: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: rect.midX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
    p.closeSubpath()
    return p
  }
}

struct TriangleShape: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: rect.midX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.closeSubpath()
    return p
  }
}

struct HexagonShape: Shape {
  func path(in rect: CGRect) -> Path {
    let cx = rect.midX, cy = rect.midY
    let r = min(rect.width, rect.height) / 2
    var p = Path()
    for i in 0..<6 {
      let angle = CGFloat(i) * .pi / 3 - .pi / 6
      let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
      i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
  }
}

struct StarShape: Shape {
  var points: Int = 5
  func path(in rect: CGRect) -> Path {
    let cx = rect.midX, cy = rect.midY
    let outerR = min(rect.width, rect.height) / 2
    let innerR = outerR * 0.42
    var p = Path()
    for i in 0..<(points * 2) {
      let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
      let r = i.isMultiple(of: 2) ? outerR : innerR
      let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
      i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
  }
}

struct PentagonShape: Shape {
  func path(in rect: CGRect) -> Path {
    let cx = rect.midX, cy = rect.midY
    let r = min(rect.width, rect.height) / 2
    var p = Path()
    for i in 0..<5 {
      let angle = CGFloat(i) * 2 * .pi / 5 - .pi / 2
      let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
      i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
  }
}

struct ShieldShape: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    let h = rect.height
    p.move(to: CGPoint(x: rect.minX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.6))
    p.addQuadCurve(
      to: CGPoint(x: rect.midX, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    p.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.minY + h * 0.6),
      control: CGPoint(x: rect.minX, y: rect.maxY)
    )
    p.closeSubpath()
    return p
  }
}

extension View {
  @ViewBuilder
  func appGlass<S: InsettableShape>(in shape: S) -> some View {
    #if os(visionOS)
    self
      .background(.regularMaterial, in: shape)
      .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 1))
    #else
    self.glassEffect(in: shape)
    #endif
  }

  // Dark glass for app chrome — Liquid Glass lightens over bright shaders, so tint it down
  @ViewBuilder
  func appChromeGlass<S: InsettableShape>(in shape: S) -> some View {
    #if os(visionOS)
    self
      .background(.regularMaterial, in: shape)
      .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 1))
    #else
    self
      .glassEffect(.regular.tint(.black.opacity(0.55)), in: shape)
      .environment(\.colorScheme, .dark)
    #endif
  }

  // Dark surface for large chrome (panels, the drawer). Liquid Glass bends what's behind it
  // like a lens, which on a big surface reads as a reflection of the shader rather than the
  // shader itself; a material blurs exactly what sits underneath.
  //
  // `isFlattened` is for while the panel is being blurred or tilted. Those effects render the
  // panel into a single image first, and a backdrop material can't be captured that way (it
  // comes out black), so the panel wears a plain dark surface until it lands. The switch is
  // inside the background, so the panel's own content keeps its identity and state.
  func appChromePanel<S: Shape>(in shape: S, isFlattened: Bool = false) -> some View {
    self
      .background {
        if isFlattened {
          shape.fill(Color(white: 0.09).opacity(0.86))
        } else {
          shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(.black.opacity(0.4)))
        }
      }
      // Stroke then clip, so the hairline sits just inside whatever shape this is
      .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 2))
      .clipShape(shape)
      .environment(\.colorScheme, .dark)
  }

  // The compact drawer's surface, with corners concentric to the screen
  @ViewBuilder
  func appChromeDrawerGlass() -> some View {
    #if os(visionOS)
    self
      .clipShape(.rect(cornerRadius: 24))
      .appChromePanel(in: .rect(cornerRadius: 24))
    #else
    let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(20)), isUniform: false)
    self
      .clipShape(shape)
      .background(.black.opacity(0.4), in: shape)
      .background(.ultraThinMaterial, in: shape)
      .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
      .environment(\.colorScheme, .dark)
    #endif
  }

  @ViewBuilder
  func appRegularGlass<S: InsettableShape>(in shape: S) -> some View {
    #if os(visionOS)
    self
      .background(.regularMaterial, in: shape)
      .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 1))
    #else
    self.glassEffect(.regular, in: shape)
    #endif
  }

  @ViewBuilder
  func appTintedGlass<S: InsettableShape>(tint: Color, in shape: S) -> some View {
    #if os(visionOS)
    self
      .background(.regularMaterial, in: shape)
      .background(tint.opacity(0.28), in: shape)
      .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 1))
    #else
    self.glassEffect(.regular.tint(tint), in: shape)
    #endif
  }

  @ViewBuilder
  func clipToCanvasShape(_ shape: CanvasShapeType) -> some View {
    switch shape {
    case .circle:       self.clipShape(Circle())
    case .diamond:      self.clipShape(Diamond())
    case .roundedSquare: self.clipShape(RoundedRectangle(cornerRadius: 40))
    case .triangle:     self.clipShape(TriangleShape())
    case .hexagon:      self.clipShape(HexagonShape())
    case .star:         self.clipShape(StarShape())
    case .pentagon:     self.clipShape(PentagonShape())
    case .shield:       self.clipShape(ShieldShape())
    }
  }
}

struct CanvasView: View {
  var model: PlaygroundModel
  /// Half-rate updates, for soft secondary passes where 15 fps can't be told from 30.
  var usesSlowClock = false
  /// Overrides the model's render quality (the magnifier needs every pixel it enlarges).
  var qualityOverride: RenderQuality? = nil
  @Environment(\.scenePhase) private var scenePhase

  private var quality: RenderQuality { qualityOverride ?? model.renderQuality }

  var body: some View {
    // Reading only one of the two properties means this view is invalidated at that rate
    let t = usesSlowClock ? model.clock.slowTime : model.clock.time
    let shader = model.selectedShader
    let params = model.currentParams

    GeometryReader { geo in
      let size = geo.size
      if shader.fixedImageName != nil {
        fixedImageCanvas(size: size, shader: shader, params: params, t: t)
      } else if shader.needsPhoto {
        photoCanvas(size: size, shader: shader, params: params, t: t)
      } else {
        fullScreenCanvas(size: size, shader: shader, params: params, t: t)
      }
    }
    // Nothing to animate for when the scene isn't on screen
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      await model.clock.run()
    }
  }

  // Full-screen generators — no background, no dot grid, shader fills everything
  @ViewBuilder
  func fullScreenCanvas(size: CGSize, shader: ShaderDefinition, params: [ShaderParam], t: Float) -> some View {
    ZStack {
      if shader.metalFunctionName == "dithering" {
        let scale = shader.renderScale(for: quality)
        let renderSize = CGSize(width: size.width * scale, height: size.height * scale)
        // The dither cells and the label's pixels are in points: shrink them with the surface
        let lbl: DitheredLabel = {
          var label = model.ditheredLabel
          label.pixelSize *= scale
          return label
        }()
        let ditherArgs = buildDitherArgs(size: renderSize, t: t,
                                         params: shader.renderParams(params, scale: scale), lbl: lbl)
        model.backgroundColor
          .colorEffect(Shader(function: ShaderFunction(library: .default, name: "dithering"),
                              arguments: ditherArgs))
          .frame(width: renderSize.width, height: renderSize.height)
          .modifier(ReducedResolution(scale: scale))
          .frame(width: size.width, height: size.height)
          .ignoresSafeArea()
          .id(shader.id)
          .transition(.shaderSwap)
      } else {
        // Soft generators are evaluated on a smaller surface and scaled up (see renderScale)
        let scale = shader.renderScale(for: quality)
        let renderSize = CGSize(width: size.width * scale, height: size.height * scale)
        model.backgroundColor
          .modifier(ShaderEffectModifier(shader: shader, params: shader.renderParams(params, scale: scale),
                                         size: renderSize, time: t, renderScale: scale))
          .frame(width: renderSize.width, height: renderSize.height)
          .modifier(ReducedResolution(scale: scale))
          .frame(width: size.width, height: size.height)
          .ignoresSafeArea()
          .id(shader.id)
          .transition(.shaderSwap)
      }

      if shader.id == FractalGrowth.shaderID {
        FractalTitleView(model: model, time: t, size: size)
          .ignoresSafeArea()
      }

      if model.overlay.showOverlay && !model.overlay.text.isEmpty {
        CanvasOverlayView(config: model.overlay, canvasSize: size)
      }
    }
  }

  // Full-screen layer effect with a bundled (or user-set) base image
  @ViewBuilder
  func fixedImageCanvas(size: CGSize, shader: ShaderDefinition, params: [ShaderParam], t: Float) -> some View {
    let img = model.waveImage ?? shader.fixedImageName.flatMap { PlaygroundModel.loadBundledImage($0) }
    ZStack {
      if let img {
        Image(uiImage: img)
          .resizable()
          .scaledToFill()
          .frame(width: size.width, height: size.height)
          .clipped()
          .modifier(ShaderEffectModifier(shader: shader, params: params, size: size, time: t))
          .ignoresSafeArea()
      } else {
        Color.black
          .modifier(ShaderEffectModifier(shader: shader, params: params, size: size, time: t))
          .frame(width: size.width, height: size.height)
          .ignoresSafeArea()
      }

      if model.overlay.showOverlay && !model.overlay.text.isEmpty {
        CanvasOverlayView(config: model.overlay, canvasSize: size)
      }
    }
    .id(shader.id)
  }

  func labelColorRGB(_ color: Color) -> (Float, Float, Float) {
    var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (Float(r), Float(g), Float(b))
  }

  func buildDitherArgs(size: CGSize, t: Float, params: [ShaderParam], lbl: DitheredLabel) -> [Shader.Argument] {
    let rgb = labelColorRGB(lbl.labelColor)
    var args: [Shader.Argument] = [.float2(Float(size.width), Float(size.height)), .float(t)]
    args += params.map { $0.shaderArgument }
    args += [.float(lbl.enabled ? 1 : 0), .float(Float(lbl.pixelSize)), .float(Float(lbl.scale)), .float(Float(lbl.rotation))]
    args += ditherGlyphArgs(lbl)
    args += [.float(rgb.0), .float(rgb.1), .float(rgb.2)]
    return args
  }

  // Encodes up to 16 characters as glyph-index floats + count float (17 args total)
  func ditherGlyphArgs(_ label: DitheredLabel) -> [Shader.Argument] {
    let text = label.enabled ? String(label.text.uppercased().prefix(16)) : ""
    var args: [Shader.Argument] = (0..<16).map { i -> Shader.Argument in
      guard i < text.count else { return .float(36) } // space/unused
      let ch = text[text.index(text.startIndex, offsetBy: i)]
      guard let v = ch.asciiValue else { return .float(36) }
      let idx: Float
      if v >= 65 && v <= 90 { idx = Float(Int(v) - 65) }
      else if v >= 48 && v <= 57 { idx = Float(26 + Int(v) - 48) }
      else { idx = 36 }
      return .float(idx)
    }
    args.append(.float(Float(text.count)))
    return args
  }

  // Photo shaders — shaped canvas on a colored background with dot grid
  @ViewBuilder
  func photoCanvas(size: CGSize, shader: ShaderDefinition, params: [ShaderParam], t: Float) -> some View {
    let shapeSize = min(size.width, size.height) * 0.72
    ZStack {
      model.backgroundColor
        .ignoresSafeArea()

      CanvasDotGrid()
        .ignoresSafeArea()

      if shader.metalFunctionName == "rainGlass" {
        let scale = shader.renderScale(for: quality)
        let renderSize = CGSize(width: size.width * scale, height: size.height * scale)
        photoFullScreen(size: renderSize)
          .modifier(ShaderEffectModifier(shader: shader, params: params, size: renderSize, time: t,
                                         renderScale: scale))
          .frame(width: renderSize.width, height: renderSize.height)
          .modifier(ReducedResolution(scale: scale))
          .frame(width: size.width, height: size.height)
          .ignoresSafeArea()
          .id(shader.id)
          .transition(.shaderSwap)
      } else if shader.metalFunctionName == "elementalReveal" {
        photoBase(shapeSize: shapeSize)
          .layerEffect(Shader(
            function: ShaderFunction(library: .default, name: "elementalReveal"),
            arguments: [
              .float2(Float(size.width), Float(size.height)),
              .float(t),
              .float(model.revealTapTime),
            ] + params.map { $0.shaderArgument }
          ), maxSampleOffset: CGSize(width: 200, height: 200))
          .frame(width: shapeSize, height: shapeSize)
          .contentShape(Rectangle())
          .onTapGesture { model.revealTapTime = t }
          .id(shader.id)
          .transition(.shaderSwap)
      } else {
        let scale = shader.renderScale(for: quality)
        // The shader works on the photo square, so it gets the square's size, not the canvas':
        // with the canvas size its centre landed below the photo on a portrait iPhone
        photoBase(shapeSize: shapeSize * scale)
          .modifier(ShaderEffectModifier(
            shader: shader, params: shader.renderParams(params, scale: scale),
            size: CGSize(width: shapeSize * scale, height: shapeSize * scale), time: t,
            renderScale: scale))
          .frame(width: shapeSize * scale, height: shapeSize * scale)
          .modifier(ReducedResolution(scale: scale, opaque: false))
          .frame(width: shapeSize, height: shapeSize)
          .id(shader.id)
          .transition(.shaderSwap)
      }

      if model.overlay.showOverlay && !model.overlay.text.isEmpty {
        CanvasOverlayView(config: model.overlay, canvasSize: size)
      }
    }
    .frame(width: size.width, height: size.height)
  }

  @ViewBuilder
  func photoFullScreen(size: CGSize) -> some View {
    if let img = model.uploadedImage {
      Image(uiImage: img)
        .resizable()
        .scaledToFill()
        .frame(width: size.width, height: size.height)
        .clipped()
    } else if model.uploadedImageName != nil {
      // A bundled photo is still decoding: stay dark rather than flash the placeholder
      Color.black
        .frame(width: size.width, height: size.height)
    } else {
      LinearGradient(
        colors: [.indigo, .purple, .pink, .orange, .yellow],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .frame(width: size.width, height: size.height)
    }
  }

  @ViewBuilder
  func photoBase(shapeSize: CGFloat) -> some View {
    if let img = model.uploadedImage {
      Image(uiImage: img)
        .resizable()
        .scaledToFill()
        .frame(width: shapeSize, height: shapeSize)
        .clipped()
    } else if model.uploadedImageName != nil {
      Color.black
        .frame(width: shapeSize, height: shapeSize)
    } else {
      LinearGradient(
        colors: [.indigo, .purple, .pink, .orange, .yellow],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .frame(width: shapeSize, height: shapeSize)
    }
  }
}

/// Rasterizes its content at the content's own (smaller) size, then scales it up to fill.
/// Without the offscreen pass the scale would just be a transform and the shader would still
/// run for every screen pixel.
struct ReducedResolution: ViewModifier {
  var scale: CGFloat
  /// False when the content's edges move (a distortion can pull transparency inward).
  var opaque = true

  func body(content: Content) -> some View {
    if scale < 1 {
      content
        .drawingGroup(opaque: opaque)
        .scaleEffect(1 / scale)
    } else {
      content
    }
  }
}

/// The dot grid behind photo effects. It has no inputs, so the canvas' 30 fps updates never
/// redraw it; inline, its ~1,500 dots were re-filled on the CPU every frame.
struct CanvasDotGrid: View {
  var body: some View {
    Canvas { ctx, canvasSize in
      let spacing: CGFloat = 24
      let dotR: CGFloat = 1.5
      var dots = Path()
      var row = 0
      var y: CGFloat = spacing / 2
      while y < canvasSize.height {
        let xOffset = row.isMultiple(of: 2) ? 0 : spacing / 2
        var x: CGFloat = xOffset + spacing / 2
        while x < canvasSize.width {
          dots.addEllipse(in: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2))
          x += spacing
        }
        y += spacing
        row += 1
      }
      // One fill for the whole grid instead of one per dot
      ctx.fill(dots, with: .color(.primary.opacity(0.12)))
    }
  }
}

struct ShaderEffectModifier: ViewModifier {
  var shader: ShaderDefinition
  var params: [ShaderParam]
  var size: CGSize
  var time: Float
  /// Share of full resolution `size` is at. The sample padding below is in points of the
  /// full-size canvas; a smaller surface needs proportionally less, and the padding is
  /// extra layer to rasterize on all four sides every frame.
  var renderScale: CGFloat = 1

  func body(content: Content) -> some View {
    effect(on: content)
      // An animated change eases every shader argument, and a discrete one passes through values
      // that mean something else: Play moved the growth's start from -1 to now, so the plant
      // ran through its whole life in a blink. When one changes, the shader takes it at once.
      .transaction(value: params.filter(\.isDiscrete).map(\.value)) { $0.animation = nil }
  }

  @ViewBuilder
  private func effect(on content: Content) -> some View {
    let sizeArg = Shader.Argument.float2(Float(size.width), Float(size.height))
    let timeArg = Shader.Argument.float(time)
    let paramArgs = params.map { $0.shaderArgument }
    let fn = ShaderFunction(library: .default, name: shader.metalFunctionName)

    switch shader.effectType {
    case .color:
      content.colorEffect(Shader(function: fn, arguments: [sizeArg, timeArg] + paramArgs))
    case .distortion:
      content.distortionEffect(
        Shader(function: fn, arguments: [sizeArg, timeArg] + paramArgs),
        maxSampleOffset: CGSize(width: 200 * renderScale, height: 200 * renderScale)
      )
    case .layer:
      content.layerEffect(
        Shader(function: fn, arguments: [sizeArg, timeArg] + paramArgs),
        maxSampleOffset: CGSize(width: 150 * renderScale, height: 150 * renderScale)
      )
    }
  }
}

// MARK: - Canvas Overlay

struct CanvasOverlayView: View {
  var config: OverlayConfig
  var canvasSize: CGSize

  var autoFontSize: CGFloat { min(canvasSize.width, canvasSize.height) * 0.072 * config.fontSize }

  var textView: some View {
    Text(config.text)
      .font(.system(size: autoFontSize, weight: .bold, design: config.fontStyle.design))
      .foregroundStyle(config.textColor)
      .multilineTextAlignment(.center)
      .shadow(color: .black.opacity(config.showContainer ? 0 : 0.18), radius: 10, x: 0, y: 3)
  }

  @ViewBuilder
  var containerBackground: some View {
    let r = config.cornerRadius
    switch config.containerStyle {
    case .none:      EmptyView()
    case .ultraThin:
      RoundedRectangle(cornerRadius: r).fill(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: r).fill(config.containerColor))
    case .thin:
      RoundedRectangle(cornerRadius: r).fill(.thinMaterial)
        .overlay(RoundedRectangle(cornerRadius: r).fill(config.containerColor))
    case .regular:
      RoundedRectangle(cornerRadius: r).fill(.regularMaterial)
        .overlay(RoundedRectangle(cornerRadius: r).fill(config.containerColor))
    case .thick:
      RoundedRectangle(cornerRadius: r).fill(.thickMaterial)
        .overlay(RoundedRectangle(cornerRadius: r).fill(config.containerColor))
    case .glass:
      Color.clear.appRegularGlass(in: .rect(cornerRadius: r))
    case .clearGlass:
      Color.clear.appGlass(in: .rect(cornerRadius: r))
    case .glassTint:
      Color.clear.appTintedGlass(tint: config.containerColor, in: .rect(cornerRadius: r))
    }
  }

  var body: some View {
    if config.showContainer {
      textView
        .padding(config.containerPadding)
        .background(containerBackground)
    } else {
      textView
        .padding(.horizontal, canvasSize.width * 0.08)
    }
  }
}

// MARK: - Shader Swap Transition

private struct ShaderSwapModifier: ViewModifier {
  var opacity: Double
  var blur: CGFloat

  func body(content: Content) -> some View {
    content
      .opacity(opacity)
      .blur(radius: blur)
  }
}

extension AnyTransition {
  static var shaderSwap: AnyTransition {
    .modifier(
      active:   ShaderSwapModifier(opacity: 0, blur: 20),
      identity: ShaderSwapModifier(opacity: 1, blur: 0)
    )
    .combined(with: .opacity)
  }
}
