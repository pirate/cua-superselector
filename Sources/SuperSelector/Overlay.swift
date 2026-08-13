import AppKit
import Foundation

private let hotPink = NSColor(calibratedRed: 1, green: 0.12, blue: 0.58, alpha: 0.96)
private let rulerPink = NSColor(calibratedRed: 1, green: 0.12, blue: 0.58, alpha: 0.46)

final class CrosshairView: NSView {
  var cursorGlobal: CGPoint = .zero { didSet { needsDisplay = true } }
  var elementFrameGlobal: CGRect? { didSet { needsDisplay = true } }
  var isActiveDisplay = false { didSet { needsDisplay = true } }

  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    NSGraphicsContext.current?.cgContext.clear(dirtyRect)
    guard isActiveDisplay, let window else { return }
    let cursor = CoordinateSpaces.localPoint(fromGlobal: cursorGlobal, in: window.frame)

    rulerPink.setStroke()
    let crosshair = NSBezierPath()
    crosshair.lineWidth = 0.8
    crosshair.move(to: CGPoint(x: bounds.minX, y: cursor.y))
    crosshair.line(to: CGPoint(x: bounds.maxX, y: cursor.y))
    crosshair.move(to: CGPoint(x: cursor.x, y: bounds.minY))
    crosshair.line(to: CGPoint(x: cursor.x, y: bounds.maxY))
    crosshair.stroke()

    drawRulerTicks(at: cursor)

    let dot = NSBezierPath(ovalIn: CGRect(x: cursor.x - 4, y: cursor.y - 4, width: 8, height: 8))
    hotPink.setFill()
    dot.fill()

    if let frame = elementFrameGlobal {
      let local = CoordinateSpaces.localRect(fromGlobal: frame, in: window.frame)
      let outline = NSBezierPath(roundedRect: local.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5)
      outline.lineWidth = 3
      hotPink.setStroke()
      outline.stroke()
    }
  }

  private func drawRulerTicks(at cursor: CGPoint) {
    let path = NSBezierPath()
    path.lineWidth = 1
    let majorEvery: CGFloat = 100
    let minorEvery: CGFloat = 20

    var x = bounds.minX
    while x <= bounds.maxX {
      let relative = abs(x - cursor.x)
      let major = Int(relative.rounded()) % Int(majorEvery) < 2
      let length: CGFloat = major ? 10 : 5
      path.move(to: CGPoint(x: x, y: cursor.y - length))
      path.line(to: CGPoint(x: x, y: cursor.y + length))
      x += minorEvery
    }
    var y = bounds.minY
    while y <= bounds.maxY {
      let relative = abs(y - cursor.y)
      let major = Int(relative.rounded()) % Int(majorEvery) < 2
      let length: CGFloat = major ? 10 : 5
      path.move(to: CGPoint(x: cursor.x - length, y: y))
      path.line(to: CGPoint(x: cursor.x + length, y: y))
      y += minorEvery
    }
    rulerPink.setStroke()
    path.stroke()
  }
}

