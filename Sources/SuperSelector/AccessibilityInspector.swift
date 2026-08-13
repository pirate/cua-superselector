import AppKit
import ApplicationServices
import Foundation

enum AccessibilityInspector {
  private struct TraversalNode {
    let element: AXUIElement
    let ancestorRoles: [String]
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
    maximumElements: Int = 12_000
  ) -> [AXElementSnapshot] {
    guard AXIsProcessTrusted() else { return [] }

    let applications: [NSRunningApplication]
    if let bundleIdentifier {
      applications = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier)
    } else {
      applications = NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular || $0.activationPolicy == .accessory
      }
    }

    var results: [AXElementSnapshot] = []
    var remaining = maximumElements
    for application in applications where remaining > 0 {
      let root = AXUIElementCreateApplication(application.processIdentifier)
      var queue = [TraversalNode(element: root, ancestorRoles: [])]
      var index = 0
      var visited: Set<CFHashCode> = []

      while index < queue.count, remaining > 0 {
        let node = queue[index]
        index += 1
        let identity = CFHash(node.element)
        guard visited.insert(identity).inserted else { continue }
        remaining -= 1

        if let candidate = snapshot(from: node.element, ancestorRoles: node.ancestorRoles),
          candidate.frameInQuartzCoordinates != nil
        {
          results.append(candidate)
        }

        let parentRole = stringAttribute(node.element, kAXRoleAttribute)
        let childAncestors = Array(
          ((parentRole.map { [$0] } ?? []) + node.ancestorRoles).prefix(10))
        for child in children(of: node.element) {
          queue.append(TraversalNode(element: child, ancestorRoles: childAncestors))
        }
      }
    }
    return results
  }

  private static func snapshot(
    from element: AXUIElement,
    ancestorRoles knownAncestorRoles: [String]? = nil
  ) -> AXElementSnapshot? {
    var processIdentifier: pid_t = 0
    AXUIElementGetPid(element, &processIdentifier)
    guard processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }

    var snapshot = AXElementSnapshot()
    snapshot.processIdentifier = processIdentifier

    if let app = NSRunningApplication(processIdentifier: snapshot.processIdentifier) {
      snapshot.applicationName = app.localizedName
      snapshot.bundleIdentifier = app.bundleIdentifier
    }

    snapshot.role = stringAttribute(element, kAXRoleAttribute)
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

    var actions: CFArray?
    if AXUIElementCopyActionNames(element, &actions) == .success {
      snapshot.actions = actions as? [String] ?? []
    }
    snapshot.ancestorRoles = knownAncestorRoles ?? ancestorRoles(of: element, maximumDepth: 10)
    return snapshot
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

  private static func ancestorRoles(of element: AXUIElement, maximumDepth: Int) -> [String] {
    var roles: [String] = []
    var current: AXUIElement? = element
    for _ in 0..<maximumDepth {
      guard let node = current,
        let parentValue = attribute(node, kAXParentAttribute),
        CFGetTypeID(parentValue) == AXUIElementGetTypeID()
      else { break }
      let parent = unsafeBitCast(parentValue, to: AXUIElement.self)
      if let role = stringAttribute(parent, kAXRoleAttribute) {
        roles.append(role)
      }
      current = parent
    }
    return roles
  }

  private static func children(of element: AXUIElement) -> [AXUIElement] {
    guard let value = attribute(element, kAXChildrenAttribute),
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
