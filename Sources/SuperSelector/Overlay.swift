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
  private static let selectorPreviewCharacterLimit = 440
  private let textView = NSTextView()
  private let scrollView = NSScrollView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.93).cgColor
    layer?.borderWidth = 1.5
    layer?.borderColor = hotPink.cgColor

    scrollView.frame = bounds
    scrollView.autoresizingMask = [.width, .height]
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true

    textView.frame = scrollView.contentView.bounds
    textView.minSize = .zero
    textView.maxSize = CGSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.isSelectable = true
    textView.isEditable = false
    textView.drawsBackground = false
    textView.textContainerInset = CGSize(width: 12, height: 10)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.containerSize = CGSize(
      width: scrollView.contentSize.width,
      height: CGFloat.greatestFiniteMagnitude
    )
    scrollView.documentView = textView
    addSubview(scrollView)
  }

  required init?(coder: NSCoder) { nil }

  func update(with observation: SuperSelectorObservation, breadcrumbs: String) {
    let hintParagraph = NSMutableParagraphStyle()
    hintParagraph.lineSpacing = 2
    hintParagraph.lineBreakMode = .byCharWrapping

    let selectorFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    let selectorParagraph = NSMutableParagraphStyle()
    selectorParagraph.lineSpacing = 1
    selectorParagraph.lineBreakMode = .byCharWrapping
    let selectorPreview =
      observation.compactSelector.count > Self.selectorPreviewCharacterLimit
      ? String(observation.compactSelector.prefix(Self.selectorPreviewCharacterLimit - 1)) + "…"
      : observation.compactSelector

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
        string: selectorPreview + "\n\n",
        attributes: [
          .font: selectorFont,
          .foregroundColor: NSColor.white,
          .paragraphStyle: selectorParagraph,
        ]
      )
    )
    output.append(
      NSAttributedString(
        string: "BREADCRUMBS  ",
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .bold),
          .foregroundColor: hotPink,
        ]
      )
    )
    output.append(
      NSAttributedString(
        string: "ESC ESC TO RESET\n",
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold),
          .foregroundColor: NSColor(calibratedWhite: 0.56, alpha: 1),
        ]
      )
    )
    output.append(
      NSAttributedString(
        string: "superselector.breadcrumbs = \(breadcrumbs)\n\n",
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
          .foregroundColor: NSColor.systemMint,
          .paragraphStyle: hintParagraph,
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
      output.append(formattedLine(for: hint, paragraph: hintParagraph))
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
  private struct ClickCaptureRequest {
    let quartzPoint: CGPoint
    let button: BreadcrumbMouseButton
    let breadcrumbWasRecorded: Bool
  }

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
  private var globalScrollMonitor: Any?
  private var globalKeyMonitor: Any?
  private var localKeyMonitor: Any?
  private var keyEventTap: CFMachPort?
  private var keyEventTapSource: CFRunLoopSource?
  private var clickCaptureQueue: [ClickCaptureRequest] = []
  private var clickCaptureInFlight = false
  private var latestObservation: SuperSelectorObservation?
  private var resolvedTarget: ResolvedSelectorTarget?
  private var breadcrumbTrail = BreadcrumbTrail()
  private var escapeResetDetector = DoubleEscapeResetDetector()
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
      let button = Self.breadcrumbButton(for: event)
      DispatchQueue.main.async {
        guard let self, !self.isSuppressed, let point, let button else { return }
        self.enqueueClickCapture(at: point, button: button)
      }
    }
    globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) {
      [weak self] event in
      let point = event.cgEvent?.location ?? CGEvent(source: nil)?.location
      let deltaX = event.scrollingDeltaX
      let deltaY = event.scrollingDeltaY
      DispatchQueue.main.async {
        guard let self, !self.isSuppressed, let point else { return }
        self.recordScroll(
          at: point,
          deltaX: deltaX,
          deltaY: deltaY
        )
      }
    }
    installKeyMonitoring()
    sampleHints()
  }

  func stop() {
    displayTimer?.invalidate()
    inspectionTimer?.invalidate()
    resolvedTargetTimer?.invalidate()
    if let globalClickMonitor {
      NSEvent.removeMonitor(globalClickMonitor)
    }
    if let globalScrollMonitor {
      NSEvent.removeMonitor(globalScrollMonitor)
    }
    if let globalKeyMonitor {
      NSEvent.removeMonitor(globalKeyMonitor)
    }
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
    }
    if let keyEventTapSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), keyEventTapSource, .commonModes)
    }
    if let keyEventTap {
      CFMachPortInvalidate(keyEventTap)
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

  private func enqueueClickCapture(at quartzPoint: CGPoint, button: BreadcrumbMouseButton) {
    let anchor = recentBreadcrumbObservation(at: quartzPoint)
    if let anchor {
      breadcrumbTrail.recordClick(observation: anchor, button: button, at: quartzPoint)
      refreshInspector()
    }
    clickCaptureQueue.append(
      ClickCaptureRequest(
        quartzPoint: quartzPoint,
        button: button,
        breadcrumbWasRecorded: anchor != nil
      ))
    startNextClickCapture()
  }

  private func startNextClickCapture() {
    guard !clickCaptureInFlight, !clickCaptureQueue.isEmpty else { return }
    clickCaptureInFlight = true
    let request = clickCaptureQueue.removeFirst()
    clickCaptureEngine.sample(at: request.quartzPoint) { [weak self] observation in
      guard let self else { return }
      if !request.breadcrumbWasRecorded {
        breadcrumbTrail.recordClick(
          observation: observation,
          button: request.button,
          at: request.quartzPoint
        )
        refreshInspector()
      }
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
      breadcrumbTrail.updateLive(observation: observation)
      latestObservation = observation
      inspectorPanel.title = "SuperSelector Hints — \(observation.compactSelector)"
      inspectorPanel.setAccessibilityLabel(
        "SuperSelector live hints, \(observation.compactSelector)")
      refreshInspector()
    }
  }

  private func refreshInspector() {
    guard let observation = latestObservation else { return }
    inspectorView.update(
      with: observation,
      breadcrumbs: breadcrumbTrail.rendered(current: observation)
    )
  }

  private func recentBreadcrumbObservation(at quartzPoint: CGPoint)
    -> SuperSelectorObservation?
  {
    guard let observation = latestObservation,
      Date().timeIntervalSince(observation.scene.sampledAt) <= 0.5
    else { return nil }
    if let frame = observation.scene.accessibilityElement?.frameInQuartzCoordinates {
      return frame.insetBy(dx: -3, dy: -3).contains(quartzPoint) ? observation : nil
    }
    let deltaX = observation.scene.cursorQuartz.x - quartzPoint.x
    let deltaY = observation.scene.cursorQuartz.y - quartzPoint.y
    return hypot(deltaX, deltaY) <= 8 ? observation : nil
  }

  private func installKeyMonitoring() {
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let coordinator = Unmanaged<OverlayCoordinator>.fromOpaque(userInfo)
        .takeUnretainedValue()
      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let keyEventTap = coordinator.keyEventTap {
          CGEvent.tapEnable(tap: keyEventTap, enable: true)
        }
        return Unmanaged.passUnretained(event)
      }
      guard type == .keyDown else { return Unmanaged.passUnretained(event) }
      let keyCode = UInt16(
        truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
      let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
      let text = OverlayCoordinator.keyboardText(from: event)
      let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
      DispatchQueue.main.async { [weak coordinator] in
        coordinator?.handleKeyDown(
          keyCode: keyCode,
          isRepeat: isRepeat,
          text: text,
          modifiers: modifiers
        )
      }
      return Unmanaged.passUnretained(event)
    }
    let userInfo = Unmanaged.passUnretained(self).toOpaque()
    if let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,
      eventsOfInterest: mask,
      callback: callback,
      userInfo: userInfo
    ) {
      keyEventTap = tap
      let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
      keyEventTapSource = source
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
      return
    }

    globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      DispatchQueue.main.async {
        self?.handleKeyDown(
          keyCode: event.keyCode,
          isRepeat: event.isARepeat,
          text: event.characters ?? "",
          modifiers: event.modifierFlags
        )
      }
    }
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      self?.handleKeyDown(
        keyCode: event.keyCode,
        isRepeat: event.isARepeat,
        text: event.characters ?? "",
        modifiers: event.modifierFlags
      )
      return event
    }
  }

  private func handleKeyDown(
    keyCode: UInt16,
    isRepeat: Bool,
    text: String,
    modifiers: NSEvent.ModifierFlags
  ) {
    guard !isRepeat else { return }
    if keyCode == 53 {
      if escapeResetDetector.registerEscape() {
        breadcrumbTrail.reset()
        refreshInspector()
      }
      return
    }
    escapeResetDetector.registerOtherKey()
    guard !isSuppressed, let observation = latestObservation else { return }
    if Self.modifierKeyCodes.contains(keyCode) { return }

    let independentModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    let isCommand =
      independentModifiers.contains(.command)
      || independentModifiers.contains(.control)
    if !isCommand, Self.isPrintableText(text) {
      breadcrumbTrail.recordText(text, observation: observation)
    } else {
      breadcrumbTrail.recordKey(
        Self.keyDescription(keyCode: keyCode, text: text, modifiers: independentModifiers),
        observation: observation
      )
    }
    refreshInspector()
  }

  private func recordScroll(at point: CGPoint, deltaX: CGFloat, deltaY: CGFloat) {
    guard abs(deltaX) > 0.01 || abs(deltaY) > 0.01,
      let observation = recentBreadcrumbObservation(at: point) ?? latestObservation
    else { return }
    breadcrumbTrail.recordScroll(
      observation: observation,
      at: point,
      deltaX: deltaX,
      deltaY: deltaY
    )
    refreshInspector()
  }

  private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

  private static func keyboardText(from event: CGEvent) -> String {
    var actualLength = 0
    var buffer = [UniChar](repeating: 0, count: 16)
    event.keyboardGetUnicodeString(
      maxStringLength: buffer.count,
      actualStringLength: &actualLength,
      unicodeString: &buffer
    )
    return String(utf16CodeUnits: buffer, count: actualLength)
  }

  private static func isPrintableText(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    return !["\r", "\n", "\t", "\u{7f}"].contains(text)
  }

  private static func keyDescription(
    keyCode: UInt16,
    text: String,
    modifiers: NSEvent.ModifierFlags
  ) -> String {
    var parts: [String] = []
    if modifiers.contains(.control) { parts.append("⌃") }
    if modifiers.contains(.option) { parts.append("⌥") }
    if modifiers.contains(.shift) { parts.append("⇧") }
    if modifiers.contains(.command) { parts.append("⌘") }
    let key: String
    switch keyCode {
    case 36: key = "Return"
    case 48: key = "Tab"
    case 49: key = "Space"
    case 51: key = "Delete"
    case 53: key = "Escape"
    case 123: key = "Left"
    case 124: key = "Right"
    case 125: key = "Down"
    case 126: key = "Up"
    default: key = text.isEmpty ? "KeyCode \(keyCode)" : text.uppercased()
    }
    parts.append(key)
    return parts.joined()
  }

  private static func breadcrumbButton(for event: NSEvent) -> BreadcrumbMouseButton? {
    switch event.type {
    case .leftMouseDown: return .left
    case .rightMouseDown: return .right
    case .otherMouseDown:
      if event.buttonNumber == 2 { return .middle }
      return .other(event.buttonNumber)
    default: return nil
    }
  }

  private func positionInspector(near cursor: CGPoint) {
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
    else {
      return
    }
    let visible = screen.visibleFrame
    let margin: CGFloat = 16
    let size = CGSize(
      width: min(820, max(320, visible.width - (margin * 2))),
      height: min(560, max(240, visible.height - (margin * 2)))
    )
    if inspectorPanel.frame.size != size {
      inspectorPanel.setContentSize(size)
    }
    var origin = CGPoint(x: cursor.x + 28, y: cursor.y - size.height - 28)
    if origin.x + size.width > visible.maxX { origin.x = cursor.x - size.width - 28 }
    if origin.y < visible.minY { origin.y = cursor.y + 28 }
    origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
    origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
    inspectorPanel.setFrameOrigin(origin)
  }
}
