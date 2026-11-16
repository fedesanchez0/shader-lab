#if os(tvOS)
import SwiftUI
import UIKit

/// The TV app: one live shader filling the screen, with a glass picker for the shader and, for
/// Rain, the photo it falls on.
///
/// Sizes are in units of a 544 pt square (`u`), so the same layout reads on a square touch panel
/// and, scaled up, on a 16:9 television. Touch selects directly; the Siri Remote moves focus.
/// Play/Pause (or a tap on the picture) hides the controls and keeps the screen awake.
struct TVShaderLabView: View {
  var model: PlaygroundModel

  @AppStorage("tv.shader") private var storedShader = TVShowcaseShader.rain.rawValue
  @AppStorage("tv.rainPhoto") private var storedPhoto = TVRainPhoto.clownfish.rawValue
  @State private var isChromeHidden = false
  @FocusState private var focus: TVFocus?
  @Namespace private var selection

  private var shader: TVShowcaseShader { TVShowcaseShader(rawValue: storedShader) ?? .rain }
  private var photo: TVRainPhoto { TVRainPhoto(rawValue: storedPhoto) ?? .clownfish }

  var body: some View {
    GeometryReader { proxy in
      let u = min(proxy.size.width, proxy.size.height) / 544

      ZStack {
        CanvasView(model: model)
          .ignoresSafeArea()
          .contentShape(Rectangle())
          // With the controls hidden the picture takes focus, so a remote click brings them back
          .focusable(isChromeHidden)
          .focused($focus, equals: .canvas)
          .onTapGesture { setChromeHidden(!isChromeHidden) }
          .accessibilityLabel("\(shader.title) shader")
          .accessibilityHint(isChromeHidden ? "Shows the controls" : "Hides the controls")

        chrome(u: u)
          .opacity(isChromeHidden ? 0 : 1)
          .disabled(isChromeHidden)
      }
      .animation(.smooth(duration: 0.35), value: isChromeHidden)
    }
    .environment(\.colorScheme, .dark)
    .defaultFocus($focus, .shader(shader))
    .onPlayPauseCommand { setChromeHidden(!isChromeHidden) }
    .onExitCommand(perform: isChromeHidden ? { setChromeHidden(false) } : nil)
    .onOpenURL(perform: open)
    .task {
      model.applyTVTuning()
      model.show(photo)
      model.show(shader)
    }
    .onChange(of: storedShader) { model.show(shader) }
    .onChange(of: storedPhoto) { model.show(photo) }
    .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
  }

  // MARK: Chrome

