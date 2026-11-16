import SwiftUI

@main
struct ShaderWatchApp: App {
  var body: some Scene {
    WindowGroup {
      WatchShaderView()
    }
  }
}

private struct WatchShaderView: View {
  @State private var selectedPreset = 0
  @State private var speed = 1.4
  @State private var showsWatchFaceLimitation = false

  var body: some View {
    ZStack {
      WatchShaderPreview(
        preset: WatchShaderPreset.allCases[selectedPreset],
        speed: speed
      )
      .id(selectedPreset)
      .transition(.opacity)
      .accessibilityLabel("\(WatchShaderPreset.allCases[selectedPreset].title) shader preview")
      .accessibilityValue("\(selectedPreset + 1) of \(WatchShaderPreset.allCases.count)")
      // Swiping up and down is the only other way to change presets
      .accessibilityAdjustableAction { direction in
        let step: Int
        switch direction {
        case .increment: step = 1
        case .decrement: step = -1
        @unknown default: return
        }
        let next = min(max(selectedPreset + step, 0), WatchShaderPreset.allCases.count - 1)
        withAnimation(.smooth) { selectedPreset = next }
      }
      .gesture(
        DragGesture(minimumDistance: 20)
          .onEnded { gesture in
            let direction = gesture.translation.height < 0 ? 1 : -1
            let next = min(
              max(selectedPreset + direction, 0),
              WatchShaderPreset.allCases.count - 1
            )
            guard next != selectedPreset else { return }
            withAnimation(.smooth) {
              selectedPreset = next
            }
          }
      )
      .ignoresSafeArea()

      VStack(spacing: 5) {
        ForEach(WatchShaderPreset.allCases.indices, id: \.self) { index in
          Circle()
            .fill(.white.opacity(index == selectedPreset ? 1 : 0.42))
            .frame(
              width: index == selectedPreset ? 6 : 5,
              height: index == selectedPreset ? 6 : 5
            )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
      .padding(.trailing, 4)
      .offset(y: -24)
      .animation(.smooth, value: selectedPreset)
      .allowsHitTesting(false)

      VStack {
        ZStack {
          HStack(spacing: 5) {
            Image(systemName: WatchShaderPreset.allCases[selectedPreset].symbol)
              .font(.caption2.weight(.semibold))
            Text(WatchShaderPreset.allCases[selectedPreset].title)
              .font(.caption.weight(.semibold))
              .contentTransition(.opacity)
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .watchGlass(in: Capsule())
          .offset(x: -4, y: -24)
          .animation(.smooth, value: selectedPreset)
          .accessibilityElement(children: .combine)
        }

        Spacer()

        VStack(spacing: 6) {
          WatchSpeedControl(
            value: $speed,
            tint: WatchShaderPreset.allCases[selectedPreset].accent
          )
          .frame(maxWidth: .infinity)
          .foregroundStyle(.white)
          .padding(.horizontal, 9)
          .padding(.vertical, 6)
          .watchGlass(in: Capsule())
          .padding(.horizontal, 5)

          Button("Set as Watch Face", systemImage: "applewatch") {
            showsWatchFaceLimitation = true
          }
          .font(.caption2.weight(.semibold))
          .buttonStyle(.plain)
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .watchGlass(in: Capsule())
        }
        .offset(y: 9)
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
    }
    .sensoryFeedback(.selection, trigger: selectedPreset)
    .alert("Watch Face Limitation", isPresented: $showsWatchFaceLimitation) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Apple Watch does not allow apps to set animated custom watch faces. A complication is the supported option.")
    }
  }
}

private struct WatchSpeedControl: View {
  @Binding var value: Double
  var tint: Color

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: "minus")
        .font(.system(size: 10, weight: .semibold))

      GeometryReader { proxy in
        let progress = (value - 0.4) / 2
        let thumbSize = 14.0
        let travel = max(0, proxy.size.width - thumbSize)

        ZStack(alignment: .leading) {
          Capsule()
            .fill(.white.opacity(0.28))
            .frame(height: 4)

          Capsule()
            .fill(tint)
            .frame(width: max(4, progress * travel + thumbSize / 2), height: 4)

          Circle()
            .fill(.white)
            .frame(width: thumbSize, height: thumbSize)
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .offset(x: progress * travel)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { gesture in
              let location = min(max(gesture.location.x - thumbSize / 2, 0), travel)
              value = 0.4 + (location / max(travel, 1)) * 2
            }
        )
      }
      .frame(height: 28)

      Image(systemName: "plus")
        .font(.system(size: 10, weight: .semibold))
    }
    .accessibilityElement()
    .accessibilityLabel("Shader speed")
    .accessibilityValue("\(value.formatted(.number.precision(.fractionLength(1)))) times")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        value = min(2.4, value + 0.2)
      case .decrement:
        value = max(0.4, value - 0.2)
      @unknown default:
        break
      }
    }
  }
}

