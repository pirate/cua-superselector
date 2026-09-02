import AppKit
import Foundation

private let inspectorPink = NSColor(calibratedRed: 1, green: 0.12, blue: 0.58, alpha: 0.96)

private struct InspectorPresentation {
  let selector: String
  let hints: [Hint]
  let providerReports: [ProviderReport]
  let breadcrumbs: String
  let renderTree: UIElementRenderTree
  let screenshot: BreadcrumbScreenshot?

  func value(_ kind: String) -> String? {
    hints.first { $0.kind == kind }?.value
  }

  func values(_ kind: String) -> [String] {
    hints.filter { $0.kind == kind }.map(\.value)
  }

  var applicationPath: String? { value("application.bundle-path") }
  var executablePath: String? { value("application.executable-path") }
  var hasApplication: Bool {
    value("application.name") != nil || value("application.bundle-id") != nil
      || applicationPath != nil
  }
  var hasGeometry: Bool { hints.contains { $0.band == "geometry" } }
  var hasIdentity: Bool {
    hints.contains { ["semantic", "native.mac.ax", "structure"].contains($0.band) }
  }
  var meaningfulStates: [Hint] {
    hints.filter { hint in
      guard hint.kind.hasPrefix("state.") else { return false }
      let isTrue = hint.value.lowercased() == "true"
      return hint.kind == "state.enabled" ? !isTrue : isTrue
    }
  }
  var hasStateOrActions: Bool {
    !meaningfulStates.isEmpty || hints.contains { $0.kind == "capability.action" }
  }
}

/// Scrollable, visual summary of the selector evidence. The overlay itself remains
/// mouse-transparent, so controls are deliberately rendered as state indicators.
final class VisualInspectorView: NSView {
  private let scrollView = NSScrollView()
  private let canvas = InspectorCanvasView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 14
    layer?.backgroundColor = NSColor(calibratedWhite: 0.045, alpha: 0.96).cgColor
    layer?.borderWidth = 1.5
    layer?.borderColor = inspectorPink.cgColor

    scrollView.frame = bounds
    scrollView.autoresizingMask = [.width, .height]
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = canvas
    addSubview(scrollView)
  }

  required init?(coder: NSCoder) { nil }

  func update(
    with observation: SuperSelectorObservation,
    breadcrumbs: String,
    screenshot: BreadcrumbScreenshot? = nil
  ) {
    update(
      selector: observation.compactSelector,
      hints: observation.hints,
      providerReports: observation.providerReports,
      breadcrumbs: breadcrumbs,
      renderTree: observation.renderTree,
      screenshot: screenshot
    )
  }

  func update(
    selector: String,
    hints: [Hint],
    providerReports: [ProviderReport],
    breadcrumbs: String,
    renderTree: UIElementRenderTree = .empty,
    screenshot: BreadcrumbScreenshot? = nil
  ) {
    canvas.presentation = InspectorPresentation(
      selector: selector,
      hints: hints,
      providerReports: providerReports,
      breadcrumbs: breadcrumbs,
      renderTree: renderTree,
      screenshot: screenshot
    )
    canvas.resize(to: scrollView.contentSize.width)
    scrollView.contentView.scroll(to: .zero)
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }

  override func layout() {
    super.layout()
    canvas.resize(to: scrollView.contentSize.width)
  }
}

private final class InspectorCanvasView: NSView {
  private struct IdentityNode {
    let depth: Int
    let role: String
    let detail: String?
    let isTarget: Bool
  }

  var presentation: InspectorPresentation? {
    didSet {
      resize(to: frame.width)
      needsDisplay = true
    }
  }

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { false }

