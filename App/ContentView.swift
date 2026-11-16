#if !os(tvOS)
import SwiftUI
import PhotosUI

// MARK: - Main View

struct ContentView: View {
  var model: PlaygroundModel
  @Environment(\.horizontalSizeClass) private var hSizeClass
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  // iPhone Duo hinge state from the app root; `unavailable` on every other device
  @Environment(\.duoPosture) private var duo


  var body: some View {
    Group {
      if hSizeClass == .regular {
        iPadLayout
      } else {
        iPhoneLayout
      }
    }
    .onChange(of: model.imageItem) {
      Task { await model.loadImage() }
    }
    // The Code and Nodes tabs are opaque: nothing behind them needs to keep animating
    .onChange(of: selectedTab, initial: true) {
      model.clock.isPaused = selectedTab != .editor
    }
    .background {
      Color.clear
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
    }
    .alert("Couldn't Save Image", isPresented: Binding(
      get: { exportError != nil },
      set: { if !$0 { exportError = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(exportError ?? "")
    }
    .onChange(of: hSizeClass) { _, sizeClass in
      // Closing the Duo: the outer display starts dark, then reveals (see iPhoneLayout)
      if sizeClass == .compact && duo.isAvailable { outerRevealed = false }
    }
  }

  /// False while the Duo's outer display is taking over from the inner one. The app lands on
  /// it a beat before the device turns from landscape to portrait, and that sideways frame
  /// shouldn't be seen. Always true on every other device.
  @State private var outerRevealed = true

  // iPad: full-screen canvas with two draggable floating glass sidebars
  @State private var leftOffset: CGSize = .zero
  @State private var leftDragStart: CGSize = .zero
  @State private var rightOffset: CGSize = .zero
  @State private var rightDragStart: CGSize = .zero
  @State private var selectedTab: AppTab = .editor
  @State private var showOverlayPopover: Bool = false
  @State private var showImagePicker: Bool = false
  @State private var nodeGraph = NodeGraph()
  @State private var lensEnabled: Bool = false
  @State private var lensPosition: CGPoint = CGPoint(x: 400, y: 400)
  @State private var lensDragStart: CGPoint = CGPoint(x: 400, y: 400)
  @State private var isPreviewMode: Bool = false
  @State private var rainPanStartValue: Float?
  @State private var isExporting: Bool = false
  @State private var exportDone: Bool = false
  @State private var exportError: String?
  /// The whole window, safe areas included: the size an export renders at.
  @State private var screenSize: CGSize = .zero
  @Environment(\.displayScale) private var displayScale
  @State private var topBarRestMinY: CGFloat = 0
  private static let topBarSpace = "topBarRow"
  var uiHidden: Bool { isPreviewMode || lensEnabled }

  /// A tap on the canvas. The lens hides the controls too, and its toolbar button with them,
  /// so the tap turns the lens off before it toggles preview mode.
  private func toggleChrome() {
    withAnimation(chromeAnim(staggerIndex: 0)) {
      if lensEnabled {
        lensEnabled = false
      } else {
        isPreviewMode.toggle()
      }
    }
  }

  func chromeAnim(staggerIndex: Int) -> Animation {
    let delay = uiHidden ? 0 : 0.06 * Double(staggerIndex)
    return uiHidden
      ? .smooth(duration: 0.2)
      : .spring(duration: 0.4, bounce: 0.25).delay(delay)
  }

  func chromeFadeAnim(staggerIndex: Int) -> Animation {
    let delay = uiHidden ? 0 : 0.06 * Double(staggerIndex)
    return uiHidden
      ? .smooth(duration: 0.18)
      : .smooth(duration: 0.22).delay(delay)
  }

  enum AppTab: String, CaseIterable {
    case editor = "Editor"
    case nodes  = "Nodes"
    case code   = "Code"
    var icon: String {
      switch self {
      case .editor: "slider.horizontal.3"
      case .nodes:  "point.3.connected.trianglepath.dotted"
      case .code:   "curlybraces"
      }
    }
  }

  var iPadLayout: some View {
    GeometryReader { geo in
      let division = Self.division(in: geo)
      let fold = FoldPosture.resolve(
        state: duo, containerSize: geo.size, divisionRegion: division?.frame,
        divisionMargins: division?.margins ?? EdgeInsets(), isDivisionActive: division?.isActive ?? false)
      // The hinge arrives as samples, and a preset can swing it 90° in a fraction of a second.
      // Springing the fold amount, and rebuilding the layout for every in-between value, turns
      // that into one continuous move instead of a jump.
      FoldAmountAnimator(amount: fold.foldAmount) { amount in
        iPadLayoutBody(
          fold: fold.with(foldAmount: amount),
          safeBottom: geo.safeAreaInsets.bottom,
          // How far the layout still has to travel: zero whenever it's at rest, at any angle
          transition: reduceMotion ? 0 : FoldPosture.transitionEnergy(target: fold.foldAmount, current: amount),
          size: geo.size
        )
      }
      .animation(.spring(duration: 0.75, bounce: 0), value: fold.foldAmount)
        // A preset switches the layout in one step; free folding follows the hinge directly
        .animation(.smooth, value: duo.pose)
        .animation(.spring(duration: 0.5, bounce: 0.25), value: fold.bookAmount > 0.5)
        .onChange(of: fold.foldAmount > 0.5) {
          // A panel the user dragged could now sit on the crease: send both home
          withAnimation(.smooth) {
            leftOffset = .zero; leftDragStart = .zero
            rightOffset = .zero; rightDragStart = .zero
          }
        }
    }
    .ignoresSafeArea()
  }

  @ViewBuilder func iPadLayoutBody(fold: FoldPosture, safeBottom: CGFloat, transition: Double, size: CGSize) -> some View {
    // Horizontal crease (nintendoDS, tabletop): the panels keep to the half lying flat, below
    // the crease. Blended by tableAmount, so it follows the hinge instead of snapping.
    let tableDivision = fold.crease == .horizontal ? fold.divisionRect : nil
    // Two 280 pt panels leave no room between them on a narrow display (the Duo's inner
    // display in portrait), so the toolbar takes its own row underneath instead of overlapping.
    let narrowToolbarRow: CGFloat = size.width < 768 ? 60 : 0
    // Tabletop hides the toolbar and hands its row to the panels
    let toolbarRowHeight = narrowToolbarRow * (1 - fold.tableAmount)
    // Panel chrome around the scroll area: drag handle and padding, bottom inset
    // Panel chrome around the scroll area: drag handle and padding, bottom inset. Tabletop
    // drops the drag handle (the panels are parked there) and trims the paddings, so the
    // panels take as much of the half below the crease as the strip allows.
    let isTabletop = fold.tableAmount > 0.5
    let panelHandleHeight: CGFloat = isTabletop ? 0 : 20
    // Tabletop: the panels reach up to the crease strip and stop a clear 16 pt above the home
    // indicator's safe area
    let panelBottomPadding: CGFloat = isTabletop ? 16 : 8
    let panelContentInset: CGFloat = 8
    let panelChrome: CGFloat = panelHandleHeight + 8 + panelContentInset + (isTabletop ? safeBottom + panelBottomPadding : 34)
    // Flat, the panels stop below the top bar row. In tabletop the top bar stays where it is,
    // up on the viewing half, so the panels get everything below the crease.
    let flatPanelHeight = min(800, max(160, size.height - topBarRestMinY - 56 - panelChrome - narrowToolbarRow))
    // Panels start 8 pt below the crease band
    let foldedPanelHeight = tableDivision.map { max(160, size.height - $0.maxY - 8 - panelChrome) } ?? flatPanelHeight
    // Two cases where the panels drop their backdrop blur for a plain dark surface: while a
    // fold transition is blurring or tilting them (a backdrop can't be captured into that),
    // and in tabletop, where what's behind them is already near-black, so re-blurring it on
    // every frame buys nothing.
    // The transition effect is only for the tabletop move, where the panels drop into the
    // lower half. Between flat and book they stay where they are, so they stay sharp.
    let panelTransition = fold.crease == .horizontal ? transition : 0
    let usesPlainPanels = panelTransition > 0.01 || fold.tableAmount > 0.98

    let panelMaxHeight = flatPanelHeight + (foldedPanelHeight - flatPanelHeight) * fold.tableAmount
    // Book: the crease parts the tab switcher and the toolbar (see CreaseSplitCapsule).
    // Everything stays where it is; only the item on the crease steps aside.
    let isBook = fold.bookAmount > 0.5
    let creaseGap = isBook ? (fold.divisionRect?.width ?? 0) + fold.divisionMargins.leading + fold.divisionMargins.trailing : 0
    let creaseX = fold.crease == .vertical ? fold.divisionRect?.midX : nil

    // Tabletop: the picture lives on the upright half only. The half lying flat goes dark
    // with a faint reflection, and the shader has half the pixels to fill.
    // The picture stops where the crease strip begins, so none of it sits on the fold
    let canvasHeight = size.height + ((tableDivision?.minY ?? size.height) - size.height) * fold.tableAmount

    // Canvas layer — shader + full-screen tab views
    ZStack(alignment: .top) {
      Color.black
        .ignoresSafeArea()

      if fold.tableAmount > 0.01 {
        TabletopReflection(
          model: model,
          canvasSize: CGSize(width: size.width, height: canvasHeight),
          strength: fold.tableAmount
        )
        .frame(height: max(size.height - canvasHeight, 0), alignment: .top)
        .clipped()
        .offset(y: canvasHeight)
      }

      CanvasView(model: model)
        .frame(width: size.width, height: canvasHeight)
        .simultaneousGesture(TapGesture().onEnded { toggleChrome() })
        // VoiceOver can't see a tap target in a shader, and once the controls fade out
        // nothing else is left to focus, so the canvas itself shows and hides them
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.selectedShader.name) canvas")
        .accessibilityAddTraits(.isImage)
        .accessibilityHint(uiHidden ? "Shows the controls" : "Hides the controls")
        .accessibilityAction { toggleChrome() }
        .accessibilityAction(named: uiHidden ? "Show Controls" : "Hide Controls") { toggleChrome() }
        .gesture(
          isPreviewMode && model.selectedShaderID == "Rain"
            ? DragGesture(minimumDistance: 10)
                .onChanged { v in
                  // Start from wherever Rain is now, not from where the last drag ended
                  let start = rainPanStartValue ?? model.shaderParams["Rain"]?[0].value ?? 0
                  rainPanStartValue = start
                  let delta = Float(v.translation.width / 600.0)
                  model.shaderParams["Rain"]?[0].value = (start + delta).clamped(to: 0...1)
                }
                .onEnded { _ in
                  rainPanStartValue = nil
                }
            : nil
        )

      if selectedTab == .nodes {
        Color.black
          .ignoresSafeArea()
          .overlay {
            Text("Coming Soon")
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(.white.opacity(0.35))
          }
          .transition(.opacity)
      }

      if selectedTab == .code {
        ShaderCodeView(model: model)
          .preferredColorScheme(.dark)
          .transition(.opacity)
      }

      if lensEnabled {
        TouchLensView(model: model, position: $lensPosition, dragStart: $lensDragStart)
          // The lens reads the canvas, so it shares the canvas' frame
          .frame(height: canvasHeight)
          .transition(.scale(scale: 0.5).combined(with: .opacity))
      }

      // Tabletop with the controls hidden: a bedside display, with a clock over the picture on
      // the upright half
      if isPreviewMode && fold.tableAmount > 0.5 && selectedTab == .editor {
        AmbientClockOverlay()
          .frame(height: canvasHeight)
          .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }
    }
    .animation(.smooth(duration: 0.4), value: isPreviewMode && fold.tableAmount > 0.5)
    .ignoresSafeArea()
    .statusBarHidden(true)
    // Top bar — back button (leading), tab switcher (center), export button (trailing)
    .overlay(alignment: .top) {
      HStack(alignment: .center) {
        // Hides the controls for a clean look at the canvas; a tap on the canvas brings them back
        Button {
          withAnimation(chromeAnim(staggerIndex: 0)) { isPreviewMode = true }
        } label: {
          Label("Hide Controls", systemImage: "eye.slash")
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 36, height: 36)
            .appChromeGlass(in: .circle)
        }
        .buttonStyle(.plain)
        .help("Hide Controls")

        Spacer()

        tabSwitcher(creaseGap: creaseGap, creaseX: creaseX)
          .frame(height: 36)

        Spacer()

        // Export button — shares code in code tab, saves canvas otherwise
        if selectedTab == .code {
          let codeSource = ShaderCodeView.extractedSource(for: model)
          ShareLink(
            item: codeSource,
            subject: Text(model.selectedShader.metalFunctionName + ".metal")
          ) {
            HStack(spacing: 6) {
              Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13, weight: .medium))
              Text("Export")
                .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .appChromeGlass(in: .capsule)
          }
          .buttonStyle(.plain)
        } else {
          Button {
            Task { await exportCanvas() }
          } label: {
            HStack(spacing: 6) {
              if isExporting {
                ProgressView().scaleEffect(0.75)
              } else if exportDone {
                Image(systemName: "checkmark")
                  .font(.system(size: 13, weight: .semibold))
              } else {
                Image(systemName: "square.and.arrow.up")
                  .font(.system(size: 13, weight: .medium))
              }
              Text(exportDone ? "Saved" : "Export")
                .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .appChromeGlass(in: .capsule)
          }
          .buttonStyle(.plain)
          .disabled(isExporting)
        }
      }
      .preferredColorScheme(model.selectedShader.prefersLightUI ? .light : .dark)
      // Where the controls rest below the screen's top edge. Measured inside the padded row,
      // so neither the safe-area padding nor the offset below leaks into it.
      .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.topBarSpace)).minY } action: { topBarRestMinY = $0 }
      .padding(.horizontal, 24)
      .padding(.top, 4)
      .safeAreaPadding(.top)
      .coordinateSpace(.named(Self.topBarSpace))
      .contentShape(Rectangle())
      .offset(y: uiHidden ? -120 : 0)
      .animation(chromeAnim(staggerIndex: 0), value: uiHidden)
      .opacity(uiHidden ? 0 : 1)
      .animation(chromeFadeAnim(staggerIndex: 0), value: uiHidden)
    }
    // Left sidebar — bottom leading
    .overlay(alignment: .bottomLeading) {
      if selectedTab == .editor {
        FloatingPanel(dragOffset: $leftOffset, dragStart: $leftDragStart, usesPlainSurface: usesPlainPanels, showsHandle: !isTabletop, contentBottomInset: panelContentInset) {
          BoundedScrollView(maxHeight: panelMaxHeight) {
            ShaderPickerView(model: model)
              .padding(.horizontal, 16)
              .padding(.bottom, 8)
          }
        }
        .preferredColorScheme(model.selectedShader.prefersLightUI ? .light : .dark)
        .frame(width: 280)
        .modifier(FoldTransitionChrome(energy: panelTransition))
        .padding(.leading, 24)
        .padding(.bottom, panelBottomPadding + toolbarRowHeight)
        .safeAreaPadding(.bottom, isTabletop ? 0 : nil)
        .transition(.opacity)
        .offset(x: uiHidden ? -360 : 0)
        .animation(chromeAnim(staggerIndex: 1), value: uiHidden)
        .opacity(uiHidden ? 0 : 1)
        .animation(chromeFadeAnim(staggerIndex: 1), value: uiHidden)
      }
    }
    // Right sidebar — bottom trailing, grows upward
    .overlay(alignment: .bottomTrailing) {
      VStack(alignment: .trailing, spacing: 12) {
        if selectedTab == .editor {
          FloatingPanel(dragOffset: $rightOffset, dragStart: $rightDragStart, usesPlainSurface: usesPlainPanels, showsHandle: !isTabletop, contentBottomInset: panelContentInset) {
            BoundedScrollView(maxHeight: panelMaxHeight) {
              VStack(spacing: 24) {
                ParametersView(model: model)
                CanvasSettingsView(model: model)
              }
              .padding(.horizontal, 16)
              .padding(.bottom, 8)
            }
          }
          .frame(width: 280)
          .modifier(FoldTransitionChrome(energy: panelTransition))
          .transition(.opacity)
        }
      }
      .preferredColorScheme(model.selectedShader.prefersLightUI ? .light : .dark)
      .padding(.trailing, 24)
      .padding(.bottom, panelBottomPadding + toolbarRowHeight)
      .safeAreaPadding(.bottom, isTabletop ? 0 : nil)
      .offset(x: uiHidden ? 360 : 0)
      .animation(chromeAnim(staggerIndex: 2), value: uiHidden)
      .opacity(uiHidden ? 0 : 1)
      .animation(chromeFadeAnim(staggerIndex: 2), value: uiHidden)
    }
    // Bottom toolbar — bottom center (hidden in code tab)
    .overlay(alignment: .bottom) {
      if selectedTab != .code {
        bottomToolbar(creaseGap: creaseGap, creaseX: creaseX)
          .preferredColorScheme(model.selectedShader.prefersLightUI ? .light : .dark)
          .safeAreaPadding(.bottom)
          .padding(.bottom, 8)
          // Tabletop: the toolbar steps out so the panels can use its row
          .offset(y: 80 * fold.tableAmount)
          .opacity(1 - fold.tableAmount)
          .allowsHitTesting(fold.tableAmount < 0.5)
          .accessibilityHidden(fold.tableAmount >= 0.5)
          .offset(y: uiHidden ? 120 : 0)
          .animation(chromeAnim(staggerIndex: 3), value: uiHidden)
          .opacity(uiHidden ? 0 : 1)
          .animation(chromeFadeAnim(staggerIndex: 3), value: uiHidden)
      }
    }
    // Image strip — floats above bottom toolbar
    .overlay(alignment: .bottom) {
      if showImagePicker && fold.tableAmount < 0.5 {
        ImageStripPopover(model: model, isPresented: $showImagePicker)
          .background(.regularMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 4)
          .clearsFold(fold, containerWidth: size.width)
          .safeAreaPadding(.bottom)
          .padding(.bottom, 70)
          .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
      }
    }
    .animation(.spring(duration: 0.5, bounce: 0.2), value: isBook)
    .animation(.spring(duration: 0.25, bounce: 0.2), value: showImagePicker)
    .animation(.bouncy, value: lensEnabled)
    .animation(.smooth(duration: 0.25), value: selectedTab)
    .ignoresSafeArea()
  }

  @MainActor
  func exportCanvas() async {
    isExporting = true
    // Let the spinner draw before the render takes over the main thread
    try? await Task.sleep(for: .milliseconds(50))
    // The screen's own shape and density, so the image works as a wallpaper as it is
    let size = WallpaperSize.points(for: screenSize, isCompact: hSizeClass == .compact)
    let renderer = ImageRenderer(content:
      // Every pixel of an export is kept, so it renders at full quality whatever the live setting
      CanvasView(model: model, qualityOverride: .full)
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
    )
    renderer.scale = displayScale
    guard let image = renderer.uiImage else {
      isExporting = false
      exportError = PhotoLibrarySaver.Failure.saveFailed.message
      return
    }
    do {
      try await PhotoLibrarySaver.save(image)
    } catch {
      isExporting = false
      exportError = error.message
      return
    }
    isExporting = false
    exportDone = true
    try? await Task.sleep(for: .seconds(2))
    exportDone = false
  }

  /// Vertical is icon-only, like a Duo side bar; the titles stay on as accessibility labels.
  @ViewBuilder func tabSwitcher(creaseGap: CGFloat, creaseX: CGFloat?) -> some View {
    CreaseSplitCapsule(items: AppTab.allCases, gap: creaseGap, creaseX: creaseX) { tab in
      let isSelected = selectedTab == tab
      Button {
        withAnimation(.smooth(duration: 0.2)) { selectedTab = tab }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: tab.icon)
            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
          Text(tab.rawValue)
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
          if isSelected {
            Capsule()
              .fill(model.selectedShader.prefersLightUI
                ? Color.white.opacity(0.55)
                : Color.white.opacity(0.18))
          }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(tab.rawValue)
    }
  }

  private enum ToolbarTool: Hashable {
    case textOverlay, lens, photo
  }

  private var toolbarTools: [ToolbarTool] {
    // Every photo effect works on the photo, so every one of them offers to change it
    model.selectedShader.needsPhoto ? [.textOverlay, .lens, .photo] : [.textOverlay, .lens]
  }

  @ViewBuilder func bottomToolbar(creaseGap: CGFloat, creaseX: CGFloat?) -> some View {
    @Bindable var model = model
    CreaseSplitCapsule(items: toolbarTools, gap: creaseGap, creaseX: creaseX, showsSeparators: true) { tool in
      Group {
        switch tool {
        case .textOverlay:
          ToolbarActiveButton(isActive: model.overlay.showOverlay) {
            showOverlayPopover.toggle()
          } label: {
            Image(systemName: "textformat")
              .font(.system(size: 18, weight: model.overlay.showOverlay ? .semibold : .regular))
          }
          .accessibilityLabel("Text Overlay Settings")
          .popover(isPresented: $showOverlayPopover) {
            OverlayPopoverView(model: model)
              .frame(width: 320)
              .preferredColorScheme(.dark)
          }
        case .lens:
          ToolbarActiveButton(isActive: lensEnabled) {
            lensEnabled.toggle()
          } label: {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 18, weight: lensEnabled ? .semibold : .regular))
          }
          .accessibilityLabel(lensEnabled ? "Disable Touch Lens" : "Enable Touch Lens")
        case .photo:
          ToolbarActiveButton(isActive: showImagePicker) {
            showImagePicker.toggle()
          } label: {
            Image(systemName: "photo")
              .font(.system(size: 18))
          }
          .accessibilityLabel("Choose Image")
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 10)
    }
    .animation(.bouncy, value: model.selectedShader.needsPhoto)
  }

  // iPhone: full-screen canvas with custom bottom drawer
  enum PhonePanel { case controls, shaders }
  @State private var phonePanel: PhonePanel = .controls
  @State private var sheetExpanded: Bool = true
  @State private var sheetContentHeight: CGFloat = 338
  @State private var dragOffset: CGFloat = 0

  private let collapsedHeight: CGFloat = 88
  private let maxHeight: CGFloat = 500
  // Matches the iPhone Duo outer display's 8 pt hinge-side corner, so the drawer reads as concentric
  private let drawerInset: CGFloat = 8

  private var currentSheetHeight: CGFloat {
    sheetExpanded ? min(sheetContentHeight, maxHeight) : collapsedHeight
  }

  /// Gap the design kit keeps between the camera and the nearest control.
  private static let lensControlGap: CGFloat = 12

  /// The camera occluding this display right now, in the proxy's coordinates.
  private static func activeOcclusion(in proxy: GeometryProxy) -> CGRect? {
    #if os(iOS)
    if #available(iOS 27.1, *) {
      return proxy.reservedRegions(kind: .occlusion).first { $0.isActive }?.frame
    }
    #endif
    return nil
  }

  /// The crease as the system reports it, in the proxy's coordinates.
  private struct SystemDivision {
    /// The crease band itself.
    var frame: CGRect
    /// Extra room the system suggests around it.
    var margins: EdgeInsets
    /// Whether the crease divides the display right now.
    var isActive: Bool
  }

  /// The crease, whether or not the device is folded right now (inactive while flat).
  private static func division(in proxy: GeometryProxy) -> SystemDivision? {
    #if os(iOS)
    if #available(iOS 27.1, *) {
      guard let region = proxy.reservedRegions(kind: .division, options: [.includeInactive]).first else { return nil }
      return SystemDivision(frame: region.frame, margins: region.margins, isActive: region.isActive)
    }
    #endif
    return nil
  }

  private struct OuterHandoffKey: Equatable {
    var isLandscape: Bool
    var isRevealed: Bool
  }

  var iPhoneLayout: some View {
    GeometryReader { geo in
      let safeBottom = geo.safeAreaInsets.bottom
      let screenFrame = CGRect(origin: .zero, size: geo.size)

      // Outer-display camera lens (iPhone Duo): keep fixed controls clear of it
      let lens = Self.activeOcclusion(in: geo)
      let lensClearance = lens.map { screenFrame.maxX - $0.minX + Self.lensControlGap } ?? 0
      let lensAtTop = lens.map { $0.midY < screenFrame.midY } ?? false
      let lensAtBottom = lens != nil && !lensAtTop
      // The lens follows the hardware, so it stays on the right in right-to-left layouts
      let isLTR = layoutDirection == .leftToRight
      let hardwareRightEdge: Edge.Set = isLTR ? .trailing : .leading
      let topBarRightPadding: CGFloat = isLTR ? 20 : 16

      // Floating drawer: inset from the screen edges, each safe-area inset handled on its own
      let drawerRightLens = lensAtBottom ? lensClearance : 0
      let drawerLeading = max(drawerInset, geo.safeAreaInsets.leading, isLTR ? 0 : drawerRightLens)
      let drawerTrailing = max(drawerInset, geo.safeAreaInsets.trailing, isLTR ? drawerRightLens : 0)

      ZStack(alignment: .bottom) {
        CanvasView(model: model)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .ignoresSafeArea()
          .onTapGesture {
            withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
              sheetExpanded.toggle()
            }
          }

        // Top bar
        VStack {
          HStack {
            Button {
              withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                phonePanel = .shaders
                sheetExpanded = true
              }
            } label: {
              // Opens the shader list in the drawer
              Label("Shaders", systemImage: "square.grid.2x2")
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .appChromeGlass(in: .capsule)
            }
            .buttonStyle(.plain)
            // The drawer has its own "Shaders" button, so this one says where it goes
            .accessibilityLabel("Show Shader List")

            Spacer()

            Button {
              Task { await exportCanvas() }
            } label: {
              HStack(spacing: 6) {
                if isExporting {
                  ProgressView().scaleEffect(0.75)
                } else {
                  Image(systemName: exportDone ? "checkmark" : "square.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
                }
                Text(exportDone ? "Saved" : "Export")
                  .font(.system(size: 14, weight: .medium))
              }
              .padding(.horizontal, 14)
              .frame(height: 36)
              .appChromeGlass(in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
          }
          .padding(.leading, 16)
          .padding(.trailing, 20)
          .padding(hardwareRightEdge, lensAtTop ? max(0, lensClearance - topBarRightPadding) : 0)
          // With a lens in the top row, center the 36 pt controls on it instead of the default offset
          .padding(.top, lensAtTop ? (lens?.midY ?? 0) - 18 : 24)
          .safeAreaPadding(.top, lensAtTop ? 0 : nil)
          .scaleEffect(lensAtTop ? 1 : 0.95, anchor: .top)
          Spacer()
        }
        // Custom bottom drawer
        VStack(spacing: 0) {
          // Drag handle
          Capsule()
            .fill(Color.primary.opacity(0.25))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 6)

          iPhoneSheetContent()
        }
        .frame(maxWidth: .infinity)
        .frame(height: currentSheetHeight + dragOffset.clamped(to: -50...0) * -1 + max(safeBottom - drawerInset, 0), alignment: .top)
        .appChromeDrawerGlass()
        .padding(.leading, drawerLeading)
        .padding(.trailing, drawerTrailing)
        .padding(.bottom, drawerInset)
        .offset(y: dragOffset.clamped(to: 0...200))
        .gesture(
          DragGesture(minimumDistance: 8)
            .onChanged { v in
              dragOffset = v.translation.height
            }
            .onEnded { v in
              let threshold: CGFloat = 60
              withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                if v.translation.height > threshold {
                  sheetExpanded = false
                } else if v.translation.height < -threshold {
                  sheetExpanded = true
                }
                dragOffset = 0
              }
            }
        )
        .animation(.spring(duration: 0.35, bounce: 0.2), value: sheetExpanded)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: sheetContentHeight)
      }
      .ignoresSafeArea()
      .opacity(outerRevealed ? 1 : 0)
      .background(Color.black.ignoresSafeArea())
      .task(id: OuterHandoffKey(isLandscape: geo.size.width > geo.size.height, isRevealed: outerRevealed)) {
        guard !outerRevealed else { return }
        // Portrait is where the hand-off ends: let the rotation settle, then wake the display.
        // Landscape that outlasts the hand-off is a real orientation, so show that too.
        let isLandscape = geo.size.width > geo.size.height
        try? await Task.sleep(for: .milliseconds(isLandscape ? 600 : 120))
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: 0.3)) { outerRevealed = true }
      }
    }
    .ignoresSafeArea()
    .statusBarHidden(true)
    .preferredColorScheme(.dark)
  }

  @ViewBuilder func iPhoneSheetContent() -> some View {
    // Header — always visible, content morphs
    ZStack {
      // Title
      Group {
        if phonePanel == .controls {
          Text(model.selectedShader.name)
            .transition(.blurReplace)
        } else {
          Text("Effects")
            .transition(.blurReplace)
        }
      }
      .font(.system(size: 17, weight: .semibold))
      .frame(maxWidth: .infinity)
      .animation(.spring(duration: 0.35, bounce: 0.15), value: phonePanel)

      HStack {
        // Left: back button (controls) or nothing (shaders)
        Button {
          withAnimation(.spring(duration: 0.35, bounce: 0.2)) { phonePanel = phonePanel == .controls ? .shaders : .controls }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: phonePanel == .controls ? "chevron.left" : "slider.horizontal.3")
              .font(.system(size: 13, weight: .semibold))
              .contentTransition(.symbolEffect(.replace.downUp))
            if phonePanel == .controls {
              Text("Shaders")
                .font(.system(size: 15, weight: .medium))
                .transition(.blurReplace)
            }
          }
          .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: phonePanel)

        Spacer()

        if phonePanel == .controls {
          let shaderID = model.selectedShaderID
          Button("Reset") {
            withAnimation(.smooth(duration: 0.25)) {
              model.shaderParams[shaderID] = model.selectedShader.defaultParams
              model.currentParamOrder = model.selectedShader.defaultParams.map(\.name)
            }
          }
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(.secondary)
          .buttonStyle(.plain)
          .transition(.blurReplace)
        }
      }
      .animation(.spring(duration: 0.35, bounce: 0.15), value: phonePanel)
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 12)

    Divider().opacity(0.3)

    ScrollView {
      if phonePanel == .shaders {
        ShaderPickerView(model: model, onSelect: { _ in
          withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
            phonePanel = .controls
            sheetExpanded = true
          }
        })
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .transition(.blurReplace)
      } else {
        VStack(spacing: 24) {
          ParametersView(model: model, showLabel: false)
          CanvasSettingsView(model: model)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(GeometryReader { geo in
          Color.clear
            .onAppear { updateSheetHeight(geo.size.height) }
            .onChange(of: geo.size.height) { _, h in updateSheetHeight(h) }
        })
        .transition(.blurReplace)
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .animation(.spring(duration: 0.35, bounce: 0.15), value: phonePanel)
    .onChange(of: phonePanel) { _, panel in
      if panel == .shaders { sheetContentHeight = maxHeight }
    }
  }

  private func updateSheetHeight(_ contentHeight: CGFloat) {
    let headerHeight: CGFloat = 57
    let total = contentHeight + headerHeight + 20 // +20 for drag handle area
    sheetContentHeight = min(max(total, collapsedHeight), maxHeight)
  }
}

