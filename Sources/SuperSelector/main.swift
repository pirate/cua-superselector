import AppKit
import Foundation

private final class StatusItemHoverObserver: NSResponder {
  var onHoverChanged: ((Bool) -> Void)?

  override func mouseEntered(with event: NSEvent) {
    onHoverChanged?(true)
  }

  override func mouseExited(with event: NSEvent) {
    onHoverChanged?(false)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var overlay: OverlayCoordinator?
  private let workflowModel = WorkflowIDEModel()
  private var ideWindowController: WorkflowIDEWindowController?
  private var statusItem: NSStatusItem?
  private var statusItemHoverObserver: StatusItemHoverObserver?
  private var isStatusItemHovered = false
  private var isStatusMenuOpen = false
  private let recentTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    installStatusItem()
    let coordinator = OverlayCoordinator()
    coordinator.onSelectorCaptured = { [weak self] selector, trail in
      self?.recordWorkflow(selector: selector, trail: trail)
    }
    coordinator.onScreenshotCaptureVisibilityChanged = { [weak self] hidden in
      self?.statusItem?.isVisible = !hidden
    }
    overlay = coordinator
    installIDE(coordinator: coordinator)
    updateOverlaySuppression()
    coordinator.start()
    DispatchQueue.main.async { [weak self] in
      self?.ideWindowController?.present()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      ideWindowController?.present()
    }
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    workflowModel.flushPersistence()
    overlay?.stop()
  }