  func resize(to width: CGFloat) {
    guard width > 0 else { return }
    let height = contentHeight(for: presentation)
    if frame.width != width || frame.height != height {
      frame = CGRect(x: 0, y: 0, width: width, height: height)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let model = presentation else { return }

    var y: CGFloat = 12
    drawHeader(model, y: &y)
    drawProviders(model.providerReports, y: &y)

    if model.screenshot != nil || !model.renderTree.nodes.isEmpty {
      drawAgentState(model, in: sectionRect(y: y, height: 310))
      y += 320
    }

    let content = CGRect(x: 12, y: y, width: bounds.width - 24, height: 1)
    let gap: CGFloat = 10
    let identityCardHeight: CGFloat = 190
    if model.hasApplication || model.hasIdentity {
      if model.hasApplication && model.hasIdentity {
        let availableWidth = content.width - gap
        let applicationWidth = floor(availableWidth * 0.3)
        let identityWidth = availableWidth - applicationWidth
        drawApplication(
          model,
          in: CGRect(x: content.minX, y: y, width: applicationWidth, height: identityCardHeight))
        drawIdentity(
          model,
          in: CGRect(
            x: content.minX + applicationWidth + gap, y: y, width: identityWidth,
            height: identityCardHeight))
      } else if model.hasApplication {
        drawApplication(
          model, in: CGRect(x: content.minX, y: y, width: content.width, height: identityCardHeight)
        )
      } else {
        drawIdentity(
          model, in: CGRect(x: content.minX, y: y, width: content.width, height: identityCardHeight)
        )
      }
      y += identityCardHeight + 10
    }

    let hasRemaining = !remainingHints(model).isEmpty
    let hasSidebar = model.hasStateOrActions || hasRemaining
    if model.hasGeometry && hasSidebar {
      let geometryWidth = floor((content.width - gap) * 0.67)
      let sideX = content.minX + geometryWidth + gap
      let sideWidth = content.width - geometryWidth - gap
      drawGeometry(
        model, in: CGRect(x: content.minX, y: y, width: geometryWidth, height: 254))
      var sideY = y
      if model.hasStateOrActions {
        drawStateAndActions(
          model, in: CGRect(x: sideX, y: sideY, width: sideWidth, height: 112))
        sideY += 122
      }
      if hasRemaining {
        drawRemainingEvidence(
          model, in: CGRect(x: sideX, y: sideY, width: sideWidth, height: y + 254 - sideY))
      }
      y += 264
    } else {
      if model.hasGeometry {
        drawGeometry(model, in: CGRect(x: content.minX, y: y, width: content.width, height: 254))
        y += 264
      }
      if model.hasStateOrActions {
        drawStateAndActions(
          model, in: CGRect(x: content.minX, y: y, width: content.width, height: 104))
        y += 114
      }
      if hasRemaining {
        drawRemainingEvidence(
          model, in: CGRect(x: content.minX, y: y, width: content.width, height: 112))
      }
    }
  }

  private func contentHeight(for model: InspectorPresentation?) -> CGFloat {
    guard let model else { return 1 }
    var height: CGFloat = 12 + 54 + 30
    if model.screenshot != nil || !model.renderTree.nodes.isEmpty { height += 320 }
    if model.hasApplication || model.hasIdentity { height += 200 }
    let hasRemaining = !remainingHints(model).isEmpty
    if model.hasGeometry && (model.hasStateOrActions || hasRemaining) {
      height += 264
    } else {
      if model.hasGeometry { height += 264 }
      if model.hasStateOrActions { height += 114 }
      if hasRemaining { height += 122 }
    }
    return height + 12
  }

  private func drawHeader(_ model: InspectorPresentation, y: inout CGFloat) {
    drawText(
      "SUPERSELECTOR", in: CGRect(x: 18, y: y, width: 126, height: 20),
      font: .monospacedSystemFont(ofSize: 15, weight: .bold), color: inspectorPink)
    let selector =
      model.selector.count > 180 ? String(model.selector.prefix(179)) + "…" : model.selector
    drawText(
      selector, in: CGRect(x: 148, y: y + 1, width: bounds.width - 166, height: 18),
      font: .monospacedSystemFont(ofSize: 9, weight: .medium), color: .white,
      lineBreak: .byTruncatingMiddle)
    y += 25
    drawSymbol(
      "point.topleft.down.to.point.bottomright.curvepath", at: CGPoint(x: 19, y: y + 1),
      color: .systemMint)
    drawText(
      model.breadcrumbs, in: CGRect(x: 40, y: y, width: bounds.width - 142, height: 19),
      font: .monospacedSystemFont(ofSize: 11.5, weight: .medium), color: .systemMint,
      lineBreak: .byTruncatingMiddle)
    drawText(
      "ESC ESC TO RESET", in: CGRect(x: bounds.width - 118, y: y, width: 100, height: 18),
      font: .monospacedSystemFont(ofSize: 9, weight: .semibold), color: muted,
      alignment: .right)
    y += 29
  }

  private func drawProviders(_ reports: [ProviderReport], y: inout CGFloat) {
    drawText(
      "PROVIDERS", in: CGRect(x: 18, y: y + 3, width: 72, height: 16),
      font: .monospacedSystemFont(ofSize: 10, weight: .bold), color: muted)
    var x: CGFloat = 92
    for report in reports {
      let color = providerColor(report.provider).withAlphaComponent(
        report.state == .unavailable ? 0.5 : 1)
      let label = "\(report.provider)  \(statusGlyph(report.state))"
      let width = min(190, textWidth(label, font: .systemFont(ofSize: 11, weight: .semibold)) + 35)
      drawCapsule(
        CGRect(x: x, y: y, width: width, height: 24), color: color.withAlphaComponent(0.12),
        stroke: color.withAlphaComponent(0.42))
      drawSymbol(
        providerSymbol(report.provider), at: CGPoint(x: x + 8, y: y + 5), color: color, size: 12)
      drawText(
        label, in: CGRect(x: x + 25, y: y + 4, width: width - 31, height: 16),
        font: .systemFont(ofSize: 11, weight: .semibold), color: color)
      x += width + 7
      if x > bounds.width - 120 { break }
    }
    y += 30
  }

  private func drawAgentState(_ model: InspectorPresentation, in rect: CGRect) {
    drawSectionBackground(rect)
    let gap: CGFloat = 12
    let content = rect.insetBy(dx: 14, dy: 12)
    let screenshotWidth = floor((content.width - gap) * 0.53)
    let screenshotPanel = CGRect(
      x: content.minX,
      y: content.minY + 24,
      width: screenshotWidth,
      height: content.height - 24
    )
    let treePanel = CGRect(
      x: screenshotPanel.maxX + gap,
      y: content.minY + 24,
      width: content.maxX - screenshotPanel.maxX - gap,
      height: content.height - 24
    )
    drawText(
      "SKYSHOT SCREENSHOT + BOX MODEL",
      in: CGRect(x: screenshotPanel.minX, y: content.minY, width: screenshotPanel.width, height: 16),
      font: .monospacedSystemFont(ofSize: 9.5, weight: .bold),
      color: muted
    )
    drawText(
      "APPSTATE.TEXT · AGENT TREE",
      in: CGRect(x: treePanel.minX, y: content.minY, width: treePanel.width, height: 16),
      font: .monospacedSystemFont(ofSize: 9.5, weight: .bold),
      color: muted
    )

    drawRoundedRect(
      screenshotPanel,
      radius: 7,
      fill: NSColor.black.withAlphaComponent(0.32),
      stroke: NSColor.white.withAlphaComponent(0.1)
    )
    if let screenshot = model.screenshot,
      let image = NSImage(data: screenshot.jpegData),
      image.size.width > 0, image.size.height > 0
    {
      let scale = min(
        screenshotPanel.width / image.size.width,
        screenshotPanel.height / image.size.height
      )
      let imageRect = CGRect(
        x: screenshotPanel.midX - image.size.width * scale / 2,
        y: screenshotPanel.midY - image.size.height * scale / 2,
        width: image.size.width * scale,
        height: image.size.height * scale
      )
      image.draw(
        in: imageRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.medium]
      )
      if let source = SuperSelectorBoxModel(hints: model.hints) {
        let targetFrame = model.renderTree.nodes.first(where: \.isTarget)?.frameQuartz
          ?? source.targetQuartz
        let boxModel = SuperSelectorBoxModel(
          screenQuartz: screenshot.screenFrameQuartz,
          windowQuartz: source.windowQuartz,
          targetQuartz: targetFrame,
          pointerQuartz: source.pointerQuartz
        )
        let projection = boxModel.projection(in: imageRect, origin: .topLeft)
        if let target = projection.target {
          drawRoundedRect(
            target.insetBy(dx: -1.5, dy: -1.5),
            radius: 4,
            fill: inspectorPink.withAlphaComponent(0.08),
            stroke: inspectorPink,
            lineWidth: 2
          )
          if let elementIndex = model.renderTree.targetElementIndex {
            let label = "[\(elementIndex)]"
            let width = textWidth(
              label,
              font: .monospacedSystemFont(ofSize: 9, weight: .bold)
            ) + 10
            let labelRect = CGRect(
              x: min(imageRect.maxX - width, max(imageRect.minX, target.minX)),
              y: max(imageRect.minY, target.minY - 19),
              width: width,
              height: 17
            )
            drawRoundedRect(
              labelRect,
              radius: 4,
              fill: inspectorPink,
              stroke: nil
            )
            drawText(
              label,
              in: labelRect.insetBy(dx: 5, dy: 2),
              font: .monospacedSystemFont(ofSize: 9, weight: .bold),
              color: .white
            )
          }
        }
      }
    } else {
      drawText(
        "Waiting for a clean screenshot…",
        in: screenshotPanel.insetBy(dx: 12, dy: 12),
        font: .systemFont(ofSize: 11, weight: .medium),
        color: muted,
        alignment: .center,
        lineBreak: .byTruncatingTail
      )
    }

    drawRoundedRect(
      treePanel,
      radius: 7,
      fill: NSColor.black.withAlphaComponent(0.24),
      stroke: NSColor.white.withAlphaComponent(0.1)
    )
    let rendered = ComputerUseNodeAPIRenderer.render(model.renderTree)
    let allLines = rendered.components(separatedBy: "\n")
    let maximumLines = max(1, Int((treePanel.height - 18) / 14))
    let visibleLines = agentTreeExcerpt(
      allLines,
      targetElementIndex: model.renderTree.targetElementIndex,
      maximumLines: maximumLines
    )
    for (row, line) in visibleLines.enumerated() {
      let targetPrefix = model.renderTree.targetElementIndex.map { "\($0) " }
      let isTarget = targetPrefix.map { line.trimmingCharacters(in: .whitespaces).hasPrefix($0) }
        ?? false
      drawText(
        line,
        in: CGRect(
          x: treePanel.minX + 9,
          y: treePanel.minY + 8 + CGFloat(row) * 14,
          width: treePanel.width - 18,
          height: 13
        ),
        font: .monospacedSystemFont(ofSize: 9.2, weight: isTarget ? .bold : .regular),
        color: isTarget ? inspectorPink : .white,
        lineBreak: .byTruncatingTail
      )
    }
  }