// MARK: - Image Strip Popover

struct ImageStripPopover: View {
  var model: PlaygroundModel
  @Binding var isPresented: Bool

  var imageNames: [String] {
    if model.selectedShader.fixedImageName != nil {
      return ["val-toch-BHeQQmZM8jE-unsplash"] + PlaygroundModel.bundledImageNames
    }
    return PlaygroundModel.bundledImageNames
  }

  func setImage(named name: String) {
    if model.selectedShader.fixedImageName != nil {
      model.waveImage = PlaygroundModel.loadBundledImage(name)
    } else {
      model.selectBundledPhoto(name)
    }
  }

  var body: some View {
    HStack(spacing: 3) {
      ForEach(imageNames, id: \.self) { name in
        // A small thumbnail for the strip, decoded at launch; the canvas-size image loads only when picked
        let img = model.areThumbnailsReady ? CanvasImageStore.thumbnail(named: name) : nil
        Button {
          setImage(named: name)
          isPresented = false
        } label: {
          Group {
            if let img {
              Image(uiImage: img)
                .resizable()
                .scaledToFill()
            } else {
              Color.primary.opacity(0.08)
                .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
          }
          .frame(width: 82, height: 64)
          .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PlaygroundModel.bundledPhotoTitle(name))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

// MARK: - Floating Panel

struct FloatingPanel<Content: View>: View {
  private static var shape: ConcentricRectangle {
    ConcentricRectangle(corners: .concentric(minimum: .fixed(24)), isUniform: false)
  }

  @Binding var dragOffset: CGSize
  @Binding var dragStart: CGSize
  /// Skips the backdrop blur for a plain dark surface (see `appChromePanel`).
  var usesPlainSurface = false
  /// The drag handle; off where the panel is parked and can't usefully be dragged (tabletop).
  var showsHandle = true
  /// Space under the content. Larger when the surface runs under the home indicator.
  var contentBottomInset: CGFloat = 8
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      if showsHandle {
        // Drag handle
        Capsule()
          .fill(Color.primary.opacity(0.25))
          .frame(width: 36, height: 4)
          .padding(.top, 10)
          .padding(.bottom, 6)
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .gesture(
            DragGesture()
              .onChanged { v in
                dragOffset = CGSize(
                  width:  dragStart.width  + v.translation.width,
                  height: dragStart.height + v.translation.height
                )
              }
              .onEnded { _ in dragStart = dragOffset }
          )
      } else {
        Color.clear.frame(height: 8)
      }

      content()
        .padding(.bottom, contentBottomInset)
    }
    // Concentric with the display: a panel parked in a screen corner takes that corner's
    // radius minus its inset, and any corner away from the edge falls back to 24 pt
    .appChromePanel(in: Self.shape, isFlattened: usesPlainSurface)
    .contentShape(Self.shape)
    .offset(dragOffset)
  }
}

// MARK: - Touch Lens

struct TouchLensView: View {
  var model: PlaygroundModel
  @Binding var position: CGPoint
  @Binding var dragStart: CGPoint

  private let lensSize: CGFloat = 200
  private let zoom: CGFloat = 3.0

  var body: some View {
    GeometryReader { geo in
      ZStack {
        // Zoomed canvas inside the lens. Only the patch under the lens is rasterized: the
        // canvas is laid out full size (the shaders need the real canvas size), slid so the
        // patch sits at the origin, clipped to it, and flattened before it's enlarged. It
        // renders at full quality because every pixel here is blown up.
        let patchSide = lensSize / zoom
        CanvasView(model: model, qualityOverride: .full)
          .frame(width: geo.size.width, height: geo.size.height)
          .offset(x: -(position.x - patchSide / 2), y: -(position.y - patchSide / 2))
          .frame(width: patchSide, height: patchSide, alignment: .topLeading)
          .clipped()
          .drawingGroup(opaque: true)
          .scaleEffect(zoom)
          .frame(width: lensSize, height: lensSize)
          .clipShape(Circle())

        // Lens border + crosshair
        Circle()
          .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
          .frame(width: lensSize, height: lensSize)

        // Crosshair
        Group {
          Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1, height: 16)
          Rectangle().fill(Color.white.opacity(0.5)).frame(width: 16, height: 1)
        }
      }
      .frame(width: lensSize, height: lensSize)
      // Only the lens itself takes touches, so a tap anywhere else reaches the canvas
      .contentShape(Circle())
      .gesture(
        DragGesture(coordinateSpace: .global)
          .onChanged { v in
            position = CGPoint(
              x: dragStart.x + v.translation.width,
              y: dragStart.y + v.translation.height
            )
          }
          .onEnded { _ in dragStart = position }
      )
      .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
      .position(position)
    }
    .ignoresSafeArea()
  }
}

// MARK: - Shader Picker

struct ShaderPickerView: View {
  var model: PlaygroundModel
  var onSelect: ((String) -> Void)? = nil
  let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

  var generators: [ShaderDefinition] { ShaderDefinition.all.filter { !$0.showInPhotoSection } }

  func selectShader(_ id: String) {
    model.carryOverSharedParams(to: id)
    model.updateParamOrder(to: id)
    withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
      model.selectedShaderID = id
    }
    onSelect?(id)
  }
  var photoEffects: [ShaderDefinition] { ShaderDefinition.all.filter { $0.showInPhotoSection } }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 10) {
        SectionLabel(title: "Effects")
        LazyVGrid(columns: columns, spacing: 8) {
          ForEach(generators) { shader in
            Button {
              selectShader(shader.id)
            } label: {
              ShaderCard(shader: shader, isSelected: model.selectedShaderID == shader.id)
            }
            .buttonStyle(ShaderCardButtonStyle())
            .accessibilityLabel(shader.name)
            .accessibilityAddTraits(model.selectedShaderID == shader.id ? .isSelected : [])
          }
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        SectionLabel(title: "Photo Effects")
        LazyVGrid(columns: columns, spacing: 8) {
          ForEach(photoEffects) { shader in
            Button {
              selectShader(shader.id)
            } label: {
              ShaderCard(shader: shader, isSelected: model.selectedShaderID == shader.id)
            }
            .buttonStyle(ShaderCardButtonStyle())
            .accessibilityLabel(shader.name)
            .accessibilityAddTraits(model.selectedShaderID == shader.id ? .isSelected : [])
          }
        }
      }
    }
  }
}

