import SwiftUI

/// Rebuilds its content on every frame of an animation of `amount`.
///
/// A plain `.animation` only tweens what SwiftUI can interpolate on its own (frames, opacity).
/// The fold layout also feeds `amount` into things it can't: the shader's size argument, the
/// panels' height limits, whether the reflection exists. Those would jump to their end values.
/// Making the amount `Animatable` hands the content each in-between value instead.
struct FoldAmountAnimator<Content: View>: View, Animatable {
  var amount: Double
  @ViewBuilder var content: (Double) -> Content

  var animatableData: Double {
    get { amount }
    set { amount = newValue }
  }

  var body: some View {
    content(amount)
  }
}
