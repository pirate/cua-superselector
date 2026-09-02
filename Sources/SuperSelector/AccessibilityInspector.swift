import AppKit
import ApplicationServices
import Foundation

enum AccessibilityInspector {
  private final class SemanticAttributesBox {
    let value: [String: String]
    let capturedAt: TimeInterval
    init(_ value: [String: String], capturedAt: TimeInterval = ProcessInfo.processInfo.systemUptime)
    {
      self.value = value
      self.capturedAt = capturedAt
    }
  }

  private static let semanticAttributesCache: NSCache<NSString, SemanticAttributesBox> = {
    let cache = NSCache<NSString, SemanticAttributesBox>()
    cache.countLimit = 4_096
    return cache
  }()

  private struct TraversalNode {
    let element: AXUIElement
    let ancestorRoles: [String]
    let ancestorBreadcrumbNodes: [AXBreadcrumbNode]
    let windowIdentifier: String?
    let windowTitle: String?
  }

  private struct RenderTraversalNode {
    let element: AXUIElement
    let depth: Int
    let windowIdentifier: String?
    let windowTitle: String?
  }

  private struct AncestorContext {
    var roles: [String] = []
    var breadcrumbNodes: [AXBreadcrumbNode] = []
    var windowIdentifier: String?
    var windowTitle: String?
  }

  static func requestTrustPrompt() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  static func inspect(at quartzPoint: CGPoint) -> AXElementSnapshot? {
    guard AXIsProcessTrusted() else { return nil }

    let system = AXUIElementCreateSystemWide()
    var candidate: AXUIElement?
    let status = AXUIElementCopyElementAtPosition(
      system,
      Float(quartzPoint.x),
      Float(quartzPoint.y),
      &candidate
    )
    if status == .success, let element = candidate,
      let snapshot = snapshot(from: element)
    {
      return snapshot
    }

    if isNearMenuBar(quartzPoint) {
      return inspectMenuBar(at: quartzPoint)
    }
    return nil
  }