  private func agentTreeExcerpt(
    _ lines: [String],
    targetElementIndex: Int?,
    maximumLines: Int
  ) -> [String] {
    guard lines.count > maximumLines, maximumLines >= 4 else {
      return Array(lines.prefix(maximumLines))
    }
    guard let targetElementIndex,
      let targetLine = lines.firstIndex(where: {
        $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(targetElementIndex) ")
      })
    else { return Array(lines.prefix(maximumLines - 1)) + ["… \(lines.count - maximumLines + 1) more lines"] }
    let bodyCount = maximumLines - 2
    let lowerBound = max(1, min(targetLine - bodyCount / 2, lines.count - bodyCount))
    let upperBound = min(lines.count, lowerBound + bodyCount)
    return [lines[0], lowerBound > 1 ? "…" : lines[1]]
      + Array(lines[lowerBound..<upperBound])
  }

  private func drawApplication(_ model: InspectorPresentation, in rect: CGRect) {
    drawSectionBackground(rect)

    let iconRect = CGRect(x: rect.minX + 16, y: rect.minY + 14, width: 46, height: 46)
    appIcon(for: model)?.draw(in: iconRect)
    let name = model.value("application.name") ?? "Unknown application"
    drawText(
      name,
      in: CGRect(x: iconRect.maxX + 11, y: rect.minY + 13, width: rect.width - 89, height: 21),
      font: .systemFont(ofSize: 15, weight: .semibold), color: .white, lineBreak: .byTruncatingTail)
    drawText(
      model.value("application.bundle-id") ?? "No bundle identifier",
      in: CGRect(x: iconRect.maxX + 11, y: rect.minY + 36, width: rect.width - 89, height: 17),
      font: .monospacedSystemFont(ofSize: 10, weight: .regular), color: .systemCyan,
      lineBreak: .byTruncatingMiddle)
    if let window = model.value("window.title") {
      drawSymbol(
        "macwindow", at: CGPoint(x: iconRect.maxX + 11, y: rect.minY + 56), color: muted, size: 10)
      drawText(
        window,
        in: CGRect(x: iconRect.maxX + 27, y: rect.minY + 55, width: rect.width - 105, height: 16),
        font: .systemFont(ofSize: 10, weight: .medium), color: muted, lineBreak: .byTruncatingTail)
    }

    let pathY = rect.minY + 82
    drawPathChain(
      model.executablePath ?? model.applicationPath ?? "No filesystem path", y: pathY, rect: rect)
  }

