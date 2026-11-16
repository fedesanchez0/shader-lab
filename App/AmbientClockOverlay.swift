import SwiftUI

/// A bedside display: a large clock over the shader. Shown on iPhone Duo in tabletop, once the
/// controls are hidden. The clock grows as the hinge opens, following `progress`.
struct AmbientClockOverlay: View {
  @Environment(\.duoPosture) private var duo

  var body: some View {
    GeometryReader { geo in
      // 70% of full size when nearly closed, 100% when flat
      let scale = 0.7 + 0.3 * duo.progress
      let fontSize = min(geo.size.width, geo.size.height) * 0.3 * scale

      TimelineView(.periodic(from: .now, by: 1)) { context in
        VStack(spacing: fontSize * 0.04) {
          Text(context.date, format: .dateTime.hour().minute())
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
          Text(context.date, format: .dateTime.weekday(.wide).month().day())
            .font(.system(size: max(fontSize * 0.16, 13), weight: .medium, design: .rounded))
            .opacity(0.8)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: fontSize * 0.08, y: fontSize * 0.02)
        .accessibilityElement(children: .combine)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .allowsHitTesting(false)
  }
}
