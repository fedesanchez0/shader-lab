#if !os(tvOS)
import SwiftUI

/// A parameter with a few named choices, drawn in the sliders' capsule: its name on the leading
/// side, then a segment for each choice, the chosen one filled the way a slider fills. VoiceOver
/// reads it as one adjustable control, as it does the sliders.
struct ParamChoicePicker: View {
  var label: String
  var options: [String]
  @Binding var selection: Int

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.horizontalSizeClass) private var hSizeClass
  @Namespace private var chosen

  private var isCompact: Bool { hSizeClass == .compact }
  // MinimalSlider's track and fill
  private var trackColor: Color { colorScheme == .light ? Color.white.opacity(0.4) : Color.primary.opacity(0.08) }
  private var fillColor: Color { colorScheme == .light ? Color.white.opacity(0.7) : Color.primary.opacity(0.2) }

  var body: some View {
    HStack(spacing: 0) {
      Text(label)
        .font(.system(size: isCompact ? 15 : 12, weight: .medium))
        .foregroundStyle(.primary.opacity(0.75))
        .lineLimit(1)
        .padding(.leading, 11)
      Spacer(minLength: 8)
      HStack(spacing: 0) {
        ForEach(options.indices, id: \.self) { index in
          Button {
            withAnimation(.snappy(duration: 0.25)) { selection = index }
          } label: {
            Text(options[index])
              .font(.system(size: isCompact ? 13 : 11, weight: .medium))
              .foregroundStyle(.primary.opacity(index == selection ? 0.9 : 0.55))
              .lineLimit(1)
              .padding(.horizontal, isCompact ? 12 : 9)
              .frame(maxHeight: .infinity)
              .background {
                if index == selection {
                  Capsule()
                    .fill(fillColor)
                    .matchedGeometryEffect(id: "chosen", in: chosen)
                }
              }
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(3)
    }
    .frame(height: isCompact ? 48 : 32)
    .background(Capsule().fill(trackColor))
    .sensoryFeedback(.selection, trigger: selection)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(options.indices.contains(selection) ? options[selection] : "")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: selection = min(selection + 1, options.count - 1)
      case .decrement: selection = max(selection - 1, 0)
      @unknown default: break
      }
    }
  }
}
#endif
