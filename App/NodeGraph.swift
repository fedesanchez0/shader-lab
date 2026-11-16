import SwiftUI

// MARK: - Port Type

enum PortType: String, Equatable {
  case float, vec2, vec4

  var color: Color {
    switch self {
    case .float: Color(white: 0.6)
    case .vec2:  Color.green
    case .vec4:  Color.purple
    }
  }

  var mslType: String {
    switch self {
    case .float: "float"
    case .vec2:  "float2"
    case .vec4:  "float4"
    }
  }

  var defaultMSL: String {
    switch self {
    case .float: "0.0"
    case .vec2:  "float2(0.0)"
    case .vec4:  "float4(0.5, 0.5, 0.5, 1.0)"
    }
  }
}

// MARK: - Node Category

enum NodeCategory {
  case input, math, uv, output

  var color: Color {
    switch self {
    case .input:  .orange
    case .math:   .purple
    case .uv:     .teal
    case .output: .red
    }
  }
}

// MARK: - Port / Node Definition

struct PortDef {
  var name: String
  var type: PortType
}

struct NodeDef {
  var name: String
  var category: NodeCategory
  var inputs: [PortDef]
  var outputs: [PortDef]
}

// MARK: - All Definitions

enum NodeDefs {
  static let all: [NodeDef] = [
    // Inputs
    NodeDef(name: "Time",       category: .input,
            inputs: [],
            outputs: [PortDef(name: "time",     type: .float)]),
    NodeDef(name: "UV",         category: .uv,
            inputs: [],
            outputs: [PortDef(name: "uv",       type: .vec2)]),
    NodeDef(name: "Resolution", category: .input,
            inputs: [],
            outputs: [PortDef(name: "res",      type: .vec2)]),
    NodeDef(name: "Touch",      category: .input,
            inputs: [],
            outputs: [PortDef(name: "pos",      type: .vec2),
                      PortDef(name: "pressure", type: .float)]),
    NodeDef(name: "Constant",   category: .input,
            inputs: [],
            outputs: [PortDef(name: "val",      type: .float)]),
    NodeDef(name: "Vec2",       category: .input,
            inputs: [PortDef(name: "x", type: .float), PortDef(name: "y", type: .float)],
            outputs: [PortDef(name: "out", type: .vec2)]),
    NodeDef(name: "Vec4",       category: .input,
            inputs: [PortDef(name: "r", type: .float), PortDef(name: "g", type: .float),
                     PortDef(name: "b", type: .float), PortDef(name: "a", type: .float)],
            outputs: [PortDef(name: "out", type: .vec4)]),
    // Math
    NodeDef(name: "Add",        category: .math,
            inputs: [PortDef(name: "a", type: .float), PortDef(name: "b", type: .float)],
            outputs: [PortDef(name: "out", type: .float)]),
    NodeDef(name: "Multiply",   category: .math,
            inputs: [PortDef(name: "a", type: .float), PortDef(name: "b", type: .float)],
            outputs: [PortDef(name: "out", type: .float)]),
    NodeDef(name: "Sine",       category: .math,
            inputs: [PortDef(name: "x", type: .float)],
            outputs: [PortDef(name: "out", type: .float)]),
    NodeDef(name: "Clamp",      category: .math,
            inputs: [PortDef(name: "x", type: .float), PortDef(name: "min", type: .float),
                     PortDef(name: "max", type: .float)],
            outputs: [PortDef(name: "out", type: .float)]),
    NodeDef(name: "Mix",        category: .math,
            inputs: [PortDef(name: "a", type: .float), PortDef(name: "b", type: .float),
                     PortDef(name: "t", type: .float)],
            outputs: [PortDef(name: "out", type: .float)]),
    NodeDef(name: "Abs",        category: .math,
            inputs: [PortDef(name: "x", type: .float)],
            outputs: [PortDef(name: "out", type: .float)]),
    NodeDef(name: "Fract",      category: .math,
            inputs: [PortDef(name: "x", type: .float)],
            outputs: [PortDef(name: "out", type: .float)]),
    NodeDef(name: "Step",       category: .math,
            inputs: [PortDef(name: "edge", type: .float), PortDef(name: "x", type: .float)],
            outputs: [PortDef(name: "out", type: .float)]),
    NodeDef(name: "Smoothstep", category: .math,
            inputs: [PortDef(name: "e0", type: .float), PortDef(name: "e1", type: .float),
                     PortDef(name: "x",  type: .float)],
            outputs: [PortDef(name: "out", type: .float)]),
    NodeDef(name: "Pow",        category: .math,
            inputs: [PortDef(name: "x", type: .float), PortDef(name: "y", type: .float)],
            outputs: [PortDef(name: "out", type: .float)]),
    // UV
    NodeDef(name: "Rotate UV",  category: .uv,
            inputs: [PortDef(name: "uv", type: .vec2), PortDef(name: "angle", type: .float)],
            outputs: [PortDef(name: "uv", type: .vec2)]),
    NodeDef(name: "Tile UV",    category: .uv,
            inputs: [PortDef(name: "uv", type: .vec2), PortDef(name: "scale", type: .float)],
            outputs: [PortDef(name: "uv", type: .vec2)]),
    NodeDef(name: "Remap UV",   category: .uv,
            inputs: [PortDef(name: "uv",     type: .vec2), PortDef(name: "scale",  type: .vec2),
                     PortDef(name: "offset", type: .vec2)],
            outputs: [PortDef(name: "uv", type: .vec2)]),
    // Output
    NodeDef(name: "Output",     category: .output,
            inputs: [PortDef(name: "color", type: .vec4)],
            outputs: []),
  ]