struct ShaderCard: View {
  var shader: ShaderDefinition
  var isSelected: Bool
  @Environment(\.colorScheme) var colorScheme
  @State private var bounceCounter: Int = 0

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: shader.icon)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .frame(width: 36, height: 36)
        .scaleEffect(isSelected ? 1.12 : 1.0)
        .symbolEffect(.bounce.byLayer, value: bounceCounter)
        .animation(.spring(duration: 0.35, bounce: 0.4), value: isSelected)
        .onChange(of: isSelected) { _, newVal in if newVal { bounceCounter += 1 } }

      Text(shader.name)
        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(isSelected
          ? (colorScheme == .light ? Color.white.opacity(0.6) : Color.primary.opacity(0.12))
          : Color.primary.opacity(0.04))
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isSelected
              ? (colorScheme == .light ? Color.white.opacity(0.9) : Color.primary.opacity(0.25))
              : Color.clear, lineWidth: 1)
        )
    )
  }
}

struct ShaderCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
      .animation(.spring(duration: 0.2, bounce: 0.2), value: configuration.isPressed)
  }
}

// MARK: - Parameters

struct ParametersView: View {
  var model: PlaygroundModel
  var showLabel: Bool = true

  var body: some View {
    let params = model.currentParams
    let shaderID = model.selectedShaderID

    VStack(alignment: .leading, spacing: 16) {
      if showLabel {
        HStack {
          SectionLabel(title: "Parameters")
          Spacer()
          Button("Reset") {
            withAnimation(.smooth(duration: 0.25)) {
              model.shaderParams[shaderID] = model.selectedShader.defaultParams
              model.currentParamOrder = model.selectedShader.defaultParams.map(\.name)
            }
          }
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
        }
      }

      VStack(spacing: 12) {
        // The Fractal's Grow row comes first, so play is always in reach
        if shaderID == FractalGrowth.shaderID {
          FractalGrowthRow(model: model)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
        ForEach(model.currentParamOrder, id: \.self) { name in
          // Values kept for the shader, and ones shown inside another control, get no row
          if let storageIndex = params.firstIndex(where: { $0.name == name }),
             !params[storageIndex].isHidden, params[storageIndex].shownIn == nil,
             !(shaderID == FractalGrowth.shaderID && name == FractalGrowth.grow) {
            let param = params[storageIndex]
            ParameterRow(param: Binding(
              get: { model.shaderParams[shaderID]?[storageIndex] ?? param },
              set: { model.shaderParams[shaderID]?[storageIndex] = $0 }
            ))
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
          }
        }
      }
    }
  }
}

struct ColorParamRow: View {
  var label: String
  @Binding var color: Color