  private func installStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "scope", accessibilityDescription: "SuperSelector")
    if let button = item.button {
      let hoverObserver = StatusItemHoverObserver()
      hoverObserver.onHoverChanged = { [weak self] hovered in
        self?.isStatusItemHovered = hovered
        self?.updateOverlaySuppression()
      }
      button.addTrackingArea(
        NSTrackingArea(
          rect: button.bounds,
          options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
          owner: hoverObserver,
          userInfo: nil
        ))
      statusItemHoverObserver = hoverObserver
    }
    statusItem = item
    rebuildStatusMenu()
  }

  private func rebuildStatusMenu() {
    guard let statusItem else { return }
    let menu = NSMenu()
    menu.delegate = self
    let title = NSMenuItem(title: "SuperSelector is inspecting", action: nil, keyEquivalent: "")
    title.isEnabled = false
    menu.addItem(title)
    let studioItem = NSMenuItem(
      title: "Open SuperSelector Studio…",
      action: #selector(openStudio),
      keyEquivalent: "i"
    )
    studioItem.keyEquivalentModifierMask = [.command, .shift]
    studioItem.target = self
    studioItem.image = NSImage(
      systemSymbolName: "macwindow.and.cursorarrow",
      accessibilityDescription: "Open SuperSelector Studio"
    )
    menu.addItem(studioItem)
    menu.addItem(.separator())

    let recentHeader = NSMenuItem(title: "Recent Selectors", action: nil, keyEquivalent: "")
    recentHeader.isEnabled = false
    menu.addItem(recentHeader)
    if workflowModel.log.workflows.isEmpty {
      let empty = NSMenuItem(title: "No clicks recorded", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      empty.indentationLevel = 1
      menu.addItem(empty)
    } else {
      for workflow in workflowModel.log.workflows.prefix(15) {
        let item = NSMenuItem(
          title: recentSelectorTitle(workflow),
          action: #selector(resolveRecentSelector(_:)),
          keyEquivalent: ""
        )
        item.target = self
        item.representedObject = workflow.finalSelector
        item.toolTip = workflow.renderedBreadcrumbs()
        item.indentationLevel = 1
        item.image = NSImage(
          systemSymbolName: "cursorarrow.click", accessibilityDescription: "Recorded selector")
        menu.addItem(item)
      }
    }

    menu.addItem(.separator())
    let resolveItem = NSMenuItem(
      title: "Resolve selector…", action: #selector(resolveSelector), keyEquivalent: "")
    resolveItem.target = self
    menu.addItem(resolveItem)
    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: "Quit SuperSelector", action: #selector(quit), keyEquivalent: "")
    quitItem.target = self
    menu.addItem(quitItem)
    statusItem.menu = menu
  }

  func menuWillOpen(_ menu: NSMenu) {
    isStatusMenuOpen = true
    updateOverlaySuppression()
  }

  func menuDidClose(_ menu: NSMenu) {
    isStatusMenuOpen = false
    updateOverlaySuppression()
  }

  private func updateOverlaySuppression() {
    overlay?.setSuppressed(isStatusItemHovered || isStatusMenuOpen)
  }

  private func recordWorkflow(selector: String, trail: BreadcrumbTrail) {
    workflowModel.record(selector: selector, trail: trail)
    rebuildStatusMenu()
  }

  private func recentSelectorTitle(_ workflow: SuperSelectorWorkflow) -> String {
    let hints = (try? SuperSelectorDecoder.decode(workflow.finalSelector)) ?? []
    func value(_ kind: String) -> String? {
      hints.first { $0.kind == kind }?.value
    }

    var parts = [recentTimeFormatter.string(from: workflow.createdAt)]
    if let application = value("application.name") ?? value("application.bundle-id") {
      parts.append(application)
    }
    if let role = value("semantic.role") {
      parts.append(role)
    }
    if let name = value("semantic.name") ?? value("native.identifier")
      ?? value("semantic.value")
    {
      parts.append("“\(name)”")
    }
    if let point = value("pointer.position.screen") {
      parts.append("@ \(point)")
    }
    let title = parts.joined(separator: " · ")
    return title.count <= 100 ? title : String(title.prefix(99)) + "…"
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  @objc private func openStudio() {
    ideWindowController?.present()
  }

  @objc private func resolveSelector() {
    let input = NSTextView(frame: CGRect(x: 0, y: 0, width: 600, height: 170))
    input.isRichText = false
    input.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    if let clipboard = NSPasteboard.general.string(forType: .string),
      clipboard.hasPrefix("ss")
    {
      input.string = clipboard
    }

    let scroll = NSScrollView(frame: input.frame)
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.documentView = input

    let alert = NSAlert()
    alert.messageText = "Resolve selector"
    alert.informativeText =
      "Paste an ss3/e1 selector. Its screen provider will pin the crosshairs and outline for eight seconds."
    alert.accessoryView = scroll
    alert.addButton(withTitle: "Resolve")
    alert.addButton(withTitle: "Cancel")

    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    resolveAndShow(input.string)
  }

  @objc private func resolveRecentSelector(_ sender: NSMenuItem) {
    guard let selector = sender.representedObject as? String else { return }
    resolveAndShow(selector)
  }

  private func resolveAndShow(_ selector: String) {
    overlay?.showResolvedSelector(selector) { result in
      guard case .failure(let error) = result else { return }
      NSApp.activate(ignoringOtherApps: true)
      let failure = NSAlert(error: error)
      failure.runModal()
    }
  }

  private func installIDE(coordinator: OverlayCoordinator) {
    let controller = WorkflowIDEWindowController(model: workflowModel)
    controller.onVisibilityChanged = { [weak self, weak coordinator] visible in
      self?.workflowModel.setStudioVisible(visible)
      coordinator?.setSuppressed(visible)
      coordinator?.setRecordingEnabled(!visible)
      coordinator?.setRecordingControlsVisible(!visible)
    }
    ideWindowController = controller
    workflowModel.onLogChanged = { [weak self] in self?.rebuildStatusMenu() }
    workflowModel.prepareVisualDebugging = { [weak self, weak coordinator] in
      self?.ideWindowController?.dismissForVisualDebugging()
      coordinator?.setSuppressed(false)
      coordinator?.setRecordingEnabled(false)
      coordinator?.setRecordingControlsVisible(false)
      coordinator?.resetBreadcrumbTrail()
    }
    workflowModel.finishVisualDebugging = { [weak coordinator] in
      coordinator?.setRecordingEnabled(true)
    }
    workflowModel.prepareReplayVisualization = { [weak self, weak coordinator] in
      self?.ideWindowController?.dismissForVisualDebugging()
      coordinator?.setSuppressed(false)
      coordinator?.setRecordingEnabled(false)
      coordinator?.setRecordingControlsVisible(false)
      coordinator?.resetBreadcrumbTrail()
      coordinator?.setReplayVisualizationActive(true)
    }
    workflowModel.finishReplayVisualization = { [weak coordinator] in
      coordinator?.setReplayVisualizationActive(false)
      coordinator?.setRecordingEnabled(true)
    }
    workflowModel.prepareNewTrail = { [weak self, weak coordinator] in
      self?.ideWindowController?.dismissForVisualDebugging()
      coordinator?.setReplayVisualizationActive(false)
      coordinator?.setSuppressed(false)
      coordinator?.setRecordingEnabled(false)
      coordinator?.setRecordingControlsVisible(true)
      coordinator?.resetBreadcrumbTrail()
    }
    workflowModel.finishNewTrail = { [weak coordinator] in
      coordinator?.setRecordingEnabled(true)
    }
    coordinator.onRecordingEnded = { [weak self] in
      self?.ideWindowController?.present()
    }
    workflowModel.showReplayTarget = { [weak coordinator] target in
      coordinator?.showReplayTarget(target)
    }
    workflowModel.restoreIDE = { [weak self] in
      self?.ideWindowController?.present()
    }
    workflowModel.showResolved = { [weak coordinator] selector, breadcrumbs, completion in
      guard let coordinator else { return }
      coordinator.showResolvedSelector(
        selector,
        breadcrumbs: breadcrumbs,
        completion: completion
      )
    }
  }
}

MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.run()
}
