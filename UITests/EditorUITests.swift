import XCTest

/// Walks through the editor the way a person would on iPhone and iPad.
final class EditorUITests: XCTestCase {
  private var app: XCUIApplication!

  private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

  private static let generators = ["Heatmap", "Wave", "Mesh", "Grain Grad", "Dithering", "Grain", "Fractal", "Sphere", "Vortex"]
  private static let photoEffects = ["Warp", "Ripple", "Pinch", "Fluted Glass", "Chromatic", "Rain"]

  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launch()
  }

  func testOpensOnTheEditorWithExport() {
    XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons[isPad ? "Hide Controls" : "Show Shader List"].exists)
  }

  // MARK: iPhone

  func testPhoneOpensOnWaveControls() throws {
    try XCTSkipIf(isPad, "iPhone layout")
    XCTAssertTrue(app.staticTexts["Wave"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Reset"].exists)
    XCTAssertTrue(app.staticTexts["Speed"].exists)
  }

  func testPhoneListsEveryShader() throws {
    try XCTSkipIf(isPad, "iPhone layout")
    openPhoneShaderList()
    for name in Self.generators + Self.photoEffects {
      XCTAssertTrue(app.buttons[name].exists, "\(name) is missing from the shader list")
    }
  }

  func testPhoneSwitchesToAGenerator() throws {
    try XCTSkipIf(isPad, "iPhone layout")
    openPhoneShaderList()
    app.buttons["Heatmap"].tap()
    XCTAssertTrue(app.staticTexts["Heatmap"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Scale"].exists, "Heatmap's own parameters should show")
  }

  func testPhoneSwitchesToAPhotoEffect() throws {
    try XCTSkipIf(isPad, "iPhone layout")
    openPhoneShaderList()
    app.buttons["Chromatic"].tap()
    XCTAssertTrue(app.staticTexts["Chromatic"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Amount"].exists)
  }

  func testParameterSlidersAreAdjustableElements() throws {
    try XCTSkipIf(isPad, "iPhone layout")
    let speed = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Speed'")).firstMatch
    XCTAssertTrue(speed.waitForExistence(timeout: 10))
    // One element carrying its value, not two loose texts
    XCTAssertEqual(speed.value as? String, "60%")
    XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Color 1'")).firstMatch.exists)
  }

  func testEveryPhotoEffectOffersThePhotos() throws {
    try XCTSkipIf(isPad, "iPhone layout")
    for name in ["Pinch", "Chromatic"] {
      openPhoneShaderList()
      app.buttons[name].tap()
      XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["Upload Image"].waitForExistence(timeout: 5), "\(name) has no photo picker")
    }
  }

  func testPhoneResetKeepsTheShader() throws {
    try XCTSkipIf(isPad, "iPhone layout")
    XCTAssertTrue(app.buttons["Reset"].waitForExistence(timeout: 10))
    app.buttons["Reset"].tap()
    XCTAssertTrue(app.staticTexts["Wave"].exists)
  }

  func testPhoneTopButtonOpensTheShaderList() throws {
    try XCTSkipIf(isPad, "iPhone layout")
    XCTAssertTrue(app.buttons["Show Shader List"].waitForExistence(timeout: 10))
    app.buttons["Show Shader List"].tap()
    XCTAssertTrue(app.staticTexts["Effects"].waitForExistence(timeout: 5))
  }

  func testPadHideControlsAndBringThemBack() throws {
    try XCTSkipUnless(isPad, "iPad layout")
    let hide = app.buttons["Hide Controls"]
    XCTAssertTrue(hide.waitForExistence(timeout: 10))
    hide.tap()
    let canvas = app.buttons.matching(NSPredicate(format: "label ENDSWITH ' canvas'")).firstMatch
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    canvas.tap()
    XCTAssertTrue(app.buttons["Text Overlay Settings"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Text Overlay Settings"].isHittable)
  }

  // MARK: iPad

  func testPadSwitchesBetweenTabs() throws {
    try XCTSkipUnless(isPad, "iPad layout")
    for tab in ["Editor", "Nodes", "Code"] {
      XCTAssertTrue(app.buttons[tab].waitForExistence(timeout: 10), "\(tab) tab is missing")
    }
    app.buttons["Nodes"].tap()
    XCTAssertTrue(app.staticTexts["Coming Soon"].waitForExistence(timeout: 5))
    app.buttons["Code"].tap()
    XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 5))
    app.buttons["Editor"].tap()
    XCTAssertTrue(app.buttons["Text Overlay Settings"].waitForExistence(timeout: 5))
  }

  func testPadSwitchesShaderFromTheSidebar() throws {
    try XCTSkipUnless(isPad, "iPad layout")
    let heatmap = app.buttons["Heatmap"]
    XCTAssertTrue(heatmap.waitForExistence(timeout: 10))
    heatmap.tap()
    XCTAssertTrue(app.staticTexts["Scale"].waitForExistence(timeout: 5))
  }

  // MARK: Helpers

  private func openPhoneShaderList() {
    let shaders = app.buttons["Shaders"]
    XCTAssertTrue(shaders.waitForExistence(timeout: 10))
    shaders.tap()
    XCTAssertTrue(app.buttons["Heatmap"].waitForExistence(timeout: 5))
  }
}
