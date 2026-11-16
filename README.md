# Shader Lab

<a href="https://bitrig.link/shader-lab-gh"><img src="Documentation/Images/Badges/made-with-bitrig.svg" alt="Made with Bitrig" height="56"></a><a href="https://fsanchez.io"><img src="Documentation/Images/Badges/designed-by.svg" alt="Designed by Fede Sánchez" height="56"></a><a href="https://claude.com/claude-code"><img src="Documentation/Images/Badges/claude-code.svg" alt="In collaboration with Claude Code" height="56"></a>

<p align="center"><img src="Documentation/Media/ipad-rain.png" alt="Shader Lab on iPad: the Rain shader running over a photo of El Capitan, with the effects sidebar on the left and the parameters panel on the right" width="720"></p>

Shader Lab is a playground for live Metal shaders. Pick one of fifteen effects, drag its parameters and watch the canvas change as you go. There are full-screen generators (gradients, dithering, a fractal plant printed as a cyanotype, an iridescent sphere) and effects that work on a photo: warp, ripple, pinch, fluted glass, chromatic aberration and rain on a window. You can lay text over the result, save any shader as a wallpaper, and read or share the Metal source of the shader on screen.

It runs on iPhone, iPad, iPhone Duo, Apple TV, Apple Vision Pro and Apple Watch, with a layout made for each.

## Platforms

| Platform | What it does | Minimum |
| --- | --- | --- |
| **iPhone** | Full-screen canvas with a drawer of controls that you drag up or tap away. | iOS 26 |
| **iPad** | The canvas with two floating glass panels: effects on the left, parameters and canvas settings on the right. Editor, Nodes and Code tabs, a touch magnifier, and text and dithered-label overlays. | iPadOS 26 |
| **iPhone Duo** | The outer display works like iPhone and the inner display like iPad. In book and tabletop poses the panels stay clear of the crease, and in tabletop the picture sits on the upright half above the panels. | iOS 26; hinge-aware layout needs iOS 27.1 |
| **Apple TV** | One shader fills the screen, with a glass picker for the shader and, for Rain, the photo it falls on. The Siri Remote moves focus, and Play/Pause hides the controls and keeps the screen awake. The layout is sized to also fit HomeView's square touch panel. | tvOS 26 |
| **Apple Vision Pro** | A lobby window, and an immersive space with a floating canvas and controls. | visionOS 26 |
| **Apple Watch** | A companion app with seven presets drawn with SwiftUI `Canvas` and a speed control. | watchOS 11 |

## Design & Examples

One goal of the design was controls that sit concentric with the screen: each sheet and panel keeps its corners an even distance from the display's own. You can see it in the iPhone's drawer, the iPhone Duo shots and the iPad's floating panels, which are all SwiftUI `ConcentricRectangle`s.