final class InspectorView: NSView {
  private let textView = NSTextView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.93).cgColor
    layer?.borderWidth = 1.5
    layer?.borderColor = hotPink.cgColor

    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.textContainerInset = CGSize(width: 12, height: 10)
    textView.textContainer?.lineFragmentPadding = 0
    textView.autoresizingMask = [.width, .height]
    textView.frame = bounds
    addSubview(textView)
  }

  required init?(coder: NSCoder) { nil }

  func update(with observation: SuperSelectorObservation) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 2

    let output = NSMutableAttributedString()
    output.append(
      NSAttributedString(
        string: "SUPERSELECTOR\n",
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .bold),
          .foregroundColor: hotPink,
        ]
      )
    )
    output.append(
      NSAttributedString(
        string: observation.compactSelector + "\n\n",
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
          .foregroundColor: NSColor.white,
          .paragraphStyle: paragraph,
        ]
      )
    )
    let providerHeader = NSMutableAttributedString(
      string: "PROVIDERS  ",
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .bold),
        .foregroundColor: NSColor(calibratedWhite: 0.56, alpha: 1),
      ]
    )
    for (index, report) in observation.providerReports.enumerated() {
      if index > 0 {
        providerHeader.append(NSAttributedString(string: "   "))
      }
      let provider = report.provider
      let color = providerColor(provider).withAlphaComponent(
        report.state == .unavailable ? 0.48 : 1)
      providerHeader.append(
        iconAttachment(named: iconName(forProvider: provider), color: color))
      providerHeader.append(
        NSAttributedString(
          string: " \(provider)\(providerStatusSuffix(report))",
          attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: color,
          ]
        )
      )
    }
    providerHeader.append(NSAttributedString(string: "\n\n"))
    output.append(
      providerHeader
    )
    for hint in observation.hints {
      output.append(formattedLine(for: hint, paragraph: paragraph))
    }
    textView.textStorage?.setAttributedString(output)
    textView.scrollToBeginningOfDocument(nil)
  }

  private func formattedLine(for hint: Hint, paragraph: NSParagraphStyle) -> NSAttributedString {
    let output = NSMutableAttributedString()
    let color = bandColor(hint.band)
    output.append(
      iconAttachment(
        named: iconName(forProvider: hint.provider), color: providerColor(hint.provider)))
    output.append(NSAttributedString(string: " "))
    output.append(
      NSAttributedString(
        string: compactBandName(hint.band).uppercased().padding(
          toLength: 4, withPad: " ", startingAt: 0),
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
          .foregroundColor: color,
          .backgroundColor: color.withAlphaComponent(0.13),
        ]
      )
    )
    output.append(
      NSAttributedString(
        string: "  ◆ \(hint.kind)",
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .medium),
          .foregroundColor: NSColor(calibratedWhite: 0.94, alpha: 1),
          .paragraphStyle: paragraph,
        ]
      )
    )
    output.append(
      NSAttributedString(
        string: "  =  \(hint.value)",
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
          .foregroundColor: color.withAlphaComponent(0.95),
          .paragraphStyle: paragraph,
        ]
      )
    )
    if hint.privacy != .publicData {
      output.append(
        NSAttributedString(
          string: "  \(hint.privacy == .secret ? "🔒" : "◈") \(hint.privacy.rawValue)",
          attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: NSColor.systemOrange,
          ]
        )
      )
    }
    if !hint.metadata.isEmpty {
      let details = hint.metadata.sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: " · ")
      output.append(
        NSAttributedString(
          string: "  ‹\(details)›",
          attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.52, alpha: 1),
          ]
        )
      )
    }
    output.append(NSAttributedString(string: "\n"))
    return output
  }

  private func iconAttachment(named name: String, color: NSColor) -> NSAttributedString {
    let attachment = NSTextAttachment()
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    let pointSize = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
    let palette = NSImage.SymbolConfiguration(paletteColors: [color])
    attachment.image = base?.withSymbolConfiguration(pointSize.applying(palette))
    attachment.bounds = CGRect(x: 0, y: -2, width: 14, height: 14)
    return NSAttributedString(attachment: attachment)
  }

  private func iconName(forProvider provider: String) -> String {
    switch provider {
    case "screen.absolute": return "scope"
    case "mac.ax": return "accessibility"
    case _ where provider.hasPrefix("browser"): return "safari"
    case _ where provider.hasPrefix("ocr"): return "text.viewfinder"
    case _ where provider.hasPrefix("visual"): return "eye"
    default: return "puzzlepiece.extension"
    }
  }

  private func providerColor(_ provider: String) -> NSColor {
    switch provider {
    case "screen.absolute": return hotPink
    case "mac.ax": return NSColor.systemCyan
    default: return NSColor.systemPurple
    }
  }

  private func providerStatusSuffix(_ report: ProviderReport) -> String {
    switch report.state {
    case .available:
      return " ✓"
    case .degraded:
      return " ◐\(report.detail.map { " (\($0))" } ?? "")"
    case .unavailable:
      return " ⚠\(report.detail.map { " (\($0))" } ?? "")"
    }
  }

  private func compactBandName(_ band: String) -> String {
    switch band {
    case "capability": return "CAP"
    case "content": return "TEXT"
    case "geometry": return "GEO"
    case "native.mac.ax": return "AX"
    case "scope": return "SCOPE"
    case "semantic": return "SEM"
    case "state": return "STATE"
    case "structure": return "TREE"
    default: return String(band.prefix(4))
    }
  }

  private func bandColor(_ band: String) -> NSColor {
    switch band {
    case "capability": return NSColor.systemGreen
    case "content": return NSColor.systemYellow
    case "geometry": return hotPink
    case "native.mac.ax": return NSColor.systemBlue
    case "scope": return NSColor.systemGray
    case "semantic": return NSColor.systemCyan
    case "state": return NSColor.systemOrange
    case "structure": return NSColor.systemPurple
    default: return NSColor.systemTeal
    }
  }
}