private struct WatchShaderPreview: View {
  var preset: WatchShaderPreset
  var speed: Double
  @State private var startDate = Date()
  @Environment(\.isLuminanceReduced) private var isLuminanceReduced
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    // Paused with the wrist down, in Always On and in the background, so the preview stops
    // drawing (and blurring) 30 times a second when nobody is looking
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isLuminanceReduced || scenePhase != .active)) { timeline in
      let time = timeline.date.timeIntervalSince(startDate) * speed * preset.animationRate

      Canvas { context, size in
        preset.draw(
          in: &context,
          size: size,
          time: time,
          intensity: 0.9
        )
      }
    }
    .ignoresSafeArea()
  }
}

private enum WatchShaderPreset: String, CaseIterable, Hashable {
  case wave
  case sphere
  case dithering
  case heatmap
  case mesh
  case grainGradient
  case vortex

  var title: String {
    self == .grainGradient ? "Grain Grad" : rawValue.capitalized
  }

  var accent: Color {
    switch self {
    case .wave: return .yellow
    case .sphere: return .cyan
    case .dithering: return Color(red: 0.68, green: 0.96, blue: 0.58)
    case .heatmap: return .orange
    case .mesh: return .cyan
    case .grainGradient: return .mint
    case .vortex: return .purple
    }
  }

  var symbol: String {
    switch self {
    case .wave: return "water.waves"
    case .sphere: return "globe"
    case .dithering: return "circle.grid.3x3"
    case .heatmap: return "sun.max"
    case .mesh: return "chart.line.uptrend.xyaxis"
    case .grainGradient: return "square.3.layers.3d"
    case .vortex: return "tornado"
    }
  }

  var animationRate: Double {
    switch self {
    case .wave: return 8.8
    case .sphere: return 2.2
    case .dithering: return 1
    case .heatmap: return 1.4
    case .mesh: return 0.35
    case .grainGradient: return 1
    case .vortex: return 0.55
    }
  }

  var palette: [Color] {
    switch self {
    case .wave:
      return [
        Color(red: 1, green: 0.85, blue: 0.1),
        Color(red: 1, green: 0.45, blue: 0.05),
        Color(red: 1, green: 0.1, blue: 0.45),
        Color(red: 1, green: 0.6, blue: 0)
      ]
    case .sphere:
      return [.cyan, .blue, .purple, .pink, .white]
    case .dithering:
      return [
        Color(red: 0.84, green: 1, blue: 0.76),
        Color(red: 0.68, green: 0.96, blue: 0.58),
        Color(red: 0.42, green: 0.82, blue: 0.36),
        Color(red: 0.16, green: 0.58, blue: 0.25)
      ]
    case .heatmap:
      return [
        Color(red: 0, green: 0, blue: 0.2),
        Color(red: 0.5, green: 0, blue: 0.8),
        Color(red: 1, green: 0.1, blue: 0.1),
        Color(red: 1, green: 0.6, blue: 0),
        Color(red: 1, green: 1, blue: 0.5)
      ]
    case .mesh:
      return [
        Color(red: 0.1, green: 0.85, blue: 1),
        Color(red: 0.12, green: 0.3, blue: 1),
        Color(red: 0.75, green: 0.08, blue: 1),
        Color(red: 1, green: 0.15, blue: 0.55),
        Color(red: 1, green: 0.72, blue: 0.05)
      ]
    case .grainGradient:
      return [
        Color(red: 1, green: 0.12, blue: 0.5),
        Color(red: 1, green: 0.42, blue: 0.08),
        Color(red: 1, green: 0.86, blue: 0.12),
        Color(red: 0.18, green: 0.9, blue: 0.62),
        Color(red: 0.05, green: 0.72, blue: 1)
      ]
    case .vortex:
      return [
        .black,
        Color(red: 0.58, green: 0.08, blue: 0.95),
        .indigo,
        .blue,
        .cyan,
        .green,
        .yellow,
        .pink
      ]
    }
  }