  private func drawGeometry(_ model: InspectorPresentation, in rect: CGRect) {
    drawSection(rect, title: "COORDINATE MAP", symbol: "scope")
    let diagram = CGRect(
      x: rect.minX + 16, y: rect.minY + 42, width: rect.width * 0.62, height: rect.height - 58)
    drawGeometryDiagram(model, in: diagram)

    let infoX = diagram.maxX + 18
    let infoWidth = rect.maxX - infoX - 14
    var infoY = rect.minY + 48
    let fields = [
      ("SCREEN POINT", model.value("pointer.position.screen")),
      ("WINDOW POINT", model.value("pointer.position.window")),
      ("DISPLAY %", model.value("pointer.position.display.normalized").map(percentPair)),
      ("ELEMENT FRAME", model.value("element.frame.window") ?? model.value("element.frame.screen")),
      ("ELEMENT SIZE", model.value("element.size.normalized").map(percentPair)),
    ]
    for (label, value) in fields where value != nil {
      drawText(
        label, in: CGRect(x: infoX, y: infoY, width: infoWidth, height: 14),
        font: .monospacedSystemFont(ofSize: 9, weight: .bold), color: muted)
      drawText(
        value!, in: CGRect(x: infoX, y: infoY + 15, width: infoWidth, height: 22),
        font: .monospacedSystemFont(ofSize: 11, weight: .semibold), color: .white,
        lineBreak: .byTruncatingMiddle)
      infoY += 41
    }
  }

  private func drawIdentity(_ model: InspectorPresentation, in rect: CGRect) {
    drawSectionBackground(rect)
    let nodes = identityNodes(model)
    let maximumRows = 12
    let shown = Array(nodes.suffix(maximumRows))
    let hiddenCount = nodes.count - shown.count
    if hiddenCount > 0 {
      drawText(
        "↑ \(hiddenCount) outer level\(hiddenCount == 1 ? "" : "s") hidden",
        in: CGRect(x: rect.minX + 14, y: rect.minY + 5, width: rect.width - 28, height: 11),
        font: .monospacedSystemFont(ofSize: 8, weight: .medium), color: muted,
        alignment: .right)
    }
    let baseDepth = shown.first?.depth ?? 0
    let firstRowY = rect.minY + (hiddenCount > 0 ? 18 : 9)
    for (index, node) in shown.enumerated() {
      let rowY = firstRowY + CGFloat(index) * 14
      let indent = CGFloat(min(max(0, node.depth - baseDepth), 11)) * 8
      let bulletX = rect.minX + 14 + indent
      if node.isTarget {
        drawRoundedRect(
          CGRect(x: bulletX - 5, y: rowY - 1, width: rect.maxX - bulletX - 6, height: 14),
          radius: 5,
          fill: inspectorPink.withAlphaComponent(0.12),
          stroke: inspectorPink.withAlphaComponent(0.38)
        )
      }
      let bullet = NSBezierPath(ovalIn: CGRect(x: bulletX, y: rowY + 4, width: 5, height: 5))
      (node.isTarget ? inspectorPink : NSColor.systemCyan).setFill()
      bullet.fill()
      let roleX = bulletX + 9
      let role = node.role.uppercased()
      let roleWidth = min(
        120,
        textWidth(role, font: .monospacedSystemFont(ofSize: 8.5, weight: .bold)) + 3
      )
      drawText(
        role,
        in: CGRect(x: roleX, y: rowY, width: roleWidth, height: 12),
        font: .monospacedSystemFont(ofSize: 8.5, weight: .bold),
        color: node.isTarget ? inspectorPink : .systemCyan,
        lineBreak: .byTruncatingTail
      )
      if let detail = node.detail {
        drawText(
          "— \(detail)",
          in: CGRect(
            x: roleX + roleWidth + 4,
            y: rowY,
            width: rect.maxX - roleX - roleWidth - 16,
            height: 12
          ),
          font: .systemFont(ofSize: 9, weight: node.isTarget ? .semibold : .regular),
          color: node.isTarget ? .white : muted,
          lineBreak: .byTruncatingTail
        )
      }
    }
  }