  @Environment(\.horizontalSizeClass) var hSizeClass
  var isCompact: Bool { hSizeClass == .compact }

  private let hueColors: [Color] = [
    .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
  ]

  // Extract hue (0–1) from the stored Color
  var hue: CGFloat {
    var h: CGFloat = 0
    UIColor(color).getHue(&h, saturation: nil, brightness: nil, alpha: nil)
    return h
  }

  func colorForHue(_ h: Float) -> Color {
    Color(hue: Double(h), saturation: 0.9, brightness: 0.95)
  }

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let t = hue

      ZStack(alignment: .leading) {
        // Rainbow gradient track (same as HueSlider)
        LinearGradient(colors: hueColors, startPoint: .leading, endPoint: .trailing)
          .clipShape(Capsule())

        // Label, drawn as HueSlider draws its own, so the four color rows can be told apart.
        // It sits on the side away from the thumb, which would otherwise cover it.
        Text(label)
          .font(.system(size: isCompact ? 15 : 12, weight: .semibold))
          .foregroundStyle(.white.opacity(0.85))
          .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
          .padding(.horizontal, 11)
          .frame(maxWidth: .infinity, alignment: t < 0.5 ? .trailing : .leading)
          .animation(.snappy(duration: 0.2), value: t < 0.5)
          .allowsHitTesting(false)

        // White thumb
        Circle()
          .fill(.white)
          .frame(width: h - 6, height: h - 6)
          .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
          .position(x: max(h / 2, min(w - h / 2, t * w)), y: h / 2)
          .allowsHitTesting(false)
      }
      .contentShape(Capsule())
      .sliderDrag { location in
        color = colorForHue(Float(max(0, min(1, location.x / w))))
      }
    }
    .frame(height: isCompact ? 48 : 32)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(HueName.describe(Double(hue)))
    .accessibilityAdjustableAction { direction in
      let step: CGFloat = 1 / 24
      switch direction {
      case .increment: color = colorForHue(Float(min(1, hue + step)))
      case .decrement: color = colorForHue(Float(max(0, hue - step)))
      @unknown default: break
      }
    }
  }
}