  func draw(
    in context: inout GraphicsContext,
    size: CGSize,
    time: TimeInterval,
    intensity: Double
  ) {
    let bounds = CGRect(origin: .zero, size: size)
    let drift = (sin(time * 0.35) + 1) * 0.5
    context.fill(
      Path(bounds),
      with: .linearGradient(
        Gradient(colors: palette),
        startPoint: CGPoint(x: size.width * drift, y: 0),
        endPoint: CGPoint(x: size.width * (1 - drift), y: size.height)
      )
    )
    context.fill(Path(bounds), with: .color(.black.opacity(0.12)))

    switch self {
    case .wave:
      drawAurora(in: &context, size: size, time: time, intensity: intensity)
    case .sphere:
      drawSphere(in: &context, size: size, time: time, intensity: intensity)
    case .dithering:
      drawDithering(in: &context, size: size, time: time, intensity: intensity)
    case .heatmap:
      drawRipple(in: &context, size: size, time: time, intensity: intensity)
    case .mesh:
      drawPulse(in: &context, size: size, time: time, intensity: intensity)
    case .grainGradient:
      drawPrism(in: &context, size: size, time: time, intensity: intensity)
    case .vortex:
      drawVortex(in: &context, size: size, time: time, intensity: intensity)
    }
  }

  private func drawAurora(
    in context: inout GraphicsContext,
    size: CGSize,
    time: TimeInterval,
    intensity: Double
  ) {
    context.drawLayer { layer in
      layer.addFilter(.blur(radius: 12))

      for index in 0..<8 {
        let phase = time * 0.65 + Double(index) * 0.7
        let y = size.height * (0.02 + Double(index) * 0.14)
        var path = Path()
        path.move(to: CGPoint(x: -40, y: y))
        for step in 0...20 {
          let x = size.width * Double(step) / 20
          let wave = sin(phase + Double(step) * 0.38) * 34 * intensity
          path.addLine(to: CGPoint(x: x, y: y + wave))
        }
        layer.stroke(
          path,
          with: .color(palette[index % palette.count].opacity(0.92)),
          lineWidth: 34
        )
      }
    }
  }

  private func drawRipple(
    in context: inout GraphicsContext,
    size: CGSize,
    time: TimeInterval,
    intensity: Double
  ) {
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    for index in 0..<12 {
      let progress = (time * 0.42 + Double(index) / 12)
        .truncatingRemainder(dividingBy: 1)
      let diameter = min(size.width, size.height) * progress * 1.85
      let rect = CGRect(
        x: center.x - diameter / 2,
        y: center.y - diameter / 2,
        width: diameter,
        height: diameter
      )
      context.stroke(
        Path(ellipseIn: rect),
        with: .color(palette[index % palette.count].opacity((1 - progress) * intensity)),
        lineWidth: 5
      )
    }
  }

  private func drawPulse(
    in context: inout GraphicsContext,
    size: CGSize,
    time: TimeInterval,
    intensity: Double
  ) {
    let centerY = size.height / 2
    for line in 0..<5 {
      var path = Path()
      path.move(to: CGPoint(x: 0, y: centerY))

      for step in 0...48 {
        let x = size.width * Double(step) / 48
        let envelope = exp(-pow((x - size.width / 2) / (size.width * 0.24), 2))
        let wave = sin(Double(step) * 0.78 - time * 5 + Double(line) * 0.65)
        let offset = Double(line - 2) * 8
        let y = centerY + offset + wave * envelope * size.height * 0.34 * intensity
        path.addLine(to: CGPoint(x: x, y: y))
      }

      context.stroke(
        path,
        with: .color(palette[line % palette.count].opacity(0.9)),
        lineWidth: 4
      )
    }
  }

  private func drawPrism(
    in context: inout GraphicsContext,
    size: CGSize,
    time: TimeInterval,
    intensity: Double
  ) {
    let stripeWidth = size.width / Double(palette.count)
    let offset = sin(time * 0.8) * stripeWidth * 1.5

    for (index, color) in palette.enumerated() {
      var path = Path()
      path.move(to: CGPoint(x: Double(index) * stripeWidth + offset - stripeWidth, y: 0))
      path.addLine(to: CGPoint(x: Double(index + 2) * stripeWidth + offset, y: 0))
      path.addLine(to: CGPoint(x: Double(index) * stripeWidth - offset, y: size.height))
      path.addLine(to: CGPoint(x: Double(index - 2) * stripeWidth - offset, y: size.height))
      path.closeSubpath()
      context.fill(
        path,
        with: .color(color.opacity(0.45 + intensity * 0.55))
      )
    }
  }