  private func identityNodes(_ model: InspectorPresentation) -> [IdentityNode] {
    var nodes = model.hints.filter { $0.kind == "ancestor.node" }
      .sorted {
        Int($0.metadata["depth"] ?? "0") ?? 0 < Int($1.metadata["depth"] ?? "0") ?? 0
      }
      .map { hint in
        let roleDetail = distinctRoleDetail(for: hint.value, metadata: hint.metadata)
        let semanticDetail = semanticAncestorDetail(hint.metadata)
        let detail = firstNonEmpty(
          hint.metadata["label"], hint.metadata["title"], hint.metadata["help"],
          hint.metadata["identifier"].map { "#\($0)" }, semanticDetail, roleDetail,
          hint.metadata["value"])
        return IdentityNode(
          depth: Int(hint.metadata["depth"] ?? "0") ?? 0,
          role: hint.value,
          detail: detail,
          isTarget: false
        )
      }
    let role = model.value("semantic.role") ?? model.value("native.role") ?? "element"
    let detail = firstNonEmpty(
      model.value("semantic.name"), model.value("semantic.description"),
      model.value("semantic.help"), model.value("native.subrole"),
      model.value("native.identifier").map { "#\($0)" }, model.value("semantic.value"))
    nodes.append(IdentityNode(depth: nodes.count, role: role, detail: detail, isTarget: true))
    return nodes.compactMap { node in
      guard node.detail != nil || node.isTarget else { return nil }
      return IdentityNode(
        depth: node.depth, role: node.role, detail: node.detail.map(clippedIdentityDetail),
        isTarget: node.isTarget)
    }
  }

  private func clippedIdentityDetail(_ detail: String) -> String {
    detail.count > 90 ? String(detail.prefix(89)) + "…" : detail
  }

  private func distinctRoleDetail(for role: String, metadata: [String: String]) -> String? {
    let normalizedRole = role.lowercased().replacingOccurrences(of: "ax", with: "")
      .replacingOccurrences(of: " ", with: "")
    for key in ["subrole", "role-description"] {
      guard let value = firstNonEmpty(metadata[key]) else { continue }
      let normalizedValue = value.lowercased().replacingOccurrences(of: "ax", with: "")
        .replacingOccurrences(of: " ", with: "")
      if normalizedValue != normalizedRole,
        !["group", "unknown", "uielement", "element"].contains(normalizedValue)
      {
        return value
      }
    }
    return nil
  }

  private func semanticAncestorDetail(_ metadata: [String: String]) -> String? {
    let attributes = metadata.filter { $0.key.hasPrefix("semantic.") }
    guard !attributes.isEmpty else { return nil }

    func value(containing fragments: String...) -> String? {
      attributes.first { key, _ in
        let lowered = key.lowercased()
        return fragments.allSatisfy(lowered.contains)
      }?.value
    }

    var components: [String] = []
    if let identifier = value(containing: "dom", "identifier") {
      components.append("#\(identifier)")
    }
    if let ariaLabel = value(containing: "aria", "label") {
      components.append(ariaLabel)
    }
    if let classes = value(containing: "dom", "class") {
      let classLabel = classes.split(whereSeparator: { $0.isWhitespace }).prefix(4)
        .map { ".\($0)" }.joined()
      if !classLabel.isEmpty { components.append(classLabel) }
    }
    if let placeholder = value(containing: "placeholder") {
      components.append("placeholder: \(placeholder)")
    }
    if components.isEmpty {
      let fallback = attributes.sorted {
        semanticAttributePriority($0.key) < semanticAttributePriority($1.key)
      }
      .first
      if let fallback { components.append(fallback.value) }
    }
    let distinct = components.reduce(into: [String]()) { result, component in
      if !result.contains(component) { result.append(component) }
    }
    return distinct.isEmpty ? nil : distinct.prefix(2).joined(separator: " · ")
  }

