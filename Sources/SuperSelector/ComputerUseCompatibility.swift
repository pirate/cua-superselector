import Foundation

/// A model-facing accessibility node using the same ephemeral-index idea as
/// Codex Computer Use's `AppState.text`. The index belongs to one render-tree
/// revision; durable replay identity remains in the SuperSelector hints.
struct AccessibilityNode: Sendable, Equatable {
  let elementIndex: Int
  let depth: Int
  let role: String
  let name: String?
  let value: String?
  let nativeIdentifier: String?
  let enabled: Bool?
  let focused: Bool?
  let selected: Bool?
  let frameQuartz: CGRect?
  let secondaryActions: [String]
  var isTarget: Bool

  init(
    elementIndex: Int,
    depth: Int,
    role: String,
    name: String? = nil,
    value: String? = nil,
    nativeIdentifier: String? = nil,
    enabled: Bool? = nil,
    focused: Bool? = nil,
    selected: Bool? = nil,
    frameQuartz: CGRect? = nil,
    secondaryActions: [String] = [],
    isTarget: Bool = false
  ) {
    self.elementIndex = elementIndex
    self.depth = depth
    self.role = role
    self.name = name
    self.value = value
    self.nativeIdentifier = nativeIdentifier
    self.enabled = enabled
    self.focused = focused
    self.selected = selected
    self.frameQuartz = frameQuartz
    self.secondaryActions = secondaryActions
    self.isTarget = isTarget
  }
}

/// A revision-local tree rendered for agents. This deliberately mirrors
/// Computer Use terminology while remaining independent of its private IPC.
struct UIElementRenderTree: Sendable, Equatable {
  let applicationName: String?
  let bundleIdentifier: String?
  let windowTitle: String?
  var nodes: [AccessibilityNode]
  let truncated: Bool

  static let empty = UIElementRenderTree(
    applicationName: nil,
    bundleIdentifier: nil,
    windowTitle: nil,
    nodes: [],
    truncated: false
  )

  var targetElementIndex: Int? { nodes.first(where: \.isTarget)?.elementIndex }
  var focusedElementIndex: Int? { nodes.first(where: { $0.focused == true })?.elementIndex }

  func highlighting(_ target: AXElementSnapshot?) -> Self {
    guard let target else { return self }
    var copy = self
    let bestIndex = copy.nodes.indices.max { left, right in
      Self.matchScore(copy.nodes[left], target: target)
        < Self.matchScore(copy.nodes[right], target: target)
    }
    let score = bestIndex.map { Self.matchScore(copy.nodes[$0], target: target) } ?? 0
    for index in copy.nodes.indices { copy.nodes[index].isTarget = index == bestIndex && score > 0 }
    return copy
  }

  static func targetBranch(from target: AXElementSnapshot?) -> Self {
    guard let target else { return .empty }
    let ancestors = target.ancestorBreadcrumbNodes.reversed().filter {
      !["application", "window"].contains(ComputerUseNodeAPIRenderer.role($0.role))
    }
    var nodes = ancestors.enumerated().map { index, node in
      AccessibilityNode(
        elementIndex: index,
        depth: index,
        role: ComputerUseNodeAPIRenderer.role(node.role),
        name: ComputerUseNodeAPIRenderer.firstText(node.title, node.label, node.help),
        value: node.value,
        nativeIdentifier: node.identifier
      )
    }
    nodes.append(
      AccessibilityNode(
        elementIndex: nodes.count,
        depth: nodes.count,
        role: ComputerUseNodeAPIRenderer.role(target.role),
        name: ComputerUseNodeAPIRenderer.firstText(
          target.title, target.label, target.help, target.identifier),
        value: target.value,
        nativeIdentifier: target.identifier,
        enabled: target.enabled,
        focused: target.focused,
        selected: target.selected,
        frameQuartz: target.frameInQuartzCoordinates,
        secondaryActions: ComputerUseNodeAPIRenderer.secondaryActions(target.actions),
        isTarget: true
      ))
    return Self(
      applicationName: target.applicationName,
      bundleIdentifier: target.bundleIdentifier,
      windowTitle: target.windowTitle,
      nodes: nodes,
      truncated: false
    )
  }

