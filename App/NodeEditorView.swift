#if !os(tvOS)
import SwiftUI

// MARK: - Node Editor Split View

struct NodeSplitView: View {
  @Bindable var graph: NodeGraph
  @State private var showAddMenu = false
  @State private var addMenuPosition: CGPoint = .zero

  var body: some View {
    HStack(spacing: 0) {
      // Left: node canvas
      ZStack(alignment: .bottomTrailing) {
        NodeCanvasView(graph: graph, showAddMenu: $showAddMenu, addMenuPosition: $addMenuPosition)

        // Add node button
        Button {
          addMenuPosition = CGPoint(x: 200, y: 200)
          showAddMenu = true
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
        }
        .appGlass(in: .circle)
        .padding(16)

        // Delete selected
        if graph.selectedNodeId != nil {
          Button {
            graph.deleteSelected()
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(.red)
              .frame(width: 36, height: 36)
          }
          .appGlass(in: .circle)
          .padding(.trailing, 64)
          .padding(.bottom, 16)
          .transition(.scale.combined(with: .opacity))
        }
      }
      .animation(.bouncy, value: graph.selectedNodeId != nil)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .sheet(isPresented: $showAddMenu) {
        NodeAddSheet(graph: graph, position: addMenuPosition)
          .presentationDetents([.medium])
      }

      Divider()
        .background(Color.primary.opacity(0.15))

      // Right: Metal preview + code
      NodePreviewPanel(graph: graph)
        .frame(width: 360)
    }
    .background(Color(white: 0.07))
    .preferredColorScheme(.dark)
  }
}

// MARK: - Canvas

struct NodeCanvasView: View {
  @Bindable var graph: NodeGraph
  @Binding var showAddMenu: Bool
  @Binding var addMenuPosition: CGPoint

  var body: some View {
    GeometryReader { geo in
      ZStack {
        // Background grid
        Canvas { ctx, size in
          let spacing: CGFloat = 28
          let dotR: CGFloat = 1
          var y: CGFloat = 0
          while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
              let dot = Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2))
              ctx.fill(dot, with: .color(.primary.opacity(0.1)))
              x += spacing
            }
            y += spacing
          }
        }
        .ignoresSafeArea()

        // Wires layer
        Canvas { ctx, _ in
          drawWires(ctx: ctx)
          drawActiveWire(ctx: ctx)
        }
        .allowsHitTesting(false)

        // Node cards
        ForEach(graph.nodes) { node in
          NodeCardView(graph: graph, node: node)
            .position(
              x: node.position.x + graph.panOffset.width + NodeGraph.nodeWidth / 2,
              y: node.position.y + graph.panOffset.height + graph.nodeHeight(node) / 2
            )
        }
      }
      .gesture(canvasGesture(geo: geo))
    }
    .background(Color(white: 0.09))
    .clipped()
  }

  // MARK: - Wire Drawing

  func drawWires(ctx: GraphicsContext) {
    for conn in graph.connections {
      guard let fromNode = graph.nodes.first(where: { $0.id == conn.fromNode }),
            let toNode   = graph.nodes.first(where: { $0.id == conn.toNode }) else { continue }
      let fromPos = graph.outputPortPos(fromNode, portIndex: conn.fromPort)
      let toPos   = graph.inputPortPos(toNode, portIndex: conn.toPort)
      let fp = CGPoint(x: fromPos.x + graph.panOffset.width, y: fromPos.y + graph.panOffset.height)
      let tp = CGPoint(x: toPos.x   + graph.panOffset.width, y: toPos.y   + graph.panOffset.height)
      let portType = fromNode.def.outputs[safe: conn.fromPort]?.type ?? .float
      drawBezier(ctx: ctx, from: fp, to: tp, color: portType.color.opacity(0.85))
    }
  }

  func drawActiveWire(ctx: GraphicsContext) {
    guard case .drawingWire(let from, let cur) = graph.dragState,
          let fromNode = graph.nodes.first(where: { $0.id == from.nodeId }) else { return }
    let portPos = from.isOutput
      ? graph.outputPortPos(fromNode, portIndex: from.portIndex)
      : graph.inputPortPos(fromNode,  portIndex: from.portIndex)
    let fp = CGPoint(x: portPos.x + graph.panOffset.width, y: portPos.y + graph.panOffset.height)
    let portType = from.isOutput
      ? fromNode.def.outputs[safe: from.portIndex]?.type ?? .float
      : fromNode.def.inputs[safe:  from.portIndex]?.type ?? .float
    drawBezier(ctx: ctx, from: fp, to: cur, color: portType.color.opacity(0.6))
  }

  func drawBezier(ctx: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
    let cx = (from.x + to.x) / 2
    var path = Path()
    path.move(to: from)
    path.addCurve(to: to,
                  control1: CGPoint(x: cx, y: from.y),
                  control2: CGPoint(x: cx, y: to.y))
    ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
  }

  // MARK: - Gesture State Machine

  func canvasGesture(geo: GeometryProxy) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { v in
        let canvasStart = CGPoint(
          x: v.startLocation.x - graph.panOffset.width,
          y: v.startLocation.y - graph.panOffset.height
        )
        switch graph.dragState {
        case .idle:
          if let port = graph.hitTestPort(at: canvasStart), port.isOutput {
            graph.dragState = .drawingWire(from: port, currentPoint: v.location)
          } else if let nodeId = graph.hitTestNode(at: canvasStart) {
            let node = graph.nodes.first { $0.id == nodeId }!
            graph.dragState = .movingNode(id: nodeId, nodeStart: node.position, dragStart: v.startLocation)
            graph.selectedNodeId = nodeId
          } else {
            graph.dragState = .panning(offsetStart: graph.panOffset, dragStart: v.startLocation)
            graph.selectedNodeId = nil
          }

        case .drawingWire(let from, _):
          graph.dragState = .drawingWire(from: from, currentPoint: v.location)

        case .movingNode(let id, let nodeStart, let dragStart):
          graph.moveNode(id: id, to: CGPoint(
            x: nodeStart.x + v.location.x - dragStart.x,
            y: nodeStart.y + v.location.y - dragStart.y
          ))

        case .panning(let offsetStart, let dragStart):
          graph.panOffset = CGSize(
            width:  offsetStart.width  + v.location.x - dragStart.x,
            height: offsetStart.height + v.location.y - dragStart.y
          )
        }
      }
      .onEnded { v in
        if case .drawingWire(let from, _) = graph.dragState {
          let canvasEnd = CGPoint(
            x: v.location.x - graph.panOffset.width,
            y: v.location.y - graph.panOffset.height
          )
          if let target = graph.hitTestPort(at: canvasEnd),
             !target.isOutput,
             target.nodeId != from.nodeId {
            let fromNode = graph.nodes.first { $0.id == from.nodeId }
            let toNode   = graph.nodes.first { $0.id == target.nodeId }
            let fromType = fromNode?.def.outputs[safe: from.portIndex]?.type
            let toType   = toNode?.def.inputs[safe: target.portIndex]?.type
            if fromType == toType {
              graph.addConnection(NodeConnection(
                fromNode: from.nodeId, fromPort: from.portIndex,
                toNode: target.nodeId, toPort: target.portIndex
              ))
            }
          }
        }
        graph.dragState = .idle
      }
  }
}

