import SwiftUI

/// The Geometry of Grief cover's title, at the Fractal's top left when Title is on: GEOMETRY in
/// spaced capitals over an indented "of GRIEF", as the book sets it, in the pale tint the plant
/// is printed in. In the Grow loop its letters come up out of the paper one by one once the
/// plant has grown (see FractalGrowth.titleReveal), and fade with the last of the plant.
struct FractalTitleView: View {
  var model: PlaygroundModel
  var time: Float
  /// The canvas'
  var size: CGSize

  /// The cover's two lines, as words: GEOMETRY, then an italic "of" and GRIEF
  private static let lines: [[TitleWord]] = [
    [TitleWord(text: "GEOMETRY")],
    [TitleWord(text: "of", isItalic: true), TitleWord(text: "GRIEF")],
  ]
  private static let letterCount = lines.joined().map(\.text.count).reduce(0, +)

  var body: some View {
    if let reveal = model.fractalTitleReveal(letters: Self.letterCount, at: time) {
      // Sized to the canvas, as the plant is: the cover's proportions on any screen
      let em = min(size.width, size.height) * 0.026
      VStack(alignment: .leading, spacing: 0.35 * em) {
        Text(printed(Self.lines[0], from: 0, reveal: reveal, em: em))
        // The cover indents the second line by three quarters of the first
        Text(printed(Self.lines[1], from: Self.lines[0].map(\.text.count).reduce(0, +), reveal: reveal, em: em))
          .padding(.leading, 6.8 * em)
      }
      .fixedSize()
      .padding(.leading, size.width * 0.06)
      .padding(.top, size.height * 0.08)
      .frame(width: size.width, height: size.height, alignment: .topLeading)
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Geometry of Grief")
      .accessibilityHidden(reveal.allSatisfy { $0 < 0.5 })
    }
  }

  /// The print's colour: the paper's hue, pale, as fractalTree tints the plant
  private var ink: Color {
    let paper = model.shaderParams[FractalGrowth.shaderID]?.first { $0.name == "Paper" }?.value ?? 0.5714
    return Color(hue: Double(paper), saturation: 0.278, brightness: 1)
  }

  /// A line of the title, each letter as far up out of the paper as `reveal` says, counting
  /// from letter `first`
  private func printed(_ words: [TitleWord], from first: Int, reveal: [Float], em: CGFloat) -> AttributedString {
    var line = AttributedString()
    var index = first
    for (position, word) in words.enumerated() {
      if position > 0 {
        var space = AttributedString(" ")
        space.font = .custom("HoeflerText-Regular", fixedSize: em)
        space.tracking = 0.2 * em
        line += space
      }
      for character in word.text {
        var letter = AttributedString(String(character))
        letter.font = .custom(word.isItalic ? "HoeflerText-Italic" : "HoeflerText-Regular", fixedSize: em)
        // Spaced capitals, as on the cover; the italic keeps its own spacing
        letter.tracking = (word.isItalic ? 0.04 : 0.42) * em
        letter.foregroundColor = ink.opacity(0.96 * Double(reveal[index]))
        line += letter
        index += 1
      }
    }
    return line
  }
}

/// A word of the title, and whether it's set in italic
private struct TitleWord {
  var text: String
  var isItalic = false
}