struct ParameterRow: View {
  @Binding var param: ShaderParam

  var body: some View {
    if param.isColor {
      ColorParamRow(label: param.name, color: $param.colorValue)
    } else if param.isToggle {
      Toggle(param.name, isOn: $param.isOn)
        .toggleStyle(ParamToggleStyle())
    } else if param.isChoice {
      ParamChoicePicker(label: param.name, options: param.options, selection: $param.choice)
    } else if param.isHue {
      HueSlider(label: param.name, value: $param.value)
    } else {
      MinimalSlider(label: param.name, value: $param.value, range: param.range,
                    valueString: param.displayString)
    }
  }
}

struct MinimalSlider: View {
  var label: String
  @Binding var value: Float
  var range: ClosedRange<Float>
  var valueString: String = ""

  @Environment(\.colorScheme) var colorScheme
  @Environment(\.horizontalSizeClass) var hSizeClass
  @State private var isDragging = false

  var isCompact: Bool { hSizeClass == .compact }

  var trackColor: Color { colorScheme == .light ? Color.white.opacity(0.4) : Color.primary.opacity(0.08) }
  var fillColor: Color { colorScheme == .light ? Color.white.opacity(0.7) : Color.primary.opacity(0.2) }

  var normalizedValue: CGFloat {
    CGFloat(((value - range.lowerBound) / (range.upperBound - range.lowerBound)).clamped(to: 0...1))
  }

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let t = normalizedValue