final class OverlayCoordinator {
  private let hintEngine = HintEngine()
  private let clickCaptureEngine = HintEngine()
  private let resolutionQueue = DispatchQueue(
    label: "SuperSelector.SelectorResolver",
    qos: .userInitiated
  )
  var onSelectorCaptured: ((String) -> Void)?
  private var crosshairPanels: [NSPanel] = []
  private let inspectorPanel: NSPanel
  private let inspectorView: InspectorView
  private var displayTimer: Timer?
  private var inspectionTimer: Timer?
  private var resolvedTargetTimer: Timer?
  private var globalClickMonitor: Any?
  private var clickCaptureQueue: [CGPoint] = []
  private var clickCaptureInFlight = false
  private var latestObservation: SuperSelectorObservation?
  private var resolvedTarget: ResolvedSelectorTarget?
  private var isSuppressed = false

  init() {
    inspectorView = InspectorView(frame: CGRect(x: 0, y: 0, width: 820, height: 560))
    inspectorPanel = NSPanel(
      contentRect: inspectorView.bounds,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configure(panel: inspectorPanel, levelOffset: 2)
    inspectorPanel.title = "SuperSelector Hints"
    inspectorPanel.setAccessibilityLabel("SuperSelector live hints")
    inspectorPanel.contentView = inspectorView
    inspectorPanel.hasShadow = true
    inspectorPanel.setAccessibilityElement(false)
    inspectorPanel.setAccessibilityHidden(true)
    inspectorView.setAccessibilityElement(false)
    inspectorView.setAccessibilityHidden(true)
    rebuildCrosshairPanels()
  }

  func start() {
    if !AXIsProcessTrusted() {
      AccessibilityInspector.requestTrustPrompt()
    }
    if !isSuppressed {
      for panel in crosshairPanels {
        panel.orderFrontRegardless()
      }
      inspectorPanel.orderFrontRegardless()
    }

    displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
      [weak self] _ in
      self?.updateCursorDisplay()
    }
    inspectionTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
      self?.sampleHints()
    }
    globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      let point = event.cgEvent?.location ?? CGEvent(source: nil)?.location
      DispatchQueue.main.async {
        guard let self, !self.isSuppressed, let point else { return }
        self.enqueueClickCapture(at: point)
      }
    }
    sampleHints()
  }

  func stop() {
    displayTimer?.invalidate()
    inspectionTimer?.invalidate()
    resolvedTargetTimer?.invalidate()
    if let globalClickMonitor {
      NSEvent.removeMonitor(globalClickMonitor)
    }
  }

  func showResolvedSelector(
    _ selector: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    resolutionQueue.async { [weak self] in
      do {
        let target = try SelectorResolver.resolve(selector)
        DispatchQueue.main.async {
          guard let self else { return }
          self.resolvedTarget = target
          self.resolvedTargetTimer?.invalidate()
          self.resolvedTargetTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) {
            [weak self] _ in
            self?.resolvedTarget = nil
          }
          self.updateCursorDisplay()
          completion(.success(()))
        }
      } catch {
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  func setSuppressed(_ suppressed: Bool) {
    guard isSuppressed != suppressed else { return }
    isSuppressed = suppressed
    if suppressed {
      for panel in crosshairPanels {
        panel.orderOut(nil)
      }
      inspectorPanel.orderOut(nil)
    } else {
      for panel in crosshairPanels {
        panel.orderFrontRegardless()
      }
      inspectorPanel.orderFrontRegardless()
      updateCursorDisplay()
    }
  }

  private func rebuildCrosshairPanels() {
    for panel in crosshairPanels {
      panel.close()
    }
    crosshairPanels = NSScreen.screens.map { screen in
      let panel = NSPanel(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      configure(panel: panel, levelOffset: 1)
      panel.setFrame(screen.frame, display: false)
      let view = CrosshairView(frame: CGRect(origin: .zero, size: screen.frame.size))
      view.setAccessibilityElement(false)
      view.setAccessibilityHidden(true)
      panel.contentView = view
      return panel
    }
  }

  private func configure(panel: NSPanel, levelOffset: Int) {
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.setAccessibilityElement(false)
    panel.setAccessibilityHidden(true)
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + levelOffset)
  }

  private func updateCursorDisplay() {
    let liveCursor = NSEvent.mouseLocation
    let cursor = resolvedTarget?.pointAppKit ?? liveCursor
    for panel in crosshairPanels {
      guard let view = panel.contentView as? CrosshairView else { continue }
      let isActive = panel.frame.contains(cursor)
      view.isActiveDisplay = isActive
      view.cursorGlobal = cursor
      view.elementFrameGlobal =
        isActive
        ? (resolvedTarget?.elementFrameAppKit ?? latestObservation?.scene.elementFrameAppKit) : nil
    }
    positionInspector(near: cursor)
  }

  private func enqueueClickCapture(at quartzPoint: CGPoint) {
    clickCaptureQueue.append(quartzPoint)
    startNextClickCapture()
  }

  private func startNextClickCapture() {
    guard !clickCaptureInFlight, !clickCaptureQueue.isEmpty else { return }
    clickCaptureInFlight = true
    let quartzPoint = clickCaptureQueue.removeFirst()
    clickCaptureEngine.sample(at: quartzPoint) { [weak self] observation in
      guard let self else { return }
      copySelector(observation.compactSelector)
      onSelectorCaptured?(observation.compactSelector)
      clickCaptureInFlight = false
      startNextClickCapture()
    }
  }

  private func copySelector(_ selector: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(selector, forType: .string)
  }

  private func sampleHints() {
    guard let quartzPoint = CGEvent(source: nil)?.location else { return }
    hintEngine.sample(at: quartzPoint) { [weak self] observation in
      guard let self else { return }
      latestObservation = observation
      inspectorPanel.title = "SuperSelector Hints — \(observation.compactSelector)"
      inspectorPanel.setAccessibilityLabel(
        "SuperSelector live hints, \(observation.compactSelector)")
      inspectorView.update(with: observation)
    }
  }

  private func positionInspector(near cursor: CGPoint) {
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
    else {
      return
    }
    let visible = screen.visibleFrame
    let size = inspectorPanel.frame.size
    var origin = CGPoint(x: cursor.x + 28, y: cursor.y - size.height - 28)
    if origin.x + size.width > visible.maxX { origin.x = cursor.x - size.width - 28 }
    if origin.y < visible.minY { origin.y = cursor.y + 28 }
    origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
    origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
    inspectorPanel.setFrameOrigin(origin)
  }
}