The controls are dynamic too, inspired by [DialKit](https://www.dialkit.dev). When you switch shaders, the panel updates from the bottom up, replacing only what changes. Controls the two shaders share stay where they are, and keep their values when the ranges match. The ones the new shader doesn't have fade out, and its new ones fade in below the rest. Nothing jumps, so you can flip between effects without losing your place. The order is kept in `updateParamOrder` and the values in `carryOverSharedParams`, both in [`ShaderModel.swift`](App/ShaderModel.swift).

### iPhone

[<img src="Documentation/Media/iphone.gif" alt="iPhone: opening the shader list and switching from Wave to Sphere, then Rain" width="270">](Documentation/Media/iphone.mp4)
<img src="Documentation/Media/iphone-wave.png" alt="iPhone: Wave with its parameters" width="270">
<img src="Documentation/Media/iphone-shaders.png" alt="iPhone: the list of effects" width="270">

### iPad

[<img src="Documentation/Media/ipad.gif" alt="iPad: switching between Sphere, Fluted Glass, the Code tab and Rain" width="720">](Documentation/Media/ipad.mp4)

<img src="Documentation/Media/ipad-wave.png" alt="iPad: Wave" width="360"> <img src="Documentation/Media/ipad-fluted-glass.png" alt="iPad: Fluted Glass over a photo" width="360">
<img src="Documentation/Media/ipad-sphere.png" alt="iPad: Sphere" width="360"> <img src="Documentation/Media/ipad-code.png" alt="iPad: the Code tab showing the Metal source" width="360">

### iPhone Duo

[<img src="Documentation/Media/duo.gif" alt="iPhone Duo inner display: folding into book pose and back, then switching to Rain" width="720">](Documentation/Media/duo.mp4)

<img src="Documentation/Media/duo-outer.png" alt="iPhone Duo outer display" width="270"> <img src="Documentation/Media/duo-tabletop.png" alt="iPhone Duo in tabletop pose: the picture above the crease and the panels below" width="270">
<img src="Documentation/Media/duo-inner.png" alt="iPhone Duo inner display, open flat" width="360"> <img src="Documentation/Media/duo-book.png" alt="iPhone Duo inner display in book pose: the tab switcher parts around the crease" width="360">

### Apple TV

[<img src="Documentation/Media/appletv.gif" alt="Apple TV: moving through the shaders with the Siri Remote, then picking a photo for Rain" width="720">](Documentation/Media/appletv.mp4)

<img src="Documentation/Media/appletv-rain.png" alt="Apple TV: Rain over Yosemite" width="360"> <img src="Documentation/Media/appletv-sphere.png" alt="Apple TV: Sphere" width="360">

### HomeView

The Apple TV layout comes from this HomeView screen: the same pickers, sized for a 544-point square and tapped directly.

[<img src="Documentation/Media/homeview.gif" alt="HomeView: Rain falling on the square display, through Clownfish, Yosemite, El Capitan, Sierra and High Sierra" width="720">](Documentation/Media/homeview.mp4)

> [!NOTE]
> **This HomeView screen runs on Apple's internal HomeView SDK, inside a virtual machine.** Apple hasn't opened that SDK to developers, though it might in the future. Until then, this screen can't run on a real HomeView. That's also why it's built as a tvOS app: tvOS is what the virtual machine's internal SDK takes. What a real HomeView runs today is CarPlay: it has no App Store, and its third-party apps are CarPlay audio and video apps shown from a paired iPhone nearby, [like Spotify](https://mastodon.social/@stroughtonsmith/117543062117057105). Bitrig can build that kind of app today. To try this screen in the virtual machine, see [Run on a HomeView virtual machine](#run-on-a-homeview-virtual-machine).

## Shaders

Generators fill the canvas. Photo effects work on one of the bundled photos or one you pick from your library. The Code tab shows the selected shader's Metal function with the current parameter values filled in, and Export shares it as a `.metal` file.

Each shader below is shown at its default settings, captured on iPad with the controls hidden. The photo effects are shown on the default El Capitan photo.

<table>
  <tr><th colspan="3" align="left">Generators</th></tr>
  <tr>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/heatmap.jpg" alt="Heatmap shader" width="260"><br><b>Heatmap</b><br>Layered noise in thermal-camera colours, flowing in bands.</td>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/wave.jpg" alt="Wave shader" width="260"><br><b>Wave</b><br>Silky ribbons in four colours, flowing at an angle, straight or radial.</td>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/mesh.jpg" alt="Mesh shader" width="260"><br><b>Mesh</b><br>A soft gradient of drifting hues, shaped by layered noise.</td>
  </tr>
  <tr>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/grain-grad.jpg" alt="Grain Grad shader" width="260"><br><b>Grain Grad</b><br>A noisy colour gradient with fine film grain.</td>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/dithering.jpg" alt="Dithering shader" width="260"><br><b>Dithering</b><br>Noise drawn as an 8 × 8 Bayer dither, with an optional pixel-font label.</td>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/grain.jpg" alt="Grain shader" width="260"><br><b>Grain</b><br>Animated film grain over the canvas colour, optionally colourised.</td>
  </tr>
  <tr>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/fractal.jpg" alt="Fractal shader" width="260"><br><b>Fractal</b><br>Seaweed printed as a cyanotype, swaying gently, after the cover of Michael Frame’s <a href="https://press.uchicago.edu/ucp/books/book/chicago/G/bo113868517.html"><i>Geometry of Grief</i></a>. Organic straightens it into a symmetric tree; Seed grows another plant; Grow plays its life on a loop, from holdfast to developed print.</td>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/sphere.jpg" alt="Sphere shader" width="260"><br><b>Sphere</b><br>An iridescent sphere with two moving lights and a slowly turning surface.</td>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/vortex.jpg" alt="Vortex shader" width="260"><br><b>Vortex</b><br>Spiral arms twisting around the centre, fading toward the edges.</td>
  </tr>
  <tr><th colspan="3" align="left">Photo effects</th></tr>
  <tr>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/warp.jpg" alt="Warp shader" width="260"><br><b>Warp</b><br>Bends the photo with crossing sine waves.</td>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/ripple.jpg" alt="Ripple shader" width="260"><br><b>Ripple</b><br>Rings spreading out from the centre of the photo.</td>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/pinch.jpg" alt="Pinch shader" width="260"><br><b>Pinch</b><br>Pulls the photo toward its centre and lets go, over and over.</td>
  </tr>
  <tr>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/fluted-glass.jpg" alt="Fluted Glass shader" width="260"><br><b>Fluted Glass</b><br>The photo through ribbed glass: lines, irregular, wave, zigzag or pattern.</td>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/chromatic.jpg" alt="Chromatic shader" width="260"><br><b>Chromatic</b><br>Splits red, green and blue apart from the centre, along an angle.</td>
    <td width="33%" valign="top"><img src="Documentation/Media/Shaders/rain.jpg" alt="Rain shader" width="260"><br><b>Rain</b><br>Drops on the glass, with the photo blurred behind it. Window picks where you watch from: a house, where they run down; a car, where the wind pushes them up; or a plane on a late-night flight, where they streak back past a row of dimmed windows.</td>
  </tr>
</table>

## Shaders as wallpapers

In the editor on iPhone, iPad or iPhone Duo, tap **Export** to save the shader on screen to Photos as a still, with any text overlay included. It renders at full quality, at your screen's own size and pixel density: 1206 × 2622 on iPhone 18 Pro, and the full display on iPad and on each of the Duo's displays. On iPhone the image is always upright, even if you export in landscape. So it drops straight in as a Lock Screen or Home Screen wallpaper: in Photos, tap Share, then Use as Wallpaper.

## How it works

- **Shaders.** Every effect is a `[[stitchable]]` function in [`App/Shaders.metal`](App/Shaders.metal), applied with SwiftUI's `colorEffect`, `distortionEffect` and `layerEffect`. [`ShaderModel.swift`](App/ShaderModel.swift) lists the shaders, their parameters, ranges and units.
- **One clock.** [`CanvasClock`](App/CanvasClock.swift) ticks about 30 times a second and stops when the scene isn't active. Every canvas reads it, so the main canvas, the magnifier and the tabletop reflection stay in step.
- **Render quality.** Soft gradients are rendered on a smaller surface and scaled up ([`ReducedResolution`](App/CanvasView.swift)). Point-sized parameters, like the dither cell size, shrink with the surface so the result looks the same.
- **Photos.** [`CanvasImageStore`](App/CanvasImageStore.swift) decodes each photo once, at the size the canvas can show, and caches it.
- **iPhone Duo.** [`DuoRuntime`](App/DuoRuntime.swift) reads the hinge with `onHingeChange`. The layout uses the system's reserved regions for the crease and the camera, so controls never sit under either.
- **Apple TV.** [`App/TV`](App/TV) reuses the same `CanvasView`. Sizes are in units of a 544-point square, so the layout reads on a square panel and, scaled up, on a television. Opening `shaderlab://shader/<name>?photo=<photo>&chrome=hidden` shows a given shader, which is handy for scripted captures.

## Build and run

1. Use Xcode 27.1 or later (iOS 27.1 SDK), or Bitrig.
2. Open `Shader Lab.xcodeproj`. The **Shader Lab** scheme builds iPhone, iPad, Apple TV and Apple Vision Pro. The Watch app is embedded in the iPhone app. **Shader Lab Watch App** builds the watch app on its own.
3. To run on a device, set your development team. The bundle identifier is a placeholder, so change it to one of your own.

No packages or setup scripts are needed.

### Run on a HomeView virtual machine

The HomeView screen runs on a virtual HomeView made with [vphone-cli](https://github.com/Lakr233/vphone-cli). That's an open-source project (MIT) that runs Apple's device systems in virtual machines on an Apple silicon Mac, with Virtualization.framework and Apple's Private Cloud Compute research VMs. It isn't affiliated with Apple or Bitrig.

1. Set up vphone with its [Quick Start](https://lakr233.github.io/vphone-cli/get-started/quick-start). Install the notarized `vphone-launchpad` from the [latest release](https://github.com/Lakr233/vphone-cli/releases/latest). In Launchpad, grant Developer Tools access, install the helper and install the Core Bundle. Then put `vphone-launchpad-cli` on your `PATH`.
2. In Launchpad 2.15 or later, click **New Machine** and choose a HomeView firmware (`HomeAccessory17,1` or `17,2`). Launchpad then selects its `homeview` preset itself. Name the machine `HomeView` and click **Create**. Creating it downloads, patches and restores the firmware, so it takes a while and needs plenty of free disk space. For what works in the virtual HomeView so far, see vphone's [HomeView notes](https://github.com/Lakr233/vphone-cli/blob/main/Research/Firmware/homeview_bringup.md). Then start it:

   ```sh
   vphone-launchpad-cli vm start HomeView --wait
   ```

3. From the repository, build the tvOS app unsigned and wrap it in an `.ipa`:

   ```sh
   xcodebuild -project "Shader Lab.xcodeproj" -scheme "Shader Lab" -sdk appletvos \
     -destination 'generic/platform=tvOS' -configuration Debug \
     -derivedDataPath build/homeview CODE_SIGNING_ALLOWED=NO build
   mkdir -p build/homeview-ipa/Payload
   cp -R "build/homeview/Build/Products/Debug-appletvos/Shader Lab.app" build/homeview-ipa/Payload/
   (cd build/homeview-ipa && zip -qr ../ShaderLab-HomeView.ipa Payload)
   ```

4. Copy it to the machine, install it and open it on a shader:

   ```sh
   BUNDLE=$(grep -m1 -o 'PRODUCT_BUNDLE_IDENTIFIER = "[^"]*"' "Shader Lab.xcodeproj/project.pbxproj" | cut -d'"' -f2)
   vphone-launchpad-cli guest push HomeView build/ShaderLab-HomeView.ipa /private/var/tmp/
   vphone-launchpad-cli guest rpc HomeView apps.install '{"path":"/private/var/tmp/ShaderLab-HomeView.ipa"}'
   vphone-launchpad-cli guest unlock HomeView
   vphone-launchpad-cli guest rpc HomeView apps.launch "{\"bundle_id\":\"$BUNDLE\",\"url\":\"shaderlab://shader/rain?photo=yosemite\"}"
   ```

   The URL picks the shader and, for Rain, the photo (see [How it works](#how-it-works)).

## Tests

```sh
# Unit tests (Swift Testing) and UI tests on an iPhone simulator
bitrig test -destination 'platform=iOS Simulator,name=iPhone 17'

# iPad-only UI tests
bitrig test -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -only-testing:"Shader Lab UI Tests"
```

`xcodebuild test -scheme "Shader Lab"` works the same way.

- **Unit tests** ([`Tests/`](Tests)) check the shader catalog, parameter formatting, render-scale rules, the model, image downsampling and settings.
- **UI tests** ([`UITests/`](UITests)) walk the iPhone editor and the iPad tabs and sidebar. Tests for the other layout skip themselves.

## Project layout

- `App/`: the app, shared by every platform except watchOS.
  - `ContentView.swift`: the iPhone, iPad and iPhone Duo editor.
  - `CanvasView.swift`: the renderer.
  - `ShaderModel.swift`: the catalog and the model.
  - `Shaders.metal`: the shaders. `ShaderSource.txt` is the copy the Code tab shows.
  - `Duo*.swift`, `Fold*.swift`: iPhone Duo.
  - `VisionShaderViews.swift`: visionOS.
  - `TV/`: tvOS.
  - `Resources/`: bundled photos.
- `Watch App/`: the watchOS companion.
- `Tests/`, `UITests/`: tests.
- `Documentation/`: screenshots, video and badges.

## Known issues

Bugs and performance work are tracked in this repository's Issues.

## Acknowledgements

**Libraries.** Shader Lab uses no third-party libraries or Swift packages, only Apple's frameworks (SwiftUI, Metal, MetalKit, PhotosUI, RealityKit and UIKit).

**Shader code and techniques**

- **Rain.** Based on [“Heartfelt”](https://www.shadertoy.com/view/ltffzl) by Martijn Steinrucken (BigWings), 2017, published on Shadertoy under [CC BY-NC-SA 3.0](https://creativecommons.org/licenses/by-nc-sa/3.0/). That licence doesn't allow commercial use, and adaptations must be shared alike. Keep this in mind before shipping Rain in a paid app.
- **Helpers and inspiration.** The `remap` helper follows [paper-design/shaders](https://github.com/paper-design/shaders) (Apache 2.0). Mesh Gradient, Grain Gradient, Dithering, Heatmap and Fluted Glass are effects that library also offers.
- **Fluted Glass falloff.** The progressive falloff along the flutes follows a technique by [Janum Trivedi](https://github.com/jtrivedi).
- **Standard methods.** Sphere uses GGX (Cook–Torrance) specular. Dithering uses an 8×8 Bayer matrix.

**Images and fonts**

- **Apple wallpapers.** The macOS wallpapers in `App/Assets.xcassets` are Apple's and are included for demonstration only: Snow Leopard (10-6), Yosemite (10-10), El Capitan (10-11), Sierra (10-12), High Sierra (10-13) and Ventura's dark wallpaper (13-dark). They come from 512 Pixels' [Default Mac Wallpapers in 5K](https://512pixels.net/projects/default-mac-wallpapers-in-5k/). The Clownfish photo (`fish.php.jpeg`) is also Apple's wallpaper.
- **Unsplash photo.** `val-toch-BHeQQmZM8jE-unsplash.jpg` is by [Val Toch](https://unsplash.com/photos/BHeQQmZM8jE), under the [Unsplash License](https://unsplash.com/license).
- **HomeView video.** The HomeView product image in that video is Apple's.

**Tools**

- **vphone-cli.** The virtual HomeView comes from [vphone-cli](https://github.com/Lakr233/vphone-cli) by Lakr233 and contributors (MIT).

Apple, iPhone, iPad, Apple TV, Apple Watch, Apple Vision Pro, HomeView, macOS and SF are trademarks of Apple Inc. This project isn't affiliated with or endorsed by Apple.

The badges come from the same set used in Fede Sánchez's other projects.

## Licence

Shader Lab's code is released under the [MIT Licence](LICENSE), with one exception: Rain adapts “Heartfelt”, so its section of [`App/Shaders.metal`](App/Shaders.metal) keeps Heartfelt's [CC BY-NC-SA 3.0](https://creativecommons.org/licenses/by-nc-sa/3.0/) licence, and the Code tab shows that notice with Rain's source. The MIT Licence doesn't cover the bundled photos or the Apple imagery in the screenshots and videos. They belong to their owners, listed under Acknowledgements.
