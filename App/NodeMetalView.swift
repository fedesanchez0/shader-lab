import SwiftUI
import Metal
import MetalKit

#if !os(visionOS)
// MARK: - Uniforms

struct NodeUniforms {
  var time: Float
  var resolution: SIMD2<Float>
  var touchPosition: SIMD2<Float>
  var touchPressure: Float
  var _pad: Float = 0
}

// MARK: - Shader Template

private let shaderTemplate = """
#include <metal_stdlib>
using namespace metal;

struct NodeUniforms {
    float time;
    float2 resolution;
    float2 touchPosition;
    float touchPressure;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut nodeVert(uint vid [[vertex_id]]) {
    float2 positions[4] = {float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1)};
    float2 uvs[4]       = {float2(0,1),   float2(1,1),   float2(0,0),  float2(1,0)};
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

fragment float4 nodeFrag(VertexOut in [[stage_in]],
                         constant NodeUniforms& uniforms [[buffer(0)]]) {
GENERATED_CODE
}
"""

// MARK: - Renderer

class NodeMetalRenderer: NSObject, MTKViewDelegate {
  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  var pipelineState: MTLRenderPipelineState?
  var compiledCode: String = ""
  var startTime = Date()
  var touchPosition: SIMD2<Float> = .zero
  var touchPressure: Float = 0

  init(device: MTLDevice) {
    self.device = device
    self.commandQueue = device.makeCommandQueue()!
    super.init()
  }

  func compile(_ code: String) {
    guard code != compiledCode else { return }
    compiledCode = code
    let source = shaderTemplate.replacingOccurrences(of: "GENERATED_CODE", with: code)
    do {
      let library = try device.makeLibrary(source: source, options: nil)
      let desc = MTLRenderPipelineDescriptor()
      desc.vertexFunction   = library.makeFunction(name: "nodeVert")
      desc.fragmentFunction = library.makeFunction(name: "nodeFrag")
      desc.colorAttachments[0].pixelFormat = .bgra8Unorm
      pipelineState = try device.makeRenderPipelineState(descriptor: desc)
    } catch {
      pipelineState = nil
    }
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    guard let ps = pipelineState,
          let drawable = view.currentDrawable,
          let rpd = view.currentRenderPassDescriptor,
          let cb = commandQueue.makeCommandBuffer(),
          let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }

    var uniforms = NodeUniforms(
      time: Float(Date().timeIntervalSince(startTime)),
      resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
      touchPosition: touchPosition,
      touchPressure: touchPressure
    )

    enc.setRenderPipelineState(ps)
    enc.setFragmentBytes(&uniforms, length: MemoryLayout<NodeUniforms>.stride, index: 0)
    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    enc.endEncoding()
    cb.present(drawable)
    cb.commit()
  }

  @objc func handlePan(_ g: UIPanGestureRecognizer) {
    guard let view = g.view else { return }
    let loc = g.location(in: view)
    touchPosition = SIMD2(Float(loc.x / view.bounds.width), Float(loc.y / view.bounds.height))
    touchPressure = g.state == .ended ? 0 : 1
  }
}

// MARK: - SwiftUI Wrapper

struct NodeMetalView: UIViewRepresentable {
  var generatedCode: String

  func makeCoordinator() -> NodeMetalRenderer {
    NodeMetalRenderer(device: MTLCreateSystemDefaultDevice()!)
  }

  func makeUIView(context: Context) -> MTKView {
    let view = MTKView()
    view.device = context.coordinator.device
    view.delegate = context.coordinator
    view.colorPixelFormat = .bgra8Unorm
    view.clearColor = MTLClearColorMake(0.08, 0.08, 0.08, 1)
    view.preferredFramesPerSecond = 60
    view.isPaused = false
    view.enableSetNeedsDisplay = false
    let pan = UIPanGestureRecognizer(target: context.coordinator,
                                     action: #selector(NodeMetalRenderer.handlePan(_:)))
    view.addGestureRecognizer(pan)
    context.coordinator.compile(generatedCode)
    return view
  }

  func updateUIView(_ view: MTKView, context: Context) {
    context.coordinator.compile(generatedCode)
  }
}

// MARK: - Preview Panel

struct NodePreviewPanel: View {
  @Bindable var graph: NodeGraph

  var body: some View {
    VStack(spacing: 0) {
      NodeMetalView(generatedCode: graph.generatedCode)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      // Code panel toggle
      VStack(spacing: 0) {
        Button {
          withAnimation(.smooth(duration: 0.25)) { graph.showCode.toggle() }
        } label: {
          HStack {
            Image(systemName: "chevron.up")
              .rotationEffect(.degrees(graph.showCode ? 180 : 0))
              .font(.system(size: 11, weight: .medium))
            Text("Generated MSL")
              .font(.system(size: 12, weight: .medium))
            Spacer()
          }
          .foregroundStyle(.secondary)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
        }
        .buttonStyle(.plain)

        if graph.showCode {
          ScrollView {
            Text(graph.generatedCode.isEmpty ? "// Connect nodes to generate code" : graph.generatedCode)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(12)
          }
          .frame(height: 180)
        }
      }
      .background(Color(white: 0.1))
    }
  }
}
#else
struct NodePreviewPanel: View {
  @Bindable var graph: NodeGraph

  var body: some View {
    VStack(spacing: 0) {
      LinearGradient(
        colors: [Color(white: 0.12), Color(white: 0.04)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .overlay {
        VStack(spacing: 12) {
          Image(systemName: "display.trianglebadge.exclamationmark")
            .font(.system(size: 28, weight: .medium))
          Text("Metal node preview is available on iPhone and iPad.")
            .font(.system(size: 14, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
        .padding(24)
      }

      ScrollView {
        Text(graph.generatedCode.isEmpty ? "// Connect nodes to generate code" : graph.generatedCode)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      }
      .frame(height: 220)
      .background(Color(white: 0.1))
    }
  }
}
#endif