  static func snapshots(
    bundleIdentifier: String?,
    applicationBundlePath: String? = nil,
    applicationExecutablePath: String? = nil,
    windowIdentifier: String? = nil,
    windowTitle: String? = nil,
    role: String? = nil,
    subrole: String? = nil,
    identifier: String? = nil,
    identityValues: Set<String> = [],
    ancestorRolePath: String? = nil,
    maximumElements: Int = 12_000
  ) -> [AXElementSnapshot] {
    guard AXIsProcessTrusted() else { return [] }

    let applications: [NSRunningApplication]
    if let bundleIdentifier {
      applications = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      )
      .filter {
        (applicationBundlePath == nil || $0.bundleURL?.path == applicationBundlePath)
          && (applicationExecutablePath == nil
            || $0.executableURL?.path == applicationExecutablePath)
      }
    } else {
      applications = NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular || $0.activationPolicy == .accessory
      }.filter {
        (applicationBundlePath == nil || $0.bundleURL?.path == applicationBundlePath)
          && (applicationExecutablePath == nil
            || $0.executableURL?.path == applicationExecutablePath)
      }
    }

    var results: [AXElementSnapshot] = []
    var remaining = maximumElements
    for application in applications where remaining > 0 {
      let root = AXUIElementCreateApplication(application.processIdentifier)
      let windows = rootWindows(of: root)
      let matchingWindows = windows.filter { window in
        if let windowIdentifier {
          return stringAttribute(window, kAXIdentifierAttribute) == windowIdentifier
        }
        if let windowTitle {
          return stringAttribute(window, kAXTitleAttribute) == windowTitle
        }
        return false
      }
      var queue: [TraversalNode]
      if !matchingWindows.isEmpty {
        queue = matchingWindows.map { window in
          TraversalNode(
            element: window,
            ancestorRoles: [kAXApplicationRole],
            ancestorBreadcrumbNodes: [],
            windowIdentifier: stringAttribute(window, kAXIdentifierAttribute),
            windowTitle: stringAttribute(window, kAXTitleAttribute)
          )
        }
      } else {
        queue = [
          TraversalNode(
            element: root,
            ancestorRoles: [],
            ancestorBreadcrumbNodes: [],
            windowIdentifier: nil,
            windowTitle: nil
          )
        ]
        for window in windows {
          queue.append(
            TraversalNode(
              element: window,
              ancestorRoles: [kAXApplicationRole],
              ancestorBreadcrumbNodes: [],
              windowIdentifier: stringAttribute(window, kAXIdentifierAttribute),
              windowTitle: stringAttribute(window, kAXTitleAttribute)
            ))
        }
      }
      var index = 0
      var visited: Set<CFHashCode> = []

      while index < queue.count, remaining > 0 {
        let node = queue[index]
        index += 1
        let identity = CFHash(node.element)
        guard visited.insert(identity).inserted else { continue }
        remaining -= 1

        let nodeRole = stringAttribute(node.element, kAXRoleAttribute)
        let nodeWindowIdentifier =
          nodeRole == kAXWindowRole
          ? stringAttribute(node.element, kAXIdentifierAttribute) : node.windowIdentifier
        let nodeWindowTitle =
          nodeRole == kAXWindowRole
          ? stringAttribute(node.element, kAXTitleAttribute) : node.windowTitle
        if cheapMatch(
          element: node.element,
          role: nodeRole,
          expectedRole: role,
          expectedSubrole: subrole,
          expectedIdentifier: identifier,
          identityValues: identityValues,
          ancestorRoles: node.ancestorRoles,
          expectedAncestorRolePath: ancestorRolePath
        ),
          let candidate = snapshot(
            from: node.element,
            ancestorRoles: node.ancestorRoles,
            ancestorBreadcrumbNodes: node.ancestorBreadcrumbNodes,
            windowIdentifier: nodeWindowIdentifier,
            windowTitle: nodeWindowTitle
          ), candidate.frameInQuartzCoordinates != nil
        {
          results.append(candidate)
        }

        let childAncestors = Array(
          ((nodeRole.map { [$0] } ?? []) + node.ancestorRoles).prefix(10))
        let children = descendants(of: node.element)
        guard !children.isEmpty else { continue }
        let childBreadcrumbs = Array(
          ((breadcrumbNode(from: node.element, forceSemanticRefresh: true).map { [$0] } ?? [])
            + node.ancestorBreadcrumbNodes).prefix(24))
        for child in children {
          queue.append(
            TraversalNode(
              element: child,
              ancestorRoles: childAncestors,
              ancestorBreadcrumbNodes: childBreadcrumbs,
              windowIdentifier: nodeWindowIdentifier,
              windowTitle: nodeWindowTitle
            ))
        }
      }
    }
    return results
  }

  /// Captures the app's current AX hierarchy into the revision-local model that
  /// Studio renders beside its screenshot. The target is only a highlight;
  /// callers must not persist or replay `elementIndex` values from this tree.
  static func computerUseRenderTree(
    around target: AXElementSnapshot,
    maximumElements: Int = 600
  ) -> UIElementRenderTree {
    guard AXIsProcessTrusted(), maximumElements > 0 else {
      return .targetBranch(from: target)
    }

    let application = runningApplication(for: target)
    guard let application else { return .targetBranch(from: target) }
    let root = AXUIElementCreateApplication(application.processIdentifier)
    var roots = descendants(of: root)
    if roots.isEmpty { roots = rootWindows(of: root) }
    var stack = roots.reversed().map {
      RenderTraversalNode(
        element: $0,
        depth: 0,
        windowIdentifier: nil,
        windowTitle: nil
      )
    }
    var visited: Set<CFHashCode> = []
    var nodes: [AccessibilityNode] = []

    while let current = stack.popLast(), nodes.count < maximumElements {
      let identity = CFHash(current.element)
      guard visited.insert(identity).inserted else { continue }
      let nativeRole = stringAttribute(current.element, kAXRoleAttribute)
      let windowIdentifier =
        nativeRole == kAXWindowRole
        ? stringAttribute(current.element, kAXIdentifierAttribute) : current.windowIdentifier
      let windowTitle =
        nativeRole == kAXWindowRole
        ? stringAttribute(current.element, kAXTitleAttribute) : current.windowTitle
      guard
        let snapshot = snapshot(
          from: current.element,
          ancestorRoles: [],
          ancestorBreadcrumbNodes: [],
          windowIdentifier: windowIdentifier,
          windowTitle: windowTitle
        )
      else { continue }

      nodes.append(
        AccessibilityNode(
          elementIndex: nodes.count,
          depth: current.depth,
          role: ComputerUseNodeAPIRenderer.role(snapshot.role),
          name: ComputerUseNodeAPIRenderer.firstText(
            snapshot.title, snapshot.label, snapshot.help, snapshot.identifier),
          value: snapshot.value,
          nativeIdentifier: snapshot.identifier,
          enabled: snapshot.enabled,
          focused: snapshot.focused,
          selected: snapshot.selected,
          frameQuartz: snapshot.frameInQuartzCoordinates,
          secondaryActions: ComputerUseNodeAPIRenderer.secondaryActions(snapshot.actions)
        ))

      let children = descendants(of: current.element)
      for child in children.reversed() {
        stack.append(
          RenderTraversalNode(
            element: child,
            depth: current.depth + 1,
            windowIdentifier: windowIdentifier,
            windowTitle: windowTitle
          ))
      }
    }

    guard !nodes.isEmpty else { return .targetBranch(from: target) }
    return UIElementRenderTree(
      applicationName: target.applicationName ?? application.localizedName,
      bundleIdentifier: target.bundleIdentifier ?? application.bundleIdentifier,
      windowTitle: target.windowTitle,
      nodes: nodes,
      truncated: stack.isEmpty == false
    ).highlighting(target)
  }

  private static func runningApplication(for target: AXElementSnapshot) -> NSRunningApplication? {
    if let bundleIdentifier = target.bundleIdentifier,
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      ).first
    {
      return application
    }
    return NSWorkspace.shared.runningApplications.first { application in
      if let path = target.applicationBundlePath, application.bundleURL?.path == path { return true }
      if let executable = target.applicationExecutablePath,
        application.executableURL?.path == executable
      {
        return true
      }
      return target.applicationName != nil && application.localizedName == target.applicationName
    }
  }

  private static func cheapMatch(
    element: AXUIElement,
    role: String?,
    expectedRole: String?,
    expectedSubrole: String?,
    expectedIdentifier: String?,
    identityValues: Set<String>,
    ancestorRoles: [String],
    expectedAncestorRolePath: String?
  ) -> Bool {
    if let expectedRole, normalizedRole(role) != expectedRole { return false }
    if let expectedSubrole,
      stringAttribute(element, kAXSubroleAttribute) != expectedSubrole
    {
      return false
    }
    if let expectedIdentifier,
      stringAttribute(element, kAXIdentifierAttribute) != expectedIdentifier
    {
      return false
    }
    if !identityValues.isEmpty {
      let candidateValues = [
        stringAttribute(element, kAXTitleAttribute),
        stringAttribute(element, kAXDescriptionAttribute),
        stringAttribute(element, kAXHelpAttribute),
        displayString(attribute(element, kAXValueAttribute)),
      ].compactMap { $0 }
      if candidateValues.allSatisfy({ !identityValues.contains($0) }) {
        return false
      }
    }
    if let expectedAncestorRolePath {
      let candidatePath = ancestorRoles.reversed().compactMap { normalizedRole($0) }
        .joined(separator: ">")
      if candidatePath != expectedAncestorRolePath { return false }
    }
    return true
  }

  private static func normalizedRole(_ role: String?) -> String? {
    role?.replacingOccurrences(of: "AX", with: "").lowercased()
  }

  private static func snapshot(
    from element: AXUIElement,
    ancestorRoles knownAncestorRoles: [String]? = nil,
    ancestorBreadcrumbNodes knownAncestorBreadcrumbNodes: [AXBreadcrumbNode]? = nil,
    windowIdentifier knownWindowIdentifier: String? = nil,
    windowTitle knownWindowTitle: String? = nil
  ) -> AXElementSnapshot? {
    var processIdentifier: pid_t = 0
    AXUIElementGetPid(element, &processIdentifier)
    guard processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }

    var snapshot = AXElementSnapshot()

    if let app = NSRunningApplication(processIdentifier: processIdentifier) {
      snapshot.applicationName = app.localizedName
      snapshot.bundleIdentifier = app.bundleIdentifier
      snapshot.applicationBundlePath = app.bundleURL?.path
      snapshot.applicationExecutablePath = app.executableURL?.path
    }

    snapshot.role = stringAttribute(element, kAXRoleAttribute)
    let directWindow =
      snapshot.role == kAXWindowRole
      ? element : elementAttribute(element, kAXWindowAttribute)
    let context =
      knownAncestorRoles == nil ? ancestorContext(of: element, maximumDepth: 24) : nil
    snapshot.windowIdentifier =
      knownWindowIdentifier
      ?? directWindow.flatMap { stringAttribute($0, kAXIdentifierAttribute) }
      ?? context?.windowIdentifier
    snapshot.windowTitle =
      knownWindowTitle
      ?? directWindow.flatMap { stringAttribute($0, kAXTitleAttribute) }
      ?? context?.windowTitle

    snapshot.subrole = stringAttribute(element, kAXSubroleAttribute)
    snapshot.identifier = stringAttribute(element, kAXIdentifierAttribute)
    snapshot.title = stringAttribute(element, kAXTitleAttribute)
    snapshot.label = stringAttribute(element, kAXDescriptionAttribute)
    snapshot.help = stringAttribute(element, kAXHelpAttribute)
    snapshot.value = displayString(attribute(element, kAXValueAttribute))
    snapshot.enabled = boolAttribute(element, kAXEnabledAttribute)
    snapshot.focused = boolAttribute(element, kAXFocusedAttribute)
    snapshot.selected = boolAttribute(element, kAXSelectedAttribute)

    if let position = pointAttribute(element, kAXPositionAttribute),
      let size = sizeAttribute(element, kAXSizeAttribute),
      size.width > 0, size.height > 0
    {
      snapshot.frameInQuartzCoordinates = CGRect(origin: position, size: size)
    }
    snapshot.windowFrameInQuartzCoordinates = windowFrame(of: element)

    var actions: CFArray?
    if AXUIElementCopyActionNames(element, &actions) == .success {
      snapshot.actions = actions as? [String] ?? []
    }
    snapshot.ancestorRoles = knownAncestorRoles ?? Array((context?.roles ?? []).prefix(10))
    snapshot.ancestorBreadcrumbNodes =
      knownAncestorBreadcrumbNodes ?? context?.breadcrumbNodes ?? []
    return snapshot
  }

  static func focusedSnapshot(bundleIdentifier: String?) -> AXElementSnapshot? {
    guard AXIsProcessTrusted() else { return nil }
    let application: NSRunningApplication?
    if let bundleIdentifier {
      application =
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .first
    } else {
      application = NSWorkspace.shared.frontmostApplication
    }
    guard let application else { return nil }
    let root = AXUIElementCreateApplication(application.processIdentifier)
    guard let focused = elementAttribute(root, kAXFocusedUIElementAttribute) else { return nil }
    return snapshot(from: focused)
  }

  private static func isNearMenuBar(_ quartzPoint: CGPoint) -> Bool {
    let appKitPoint = CoordinateSpaces.appKitPoint(fromQuartz: quartzPoint)
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }) else {
      return false
    }
    return screen.frame.maxY - appKitPoint.y <= 64
  }

  private static func inspectMenuBar(at quartzPoint: CGPoint) -> AXElementSnapshot? {
    let workspace = NSWorkspace.shared
    let frontmostPID = workspace.frontmostApplication?.processIdentifier
    let applications = workspace.runningApplications
      .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
      .sorted { left, right in
        let leftRank = menuBarApplicationRank(left, frontmostPID: frontmostPID)
        let rightRank = menuBarApplicationRank(right, frontmostPID: frontmostPID)
        if leftRank != rightRank { return leftRank < rightRank }
        return left.processIdentifier < right.processIdentifier
      }

    for application in applications {
      let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
      var candidate: AXUIElement?
      let status = AXUIElementCopyElementAtPosition(
        applicationElement,
        Float(quartzPoint.x),
        Float(quartzPoint.y),
        &candidate
      )
      guard status == .success, let element = candidate,
        stringAttribute(element, kAXRoleAttribute) == kAXMenuBarItemRole
      else { continue }
      if let snapshot = snapshot(from: element) {
        return snapshot
      }
    }
    return nil
  }

  private static func menuBarApplicationRank(
    _ application: NSRunningApplication,
    frontmostPID: pid_t?
  ) -> Int {
    if application.processIdentifier == frontmostPID { return 0 }
    switch application.bundleIdentifier {
    case "com.apple.controlcenter", "com.apple.systemuiserver": return 1
    default: return 2
    }
  }

  private static func ancestorContext(of element: AXUIElement, maximumDepth: Int)
    -> AncestorContext
  {
    var context = AncestorContext()
    var current: AXUIElement? = element
    for _ in 0..<maximumDepth {
      guard let node = current,
        let parentValue = attribute(node, kAXParentAttribute),
        CFGetTypeID(parentValue) == AXUIElementGetTypeID()
      else { break }
      let parent = unsafeBitCast(parentValue, to: AXUIElement.self)
      if let breadcrumb = breadcrumbNode(from: parent) {
        context.roles.append(breadcrumb.role)
        context.breadcrumbNodes.append(breadcrumb)
        if breadcrumb.role == kAXWindowRole, context.windowIdentifier == nil,
          context.windowTitle == nil
        {
          context.windowIdentifier = breadcrumb.identifier
          context.windowTitle = breadcrumb.title
        }
      }
      current = parent
    }
    return context
  }

  private static func breadcrumbNode(
    from element: AXUIElement, forceSemanticRefresh: Bool = false
  ) -> AXBreadcrumbNode? {
    guard let role = stringAttribute(element, kAXRoleAttribute) else { return nil }
    let title = stringAttribute(element, kAXTitleAttribute)
    let label = stringAttribute(element, kAXDescriptionAttribute)
    let help = stringAttribute(element, kAXHelpAttribute)
    let value = displayString(attribute(element, kAXValueAttribute))
    let identifier = stringAttribute(element, kAXIdentifierAttribute)
    let needsSemanticFallback = [title, label, help, value, identifier].allSatisfy {
      $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }
    return AXBreadcrumbNode(
      role: role,
      subrole: stringAttribute(element, kAXSubroleAttribute),
      roleDescription: stringAttribute(element, kAXRoleDescriptionAttribute),
      title: title,
      label: label,
      help: help,
      value: value,
      identifier: identifier,
      semanticAttributes: needsSemanticFallback
        ? semanticAttributes(of: element, forceRefresh: forceSemanticRefresh) : [:]
    )
  }

  private static func semanticAttributes(
    of element: AXUIElement, forceRefresh: Bool = false
  ) -> [String: String] {
    var processIdentifier: pid_t = 0
    AXUIElementGetPid(element, &processIdentifier)
    let cacheKey = "\(processIdentifier):\(CFHash(element))" as NSString
    let now = ProcessInfo.processInfo.systemUptime
    if !forceRefresh, let cached = semanticAttributesCache.object(forKey: cacheKey),
      now - cached.capturedAt < 1
    {
      return cached.value
    }
    var namesValue: CFArray?
    guard AXUIElementCopyAttributeNames(element, &namesValue) == .success,
      let names = namesValue as? [String]
    else {
      semanticAttributesCache.setObject(SemanticAttributesBox([:]), forKey: cacheKey)
      return [:]
    }
    let semanticNames = names.filter { name in
      let lowered = name.lowercased()
      return lowered.contains("dom") || lowered.contains("aria")
        || lowered.contains("identifier") || lowered.contains("placeholder")
        || lowered.contains("description") || lowered.contains("help")
        || lowered.contains("title") || lowered.contains("url")
        || lowered.contains("document") || lowered.contains("class")
        || lowered.contains("label") || lowered.contains("name")
        || lowered.contains("customcontent")
    }
    var result: [String: String] = [:]
    for name in semanticNames.prefix(32) {
      guard let rawValue = attribute(element, name), let value = semanticString(rawValue) else {
        continue
      }
      result[name] = value.count > 512 ? String(value.prefix(511)) + "…" : value
    }
    semanticAttributesCache.setObject(SemanticAttributesBox(result), forKey: cacheKey)
    return result
  }

  private static func semanticString(_ value: CFTypeRef) -> String? {
    if CFGetTypeID(value) == CFStringGetTypeID() {
      guard let string = value as? String else { return nil }
      let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return cleaned.isEmpty ? nil : cleaned
    }
    if CFGetTypeID(value) == CFURLGetTypeID() {
      return (value as? URL)?.absoluteString
    }
    if CFGetTypeID(value) == AXUIElementGetTypeID() {
      return semanticText(of: unsafeBitCast(value, to: AXUIElement.self))
    }
    if CFGetTypeID(value) == CFArrayGetTypeID(), let values = value as? [Any] {
      let strings = values.compactMap { item -> String? in
        if let string = item as? String {
          let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
          return cleaned.isEmpty ? nil : cleaned
        }
        let rawItem = item as CFTypeRef
        if CFGetTypeID(rawItem) == AXUIElementGetTypeID() {
          return semanticText(of: unsafeBitCast(rawItem, to: AXUIElement.self))
        }
        return nil
      }
      return strings.isEmpty ? nil : strings.prefix(16).joined(separator: " ")
    }
    return nil
  }

  private static func semanticText(of element: AXUIElement) -> String? {
    for attributeName in [
      kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute,
      kAXIdentifierAttribute,
    ] {
      if let value = displayString(attribute(element, attributeName))?
        .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
      {
        return value
      }
    }
    return nil
  }

  private static func rootWindows(of application: AXUIElement) -> [AXUIElement] {
    var windows = elementArrayAttribute(application, kAXWindowsAttribute)
    for attributeName in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
      if let window = elementAttribute(application, attributeName) {
        windows.append(window)
      }
    }
    return windows
  }

  private static func descendants(of element: AXUIElement) -> [AXUIElement] {
    var descendants: [AXUIElement] = []
    for attributeName in [
      kAXChildrenAttribute,
      kAXVisibleChildrenAttribute,
      kAXContentsAttribute,
      kAXRowsAttribute,
    ] {
      descendants.append(contentsOf: elementArrayAttribute(element, attributeName))
    }
    return descendants
  }

  private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name),
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
  }

  private static func elementArrayAttribute(_ element: AXUIElement, _ name: String)
    -> [AXUIElement]
  {
    guard let value = attribute(element, name),
      CFGetTypeID(value) == CFArrayGetTypeID()
    else { return [] }
    return value as? [AXUIElement] ?? []
  }

  private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value
  }

  private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    guard let value = attribute(element, name) else { return nil }
    if CFGetTypeID(value) == CFStringGetTypeID() {
      return value as? String
    }
    return nil
  }

  private static func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
    guard let value = attribute(element, name), CFGetTypeID(value) == CFBooleanGetTypeID() else {
      return nil
    }
    return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
  }

  private static func pointAttribute(_ element: AXUIElement, _ name: String) -> CGPoint? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else {
      return nil
    }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgPoint else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
  }

  private static func sizeAttribute(_ element: AXUIElement, _ name: String) -> CGSize? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else {
      return nil
    }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgSize else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
  }

  private static func windowFrame(of element: AXUIElement) -> CGRect? {
    var window: AXUIElement?
    if stringAttribute(element, kAXRoleAttribute) == kAXWindowRole {
      window = element
    } else {
      window = elementAttribute(element, kAXWindowAttribute)
    }

    var current: AXUIElement? = element
    for _ in 0..<10 where window == nil {
      guard let node = current,
        let parent = elementAttribute(node, kAXParentAttribute)
      else { break }
      if stringAttribute(parent, kAXRoleAttribute) == kAXWindowRole {
        window = parent
      }
      current = parent
    }

    guard let window,
      let position = pointAttribute(window, kAXPositionAttribute),
      let size = sizeAttribute(window, kAXSizeAttribute),
      size.width > 0, size.height > 0
    else { return nil }
    return CGRect(origin: position, size: size)
  }

  private static func displayString(_ value: CFTypeRef?) -> String? {
    guard let value else { return nil }
    if CFGetTypeID(value) == CFStringGetTypeID() {
      return value as? String
    }
    if CFGetTypeID(value) == CFNumberGetTypeID() || CFGetTypeID(value) == CFBooleanGetTypeID() {
      return "\(value)"
    }
    return nil
  }
}
