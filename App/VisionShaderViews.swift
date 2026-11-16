#if os(visionOS)
import SwiftUI
import RealityKit

struct VisionShaderLobbyView: View {
  var model: PlaygroundModel
  @Environment(\.openImmersiveSpace) private var openImmersiveSpace
  @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
  @State private var isOpeningSpace = false
  @State private var spaceMessage: String?

  private var colorShaders: [ShaderDefinition] {
    ShaderDefinition.all.filter { $0.effectType == .color }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          header

          CanvasView(model: model)
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .bottomLeading) {
              Text(model.selectedShader.name)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                .padding(28)
            }
            .appGlass(in: .rect(cornerRadius: 28))

          LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            ForEach(colorShaders) { shader in
              Button {
                selectShader(shader)
              } label: {
                VisionShaderTile(shader: shader, isSelected: model.selectedShaderID == shader.id)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(.black.opacity(0.08))
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Shader Space")
          .font(.system(size: 52, weight: .bold))
        Text("Open an immersive shader room with floating controls and a live canvas.")
          .font(.system(size: 19, weight: .medium))
          .foregroundStyle(.secondary)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 8) {
        Button {
          Task {
            isOpeningSpace = true
            defer { isOpeningSpace = false }

            if model.isImmersiveSpaceOpen {
              await dismissImmersiveSpace()
              spaceMessage = "Space closed"
            } else {
              let result = await openImmersiveSpace(id: VisionShaderImmersiveView.spaceID)
              switch result {
              case .opened:
                spaceMessage = "Space open"
              case .userCancelled:
                spaceMessage = "Opening was cancelled"
              case .error:
                spaceMessage = "Immersive spaces are unavailable here"
              @unknown default:
                spaceMessage = "Immersive space could not open"
              }
            }
          }
        } label: {
          Label(model.isImmersiveSpaceOpen ? "Close Space" : "Open Space", systemImage: model.isImmersiveSpaceOpen ? "xmark" : "visionpro")
            .font(.system(size: 18, weight: .semibold))
            .padding(.horizontal, 20)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isOpeningSpace)
        .accessibilityLabel(model.isImmersiveSpaceOpen ? "Close immersive shader space" : "Open immersive shader space")

        if let spaceMessage {
          Text(spaceMessage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func selectShader(_ shader: ShaderDefinition) {
    model.updateParamOrder(to: shader.id)
    withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
      model.selectedShaderID = shader.id
    }
  }
}

struct VisionShaderImmersiveView: View {
  static let spaceID = "shader-space"

  var model: PlaygroundModel
  @State private var selectionPulse = 0

  private var featuredShaders: [ShaderDefinition] {
    Array(ShaderDefinition.all.filter { $0.effectType == .color }.prefix(9))
  }

  var body: some View {
    immersiveScene
      // The system can close the space too (a Digital Crown press), so the lobby's button
      // follows the space itself rather than its own guess
      .onAppear { model.isImmersiveSpaceOpen = true }
      .onDisappear { model.isImmersiveSpaceOpen = false }
  }

  private var immersiveScene: some View {
    RealityView { content, attachments in
      addAttachment("main-canvas", from: attachments, to: content, position: [0, 1.35, -1.35], scale: 1.18)
      addAttachment("controls", from: attachments, to: content, position: [0.72, 1.2, -1.05], rotationY: -.pi / 9, scale: 0.85)
      addAttachment("shader-ring", from: attachments, to: content, position: [-0.78, 1.18, -1.08], rotationY: .pi / 8, scale: 0.8)
      addAttachment("floor-glow", from: attachments, to: content, position: [0, 0.42, -1.55], rotationX: -.pi / 2, scale: 1.25)
    } update: { content, attachments in
      updateAttachment("main-canvas", from: attachments, in: content, position: [0, 1.35, -1.35], scale: 1.18)
      updateAttachment("controls", from: attachments, in: content, position: [0.72, 1.2, -1.05], rotationY: -.pi / 9, scale: 0.85)
      updateAttachment("shader-ring", from: attachments, in: content, position: [-0.78, 1.18, -1.08], rotationY: .pi / 8, scale: 0.8)
      updateAttachment("floor-glow", from: attachments, in: content, position: [0, 0.42, -1.55], rotationX: -.pi / 2, scale: 1.25)
    } attachments: {
      Attachment(id: "main-canvas") {
        VisionFloatingCanvas(model: model)
      }
      Attachment(id: "controls") {
        VisionControlPanel(model: model)
      }
      Attachment(id: "shader-ring") {
        VisionShaderRingPanel(model: model, shaders: featuredShaders, selectionPulse: $selectionPulse)
      }
      Attachment(id: "floor-glow") {
        VisionFloorGlow(model: model, pulse: selectionPulse)
      }
    }
  }

  private func addAttachment(
    _ id: String,
    from attachments: RealityViewAttachments,
    to content: RealityViewContent,
    position: SIMD3<Float>,
    rotationX: Float = 0,
    rotationY: Float = 0,
    scale: Float = 1
  ) {
    guard let entity = attachments.entity(for: id) else { return }
    applyTransform(to: entity, position: position, rotationX: rotationX, rotationY: rotationY, scale: scale)
    content.add(entity)
  }

  private func updateAttachment(
    _ id: String,
    from attachments: RealityViewAttachments,
    in content: RealityViewContent,
    position: SIMD3<Float>,
    rotationX: Float = 0,
    rotationY: Float = 0,
    scale: Float = 1
  ) {
    guard let entity = attachments.entity(for: id) else { return }
    applyTransform(to: entity, position: position, rotationX: rotationX, rotationY: rotationY, scale: scale)
  }

  private func applyTransform(
    to entity: Entity,
    position: SIMD3<Float>,
    rotationX: Float,
    rotationY: Float,
    scale: Float
  ) {
    entity.position = position
    entity.orientation = simd_quatf(angle: rotationY, axis: [0, 1, 0]) * simd_quatf(angle: rotationX, axis: [1, 0, 0])
    entity.scale = [scale, scale, scale]
  }
}

struct VisionFloatingCanvas: View {
  var model: PlaygroundModel

  var body: some View {
    CanvasView(model: model)
      .frame(width: 700, height: 700)
      .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 48, style: .continuous)
          .strokeBorder(.white.opacity(0.18), lineWidth: 2)
      }
      .overlay(alignment: .bottomLeading) {
        Text(model.selectedShader.name)
          .font(.system(size: 44, weight: .bold))
          .foregroundStyle(.white)
          .padding(32)
          .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
      }
      .shadow(color: .black.opacity(0.35), radius: 36, y: 18)
      .accessibilityLabel("Live shader canvas")
  }
}

struct VisionControlPanel: View {
  var model: PlaygroundModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Label("Controls", systemImage: "slider.horizontal.3")
          .font(.system(size: 24, weight: .semibold))
        Spacer()
        Button("Reset") {
          let shaderID = model.selectedShaderID
          model.shaderParams[shaderID] = model.selectedShader.defaultParams
          model.currentParamOrder = model.selectedShader.defaultParams.map(\.name)
        }
        .font(.system(size: 15, weight: .semibold))
      }

