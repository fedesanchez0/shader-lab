import SwiftUI

/// A horizontal glass capsule that the crease parts in two.
///
/// The items keep their places. When the display folds into book pose the one item that
/// would sit on the crease steps to the side it mostly belongs to, a gap the width of the
/// division region opens there, and the glass separates into one lobe per half. Opening
/// the device closes the gap and the lobes merge back into a single capsule.
///
/// This follows the HIG's displacement rule: nothing tappable in the fold, and only what
/// must move moves.
struct CreaseSplitCapsule<Item: Hashable, Content: View>: View {
  var items: [Item]
  /// Width of the gap to open at the crease; 0 keeps a single capsule.
  var gap: CGFloat
  /// The crease's center, in global coordinates. Nil means no crease.
  var creaseX: CGFloat?
  var showsSeparators = false
  @ViewBuilder var content: (Item) -> Content

  @Namespace private var glass
  @State private var itemCenters: [Item: CGFloat] = [:]

  private var isSplit: Bool { gap > 0.5 && creaseX != nil }

  /// Which half an item belongs to: the one holding its center.
  private func isTrailing(_ item: Item) -> Bool {
    guard isSplit, let creaseX, let center = itemCenters[item] else { return false }
    return center >= creaseX
  }

  var body: some View {
    #if os(visionOS)
    HStack(spacing: 0) {
      ForEach(items, id: \.self) { item in content(item) }
    }
    .appChromeGlass(in: .capsule)
    #else
    GlassEffectContainer(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.element) { index, item in
          let trailing = isTrailing(item)
          if index > 0 {
            let previousTrailing = isTrailing(items[index - 1])
            if trailing != previousTrailing {
              Spacer().frame(width: gap)
            } else if showsSeparators {
              Rectangle()
                .fill(Color.primary.opacity(0.25))
                .frame(width: 1, height: 18)
                .accessibilityHidden(true)
            }
          }
          content(item)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { itemCenters[item] = $0 }
            .glassEffect(.regular.tint(.black.opacity(0.55)), in: .capsule)
            .glassEffectUnion(id: trailing ? "trailing" : "leading", namespace: glass)
        }
      }
    }
    .environment(\.colorScheme, .dark)
    #endif
  }
}