  private func chrome(u: CGFloat) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text("Shader Lab")
          .font(.system(size: 22 * u, weight: .bold))
        Spacer()
        TimelineView(.everyMinute) { context in
          Text(context.date, format: .dateTime.hour().minute())
            .font(.system(size: 22 * u, weight: .semibold))
            .monospacedDigit()
        }
      }
      .padding(.horizontal, 6 * u)

      Spacer(minLength: 0)

      VStack(alignment: .leading, spacing: 2 * u) {
        Text(shader == .rain ? photo.title : shader.title)
          .font(.system(size: 34 * u, weight: .bold))
          .contentTransition(.opacity)
        Text(shader == .rain ? "Rain · Metal · Live" : "Metal · Live")
          .font(.system(size: 17 * u, weight: .medium))
          .foregroundStyle(.secondary)
          .blendMode(.plusLighter)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 6 * u)
      .padding(.bottom, 16 * u)
      .accessibilityElement(children: .combine)

      GlassEffectContainer(spacing: 10 * u) {
        VStack(spacing: 10 * u) {
          if shader == .rain {
            photoPicker(u: u)
              .transition(.blurReplace)
          }
          shaderPicker(u: u)
        }
        .frame(maxWidth: .infinity)
      }
      .focusSection()
    }
    .padding(24 * u)
    .foregroundStyle(.white)
    .animation(.spring(duration: 0.4, bounce: 0.2), value: shader)
    .animation(.smooth(duration: 0.35), value: photo)
  }

  private func shaderPicker(u: CGFloat) -> some View {
    HStack(spacing: 2 * u) {
      ForEach(TVShowcaseShader.allCases) { option in
        let isSelected = option == shader
        Button {
          select(option)
        } label: {
          HStack(spacing: 8 * u) {
            Image(systemName: option.symbol)
              .font(.system(size: 19 * u, weight: .semibold))
            if isSelected {
              Text(option.title)
                .font(.system(size: 17 * u, weight: .semibold))
                .fixedSize()
            }
          }
          .foregroundStyle(isSelected ? Color.black : Color.white)
          .padding(.horizontal, isSelected ? 18 * u : 0)
          .frame(minWidth: 52 * u, minHeight: 52 * u, maxHeight: 52 * u)
          .background {
            if isSelected {
              Capsule()
                .fill(.white)
                .matchedGeometryEffect(id: "selection", in: selection)
            }
          }
          .contentShape(Capsule())
        }
        .buttonStyle(TVPickerButtonStyle(shape: Capsule(), u: u))
        .focused($focus, equals: .shader(option))
        // A touch panel delivers taps rather than focus-and-select
        .simultaneousGesture(TapGesture().onEnded { select(option) })
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(6 * u)
    .glassEffect(.regular, in: .capsule)
  }

  private func photoPicker(u: CGFloat) -> some View {
    HStack(spacing: 8 * u) {
      ForEach(TVRainPhoto.allCases) { option in
        let isSelected = option == photo
        Button {
          select(option)
        } label: {
          Group {
            if model.areThumbnailsReady, let image = CanvasImageStore.thumbnail(named: option.imageName) {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
            } else {
              Color.gray
            }
          }
          .frame(width: 40 * u, height: 40 * u)
          .clipShape(.circle)
          .padding(isSelected ? 3 * u : 0)
          .overlay {
            Circle().strokeBorder(.white, lineWidth: isSelected ? 2.5 * u : 0)
          }
          .frame(width: 46 * u, height: 46 * u)
          .scaleEffect(isSelected ? 1 : 0.92)
          .contentShape(.circle)
        }
        .buttonStyle(TVPickerButtonStyle(shape: Circle(), u: u))
        .focused($focus, equals: .photo(option))
        .simultaneousGesture(TapGesture().onEnded { select(option) })
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(6 * u)
    .glassEffect(.regular, in: .capsule)
  }

  // MARK: Actions

  private func select(_ option: TVShowcaseShader) {
    guard option != shader else { return }
    withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
      storedShader = option.rawValue
    }
  }

  private func select(_ option: TVRainPhoto) {
    guard option != photo else { return }
    storedPhoto = option.rawValue
  }

  private func setChromeHidden(_ hidden: Bool) {
    isChromeHidden = hidden
    // An ambient picture shouldn't give way to the screen saver
    UIApplication.shared.isIdleTimerDisabled = hidden
    focus = hidden ? .canvas : .shader(shader)
  }

  private func open(_ url: URL) {
    guard let link = TVLaunchLink(url: url) else { return }
    if let shader = link.shader { storedShader = shader.rawValue }
    if let photo = link.photo { storedPhoto = photo.rawValue }
    if let hidden = link.hidesChrome { setChromeHidden(hidden) }
  }
}

private enum TVFocus: Hashable {
  case canvas
  case shader(TVShowcaseShader)
  case photo(TVRainPhoto)
}

/// Lifts and outlines the focused item, the way tvOS shows focus, without the system's platter.
private struct TVPickerButtonStyle<S: InsettableShape>: ButtonStyle {
  var shape: S
  var u: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    FocusedLabel(configuration: configuration, shape: shape, u: u)
  }

  private struct FocusedLabel: View {
    let configuration: ButtonStyleConfiguration
    var shape: S
    var u: CGFloat
    @Environment(\.isFocused) private var isFocused

    var body: some View {
      configuration.label
        .background {
          if isFocused {
            shape.fill(.white.opacity(0.18))
          }
        }
        .overlay {
          if isFocused {
            shape.strokeBorder(.white.opacity(0.85), lineWidth: 2 * u)
          }
        }
        .scaleEffect(configuration.isPressed ? 0.94 : (isFocused ? 1.08 : 1))
        .animation(.snappy(duration: 0.2), value: isFocused)
        .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
  }
}
#endif