  private func drawDithering(
    in context: inout GraphicsContext,
    size: CGSize,
    time: TimeInterval,
    intensity: Double
  ) {
    let cell = max(6, min(size.width, size.height) / 18)
    let columns = Int(size.width / cell) + 2
    let rows = Int(size.height / cell) + 2
    let phase = Int(time * 8)

    for row in 0..<rows {
      for column in 0..<columns {
        let value = (row * 7 + column * 13 + phase) % 11
        guard value < Int(3 + intensity * 5) else { continue }
        let rect = CGRect(
          x: Double(column) * cell,
          y: Double(row) * cell,
          width: cell - 1,
          height: cell - 1
        )
        context.fill(
          Path(rect),
          with: .color(palette[(row + column + phase) % palette.count].opacity(0.86))
        )
      }
    }
  }

  private func drawGrain(
    in context: inout GraphicsContext,
    size: CGSize,
    time: TimeInterval,
    intensity: Double
  ) {
    let frame = Int(time * 18)
    let spacing = 4.0
    let columns = Int(size.width / spacing) + 1
    let rows = Int(size.height / spacing) + 1

    for row in 0..<rows {
      for column in 0..<columns {
        let seed = (column * 37 + row * 61 + frame * 17) % 101
        let brightness = Double(seed) / 100
        guard brightness > 1 - intensity * 0.72 else { continue }
        let rect = CGRect(
          x: Double(column) * spacing,
          y: Double(row) * spacing,
          width: 2,
          height: 2
        )
        context.fill(Path(rect), with: .color(.white.opacity(brightness)))
      }
    }
  }

  private func drawFractal(
    in context: inout GraphicsContext,
    size: CGSize,
    time: TimeInterval,
    intensity: Double
  ) {
    var branches: [(start: CGPoint, end: CGPoint, angle: Double, length: Double)] = [
      (
        CGPoint(x: size.width / 2, y: size.height),
        CGPoint(x: size.width / 2, y: size.height * 0.65),
        -.pi / 2,
        size.height * 0.35
      )
    ]

    for depth in 0..<7 {
      var next: [(start: CGPoint, end: CGPoint, angle: Double, length: Double)] = []
      var path = Path()
      for branch in branches {
        path.move(to: branch.start)
        path.addLine(to: branch.end)
        let length = branch.length * 0.68
        let sway = sin(time * 0.35 + Double(depth) * 0.4) * 0.035
        for turn in [-0.48 + sway, 0.48 + sway] {
          let angle = branch.angle + turn
          let end = CGPoint(
            x: branch.end.x + cos(angle) * length,
            y: branch.end.y + sin(angle) * length
          )
          next.append((branch.end, end, angle, length))
        }
      }
      context.stroke(
        path,
        with: .color(palette[min(depth / 2 + 1, palette.count - 1)].opacity(intensity)),
        lineWidth: max(1, 5 - Double(depth) * 0.6)
      )
      branches = next
    }
  }

  private func drawSphere(
    in context: inout GraphicsContext,
    size: CGSize,
    time: TimeInterval,
    intensity: Double
  ) {
    let diameter = min(size.width, size.height) * 0.78
    let center = CGPoint(
      x: size.width / 2 + sin(time * 0.35) * 5,
      y: size.height / 2
    )
    let rect = CGRect(
      x: center.x - diameter / 2,
      y: center.y - diameter / 2,
      width: diameter,
      height: diameter
    )
    context.fill(
      Path(ellipseIn: rect),
      with: .radialGradient(
        Gradient(colors: palette.map { $0.opacity(intensity) }),
        center: CGPoint(x: center.x - diameter * 0.18, y: center.y - diameter * 0.2),
        startRadius: 2,
        endRadius: diameter * 0.58
      )
    )
    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.7)), lineWidth: 2)
  }

  private func drawVortex(
    in context: inout GraphicsContext,
    size: CGSize,
    time: TimeInterval,
    intensity: Double
  ) {
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let radius = max(size.width, size.height) * 0.72

    for arm in 0..<7 {
      var path = Path()
      for step in 0...80 {
        let progress = Double(step) / 80
        let angle = progress * .pi * 5 + time * 0.7 + Double(arm) * .pi * 2 / 7
        let distance = progress * radius
        let point = CGPoint(
          x: center.x + cos(angle) * distance,
          y: center.y + sin(angle) * distance
        )
        if step == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
      context.stroke(
        path,
        with: .color(palette[arm + 1].opacity(0.78 * intensity)),
        lineWidth: 8
      )
    }
  }
}

private extension View {
  func watchGlass<S: InsettableShape>(in shape: S) -> some View {
    background(.ultraThinMaterial, in: shape)
      .overlay {
        shape
          .stroke(.white.opacity(0.35), lineWidth: 0.75)
      }
      .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
  }
}