      ZStack(alignment: .leading) {
        // Track background
        Capsule()
          .fill(trackColor)

        // Fill
        Capsule()
          .fill(fillColor)
          .frame(width: max(h, w * t))

        // Label inside the track (leading)
        Text(label)
          .font(.system(size: isCompact ? 15 : 12, weight: .medium))
          .foregroundStyle(.primary.opacity(0.75))
          .padding(.leading, 11)
          .frame(maxWidth: .infinity, alignment: .leading)
          .allowsHitTesting(false)

        // Value inside the track (trailing)
        if !valueString.isEmpty {
          Text(valueString)
            .font(.system(size: isCompact ? 13 : 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.6))
            .padding(.trailing, 11)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .allowsHitTesting(false)
        }

        // Dots — appear only while dragging, fade out on release
        GeometryReader { _ in
          ForEach(1..<4) { i in
            let x = w * CGFloat(i) / 4.0
            Circle()
              .fill(Color.primary.opacity(CGFloat(i) / 4.0 <= t ? 0.6 : 0.3))
              .frame(width: 3.5, height: 3.5)
              .position(x: x, y: h / 2)
          }
        }
        .opacity(isDragging ? 1 : 0)
        .animation(.smooth(duration: isDragging ? 0.1 : 0.5), value: isDragging)
      }
      .contentShape(Capsule())
      .sliderDrag { location in
        if !isDragging { isDragging = true }
        let ratio = Float(max(0, min(1, location.x / w)))
        value = ratio * (range.upperBound - range.lowerBound) + range.lowerBound
      } onEnded: {
        isDragging = false
      }
    }
    .frame(height: isCompact ? 48 : 32)
    // Drawn with a drag gesture, so it needs its own slider semantics
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(valueString.isEmpty ? "\(Int((normalizedValue * 100).rounded())) percent" : valueString)
    .accessibilityAdjustableAction { direction in
      let step = (range.upperBound - range.lowerBound) / 20
      switch direction {
      case .increment: value = min(range.upperBound, value + step)
      case .decrement: value = max(range.lowerBound, value - step)
      @unknown default: break
      }
    }
  }
}

struct HueSlider: View {
  var label: String
  @Binding var value: Float  // 0–1 hue

  @Environment(\.horizontalSizeClass) var hSizeClass
  var isCompact: Bool { hSizeClass == .compact }

  private let hueColors: [Color] = [
    .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
  ]

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let t = CGFloat(value)

      ZStack(alignment: .leading) {
        // Rainbow gradient track
        LinearGradient(colors: hueColors, startPoint: .leading, endPoint: .trailing)
          .clipShape(Capsule())

        // Label, on the side away from the thumb
        Text(label)
          .font(.system(size: isCompact ? 15 : 12, weight: .semibold))
          .foregroundStyle(.white.opacity(0.85))
          .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
          .padding(.horizontal, 11)
          .frame(maxWidth: .infinity, alignment: t < 0.5 ? .trailing : .leading)
          .animation(.snappy(duration: 0.2), value: t < 0.5)
          .allowsHitTesting(false)

        // Thumb
        Circle()
          .fill(.white)
          .frame(width: h - 6, height: h - 6)
          .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
          .position(x: max(h / 2, min(w - h / 2, t * w)), y: h / 2)
          .allowsHitTesting(false)
      }
      .contentShape(Capsule())
      .sliderDrag { location in
        value = Float(max(0, min(1, location.x / w)))
      }
    }
    .frame(height: isCompact ? 48 : 32)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(HueName.describe(Double(value)))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: value = min(1, value + 1 / 24)
      case .decrement: value = max(0, value - 1 / 24)
      @unknown default: break
      }
    }
  }
}

// MARK: - Canvas Settings

struct CanvasSettingsView: View {
  var model: PlaygroundModel

  var hasContent: Bool {
    model.selectedShader.needsPhoto || model.selectedShaderID == "Dithering"
  }

  var body: some View {
    @Bindable var model = model
    if hasContent {
      VStack(alignment: .leading, spacing: 24) {
        if model.selectedShader.needsPhoto {
          ImageSourceSection(model: model)
        }
        if model.selectedShaderID == "Dithering" {
          DitheredLabelInspector(label: $model.ditheredLabel)
        }
      }
    }
  }
}

/// MARK: - Background Color Section

struct CanvasBgColorSection: View {
  @Binding var color: Color

  private let hueColors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red]

  var hue: CGFloat {
    var h: CGFloat = 0
    UIColor(color).getHue(&h, saturation: nil, brightness: nil, alpha: nil)
    return h
  }
  var brightness: CGFloat {
    var b: CGFloat = 1
    UIColor(color).getHue(nil, saturation: nil, brightness: &b, alpha: nil)
    return b
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel(title: "Background")
      VStack(spacing: 8) {
        BgHueSlider(label: "Color", hueColors: hueColors, hue: hue) { newHue in
          color = Color(hue: newHue, saturation: brightness < 0.05 ? 0 : 0.85, brightness: max(brightness, 0.05))
        }
        BgBrightnessSlider(label: "Brightness", hue: hue, brightness: brightness) { newBrightness in
          color = Color(hue: hue, saturation: newBrightness < 0.05 ? 0 : 0.85, brightness: newBrightness)
        }
      }
    }
  }
}

struct BgHueSlider: View {
  var label: String
  var hueColors: [Color]
  var hue: CGFloat
  var onChange: (CGFloat) -> Void

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      ZStack(alignment: .leading) {
        LinearGradient(colors: hueColors, startPoint: .leading, endPoint: .trailing)
          .clipShape(Capsule())
        Text(label)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white.opacity(0.85))
          .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
          .padding(.leading, 11)
          .frame(maxWidth: .infinity, alignment: .leading)
          .allowsHitTesting(false)
        Circle()
          .fill(.white)
          .frame(width: h - 6, height: h - 6)
          .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
          .position(x: max(h / 2, min(w - h / 2, hue * w)), y: h / 2)
          .allowsHitTesting(false)
      }
      .contentShape(Capsule())
      .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
        onChange(max(0, min(1, drag.location.x / w)))
      })
    }
    .frame(height: 32)
  }
}

