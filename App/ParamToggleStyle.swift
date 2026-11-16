#if !os(tvOS)
import SwiftUI

/// A parameter switch drawn like the sliders around it: a capsule with the control's name that
/// fills edge to edge when on and empties when off, with On or Off at the trailing end so the
/// state doesn't rest on the fill alone. Tapping anywhere on it toggles it.
struct ParamToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    ParamToggleCapsule(configuration: configuration)
  }
}

private struct ParamToggleCapsule: View {
  var configuration: ToggleStyleConfiguration

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.horizontalSizeClass) private var hSizeClass

  private var isCompact: Bool { hSizeClass == .compact }
  // MinimalSlider's track and fill, so a switch that's on looks like a slider at 100%
  private var trackColor: Color { colorScheme == .light ? Color.white.opacity(0.4) : Color.primary.opacity(0.08) }
  private var fillColor: Color { colorScheme == .light ? Color.white.opacity(0.7) : Color.primary.opacity(0.2) }

  var body: some View {
    Button {
      withAnimation(.snappy(duration: 0.25)) { configuration.isOn.toggle() }
    } label: {
      ZStack {
        Capsule()
          .fill(trackColor)
        Capsule()
          .fill(fillColor)
          .opacity(configuration.isOn ? 1 : 0)
        HStack {
          configuration.label
            .font(.system(size: isCompact ? 15 : 12, weight: .medium))
            .foregroundStyle(.primary.opacity(0.75))
          Spacer(minLength: 8)
          Text(configuration.isOn ? "On" : "Off")
            .font(.system(size: isCompact ? 13 : 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.6))
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 11)
      }
      .frame(height: isCompact ? 48 : 32)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isToggle)
    .accessibilityValue(configuration.isOn ? "On" : "Off")
    .sensoryFeedback(.selection, trigger: configuration.isOn)
  }
}
#endif
