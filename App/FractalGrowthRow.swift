#if !os(tvOS)
import SwiftUI

/// The Fractal's Grow control in one capsule, drawn like the sliders around it: play or pause,
/// its name, a chip that steps through the speeds, and a menu with the ways it can grow.
struct FractalGrowthRow: View {
  var model: PlaygroundModel

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.horizontalSizeClass) private var hSizeClass

  private var isCompact: Bool { hSizeClass == .compact }
  private var height: CGFloat { isCompact ? 48 : 32 }
  // MinimalSlider's track and fill
  private var trackColor: Color { colorScheme == .light ? Color.white.opacity(0.4) : Color.primary.opacity(0.08) }
  private var fillColor: Color { colorScheme == .light ? Color.white.opacity(0.7) : Color.primary.opacity(0.2) }

  private var params: [ShaderParam] { model.shaderParams[FractalGrowth.shaderID] ?? [] }
  private var options: [ShaderParam] { params.filter { $0.shownIn == FractalGrowth.grow && $0.isToggle } }
  private var speed: String {
    let choice = params.first { $0.name == FractalGrowth.growSpeed }?.choice ?? 1
    return FractalGrowth.speeds[choice]
  }

  var body: some View {
    let isPlaying = model.fractalGrowthState == .playing
    HStack(spacing: 4) {
      Button {
        withAnimation(.snappy(duration: 0.2)) { model.toggleFractalGrowth(at: model.clock.time) }
      } label: {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: isCompact ? 15 : 11, weight: .semibold))
          .foregroundStyle(.primary.opacity(0.9))
          .contentTransition(.symbolEffect(.replace))
          .frame(width: height - 6, height: height - 6)
          .background(Circle().fill(fillColor))
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isPlaying ? "Pause Growth" : "Play Growth")

      Text(FractalGrowth.grow)
        .font(.system(size: isCompact ? 15 : 12, weight: .medium))
        .foregroundStyle(.primary.opacity(0.75))
        .padding(.leading, 4)
        .accessibilityHidden(true)

      Spacer(minLength: 4)

      Button {
        model.stepFractalGrowthSpeed(at: model.clock.time)
      } label: {
        Text(speed)
          .font(.system(size: isCompact ? 13 : 11, weight: .medium, design: .monospaced))
          .foregroundStyle(.primary.opacity(0.85))
          .padding(.horizontal, isCompact ? 12 : 9)
          .frame(maxHeight: .infinity)
          .background(Capsule().fill(fillColor))
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Growth Speed")
      .accessibilityValue(speed)
      .accessibilityHint("Changes to the next speed")

      Menu {
        ForEach(options) { option in
          Toggle(option.name, isOn: binding(for: option.name))
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: isCompact ? 15 : 12, weight: .semibold))
          .foregroundStyle(.primary.opacity(0.75))
          .frame(width: height - 6, height: height - 6)
          .contentShape(Circle())
      }
      .menuActionDismissBehavior(.disabled)
      .tint(.primary)
      .accessibilityLabel("Growth Options")
    }
    .padding(3)
    .frame(height: height)
    .background(Capsule().fill(trackColor))
    .sensoryFeedback(.selection, trigger: isPlaying)
    .sensoryFeedback(.selection, trigger: speed)
  }

  private func binding(for name: String) -> Binding<Bool> {
    Binding {
      model.shaderParams[FractalGrowth.shaderID]?.first { $0.name == name }?.isOn ?? false
    } set: { isOn in
      guard let index = model.shaderParams[FractalGrowth.shaderID]?.firstIndex(where: { $0.name == name }) else { return }
      model.shaderParams[FractalGrowth.shaderID]?[index].isOn = isOn
    }
  }
}
#endif