  static func named(_ name: String) -> NodeDef {
    all.first { $0.name == name }!
  }
}

// MARK: - Node Instance

struct NodeInstance: Identifiable {
  var id = UUID()
  var defName: String
  var position: CGPoint
  var constantValues: [Float] = [0.5]

  var def: NodeDef { NodeDefs.named(defName) }
}

// MARK: - Connection

struct NodeConnection: Identifiable {
  var id = UUID()
  var fromNode: UUID
  var fromPort: Int
  var toNode: UUID
  var toPort: Int
}

// MARK: - Port Address (for gesture state)

struct PortAddress: Equatable {
  var nodeId: UUID
  var portIndex: Int
  var isOutput: Bool
}

// MARK: - Drag State

enum CanvasDragState {
  case idle
  case movingNode(id: UUID, nodeStart: CGPoint, dragStart: CGPoint)
  case drawingWire(from: PortAddress, currentPoint: CGPoint)
  case panning(offsetStart: CGSize, dragStart: CGPoint)
}

// MARK: - NodeGraph

@Observable
class NodeGraph {
  var nodes: [NodeInstance] = []
  var connections: [NodeConnection] = []
  var panOffset: CGSize = CGSize(width: 40, height: 80)
  var selectedNodeId: UUID? = nil
  var dragState: CanvasDragState = .idle
  var generatedCode: String = ""
  var showCode: Bool = false

  // Layout constants
  static let nodeWidth: CGFloat = 164
  static let nodeHeaderHeight: CGFloat = 34
  static let portRowHeight: CGFloat = 26
  static let portDotRadius: CGFloat = 5

  init() {
    // Starter graph: Time → Sine → Vec4 → Output (animated grayscale pulse)
    let time  = NodeInstance(defName: "Time",     position: CGPoint(x: 60,  y: 80))
    let sine  = NodeInstance(defName: "Sine",     position: CGPoint(x: 280, y: 80))
    let uv    = NodeInstance(defName: "UV",       position: CGPoint(x: 60,  y: 240))
    let fract = NodeInstance(defName: "Fract",    position: CGPoint(x: 280, y: 240))
    let mul   = NodeInstance(defName: "Multiply", position: CGPoint(x: 500, y: 160))
    let vec4  = NodeInstance(defName: "Vec4",     position: CGPoint(x: 700, y: 100))
    let out   = NodeInstance(defName: "Output",   position: CGPoint(x: 930, y: 100))

    nodes = [time, sine, uv, fract, mul, vec4, out]

    connections = [
      NodeConnection(fromNode: time.id,  fromPort: 0, toNode: sine.id,  toPort: 0), // Time → Sine.x
      NodeConnection(fromNode: uv.id,    fromPort: 0, toNode: fract.id, toPort: 0), // UV → Fract.x (vec2 into float — handled gracefully)
      NodeConnection(fromNode: sine.id,  fromPort: 0, toNode: mul.id,   toPort: 0), // Sine → Mul.a
      NodeConnection(fromNode: sine.id,  fromPort: 0, toNode: mul.id,   toPort: 1), // Sine → Mul.b
      NodeConnection(fromNode: mul.id,   fromPort: 0, toNode: vec4.id,  toPort: 0), // Mul → Vec4.r
      NodeConnection(fromNode: mul.id,   fromPort: 0, toNode: vec4.id,  toPort: 1), // Mul → Vec4.g
      NodeConnection(fromNode: mul.id,   fromPort: 0, toNode: vec4.id,  toPort: 2), // Mul → Vec4.b
      NodeConnection(fromNode: vec4.id,  fromPort: 0, toNode: out.id,   toPort: 0), // Vec4 → Output
    ]

    generateCode()
  }