struct BgBrightnessSlider: View {
  var label: String
  var hue: CGFloat
  var brightness: CGFloat
  var onChange: (CGFloat) -> Void

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      ZStack(alignment: .leading) {
        LinearGradient(
          colors: [.black, Color(hue: hue, saturation: 0.85, brightness: 1.0)],
          startPoint: .leading,
          endPoint: .trailing
        )
        .clipShape(Capsule())
        Text(label)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white.opacity(0.7))
          .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
          .padding(.leading, 11)
          .frame(maxWidth: .infinity, alignment: .leading)
          .allowsHitTesting(false)
        Circle()
          .fill(.white)
          .frame(width: h - 6, height: h - 6)
          .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
          .position(x: max(h / 2, min(w - h / 2, brightness * w)), y: h / 2)
          .allowsHitTesting(false)
      }
      .contentShape(Capsule())
      .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
        onChange(max(0, min(1, drag.location.x / w)))
      })
    }
    .frame(height: 32)
  }
}

// MARK: - Image Source Section

struct ImageSourceSection: View {
  var model: PlaygroundModel
  let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel(title: "Image")
      LazyVGrid(columns: columns, spacing: 8) {
        // Upload tile
        PhotosPicker(
          selection: Binding(get: { model.imageItem }, set: { model.imageItem = $0 }),
          matching: .images
        ) {
          VStack(spacing: 6) {
            Image(systemName: "plus.circle")
              .font(.system(size: 22, weight: .light))
              .foregroundStyle(.secondary)
            Text("Upload")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(Color.primary.opacity(0.06))
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1, antialiased: true)
              )
          )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Upload Image")

        ForEach(PlaygroundModel.bundledImageNames, id: \.self) { name in
          // A small thumbnail for the grid, decoded at launch; the canvas-size image loads only when picked
          let img = model.areThumbnailsReady ? CanvasImageStore.thumbnail(named: name) : nil
          let isSelected = model.uploadedImageName == name
          Button {
            model.selectBundledPhoto(name)
          } label: {
            Color.clear
              .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74)
              .overlay {
                if let img {
                  Image(uiImage: img).resizable().scaledToFill()
                } else {
                  Color.primary.opacity(0.08)
                }
              }
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .overlay {
                RoundedRectangle(cornerRadius: 8)
                  .strokeBorder(
                    isSelected ? Color.primary.opacity(0.85) : Color.primary.opacity(0.12),
                    lineWidth: isSelected ? 2 : 1
                  )
              }
              .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
              .contentShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(ImageTileButtonStyle())
          .accessibilityLabel(PlaygroundModel.bundledPhotoTitle(name))
        }
      }
    }
  }
}

struct ImageTileButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
      .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
  }
}

// MARK: - Overlay Popover

struct OverlayPopoverView: View {
  var model: PlaygroundModel

  var body: some View {
    @Bindable var model = model
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          SectionLabel(title: "Text Overlay")
          Spacer()
          Toggle("", isOn: $model.overlay.showOverlay).labelsHidden()
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Text")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
          TextEditor(text: $model.overlay.text)
            .font(.system(size: 14))
            .frame(minHeight: 72, maxHeight: 120)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
            .scrollContentBackground(.hidden)
        }

        VStack(spacing: 0) {
          HStack {
            Text("Color")
              .font(.system(size: 14)).foregroundStyle(.primary)
            Spacer()
            ColorPicker("", selection: $model.overlay.textColor, supportsOpacity: true)
              .labelsHidden()
          }
          .padding(.horizontal, 16).padding(.vertical, 12)

          Divider().background(Color.primary.opacity(0.08))

          HStack {
            Text("Font")
              .font(.system(size: 14)).foregroundStyle(.primary)
            Spacer()
            Picker("", selection: $model.overlay.fontStyle) {
              ForEach(OverlayFontStyle.allCases) { f in
                Text(f.rawValue).tag(f)
              }
            }
            .pickerStyle(.menu)
            .font(.system(size: 13))
          }
          .padding(.horizontal, 16).padding(.vertical, 12)

          Divider().background(Color.primary.opacity(0.08))

          MinimalSlider(
            label: "Size",
            value: Binding(get: { Float(model.overlay.fontSize) }, set: { model.overlay.fontSize = CGFloat($0) }),
            range: 0.3...2.5,
            valueString: String(format: "%.1f×", model.overlay.fontSize)
          )
          .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))

        VStack(spacing: 0) {
          HStack {
            Text("Container")
              .font(.system(size: 14)).foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: $model.overlay.showContainer).labelsHidden()
          }
          .padding(.horizontal, 16).padding(.vertical, 12)

          if model.overlay.showContainer {
            Divider().background(Color.primary.opacity(0.08))

            HStack {
              Text("Style")
                .font(.system(size: 14)).foregroundStyle(.primary)
              Spacer()
              Picker("", selection: $model.overlay.containerStyle) {
                ForEach(ContainerStyle.allCases.filter { $0 != .none }) { s in
                  Text(s.rawValue).tag(s)
                }
              }
              .pickerStyle(.menu)
              .font(.system(size: 13))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            if model.overlay.containerStyle.isMaterial || model.overlay.containerStyle == .glassTint {
              Divider().background(Color.primary.opacity(0.08))
              HStack {
                Text("Tint")
                  .font(.system(size: 14)).foregroundStyle(.primary)
                Spacer()
                ColorPicker("", selection: $model.overlay.containerColor, supportsOpacity: true)
                  .labelsHidden()
              }
              .padding(.horizontal, 16).padding(.vertical, 12)
            }

            Divider().background(Color.primary.opacity(0.08))

            MinimalSlider(
              label: "Radius",
              value: Binding(get: { Float(model.overlay.cornerRadius) }, set: { model.overlay.cornerRadius = CGFloat($0) }),
              range: 0...48,
              valueString: "\(Int(model.overlay.cornerRadius))pt"
            )
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().background(Color.primary.opacity(0.08))

            MinimalSlider(
              label: "Padding",
              value: Binding(get: { Float(model.overlay.containerPadding) }, set: { model.overlay.containerPadding = CGFloat($0) }),
              range: 0...48,
              valueString: "\(Int(model.overlay.containerPadding))pt"
            )
            .padding(.horizontal, 16).padding(.vertical, 12)
          }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
        .animation(.smooth(duration: 0.25), value: model.overlay.showContainer)
      }
      .padding(20)
    }
  }
}

// MARK: - Shader Code Viewer

struct ShaderCodeView: View {
  var model: PlaygroundModel
  @State private var copied = false

  private static let fullSource: String = {
    guard let url = Bundle.main.url(forResource: "ShaderSource", withExtension: "txt"),
          let src = try? String(contentsOf: url, encoding: .utf8) else { return "" }
    return src
  }()

  var shaderSource: String {
    let fnName = model.selectedShader.metalFunctionName
    let raw = extractFunction(named: fnName, from: Self.fullSource)
    return injectCurrentValues(into: raw)
  }

  static func extractedSource(for model: PlaygroundModel) -> String {
    let view = ShaderCodeView(model: model)
    return view.shaderSource
  }

  private func injectCurrentValues(into source: String) -> String {
    let params = model.currentParams
    guard !params.isEmpty else { return source }

    // Build a const block with current values
    var lines: [String] = ["  // ── Current parameter values ──────────────────"]
    for param in params where !param.isHidden {
      let label = param.name.padding(toLength: 14, withPad: " ", startingAt: 0)
      if param.isColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(param.colorValue).getRed(&r, green: &g, blue: &b, alpha: &a)
        lines.append(String(format: "  // \(label)  rgba(%.2f, %.2f, %.2f, 1.0)", r, g, b))
      } else {
        lines.append("  // \(label)  \(param.displayString)")
      }
    }
    lines.append("  // ─────────────────────────────────────────────────")

    let injection = lines.joined(separator: "\n")

    // Insert after the first opening brace of the function body
    if let braceRange = source.range(of: "{\n") {
      let insertPos = braceRange.upperBound
      return source[source.startIndex..<insertPos] + injection + "\n" + source[insertPos...]
    }
    return source
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color(white: 0.06).ignoresSafeArea()

      ScrollView([.vertical]) {
        if Self.fullSource.isEmpty {
          Text("Source unavailable")
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(24)
        } else {
          Text(AttributedString(highlightedMetal(shaderSource)))
            .font(.system(size: 13, design: .monospaced))
            .textSelection(.enabled)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .safeAreaPadding(.top)
      .padding(.top, 52)
    }
    .ignoresSafeArea()
  }

