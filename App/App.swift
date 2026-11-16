import SwiftUI

@main
struct AppDefinition: App {
  @State private var model = PlaygroundModel()

  #if os(visionOS)
  var body: some Scene {
    WindowGroup {
      VisionShaderLobbyView(model: model)
        .task { await model.prewarmImages() }
    }
    .windowStyle(.plain)
    .defaultSize(width: 960, height: 640)

    ImmersiveSpace(id: VisionShaderImmersiveView.spaceID) {
      VisionShaderImmersiveView(model: model)
    }
    .immersionStyle(selection: .constant(.mixed), in: .mixed, .progressive, .full)
  }
  #elseif os(tvOS)
  var body: some Scene {
    WindowGroup {
      TVShaderLabView(model: model)
        .task { await model.prewarmImages() }
    }
  }
  #else
  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
        .duoRuntime()
        // Photos and thumbnails decode in the background instead of in view bodies
        .task { await model.prewarmImages() }
        // A canvas app: the home indicator fades after a moment idle and returns on a swipe.
        // At the scene root so nothing in the layout tree can get in its way.
        .persistentSystemOverlays(.hidden)
    }
  }
  #endif
}