  // MARK: - Layout Helpers

  func nodeHeight(_ node: NodeInstance) -> CGFloat {
    let rows = max(node.def.inputs.count, node.def.outputs.count, 1)
    return Self.nodeHeaderHeight + CGFloat(rows) * Self.portRowHeight + 8
  }

  func inputPortPos(_ node: NodeInstance, portIndex: Int) -> CGPoint {
    CGPoint(
      x: node.position.x,
      y: node.position.y + Self.nodeHeaderHeight + CGFloat(portIndex) * Self.portRowHeight + Self.portRowHeight / 2
    )
  }

  func outputPortPos(_ node: NodeInstance, portIndex: Int) -> CGPoint {
    CGPoint(
      x: node.position.x + Self.nodeWidth,
      y: node.position.y + Self.nodeHeaderHeight + CGFloat(portIndex) * Self.portRowHeight + Self.portRowHeight / 2
    )
  }

  // MARK: - Hit Testing (canvas space, no pan applied)

  func hitTestPort(at point: CGPoint) -> PortAddress? {
    let r: CGFloat = 16
    for node in nodes.reversed() {
      for i in node.def.outputs.indices {
        let p = outputPortPos(node, portIndex: i)
        if hypot(point.x - p.x, point.y - p.y) < r {
          return PortAddress(nodeId: node.id, portIndex: i, isOutput: true)
        }
      }
      for i in node.def.inputs.indices {
        let p = inputPortPos(node, portIndex: i)
        if hypot(point.x - p.x, point.y - p.y) < r {
          return PortAddress(nodeId: node.id, portIndex: i, isOutput: false)
        }
      }
    }
    return nil
  }

  func hitTestNode(at point: CGPoint) -> UUID? {
    for node in nodes.reversed() {
      let rect = CGRect(x: node.position.x, y: node.position.y,
                        width: Self.nodeWidth, height: nodeHeight(node))
      if rect.contains(point) { return node.id }
    }
    return nil
  }

  // MARK: - Mutations

  func moveNode(id: UUID, to position: CGPoint) {
    guard let i = nodes.firstIndex(where: { $0.id == id }) else { return }
    nodes[i].position = position
  }

  func addConnection(_ conn: NodeConnection) {
    connections.removeAll { $0.toNode == conn.toNode && $0.toPort == conn.toPort }
    connections.append(conn)
    generateCode()
  }

  func deleteConnection(from portAddr: PortAddress) {
    if portAddr.isOutput {
      connections.removeAll { $0.fromNode == portAddr.nodeId && $0.fromPort == portAddr.portIndex }
    } else {
      connections.removeAll { $0.toNode == portAddr.nodeId && $0.toPort == portAddr.portIndex }
    }
    generateCode()
  }

  func addNode(defName: String, at position: CGPoint) {
    let node = NodeInstance(defName: defName, position: position)
    nodes.append(node)
  }

  func deleteSelected() {
    guard let id = selectedNodeId else { return }
    if nodes.first(where: { $0.id == id })?.defName == "Output" { return } // protect output
    connections.removeAll { $0.fromNode == id || $0.toNode == id }
    nodes.removeAll { $0.id == id }
    selectedNodeId = nil
    generateCode()
  }

  // MARK: - Code Generation

