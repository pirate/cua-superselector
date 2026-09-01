import AppKit
import Foundation
import SwiftUI

private let hotPink = NSColor(calibratedRed: 1, green: 0.12, blue: 0.58, alpha: 0.96)
private let rulerPink = NSColor(calibratedRed: 1, green: 0.12, blue: 0.58, alpha: 0.46)

final class CrosshairView: NSView {
  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    NSGraphicsContext.current?.cgContext.clear(dirtyRect)
    let cursor = CGPoint(x: bounds.midX, y: bounds.midY)

    rulerPink.setStroke()
    let crosshair = NSBezierPath()
    crosshair.lineWidth = 1
    crosshair.move(to: CGPoint(x: bounds.minX, y: cursor.y))
    crosshair.line(to: CGPoint(x: bounds.maxX, y: cursor.y))
    crosshair.move(to: CGPoint(x: cursor.x, y: bounds.minY))
    crosshair.line(to: CGPoint(x: cursor.x, y: bounds.maxY))
    crosshair.stroke()

    let dot = NSBezierPath(ovalIn: CGRect(x: cursor.x - 4, y: cursor.y - 4, width: 8, height: 8))
    hotPink.setFill()
    dot.fill()
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
    update(
      selector: observation.compactSelector,
      hints: observation.hints,
      providerReports: observation.providerReports,
      breadcrumbs: breadcrumbs
    )
  }

  func update(
    selector: String,
    hints: [Hint],
    providerReports: [ProviderReport],
    breadcrumbs: String
  ) {
    let hintParagraph = NSMutableParagraphStyle()
    hintParagraph.lineSpacing = 2
    hintParagraph.lineBreakMode = .byCharWrapping

    let selectorFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    let selectorParagraph = NSMutableParagraphStyle()
    selectorParagraph.lineSpacing = 1
    selectorParagraph.lineBreakMode = .byCharWrapping
    let selectorPreview =
      selector.count > Self.selectorPreviewCharacterLimit
      ? String(selector.prefix(Self.selectorPreviewCharacterLimit - 1)) + "…"
      : selector

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
    for (index, report) in providerReports.enumerated() {
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
    for hint in hints {
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
  private struct ResolvedPresentation {
    let selector: String
    let hints: [Hint]
    let providerReports: [ProviderReport]
    let breadcrumbs: String
  }

  private struct ClickCaptureRequest {
    let quartzPoint: CGPoint
    let button: BreadcrumbMouseButton
    let hid: PointerHIDEvent
    let breadcrumbWasRecorded: Bool
  }

  private let hintEngine = HintEngine()
  private let clickCaptureEngine = HintEngine()
  private let resolutionQueue = DispatchQueue(
    label: "SuperSelector.SelectorResolver",
    qos: .userInitiated
  )
  var onSelectorCaptured: ((String, BreadcrumbTrail) -> Void)?
  var onScreenshotCaptureVisibilityChanged: ((Bool) -> Void)?
  var onRecordingEnded: (() -> Void)?
  private let crosshairPanel: NSPanel
  private var targetEdgePanels: [NSPanel] = []
  private let inspectorPanel: NSPanel
  private let inspectorView: VisualInspectorView
  private let recordingControlPanel: NSPanel
  private let recordingControlState: RecordingControlState
  private var displayTimer: Timer?
  private var inspectionTimer: Timer?
  private var resolvedTargetTimer: Timer?
  private var screenParametersObserver: NSObjectProtocol?
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
  private var resolvedPresentation: ResolvedPresentation?
  private var breadcrumbTrail = BreadcrumbTrail()
  private var escapeResetDetector = DoubleEscapeResetDetector()
  private var isSuppressed = false
  private var isRecordingEnabled = true
  private var isReplayVisualizationActive = false
  private var isCapturingScreenshot = false
  private var recordingControlsVisible = false

  init() {
    recordingControlState = RecordingControlState()
    let recordingControlHost = NSHostingView(
      rootView: RecordingControlView(state: recordingControlState))
    recordingControlHost.frame = CGRect(x: 0, y: 0, width: 250, height: 48)
    recordingControlPanel = NSPanel(
      contentRect: recordingControlHost.bounds,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    inspectorView = VisualInspectorView(frame: CGRect(x: 0, y: 0, width: 820, height: 620))
    inspectorPanel = NSPanel(
      contentRect: inspectorView.bounds,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    crosshairPanel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 56, height: 56),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configure(panel: inspectorPanel, levelOffset: 2)
    inspectorPanel.title = "SuperSelector Hints"
    inspectorPanel.setAccessibilityLabel("SuperSelector live hints")
    inspectorPanel.contentView = inspectorView
    inspectorPanel.setAccessibilityElement(false)
    inspectorPanel.setAccessibilityHidden(true)
    inspectorView.setAccessibilityElement(false)
    inspectorView.setAccessibilityHidden(true)
    configure(panel: crosshairPanel, levelOffset: 1)
    let crosshairView = CrosshairView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
    crosshairView.setAccessibilityElement(false)
    crosshairView.setAccessibilityHidden(true)
    crosshairPanel.contentView = crosshairView
    targetEdgePanels = (0..<4).map { _ in
      let panel = NSPanel(
        contentRect: CGRect(x: 0, y: 0, width: 3, height: 3),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      configure(panel: panel, levelOffset: 1)
      panel.isOpaque = true
      panel.backgroundColor = hotPink
      return panel
    }
    recordingControlPanel.isOpaque = false
    recordingControlPanel.backgroundColor = .clear
    recordingControlPanel.hasShadow = true
    recordingControlPanel.ignoresMouseEvents = false
    recordingControlPanel.hidesOnDeactivate = false
    recordingControlPanel.isReleasedWhenClosed = false
    recordingControlPanel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    recordingControlPanel.level = NSWindow.Level(
      rawValue: NSWindow.Level.screenSaver.rawValue + 4)
    recordingControlPanel.contentView = recordingControlHost
    recordingControlPanel.setAccessibilityLabel("SuperSelector recording controls")
    recordingControlState.onReset = { [weak self] in self?.resetBreadcrumbTrail() }
    recordingControlState.onPauseChanged = { [weak self] paused in
      self?.setRecordingPaused(paused)
    }
    recordingControlState.onEnd = { [weak self] in self?.finishRecording() }
  }

  func start() {
    if !AXIsProcessTrusted() {
      AccessibilityInspector.requestTrustPrompt()
    }
    if !isSuppressed {
      crosshairPanel.orderFrontRegardless()
      inspectorPanel.orderFrontRegardless()
    }

    displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
      [weak self] _ in
      self?.updateCursorDisplay()
    }
    // AX semantic ancestry is substantially more expensive than cursor painting. Keep it fresh
    // enough for hover inspection without coupling the complete metadata scan to the 60 Hz overlay.
    inspectionTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
      self?.sampleHints()
    }
    screenParametersObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.positionRecordingControls()
    }
    globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      let point = event.cgEvent?.location ?? CGEvent(source: nil)?.location
      let button = Self.breadcrumbButton(for: event)
      let hid = PointerHIDEvent(
        buttonNumber: event.buttonNumber,
        modifierFlags: UInt64(event.modifierFlags.rawValue),
        clickCount: event.clickCount,
        pressure: Double(event.pressure)
      )
      DispatchQueue.main.async {
        guard let self, !self.isSuppressed, self.isRecordingEnabled, let point, let button else {
          return
        }
        self.enqueueClickCapture(at: point, button: button, hid: hid)
      }
    }
    globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) {
      [weak self] event in
      let point = event.cgEvent?.location ?? CGEvent(source: nil)?.location
      let deltaX = event.scrollingDeltaX
      let deltaY = event.scrollingDeltaY
      DispatchQueue.main.async {
        guard let self, !self.isSuppressed, self.isRecordingEnabled, let point else { return }
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
    if let screenParametersObserver {
      NotificationCenter.default.removeObserver(screenParametersObserver)
    }
    recordingControlPanel.orderOut(nil)
  }

  func showResolvedSelector(
    _ selector: String,
    breadcrumbs: String? = nil,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    resolutionQueue.async { [weak self] in
      do {
        let hints = try SuperSelectorDecoder.decode(selector)
        let target = try SelectorResolver.resolve(selector)
        DispatchQueue.main.async {
          guard let self else { return }
          self.resolvedTarget = target
          let providers = Dictionary(grouping: hints, by: \.provider).keys.sorted().map {
            ProviderReport(provider: $0, state: .available, detail: "resolved selector")
          }
          self.resolvedPresentation = ResolvedPresentation(
            selector: selector,
            hints: hints,
            providerReports: providers,
            breadcrumbs: breadcrumbs ?? "[Resolved selector]"
          )
          self.resolvedTargetTimer?.invalidate()
          self.resolvedTargetTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) {
            [weak self] _ in
            self?.resolvedTarget = nil
            self?.resolvedPresentation = nil
            self?.refreshInspector()
          }
          self.refreshInspector()
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
      crosshairPanel.orderOut(nil)
      for panel in targetEdgePanels { panel.orderOut(nil) }
      inspectorPanel.orderOut(nil)
    } else {
      crosshairPanel.orderFrontRegardless()
      if !isReplayVisualizationActive { inspectorPanel.orderFrontRegardless() }
      updateCursorDisplay()
    }
  }

  func setRecordingEnabled(_ enabled: Bool) {
    isRecordingEnabled = enabled
    if recordingControlsVisible {
      recordingControlState.isPaused = !enabled
    }
  }

  func setRecordingControlsVisible(_ visible: Bool) {
    recordingControlsVisible = visible
    if visible {
      positionRecordingControls()
      recordingControlPanel.orderFrontRegardless()
    } else {
      recordingControlPanel.orderOut(nil)
    }
  }

  @MainActor
  func setReplayVisualizationActive(_ active: Bool) {
    isReplayVisualizationActive = active
    resolvedTargetTimer?.invalidate()
    resolvedPresentation = nil
    if active {
      inspectorPanel.orderOut(nil)
      if !isSuppressed {
        crosshairPanel.orderFrontRegardless()
      }
    } else {
      resolvedTarget = nil
      if !isSuppressed { inspectorPanel.orderFrontRegardless() }
    }
    updateCursorDisplay()
  }

  @MainActor
  func showReplayTarget(_ target: ResolvedSelectorTarget) {
    resolvedTargetTimer?.invalidate()
    resolvedPresentation = nil
    resolvedTarget = target
    updateCursorDisplay()
  }

  func resetBreadcrumbTrail() {
    resolvedTargetTimer?.invalidate()
    resolvedTarget = nil
    resolvedPresentation = nil
    breadcrumbTrail.reset()
    refreshInspector()
  }

  private func setRecordingPaused(_ paused: Bool) {
    isRecordingEnabled = !paused
    if paused {
      breadcrumbTrail.suspendLiveTarget()
    }
  }

  private func finishRecording() {
    isRecordingEnabled = false
    recordingControlState.isPaused = false
    if !breadcrumbTrail.links.isEmpty, let observation = latestObservation {
      onSelectorCaptured?(observation.compactSelector, breadcrumbTrail)
    }
    setRecordingControlsVisible(false)
    onRecordingEnded?()
  }

  private func pointerIsOverRecordingControls(_ point: CGPoint) -> Bool {
    recordingControlPanel.isVisible && recordingControlPanel.frame.contains(point)
  }

  private func positionRecordingControls() {
    guard recordingControlsVisible else { return }
    let screen =
      NSScreen.screens.first(where: { screen in
        guard
          let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber
        else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
      }) ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }
    let size = recordingControlPanel.frame.size
    let safeTop = min(
      screen.visibleFrame.maxY,
      screen.frame.maxY - screen.safeAreaInsets.top
    )
    recordingControlPanel.setFrameOrigin(
      CGPoint(
        x: screen.frame.midX - size.width / 2,
        y: safeTop - size.height - 8
      ))
  }

  private func configure(panel: NSPanel, levelOffset: Int) {
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
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
    guard !isSuppressed else { return }
    let liveCursor = NSEvent.mouseLocation
    if pointerIsOverRecordingControls(liveCursor) {
      crosshairPanel.orderOut(nil)
      targetEdgePanels.forEach { $0.orderOut(nil) }
      inspectorPanel.orderOut(nil)
      return
    }
    let cursor = resolvedTarget?.pointAppKit ?? liveCursor
    crosshairPanel.setFrameOrigin(CGPoint(x: cursor.x - 28, y: cursor.y - 28))
    crosshairPanel.orderFrontRegardless()
    let rawTarget =
      resolvedTarget?.elementFrameAppKit ?? latestObservation?.scene.elementFrameAppKit
    let activeScreen = NSScreen.screens.first { $0.frame.contains(cursor) }
    let visibleTarget = activeScreen.flatMap { screen in
      SuperSelectorBoxModel(
        screenAppKit: screen.frame, targetAppKit: rawTarget, pointerAppKit: cursor
      ).projection(in: screen.frame, origin: .bottomLeft).target
    }
    updateTargetEdges(around: visibleTarget)
    positionInspector(near: cursor)
  }

  private func updateTargetEdges(around frame: CGRect?) {
    guard let frame, frame.width > 1, frame.height > 1 else {
      for panel in targetEdgePanels { panel.orderOut(nil) }
      return
    }
    let outline = frame.insetBy(dx: -2, dy: -2)
    let thickness: CGFloat = 3
    let edges = [
      CGRect(x: outline.minX, y: outline.minY, width: outline.width, height: thickness),
      CGRect(x: outline.minX, y: outline.maxY - thickness, width: outline.width, height: thickness),
      CGRect(x: outline.minX, y: outline.minY, width: thickness, height: outline.height),
      CGRect(
        x: outline.maxX - thickness, y: outline.minY, width: thickness, height: outline.height),
    ]
    for (panel, edge) in zip(targetEdgePanels, edges) {
      panel.setFrame(edge, display: false)
      panel.orderFrontRegardless()
    }
  }

  private func enqueueClickCapture(
    at quartzPoint: CGPoint, button: BreadcrumbMouseButton, hid: PointerHIDEvent
  ) {
    let anchor = recentBreadcrumbObservation(at: quartzPoint)
    if let anchor {
      breadcrumbTrail.recordClick(
        observation: anchor,
        button: button,
        at: quartzPoint,
        hid: hid,
        screenshot: captureBreadcrumbScreenshot(for: anchor)
      )
      refreshInspector()
    }
    clickCaptureQueue.append(
      ClickCaptureRequest(
        quartzPoint: quartzPoint,
        button: button,
        hid: hid,
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
          at: request.quartzPoint,
          hid: request.hid,
          screenshot: captureBreadcrumbScreenshot(for: observation)
        )
        refreshInspector()
      }
      copySelector(observation.compactSelector)
      onSelectorCaptured?(observation.compactSelector, breadcrumbTrail)
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
    guard !isSuppressed else { return }
    guard !pointerIsOverRecordingControls(NSEvent.mouseLocation) else { return }
    guard let quartzPoint = CGEvent(source: nil)?.location else { return }
    hintEngine.sample(at: quartzPoint) { [weak self] observation in
      guard let self else { return }
      if isRecordingEnabled {
        breadcrumbTrail.updateLive(observation: observation)
      }
      latestObservation = observation
      refreshInspector()
    }
  }

  private func refreshInspector() {
    if let presentation = resolvedPresentation {
      inspectorView.update(
        selector: presentation.selector,
        hints: presentation.hints,
        providerReports: presentation.providerReports,
        breadcrumbs: presentation.breadcrumbs
      )
      return
    }
    guard let observation = latestObservation else { return }
    inspectorView.update(
      with: observation,
      breadcrumbs: breadcrumbTrail.rendered(current: observation, maximumLinks: 6)
    )
  }

  private func captureBreadcrumbScreenshot(
    for observation: SuperSelectorObservation
  ) -> BreadcrumbScreenshot? {
    guard !isCapturingScreenshot else { return nil }
    isCapturingScreenshot = true
    let cursor = observation.scene.cursorAppKit
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) else {
      isCapturingScreenshot = false
      return nil
    }
    let screenFrameQuartz = CoordinateSpaces.quartzRect(fromAppKit: screen.frame)
    let overlayPanels = [crosshairPanel] + targetEdgePanels + [recordingControlPanel]
    let visiblePanels = overlayPanels.filter(\.isVisible)
    let inspectorWasVisible = inspectorPanel.isVisible
    visiblePanels.forEach { $0.orderOut(nil) }
    inspectorPanel.orderOut(nil)
    onScreenshotCaptureVisibilityChanged?(true)
    defer {
      onScreenshotCaptureVisibilityChanged?(false)
      if !isSuppressed {
        visiblePanels.forEach { $0.orderFrontRegardless() }
        if inspectorWasVisible && !isReplayVisualizationActive {
          inspectorPanel.orderFrontRegardless()
        }
      }
      isCapturingScreenshot = false
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
    guard
      let image = CGWindowListCreateImage(
        screenFrameQuartz,
        .optionOnScreenOnly,
        kCGNullWindowID,
        [.bestResolution, .boundsIgnoreFraming]
      )
    else { return nil }
    guard let thumbnail = Self.downsample(image, maximumPixelSize: 1280) else { return nil }
    let representation = NSBitmapImageRep(cgImage: thumbnail)
    guard
      let data = representation.representation(
        using: .jpeg,
        properties: [.compressionFactor: 0.68]
      )
    else { return nil }
    return BreadcrumbScreenshot(jpegData: data, screenFrameQuartz: screenFrameQuartz)
  }

  private static func downsample(_ image: CGImage, maximumPixelSize: Int) -> CGImage? {
    let longestEdge = max(image.width, image.height)
    guard longestEdge > maximumPixelSize else { return image }
    let scale = CGFloat(maximumPixelSize) / CGFloat(longestEdge)
    let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
    let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
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
    guard !isRepeat, isRecordingEnabled else { return }
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
    let screenshot =
      breadcrumbTrail.screenshot(for: observation)
      ?? captureBreadcrumbScreenshot(for: observation)

    let independentModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    let hidEvent = KeyboardHIDEvent(
      virtualKeyCode: keyCode,
      modifierFlags: UInt64(independentModifiers.rawValue),
      text: text
    )
    let isCommand =
      independentModifiers.contains(.command)
      || independentModifiers.contains(.control)
    if !isCommand, Self.isPrintableText(text) {
      breadcrumbTrail.recordText(
        text, event: hidEvent, observation: observation, screenshot: screenshot)
    } else {
      breadcrumbTrail.recordKey(
        Self.keyDescription(keyCode: keyCode, text: text, modifiers: independentModifiers),
        event: hidEvent,
        observation: observation,
        screenshot: screenshot
      )
    }
    refreshInspector()
  }

  private func recordScroll(at point: CGPoint, deltaX: CGFloat, deltaY: CGFloat) {
    guard isRecordingEnabled,
      abs(deltaX) > 0.01 || abs(deltaY) > 0.01,
      let observation = recentBreadcrumbObservation(at: point) ?? latestObservation
    else { return }
    breadcrumbTrail.recordScroll(
      observation: observation,
      at: point,
      deltaX: deltaX,
      deltaY: deltaY,
      screenshot: breadcrumbTrail.screenshot(for: observation)
        ?? captureBreadcrumbScreenshot(for: observation)
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