      ParametersView(model: model, showLabel: false)
    }
    .padding(24)
    .frame(width: 360)
    .appGlass(in: .rect(cornerRadius: 28))
    .accessibilityLabel("Shader controls")
  }
}

struct VisionShaderRingPanel: View {
  var model: PlaygroundModel
  var shaders: [ShaderDefinition]
  @Binding var selectionPulse: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Shaders", systemImage: "square.3.layers.3d")
        .font(.system(size: 24, weight: .semibold))

      LazyVGrid(columns: [GridItem(.fixed(92)), GridItem(.fixed(92)), GridItem(.fixed(92))], spacing: 10) {
        ForEach(shaders) { shader in
          Button {
            model.updateParamOrder(to: shader.id)
            withAnimation(.bouncy) {
              model.selectedShaderID = shader.id
              selectionPulse += 1
            }
          } label: {
            VisionShaderTile(shader: shader, isSelected: model.selectedShaderID == shader.id)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(24)
    .appGlass(in: .rect(cornerRadius: 28))
    .accessibilityLabel("Shader picker")
  }
}

struct VisionShaderTile: View {
  var shader: ShaderDefinition
  var isSelected: Bool

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: shader.icon)
        .font(.system(size: 28, weight: .medium))
        .symbolEffect(.bounce, value: isSelected)
      Text(shader.name)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    .frame(maxWidth: .infinity)
    .frame(height: 96)
    .padding(.horizontal, 8)
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(isSelected ? Color.blue.opacity(0.72) : Color.white.opacity(0.08))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(isSelected ? .white.opacity(0.6) : .white.opacity(0.12), lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .accessibilityLabel(shader.name)
  }
}

struct VisionFloorGlow: View {
  var model: PlaygroundModel
  var pulse: Int

  var body: some View {
    ZStack {
      Circle()
        .fill(
          RadialGradient(
            colors: [.white.opacity(0.18), .blue.opacity(0.16), .clear],
            center: .center,
            startRadius: 10,
            endRadius: 260
          )
        )
      Circle()
        .stroke(.white.opacity(0.12), lineWidth: 2)
        .padding(46)
      Text(model.selectedShader.name)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.white.opacity(0.72))
    }
    .frame(width: 560, height: 560)
    .scaleEffect(pulse.isMultiple(of: 2) ? 1 : 1.04)
    .animation(.spring(duration: 0.45, bounce: 0.2), value: pulse)
    .allowsHitTesting(false)
  }
}
#endif