  func generateCode() {
    guard let outputNode = nodes.first(where: { $0.defName == "Output" }) else {
      generatedCode = "    return float4(0.5, 0.5, 0.5, 1.0);"
      return
    }

    var lines: [String] = []
    var nodeVars: [UUID: [String]] = [:]
    var counter = 0

    func fresh() -> String { let v = "v\(counter)"; counter += 1; return v }

    func emit(nodeId: UUID, port: Int) -> String {
      if let cached = nodeVars[nodeId], port < cached.count { return cached[port] }
      guard let node = nodes.first(where: { $0.id == nodeId }) else { return "0.0" }
      let def = node.def

      func inp(_ i: Int) -> String {
        if let c = connections.first(where: { $0.toNode == nodeId && $0.toPort == i }) {
          return emit(nodeId: c.fromNode, port: c.fromPort)
        }
        return def.inputs[safe: i]?.type.defaultMSL ?? "0.0"
      }

      var outs: [String] = []
      switch def.name {
      case "Time":
        let v = fresh(); lines.append("float \(v) = uniforms.time;"); outs = [v]
      case "UV":
        let v = fresh(); lines.append("float2 \(v) = in.uv;"); outs = [v]
      case "Resolution":
        let v = fresh(); lines.append("float2 \(v) = uniforms.resolution;"); outs = [v]
      case "Touch":
        let p = fresh(); let pr = fresh()
        lines.append("float2 \(p) = uniforms.touchPosition;")
        lines.append("float \(pr) = uniforms.touchPressure;")
        outs = [p, pr]
      case "Constant":
        let v = fresh()
        let val = node.constantValues.first ?? 0.5
        lines.append("float \(v) = \(String(format: "%.4f", val));")
        outs = [v]
      case "Vec2":
        let v = fresh(); lines.append("float2 \(v) = float2(\(inp(0)), \(inp(1)));"); outs = [v]
      case "Vec4":
        let v = fresh(); lines.append("float4 \(v) = float4(\(inp(0)), \(inp(1)), \(inp(2)), \(inp(3)));"); outs = [v]
      case "Add":
        let v = fresh(); lines.append("float \(v) = \(inp(0)) + \(inp(1));"); outs = [v]
      case "Multiply":
        let v = fresh(); lines.append("float \(v) = \(inp(0)) * \(inp(1));"); outs = [v]
      case "Sine":
        let v = fresh(); lines.append("float \(v) = sin(\(inp(0)));"); outs = [v]
      case "Clamp":
        let v = fresh(); lines.append("float \(v) = clamp(\(inp(0)), \(inp(1)), \(inp(2)));"); outs = [v]
      case "Mix":
        let v = fresh(); lines.append("float \(v) = mix(\(inp(0)), \(inp(1)), \(inp(2)));"); outs = [v]
      case "Abs":
        let v = fresh(); lines.append("float \(v) = abs(\(inp(0)));"); outs = [v]
      case "Fract":
        let v = fresh(); lines.append("float \(v) = fract(\(inp(0)));"); outs = [v]
      case "Step":
        let v = fresh(); lines.append("float \(v) = step(\(inp(0)), \(inp(1)));"); outs = [v]
      case "Smoothstep":
        let v = fresh(); lines.append("float \(v) = smoothstep(\(inp(0)), \(inp(1)), \(inp(2)));"); outs = [v]
      case "Pow":
        let v = fresh(); lines.append("float \(v) = pow(\(inp(0)), \(inp(1)));"); outs = [v]
      case "Rotate UV":
        let v = fresh(); let uv = inp(0); let a = inp(1)
        lines.append("float2 \(v) = float2(\(uv).x*cos(\(a))-\(uv).y*sin(\(a)), \(uv).x*sin(\(a))+\(uv).y*cos(\(a)));")
        outs = [v]
      case "Tile UV":
        let v = fresh(); lines.append("float2 \(v) = fract(\(inp(0)) * \(inp(1)));"); outs = [v]
      case "Remap UV":
        let v = fresh(); lines.append("float2 \(v) = \(inp(0)) * \(inp(1)) + \(inp(2));"); outs = [v]
      default:
        outs = def.outputs.map { _ in "0.0" }
      }
      nodeVars[nodeId] = outs
      return outs[safe: port] ?? "0.0"
    }

    // Evaluate the color input of the Output node
    let colorExpr: String
    let colorType: PortType
    if let c = connections.first(where: { $0.toNode == outputNode.id && $0.toPort == 0 }),
       let fromNode = nodes.first(where: { $0.id == c.fromNode }) {
      colorExpr = emit(nodeId: c.fromNode, port: c.fromPort)
      colorType = fromNode.def.outputs[safe: c.fromPort]?.type ?? .float
    } else {
      colorExpr = "float4(0.5, 0.5, 0.5, 1.0)"
      colorType = .vec4
    }

    // Wrap to float4 if needed
    let finalColor: String
    switch colorType {
    case .float: finalColor = "float4(\(colorExpr), \(colorExpr), \(colorExpr), 1.0)"
    case .vec2:  finalColor = "float4(\(colorExpr).x, \(colorExpr).y, 0.0, 1.0)"
    case .vec4:  finalColor = colorExpr
    }

    let indent = "    "
    generatedCode = lines.map { indent + $0 }.joined(separator: "\n")
    if !generatedCode.isEmpty { generatedCode += "\n" }
    generatedCode += indent + "return \(finalColor);"
  }
}

// MARK: - Safe Subscript

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