// MARK: - Node Card

struct NodeCardView: View {
  @Bindable var graph: NodeGraph
  var node: NodeInstance

  var isSelected: Bool { graph.selectedNodeId == node.id }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text(node.def.name)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
      }
      .frame(height: NodeGraph.nodeHeaderHeight)
      .frame(maxWidth: .infinity)
      .background(node.def.category.color.opacity(0.85))

      // Port rows
      let rows = max(node.def.inputs.count, node.def.outputs.count, 1)
      ForEach(0..<rows, id: \.self) { i in
        HStack(spacing: 0) {
          // Input port
          if let port = node.def.inputs[safe: i] {
            portDot(type: port.type, isOutput: false)
            Text(port.name)
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
              .padding(.leading, 6)
          }
          Spacer(minLength: 4)
          // Output port
          if let port = node.def.outputs[safe: i] {
            Text(port.name)
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
              .padding(.trailing, 6)
            portDot(type: port.type, isOutput: true)
          }
        }
        .frame(height: NodeGraph.portRowHeight)
      }

      // Constant value slider (for Constant nodes)
      if node.defName == "Constant", let idx = graph.nodes.firstIndex(where: { $0.id == node.id }) {
        Divider().background(Color.primary.opacity(0.1))
        HStack {
          Text(String(format: "%.2f", graph.nodes[idx].constantValues.first ?? 0))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
          Slider(value: Binding(
            get: { Double(graph.nodes[idx].constantValues.first ?? 0) },
            set: { graph.nodes[idx].constantValues = [Float($0)]; graph.generateCode() }
          ), in: 0...1)
          .scaleEffect(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
      }

      Spacer(minLength: 0)
    }
    .frame(width: NodeGraph.nodeWidth, height: graph.nodeHeight(node))
    .background(Color(white: isSelected ? 0.22 : 0.17))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(
          isSelected ? Color.white.opacity(0.7) : node.def.category.color.opacity(0.4),
          lineWidth: isSelected ? 1.5 : 1
        )
    )
    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    .onTapGesture { graph.selectedNodeId = node.id }
  }

  func portDot(type: PortType, isOutput: Bool) -> some View {
    Circle()
      .fill(type.color)
      .frame(width: NodeGraph.portDotRadius * 2, height: NodeGraph.portDotRadius * 2)
      .offset(x: isOutput ? NodeGraph.portDotRadius : -NodeGraph.portDotRadius)
  }
}

// MARK: - Add Node Sheet

struct NodeAddSheet: View {
  @Bindable var graph: NodeGraph
  var position: CGPoint
  @Environment(\.dismiss) var dismiss
  @State private var search = ""

  var filtered: [NodeDef] {
    let all = NodeDefs.all.filter { $0.name != "Output" }
    guard !search.isEmpty else { return all }
    return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
  }

  var body: some View {
    NavigationStack {
      List(filtered, id: \.name) { def in
        Button {
          let canvasPos = CGPoint(
            x: position.x - graph.panOffset.width,
            y: position.y - graph.panOffset.height
          )
          graph.addNode(defName: def.name, at: canvasPos)
          graph.generateCode()
          dismiss()
        } label: {
          HStack {
            Circle()
              .fill(def.category.color)
              .frame(width: 8, height: 8)
            Text(def.name)
            Spacer()
            Text(def.category == .input ? "Input" :
                 def.category == .math  ? "Math"  :
                 def.category == .uv    ? "UV"    : "Output")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
      }
      .searchable(text: $search, prompt: "Search nodes…")
      .navigationTitle("Add Node")
      .navigationBarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.dark)
  }
}
#endif