  private static func matchScore(_ node: AccessibilityNode, target: AXElementSnapshot) -> Int {
    guard node.role == ComputerUseNodeAPIRenderer.role(target.role) else { return 0 }
    var score = 1
    if let identifier = target.identifier, node.nativeIdentifier == identifier { score += 100 }
    let targetName = ComputerUseNodeAPIRenderer.firstText(
      target.title, target.label, target.help, target.identifier)
    if targetName != nil, node.name == targetName { score += 20 }
    if let targetFrame = target.frameInQuartzCoordinates, let frame = node.frameQuartz,
      abs(targetFrame.minX - frame.minX) < 1,
      abs(targetFrame.minY - frame.minY) < 1,
      abs(targetFrame.width - frame.width) < 1,
      abs(targetFrame.height - frame.height) < 1
    {
      score += 50
    }
    return score
  }
}

enum ComputerUseNodeAPIRenderer {
  static func render(_ tree: UIElementRenderTree) -> String {
    let app = clean(tree.applicationName) ?? clean(tree.bundleIdentifier) ?? "Unknown App"
    var lines: [String] = []
    if let window = clean(tree.windowTitle) {
      lines.append("Window: \(quoted(window)), App: \(app).")
    } else {
      lines.append("App: \(app).")
    }

    for node in tree.nodes {
      var components = ["\(node.elementIndex)", node.role]
      if node.enabled == false { components.append("(disabled)") }
      if let text = firstText(node.name, node.value), text != node.role {
        components.append(cleanLine(text))
      }
      if node.selected == true { components.append("(selected)") }
      if !node.secondaryActions.isEmpty {
        components.append("Secondary Actions: \(node.secondaryActions.joined(separator: ", "))")
      }
      lines.append(String(repeating: "\t", count: max(0, node.depth)) + components.joined(separator: " "))
    }
    if tree.truncated { lines.append("… render tree truncated …") }
    if let focused = tree.focusedElementIndex,
      let node = tree.nodes.first(where: { $0.elementIndex == focused })
    {
      lines.append("")
      lines.append("The focused UI element is \(focused) \(node.role)\(node.name.map { " \(cleanLine($0))" } ?? "")")
    }
    return lines.joined(separator: "\n")
  }

  static func role(_ nativeRole: String?) -> String {
    guard var value = clean(nativeRole) else { return "element" }
    if value.hasPrefix("AX") { value.removeFirst(2) }
    let spaced = value.replacingOccurrences(
      of: "([a-z0-9])([A-Z])",
      with: "$1 $2",
      options: .regularExpression
    )
    return spaced.lowercased()
  }

  static func secondaryActions(_ nativeActions: [String]) -> [String] {
    nativeActions.compactMap { action in
      switch action {
      case "AXPress", "AXConfirm": return nil
      case "AXOpen": return "open"
      case "AXShowMenu": return "Show Menu"
      case "AXIncrement": return "Increment"
      case "AXDecrement": return "Decrement"
      case "AXCancel": return "Cancel"
      default:
        return action.hasPrefix("AX") ? String(action.dropFirst(2)) : action
      }
    }
  }

  static func firstText(_ values: String?...) -> String? {
    values.compactMap(clean).first
  }

  private static func clean(_ value: String?) -> String? {
    guard let value else { return nil }
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
  }

  private static func cleanLine(_ value: String) -> String {
    value.replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
  }

  private static func quoted(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
  }
}

/// A tiny cache prevents the hover inspector from rescanning an entire app on
/// every pointer sample. Cached nodes are re-highlighted against the current
/// durable target observation before presentation.
final class UIElementRenderTreeCache: @unchecked Sendable {
  private struct Entry {
    let key: String
    let capturedAt: TimeInterval
    let tree: UIElementRenderTree
  }

  private let lock = NSLock()
  private var entry: Entry?
  private let maximumAge: TimeInterval
  private let maximumElements: Int

  init(maximumAge: TimeInterval = 1.25, maximumElements: Int = 600) {
    self.maximumAge = maximumAge
    self.maximumElements = maximumElements
  }

  func tree(for target: AXElementSnapshot?) -> UIElementRenderTree {
    guard let target else { return .empty }
    let key = [
      target.bundleIdentifier ?? target.applicationBundlePath ?? target.applicationName ?? "",
      target.windowIdentifier ?? target.windowTitle ?? "",
    ].joined(separator: "\u{1f}")
    let now = ProcessInfo.processInfo.systemUptime
    lock.lock()
    if let entry, entry.key == key, now - entry.capturedAt < maximumAge {
      lock.unlock()
      return entry.tree.highlighting(target)
    }
    lock.unlock()

    let captured = AccessibilityInspector.computerUseRenderTree(
      around: target,
      maximumElements: maximumElements
    )
    lock.lock()
    entry = Entry(key: key, capturedAt: now, tree: captured)
    lock.unlock()
    return captured.highlighting(target)
  }
}
