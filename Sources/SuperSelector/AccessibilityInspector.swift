import AppKit
import ApplicationServices
import Foundation

enum AccessibilityInspector {
  private struct TraversalNode {
    let element: AXUIElement
    let ancestorRoles: [String]
    let windowIdentifier: String?
    let windowTitle: String?
  }

  private struct AncestorContext {
    var roles: [String] = []
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
            windowIdentifier: stringAttribute(window, kAXIdentifierAttribute),
            windowTitle: stringAttribute(window, kAXTitleAttribute)
          )
        }
      } else {
        queue = [
          TraversalNode(
            element: root,
            ancestorRoles: [],
            windowIdentifier: nil,
            windowTitle: nil
          )
        ]
        for window in windows {
          queue.append(
            TraversalNode(
              element: window,
              ancestorRoles: [kAXApplicationRole],
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
            windowIdentifier: nodeWindowIdentifier,
            windowTitle: nodeWindowTitle
          ), candidate.frameInQuartzCoordinates != nil
        {
          results.append(candidate)
        }

        let childAncestors = Array(
          ((nodeRole.map { [$0] } ?? []) + node.ancestorRoles).prefix(10))
        for child in descendants(of: node.element) {
          queue.append(
            TraversalNode(
              element: child,
              ancestorRoles: childAncestors,
              windowIdentifier: nodeWindowIdentifier,
              windowTitle: nodeWindowTitle
            ))
        }
      }
    }
    return results
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
      knownAncestorRoles == nil ? ancestorContext(of: element, maximumDepth: 10) : nil
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
    snapshot.ancestorRoles = knownAncestorRoles ?? context?.roles ?? []
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
      if let role = stringAttribute(parent, kAXRoleAttribute) {
        context.roles.append(role)
        if role == kAXWindowRole, context.windowIdentifier == nil, context.windowTitle == nil {
          context.windowIdentifier = stringAttribute(parent, kAXIdentifierAttribute)
          context.windowTitle = stringAttribute(parent, kAXTitleAttribute)
        }
      }
      current = parent
    }
    return context
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