  private func extractFunction(named name: String, from source: String) -> String {
    let lines = source.components(separatedBy: "\n")
    var startLine = -1
    for (i, line) in lines.enumerated() {
      // Match the declaration exactly: a bare contains("grain") would find grainGradient first
      let declares = line.contains(" \(name)(")
      let isDeclaration = line.contains("[[stitchable]]") || ["half4 ", "float2 ", "float ", "void "].contains { line.hasPrefix($0) }
      if declares && isDeclaration {
        // look back for [[stitchable]] if not on this line
        startLine = i
        for j in stride(from: i, through: max(0, i-3), by: -1) {
          if lines[j].contains("[[stitchable]]") { startLine = j; break }
        }
        break
      }
    }
    guard startLine >= 0 else { return "// Function '\(name)' not found" }

    var depth = 0
    var started = false
    var result: [String] = []
    for i in startLine..<lines.count {
      let l = lines[i]
      result.append(l)
      for ch in l {
        if ch == "{" { depth += 1; started = true }
        else if ch == "}" { depth -= 1 }
      }
      if started && depth == 0 { break }
    }
    return result.joined(separator: "\n")
  }
}

private extension Float {
  func clamped(to range: ClosedRange<Float>) -> Float {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

extension CGFloat {
  func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

// MARK: - Metal Syntax Highlighter

private func highlightedMetal(_ source: String) -> NSAttributedString {
  let result = NSMutableAttributedString(string: source)
  let fullRange = NSRange(source.startIndex..., in: source)

  let base = UIColor(white: 0.88, alpha: 1)
  result.addAttribute(.foregroundColor, value: base, range: fullRange)

  // Comment: // ...
  apply(pattern: #"//[^\n]*"#, to: result, in: source, color: UIColor(red: 0.42, green: 0.62, blue: 0.42, alpha: 1))
  // Comment: /* ... */
  apply(pattern: #"/\*[\s\S]*?\*/"#, to: result, in: source, color: UIColor(red: 0.42, green: 0.62, blue: 0.42, alpha: 1))
  // Preprocessor
  apply(pattern: #"#\w+"#, to: result, in: source, color: UIColor(red: 0.78, green: 0.55, blue: 0.78, alpha: 1))
  // Numbers
  apply(pattern: #"\b\d+(\.\d+)?[fhFH]?\b"#, to: result, in: source, color: UIColor(red: 0.70, green: 0.85, blue: 0.65, alpha: 1))
  // Types
  let types = ["half4","half3","half2","half","float4","float3","float2","float","int2","int","uint8_t","uint","bool","void","constant","device","thread","threadgroup"]
  for t in types {
    apply(pattern: #"\b"# + t + #"\b"#, to: result, in: source, color: UIColor(red: 0.42, green: 0.75, blue: 0.90, alpha: 1))
  }
  // Keywords
  let keywords = ["return","if","else","for","while","break","continue","using","namespace","include","stitchable","kernel","vertex","fragment","struct","static"]
  for k in keywords {
    apply(pattern: #"\b"# + k + #"\b"#, to: result, in: source, color: UIColor(red: 0.90, green: 0.50, blue: 0.60, alpha: 1))
  }
  // Attributes
  apply(pattern: #"\[\[.*?\]\]"#, to: result, in: source, color: UIColor(red: 0.85, green: 0.70, blue: 0.40, alpha: 1))
  // Built-in functions
  let builtins = ["sin","cos","tan","sqrt","abs","min","max","mix","clamp","step","smoothstep","length","normalize","dot","cross","reflect","pow","fract","floor","ceil","mod","atan2","log","exp"]
  for b in builtins {
    apply(pattern: #"\b"# + b + #"\b"#, to: result, in: source, color: UIColor(red: 0.75, green: 0.60, blue: 0.95, alpha: 1))
  }

  return result
}

private func apply(pattern: String, to attr: NSMutableAttributedString, in source: String, color: UIColor) {
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
  let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
  for m in matches {
    attr.addAttribute(.foregroundColor, value: color, range: m.range)
  }
}

// MARK: - Dithered Label Inspector

struct DitheredLabelInspector: View {
  @Binding var label: DitheredLabel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionLabel(title: "Dithered Label")

      VStack(spacing: 0) {
        // On/off toggle
        HStack {
          Text("Show Label")
            .font(.system(size: 14)).foregroundStyle(.primary)
          Spacer()
          Toggle("", isOn: $label.enabled).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)

        if label.enabled {
          Divider().background(Color.primary.opacity(0.08))

          // Text input
          HStack {
            Text("Text")
              .font(.system(size: 14)).foregroundStyle(.primary)
            Spacer()
            TextField("BITRIG", text: $label.text)
              .multilineTextAlignment(.trailing)
              .font(.system(size: 13, design: .monospaced))
              .foregroundStyle(.secondary)
              .frame(maxWidth: 120)
              .textInputAutocapitalization(.characters)
          }
          .padding(.horizontal, 16).padding(.vertical, 12)

          Divider().background(Color.primary.opacity(0.08))

          MinimalSlider(
            label: "Pixel Size",
            value: Binding(get: { Float(label.pixelSize) }, set: { label.pixelSize = CGFloat($0) }),
            range: 2...20,
            valueString: "\(Int(label.pixelSize))px"
          )
          .padding(.horizontal, 16).padding(.vertical, 12)

          Divider().background(Color.primary.opacity(0.08))

          MinimalSlider(
            label: "Scale",
            value: Binding(get: { Float(label.scale) }, set: { label.scale = Double($0) }),
            range: 0.5...4,
            valueString: String(format: "×%.1f", label.scale)
          )
          .padding(.horizontal, 16).padding(.vertical, 12)

          Divider().background(Color.primary.opacity(0.08))

          MinimalSlider(
            label: "Rotation",
            value: Binding(get: { Float(label.rotation) }, set: { label.rotation = Double($0) }),
            range: -180...180,
            valueString: "\(Int(label.rotation))°"
          )
          .padding(.horizontal, 16).padding(.vertical, 12)

          Divider().background(Color.primary.opacity(0.08))

          HStack {
            Text("Color")
              .font(.system(size: 14)).foregroundStyle(.primary)
            Spacer()
            ColorPicker("", selection: $label.labelColor, supportsOpacity: false)
              .labelsHidden()
          }
          .padding(.horizontal, 16).padding(.vertical, 12)
        }
      }
      .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
      .animation(.smooth(duration: 0.25), value: label.enabled)
    }
  }
}

// MARK: - Nodes Placeholder

struct NodesPlaceholderView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "circle.grid.3x3.fill")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
      Text("Nodes")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.primary)
      Text("Node-based shader editor\ncoming soon")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Content Height Preference

private struct ContentHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

/// A ScrollView that hugs its content height up to `maxHeight`, then scrolls.
struct BoundedScrollView<Content: View>: View {
  var maxHeight: CGFloat
  @ViewBuilder var content: () -> Content
  @State private var contentHeight: CGFloat = 0

  private let fadeHeight: CGFloat = 28
  private var overflows: Bool { contentHeight > maxHeight + 1 }

  var body: some View {
    ScrollView {
      content()
        .background(
          GeometryReader { geo in
            Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
          }
        )
    }
    .onPreferenceChange(ContentHeightKey.self) { h in
      withAnimation(.smooth(duration: 0.35)) { contentHeight = h }
    }
    .frame(height: min(contentHeight, maxHeight))
    // When there's more below, fade the last rows out so a cut-off row reads as "scroll"
    .contentMargins(.bottom, overflows ? fadeHeight : 0, for: .scrollContent)
    .modifier(BottomFadeMask(isActive: overflows, height: fadeHeight))
  }
}

/// Fades out the bottom edge. A mask is an extra offscreen pass on every frame the layer is
/// composited, and these panels sit over a canvas that redraws 30 times a second, so it's
/// only applied while there is actually something cut off.
struct BottomFadeMask: ViewModifier {
  var isActive: Bool
  var height: CGFloat

  func body(content: Content) -> some View {
    if isActive {
      content.mask {
        VStack(spacing: 0) {
          Color.black
          LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
        }
      }
    } else {
      content
    }
  }
}

// MARK: - Helpers

struct SectionLabel: View {
  var title: String
  var body: some View {
    Text(title.uppercased())
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(.secondary)
      .kerning(1.2)
  }
}

struct ToolbarActiveButton<Label: View>: View {
  var isActive: Bool
  var action: () -> Void
  @ViewBuilder var label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
        .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .frame(width: 36, height: 32)
        .background {
          if isActive {
            Capsule().fill(Color.primary.opacity(0.15))
          }
        }
    }
    .buttonStyle(.plain)
  }
}
#endif