  private func semanticAttributePriority(_ key: String) -> Int {
    let lowered = key.lowercased()
    if lowered.contains("title") { return 0 }
    if lowered.contains("description") { return 1 }
    if lowered.contains("help") { return 2 }
    if lowered.contains("url") { return 3 }
    if lowered.contains("document") { return 4 }
    return 5
  }

  private func firstNonEmpty(_ values: String?...) -> String? {
    values.compactMap { value in
      guard let value else { return nil }
      let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return cleaned.isEmpty ? nil : cleaned
    }.first
  }

  private func drawStateAndActions(_ model: InspectorPresentation, in rect: CGRect) {
    let stateHints = model.meaningfulStates
    drawSection(
      rect, title: stateHints.isEmpty ? "CAPABILITIES" : "STATE & CAPABILITIES",
      symbol: stateHints.isEmpty ? "bolt" : "switch.2")
    var x = rect.minX + 16
    for hint in stateHints {
      let isDisabled = hint.kind == "state.enabled"
      let label =
        isDisabled
        ? "Disabled" : hint.kind.replacingOccurrences(of: "state.", with: "").capitalized
      drawToggle(
        label: label, isOn: true, color: isDisabled ? .systemOrange : .systemGreen,
        x: &x, y: rect.minY + 43)
    }
    x = rect.minX + 16
    let actionY = stateHints.isEmpty ? rect.minY + 47 : rect.minY + 76
    for action in model.values("capability.action") {
      let width = textWidth(action, font: .systemFont(ofSize: 10.5, weight: .semibold)) + 27
      drawCapsule(
        CGRect(x: x, y: actionY, width: width, height: 22),
        color: NSColor.systemGreen.withAlphaComponent(0.13),
        stroke: NSColor.systemGreen.withAlphaComponent(0.38))
      drawSymbol(
        "bolt.fill", at: CGPoint(x: x + 7, y: actionY + 5), color: .systemGreen, size: 9)
      drawText(
        action, in: CGRect(x: x + 20, y: actionY + 3, width: width - 25, height: 14),
        font: .systemFont(ofSize: 10.5, weight: .semibold), color: .systemGreen)
      x += width + 6
      if x > rect.maxX - 80 { break }
    }
  }

  private func drawRemainingEvidence(_ model: InspectorPresentation, in rect: CGRect) {
    let hints = remainingHints(model)
    guard !hints.isEmpty else { return }
    drawSection(rect, title: "OTHER EVIDENCE", symbol: "ellipsis.curlybraces")
    var x = rect.minX + 16
    var rowY = rect.minY + 42
    for hint in hints.prefix(12) {
      let label = "\(shortKind(hint.kind)): \(hint.value)"
      let width = min(
        rect.width - 32,
        textWidth(label, font: .monospacedSystemFont(ofSize: 9.5, weight: .medium)) + 18)
      if x + width > rect.maxX - 16 {
        x = rect.minX + 16
        rowY += 29
      }
      if rowY > rect.maxY - 26 { break }
      let color = bandColor(hint.band)
      drawCapsule(
        CGRect(x: x, y: rowY, width: width, height: 22), color: color.withAlphaComponent(0.09),
        stroke: color.withAlphaComponent(0.28))
      drawText(
        label, in: CGRect(x: x + 9, y: rowY + 4, width: width - 18, height: 14),
        font: .monospacedSystemFont(ofSize: 9.5, weight: .medium), color: color,
        lineBreak: .byTruncatingMiddle)
      x += width + 6
    }
  }

  private func drawGeometryDiagram(_ model: InspectorPresentation, in rect: CGRect) {
    let viewport = rect.insetBy(dx: 2, dy: 3)
    // Window, element, and pointer are all display-relative evidence. Drawing them on one
    // canvas preserves containment; nesting independently inset canvases visually shifts them.
    let coordinateCanvas = viewport.insetBy(dx: 18, dy: 21)
    drawRoundedRect(
      viewport, radius: 9, fill: NSColor.systemPink.withAlphaComponent(0.045),
      stroke: inspectorPink.withAlphaComponent(0.5), lineWidth: 1.5)
    drawText(
      "DISPLAY", in: CGRect(x: viewport.minX + 9, y: viewport.minY + 7, width: 70, height: 14),
      font: .monospacedSystemFont(ofSize: 9, weight: .bold), color: inspectorPink)

    let projection = SuperSelectorBoxModel(hints: model.hints)?
      .projection(in: coordinateCanvas, origin: .topLeft)
    if model.hasApplication, let windowRect = projection?.window {
      drawRoundedRect(
        windowRect, radius: 7, fill: NSColor.systemBlue.withAlphaComponent(0.06),
        stroke: NSColor.systemBlue.withAlphaComponent(0.58), lineWidth: 1.5)
      drawText(
        "WINDOW",
        in: CGRect(x: windowRect.minX + 8, y: windowRect.minY + 6, width: 64, height: 13),
        font: .monospacedSystemFont(ofSize: 8.5, weight: .bold), color: .systemBlue)
    }

    if model.hasApplication, let elementRect = projection?.target {
      drawRoundedRect(
        elementRect, radius: 5, fill: NSColor.systemCyan.withAlphaComponent(0.12),
        stroke: NSColor.systemCyan, lineWidth: 2)
      drawText(
        "ELEMENT",
        in: CGRect(
          x: elementRect.minX + 5, y: elementRect.minY + 4,
          width: max(10, elementRect.width - 10),
          height: 13), font: .monospacedSystemFont(ofSize: 8, weight: .bold), color: .systemCyan,
        alignment: .center, lineBreak: .byTruncatingTail)
    }

    let crosshair =
      projection?.pointer ?? CGPoint(x: coordinateCanvas.midX, y: coordinateCanvas.midY)
    let path = NSBezierPath()
    path.move(to: CGPoint(x: viewport.minX, y: crosshair.y))
    path.line(to: CGPoint(x: viewport.maxX, y: crosshair.y))
    path.move(to: CGPoint(x: crosshair.x, y: viewport.minY))
    path.line(to: CGPoint(x: crosshair.x, y: viewport.maxY))
    path.lineWidth = 0.8
    inspectorPink.withAlphaComponent(0.55).setStroke()
    path.stroke()
    inspectorPink.setFill()
    NSBezierPath(ovalIn: CGRect(x: crosshair.x - 4, y: crosshair.y - 4, width: 8, height: 8)).fill()
    if let rawPoint = model.value("pointer.position.screen") {
      let labelWidth = min(
        125, textWidth(rawPoint, font: .monospacedSystemFont(ofSize: 9, weight: .bold)) + 12)
      let labelX = min(viewport.maxX - labelWidth - 4, max(viewport.minX + 4, crosshair.x + 7))
      let labelY = min(viewport.maxY - 21, max(viewport.minY + 4, crosshair.y - 21))
      drawCapsule(
        CGRect(x: labelX, y: labelY, width: labelWidth, height: 18),
        color: inspectorPink.withAlphaComponent(0.9), stroke: nil)
      drawText(
        rawPoint, in: CGRect(x: labelX + 6, y: labelY + 3, width: labelWidth - 12, height: 12),
        font: .monospacedSystemFont(ofSize: 9, weight: .bold), color: .white)
    }
  }

  private func drawPathChain(_ path: String, y: CGFloat, rect: CGRect) {
    let components = path.split(separator: "/").map(String.init)
    let shown: [String]
    if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
      let tail = Array(components.dropFirst(appIndex + 1))
      if tail.count >= 3 {
        shown = [components[appIndex], tail.dropLast().joined(separator: "/"), tail.last!]
      } else {
        shown = [components[appIndex]] + tail
      }
    } else if components.count > 4 {
      shown = ["/…"] + Array(components.suffix(4))
    } else {
      shown = ["/"] + components
    }
    var x = rect.minX + 16
    for (index, component) in shown.enumerated() {
      let width = min(
        150,
        max(
          24, textWidth(component, font: .monospacedSystemFont(ofSize: 9.5, weight: .semibold)) + 14
        ))
      if x + width > rect.maxX - 16 { break }
      drawRoundedRect(
        CGRect(x: x, y: y, width: width, height: 22), radius: 4,
        fill: NSColor.white.withAlphaComponent(0.055),
        stroke: NSColor.white.withAlphaComponent(0.12))
      drawText(
        component, in: CGRect(x: x + 7, y: y + 4, width: width - 14, height: 14),
        font: .monospacedSystemFont(ofSize: 9.5, weight: .semibold),
        color: index == shown.count - 1 ? .white : muted, lineBreak: .byTruncatingMiddle)
      x += width + 17
      if index < shown.count - 1 {
        drawSymbol("chevron.right", at: CGPoint(x: x - 12, y: y + 6), color: muted, size: 8)
      }
    }
  }

  private func drawToggle(
    label: String, isOn: Bool, color: NSColor, x: inout CGFloat, y: CGFloat
  ) {
    let labelWidth = textWidth(label, font: .systemFont(ofSize: 10.5, weight: .medium))
    drawCapsule(
      CGRect(x: x, y: y + 2, width: 30, height: 17),
      color: color.withAlphaComponent(isOn ? 0.8 : 0.35), stroke: nil)
    let knobX = isOn ? x + 15 : x + 2
    NSColor.white.setFill()
    NSBezierPath(ovalIn: CGRect(x: knobX, y: y + 4, width: 13, height: 13)).fill()
    drawText(
      label, in: CGRect(x: x + 36, y: y + 3, width: labelWidth + 2, height: 16),
      font: .systemFont(ofSize: 10.5, weight: .medium), color: isOn ? .white : muted)
    x += 42 + labelWidth
  }

  private func remainingHints(_ model: InspectorPresentation) -> [Hint] {
    let visualizedKinds: Set<String> = [
      "application.name", "application.bundle-id", "application.bundle-path",
      "application.executable-path", "window.identifier", "window.title",
      "pointer.position.screen", "pointer.position.window",
      "pointer.position.display.normalized", "window.frame.screen",
      "element.frame.screen", "element.frame.window", "element.size.normalized",
      "semantic.role", "native.role", "native.subrole", "native.identifier",
      "semantic.name", "semantic.value", "ancestor.role-path", "capability.action",
      "state.enabled", "state.focused", "state.selected", "display.id",
      "provider.status", "ancestor.contains-role", "ancestor.node",
    ]
    return model.hints.filter {
      !visualizedKinds.contains($0.kind) && !$0.kind.hasPrefix("element.center.grid.")
    }
  }

  private func parsePair(_ value: String) -> CGPoint? {
    let parts = value.split(separator: ",").compactMap {
      Double($0.trimmingCharacters(in: .whitespaces))
    }
    guard parts.count == 2 else { return nil }
    return CGPoint(x: parts[0], y: parts[1])
  }

  private func percentPair(_ value: String) -> String {
    guard let point = parsePair(value) else { return value }
    return String(format: "%.1f%% × %.1f%%", point.x * 100, point.y * 100)
  }

  private func abbreviatedPath(_ path: String) -> String {
    let components = path.split(separator: "/")
    guard components.count > 5 else { return path }
    return "/…/" + components.suffix(4).joined(separator: "/")
  }

  private func appIcon(for model: InspectorPresentation) -> NSImage? {
    if let path = model.applicationPath { return NSWorkspace.shared.icon(forFile: path) }
    if let bundleID = model.value("application.bundle-id"),
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    {
      return app.icon
    }
    return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
  }

  private func sectionRect(y: CGFloat, height: CGFloat) -> CGRect {
    CGRect(x: 12, y: y, width: bounds.width - 24, height: height)
  }

  private func drawSection(_ rect: CGRect, title: String, symbol: String) {
    drawSectionBackground(rect)
    drawSymbol(symbol, at: CGPoint(x: rect.minX + 14, y: rect.minY + 13), color: muted, size: 11)
    drawText(
      title, in: CGRect(x: rect.minX + 34, y: rect.minY + 11, width: rect.width - 48, height: 16),
      font: .monospacedSystemFont(ofSize: 10, weight: .bold), color: muted)
  }

  private func drawSectionBackground(_ rect: CGRect) {
    drawRoundedRect(
      rect, radius: 10, fill: NSColor.white.withAlphaComponent(0.035),
      stroke: NSColor.white.withAlphaComponent(0.11))
  }

  private func drawRoundedRect(
    _ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor?, lineWidth: CGFloat = 1
  ) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
      stroke.setStroke()
      path.lineWidth = lineWidth
      path.stroke()
    }
  }

  private func drawCapsule(_ rect: CGRect, color: NSColor, stroke: NSColor?) {
    drawRoundedRect(rect, radius: rect.height / 2, fill: color, stroke: stroke)
  }

  private func drawText(
    _ text: String, in rect: CGRect, font: NSFont?, color: NSColor,
    alignment: NSTextAlignment = .left, lineBreak: NSLineBreakMode = .byClipping
  ) {
    guard rect.width > 0, rect.height > 0 else { return }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = lineBreak
    (text.replacingOccurrences(of: "\n", with: " ") as NSString).draw(
      with: rect,
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      attributes: [
        .font: font ?? NSFont.systemFont(ofSize: 11),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
      ])
  }

  private func drawSymbol(_ name: String, at point: CGPoint, color: NSColor, size: CGFloat = 12) {
    let sizeConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
    let paletteConfiguration = NSImage.SymbolConfiguration(paletteColors: [color])
    guard
      let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(sizeConfiguration.applying(paletteConfiguration))
    else { return }
    image.draw(in: CGRect(x: point.x, y: point.y, width: size + 2, height: size + 2))
  }

  private func textWidth(_ text: String, font: NSFont?) -> CGFloat {
    (text as NSString).size(withAttributes: [
      .font: font ?? NSFont.systemFont(ofSize: 11)
    ]).width
  }

  private func providerColor(_ provider: String) -> NSColor {
    switch provider {
    case "screen.absolute": return inspectorPink
    case "window.relative": return .systemBlue
    case "mac.ax": return .systemCyan
    default: return .systemPurple
    }
  }

  private func providerSymbol(_ provider: String) -> String {
    switch provider {
    case "screen.absolute": return "scope"
    case "window.relative": return "macwindow"
    case "mac.ax": return "accessibility"
    default: return "puzzlepiece.extension"
    }
  }

  private func statusGlyph(_ state: ProviderReport.State) -> String {
    switch state {
    case .available: return "✓"
    case .degraded: return "◐"
    case .unavailable: return "!"
    }
  }

  private func bandColor(_ band: String) -> NSColor {
    switch band {
    case "capability": return .systemGreen
    case "content": return .systemYellow
    case "geometry": return inspectorPink
    case "native.mac.ax": return .systemBlue
    case "scope": return .systemGray
    case "semantic": return .systemCyan
    case "state": return .systemOrange
    case "structure": return .systemPurple
    default: return .systemTeal
    }
  }

  private func shortKind(_ kind: String) -> String {
    kind.split(separator: ".").suffix(2).joined(separator: ".")
  }

  private var muted: NSColor { NSColor(calibratedWhite: 0.6, alpha: 1) }
}
