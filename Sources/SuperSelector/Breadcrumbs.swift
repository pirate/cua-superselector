import AppKit
import Foundation

enum BreadcrumbMouseButton: Sendable, Equatable {
  case left
  case right
  case middle
  case other(Int)

  var displayName: String {
    switch self {
    case .left: return "Left Click"
    case .right: return "Right Click"
    case .middle: return "Middle Click"
    case .other(let number): return "Button \(number) Click"
    }
  }
}

struct KeyboardHIDEvent: Codable, Sendable, Equatable {
  let virtualKeyCode: UInt16
  let modifierFlags: UInt64
  let text: String
  let isRepeat: Bool

  init(
    virtualKeyCode: UInt16, modifierFlags: UInt64, text: String, isRepeat: Bool = false
  ) {
    self.virtualKeyCode = virtualKeyCode
    self.modifierFlags = modifierFlags
    self.text = text
    self.isRepeat = isRepeat
  }
}

struct PointerHIDEvent: Codable, Sendable, Equatable {
  let buttonNumber: Int
  let modifierFlags: UInt64
  let clickCount: Int
  let pressure: Double
}

struct ScrollHIDEvent: Codable, Sendable, Equatable {
  let modifierFlags: UInt64
  let hasPreciseDeltas: Bool
  let isDirectionInvertedFromDevice: Bool
}

enum BreadcrumbInteraction: Sendable, Equatable {
  case hover(offset: CGPoint)
  case click(button: BreadcrumbMouseButton, offset: CGPoint, hid: PointerHIDEvent? = nil)
  case scroll(
    offset: CGPoint, deltaX: CGFloat, deltaY: CGFloat, hid: ScrollHIDEvent? = nil)
  case type(String, events: [KeyboardHIDEvent] = [])
  case key(String, event: KeyboardHIDEvent? = nil)
}

struct BreadcrumbScreenshot: Sendable, Equatable {
  let id: UUID
  let jpegData: Data
  let screenFrameQuartz: CGRect

  init(id: UUID = UUID(), jpegData: Data, screenFrameQuartz: CGRect) {
    (self.id, self.jpegData, self.screenFrameQuartz) = (id, jpegData, screenFrameQuartz)
  }
}

struct SuperSelectorBreadcrumbLink: Sendable, Equatable {
  let selector: String
  let targetPath: String
  let targetIdentity: String
  let interaction: BreadcrumbInteraction
  let elementFrameQuartz: CGRect?
  let pointerQuartz: CGPoint
  let screenshot: BreadcrumbScreenshot?
  let previousIndex: Int?
  let occurredAt: Date

  var subBreadcrumbs: [String] {
    [targetPath, BreadcrumbRenderer.interactionPath(for: interaction)]
  }
}

struct LiveSuperSelectorBreadcrumbLink: Sendable, Equatable {
  let selector: String
  let targetPath: String
  let interaction: BreadcrumbInteraction
  let previousIndex: Int?

  var subBreadcrumbs: [String] {
    [targetPath, BreadcrumbRenderer.interactionPath(for: interaction)]
  }
}

struct BreadcrumbTrail: Sendable {
  private struct LiveTarget: Sendable {
    let selector: String
    let targetPath: String
    let targetIdentity: String
    let cursorQuartz: CGPoint
    let elementFrameQuartz: CGRect?
    let screenshot: BreadcrumbScreenshot?
    let observedSince: Date
  }

  private(set) var links: [SuperSelectorBreadcrumbLink] = []
  private var tailIndex: Int?
  private var liveTarget: LiveTarget?
  private var liveTargetWasCommitted = false

  var currentScreenshot: BreadcrumbScreenshot? { liveTarget?.screenshot }

  func screenshot(
    for observation: SuperSelectorObservation,
    at quartzPoint: CGPoint? = nil
  ) -> BreadcrumbScreenshot? {
    guard liveTarget?.targetIdentity == BreadcrumbRenderer.targetIdentity(for: observation) else {
      return nil
    }
    guard let screenshot = liveTarget?.screenshot,
      screenshot.screenFrameQuartz.contains(quartzPoint ?? observation.scene.cursorQuartz)
    else { return nil }
    return screenshot
  }

  func needsScreenshot(
    for observation: SuperSelectorObservation,
    at date: Date = Date()
  ) -> Bool {
    guard let liveTarget,
      liveTarget.targetIdentity == BreadcrumbRenderer.targetIdentity(for: observation)
    else { return false }
    let screenshotFollowsPointer = liveTarget.screenshot?.screenFrameQuartz.contains(
      observation.scene.cursorQuartz
    ) == true
    return !screenshotFollowsPointer
      && date.timeIntervalSince(liveTarget.observedSince) >= 0.18
  }

  var currentLiveLink: LiveSuperSelectorBreadcrumbLink? {
    liveTarget.map {
      LiveSuperSelectorBreadcrumbLink(
        selector: $0.selector,
        targetPath: $0.targetPath,
        interaction: .hover(
          offset: mouseOffset(at: $0.cursorQuartz, currentFrame: $0.elementFrameQuartz)),
        previousIndex: tailIndex
      )
    }
  }

  mutating func updateLive(
    observation: SuperSelectorObservation,
    screenshot: BreadcrumbScreenshot? = nil,
    at date: Date = Date()
  ) {
    let target = LiveTarget(
      selector: observation.compactSelector,
      targetPath: BreadcrumbRenderer.targetPath(for: observation),
      targetIdentity: BreadcrumbRenderer.targetIdentity(for: observation),
      cursorQuartz: observation.scene.cursorQuartz,
      elementFrameQuartz: observation.scene.accessibilityElement?.frameInQuartzCoordinates,
      screenshot: screenshot,
      observedSince: date
    )
    guard let previous = liveTarget else {
      liveTarget = target
      liveTargetWasCommitted = false
      return
    }
    guard previous.targetIdentity != target.targetIdentity else {
      liveTarget = LiveTarget(
        selector: target.selector,
        targetPath: target.targetPath,
        targetIdentity: target.targetIdentity,
        cursorQuartz: target.cursorQuartz,
        elementFrameQuartz: target.elementFrameQuartz,
        screenshot: screenshot ?? previous.screenshot,
        observedSince: previous.observedSince
      )
      return
    }
    let movement = hypot(
      previous.cursorQuartz.x - target.cursorQuartz.x,
      previous.cursorQuartz.y - target.cursorQuartz.y
    )
    guard movement >= 4 else {
      liveTarget = target
      liveTargetWasCommitted = false
      return
    }
    if !liveTargetWasCommitted, date.timeIntervalSince(previous.observedSince) >= 0.18 {
      append(
        selector: previous.selector,
        targetPath: previous.targetPath,
        targetIdentity: previous.targetIdentity,
        interaction: .hover(
          offset: mouseOffset(
            at: previous.cursorQuartz,
            currentFrame: previous.elementFrameQuartz
          )),
        elementFrameQuartz: previous.elementFrameQuartz,
        pointerQuartz: previous.cursorQuartz,
        screenshot: previous.screenshot,
        at: date
      )
    }
    liveTarget = target
    liveTargetWasCommitted = false
  }

  mutating func recordClick(
    observation: SuperSelectorObservation,
    button: BreadcrumbMouseButton,
    at quartzPoint: CGPoint,
    hid: PointerHIDEvent? = nil,
    screenshot: BreadcrumbScreenshot? = nil,
    occurredAt: Date = Date()
  ) {
    updateLive(observation: observation, screenshot: screenshot, at: occurredAt)
    let frame = observation.scene.accessibilityElement?.frameInQuartzCoordinates
    append(
      selector: observation.compactSelector,
      targetPath: BreadcrumbRenderer.targetPath(for: observation),
      targetIdentity: BreadcrumbRenderer.targetIdentity(for: observation),
      interaction: .click(
        button: button,
        offset: mouseOffset(at: quartzPoint, currentFrame: frame),
        hid: hid
      ),
      elementFrameQuartz: frame,
      pointerQuartz: quartzPoint,
      screenshot: liveTarget?.screenshot ?? screenshot,
      at: occurredAt
    )
    liveTargetWasCommitted = true
  }

  mutating func recordScroll(
    observation: SuperSelectorObservation,
    at quartzPoint: CGPoint,
    deltaX: CGFloat,
    deltaY: CGFloat,
    hid: ScrollHIDEvent? = nil,
    screenshot: BreadcrumbScreenshot? = nil,
    occurredAt: Date = Date()
  ) {
    updateLive(observation: observation, screenshot: screenshot, at: occurredAt)
    let targetIdentity = BreadcrumbRenderer.targetIdentity(for: observation)
    let frame = observation.scene.accessibilityElement?.frameInQuartzCoordinates
    if let tailIndex,
      links[tailIndex].targetIdentity == targetIdentity,
      occurredAt.timeIntervalSince(links[tailIndex].occurredAt) <= 0.35,
      case .scroll(let offset, let previousX, let previousY, let previousHID) =
        links[tailIndex].interaction
    {
      let previous = links[tailIndex]
      links[tailIndex] = SuperSelectorBreadcrumbLink(
        selector: observation.compactSelector,
        targetPath: BreadcrumbRenderer.targetPath(for: observation),
        targetIdentity: targetIdentity,
        interaction: .scroll(
          offset: offset,
          deltaX: previousX + deltaX,
          deltaY: previousY + deltaY,
          hid: hid ?? previousHID
        ),
        elementFrameQuartz: frame,
        pointerQuartz: quartzPoint,
        screenshot: liveTarget?.screenshot ?? screenshot ?? previous.screenshot,
        previousIndex: previous.previousIndex,
        occurredAt: occurredAt
      )
    } else {
      append(
        selector: observation.compactSelector,
        targetPath: BreadcrumbRenderer.targetPath(for: observation),
        targetIdentity: targetIdentity,
        interaction: .scroll(
          offset: mouseOffset(at: quartzPoint, currentFrame: frame),
          deltaX: deltaX,
          deltaY: deltaY,
          hid: hid
        ),
        elementFrameQuartz: frame,
        pointerQuartz: quartzPoint,
        screenshot: liveTarget?.screenshot ?? screenshot,
        at: occurredAt
      )
    }
    liveTargetWasCommitted = true
  }

  mutating func recordText(
    _ text: String,
    event: KeyboardHIDEvent? = nil,
    observation: SuperSelectorObservation,
    screenshot: BreadcrumbScreenshot? = nil,
    occurredAt: Date = Date()
  ) {
    guard !text.isEmpty else { return }
    updateLive(observation: observation, screenshot: screenshot, at: occurredAt)
    let targetIdentity = BreadcrumbRenderer.targetIdentity(for: observation)
    if let tailIndex,
      links[tailIndex].targetIdentity == targetIdentity,
      occurredAt.timeIntervalSince(links[tailIndex].occurredAt) <= 0.6,
      case .type(let previousText, let previousEvents) = links[tailIndex].interaction
    {
      let previous = links[tailIndex]
      links[tailIndex] = SuperSelectorBreadcrumbLink(
        selector: observation.compactSelector,
        targetPath: BreadcrumbRenderer.targetPath(for: observation),
        targetIdentity: targetIdentity,
        interaction: .type(previousText + text, events: previousEvents + [event].compactMap { $0 }),
        elementFrameQuartz: observation.scene.accessibilityElement?.frameInQuartzCoordinates,
        pointerQuartz: observation.scene.cursorQuartz,
        screenshot: liveTarget?.screenshot ?? screenshot ?? previous.screenshot,
        previousIndex: previous.previousIndex,
        occurredAt: occurredAt
      )
    } else {
      append(
        selector: observation.compactSelector,
        targetPath: BreadcrumbRenderer.targetPath(for: observation),
        targetIdentity: targetIdentity,
        interaction: .type(text, events: [event].compactMap { $0 }),
        elementFrameQuartz: observation.scene.accessibilityElement?.frameInQuartzCoordinates,
        pointerQuartz: observation.scene.cursorQuartz,
        screenshot: liveTarget?.screenshot ?? screenshot,
        at: occurredAt
      )
    }
    liveTargetWasCommitted = true
  }

  mutating func recordKey(
    _ key: String,
    event: KeyboardHIDEvent? = nil,
    observation: SuperSelectorObservation,
    screenshot: BreadcrumbScreenshot? = nil,
    occurredAt: Date = Date()
  ) {
    updateLive(observation: observation, screenshot: screenshot, at: occurredAt)
    append(
      selector: observation.compactSelector,
      targetPath: BreadcrumbRenderer.targetPath(for: observation),
      targetIdentity: BreadcrumbRenderer.targetIdentity(for: observation),
      interaction: .key(key, event: event),
      elementFrameQuartz: observation.scene.accessibilityElement?.frameInQuartzCoordinates,
      pointerQuartz: observation.scene.cursorQuartz,
      screenshot: liveTarget?.screenshot ?? screenshot,
      at: occurredAt
    )
    liveTargetWasCommitted = true
  }

  private mutating func append(
    selector: String,
    targetPath: String,
    targetIdentity: String,
    interaction: BreadcrumbInteraction,
    elementFrameQuartz: CGRect?,
    pointerQuartz: CGPoint,
    screenshot: BreadcrumbScreenshot?,
    at date: Date
  ) {
    let index = links.count
    links.append(
      SuperSelectorBreadcrumbLink(
        selector: selector,
        targetPath: targetPath,
        targetIdentity: targetIdentity,
        interaction: interaction,
        elementFrameQuartz: elementFrameQuartz,
        pointerQuartz: pointerQuartz,
        screenshot: screenshot,
        previousIndex: tailIndex,
        occurredAt: date
      ))
    tailIndex = index
  }

  private func mouseOffset(at point: CGPoint, currentFrame: CGRect?) -> CGPoint {
    let anchor: CGPoint
    if let tailIndex {
      let previous = links[tailIndex]
      anchor = previous.elementFrameQuartz?.origin ?? previous.pointerQuartz
    } else {
      anchor = currentFrame?.origin ?? .zero
    }
    return CGPoint(x: point.x - anchor.x, y: point.y - anchor.y)
  }

  mutating func reset() {
    links.removeAll(keepingCapacity: true)
    tailIndex = nil
    liveTarget = nil
    liveTargetWasCommitted = false
  }

  mutating func suspendLiveTarget() {
    liveTarget = nil
    liveTargetWasCommitted = false
  }

  func rendered(current observation: SuperSelectorObservation, maximumLinks: Int? = nil) -> String {
    var orderedLinks: [SuperSelectorBreadcrumbLink] = []
    var index = tailIndex
    while let currentIndex = index {
      let link = links[currentIndex]
      orderedLinks.append(link)
      index = link.previousIndex
    }
    orderedLinks.reverse()
    if let maximumLinks, orderedLinks.count > maximumLinks {
      orderedLinks = Array(orderedLinks.suffix(maximumLinks))
    }

    var renderedLinks = orderedLinks.map { link in
      link.subBreadcrumbs.joined(separator: ", ")
    }
    if let currentLiveLink {
      renderedLinks.append(currentLiveLink.subBreadcrumbs.joined(separator: ", "))
    } else {
      renderedLinks.append(BreadcrumbRenderer.targetPath(for: observation))
    }
    return renderedLinks.joined(separator: "\n")
  }
}

struct DoubleEscapeResetDetector {
  var maximumInterval: TimeInterval = 0.8
  private var previousEscapeAt: Date?

  init(maximumInterval: TimeInterval = 0.8) {
    self.maximumInterval = maximumInterval
  }

  mutating func registerEscape(at date: Date = Date()) -> Bool {
    guard let previousEscapeAt,
      date.timeIntervalSince(previousEscapeAt) <= maximumInterval
    else {
      previousEscapeAt = date
      return false
    }
    self.previousEscapeAt = nil
    return true
  }

  mutating func registerOtherKey() {
    previousEscapeAt = nil
  }
}

enum BreadcrumbRenderer {
  static func interactionPath(for interaction: BreadcrumbInteraction) -> String {
    switch interaction {
    case .hover(let offset):
      return mousePath(action: "Hover", offset: offset)
    case .click(let button, let offset, _):
      return mousePath(action: button.displayName, offset: offset)
    case .scroll(let offset, let deltaX, let deltaY, _):
      return String(
        format: "[Mouse: Scroll > offset: x=%.0f,y=%.0f > dx=%.1f,dy=%.1f]",
        offset.x,
        offset.y,
        deltaX,
        deltaY
      )
    case .type(let text, _):
      return "[Keyboard: Type > \(quoted(text))]"
    case .key(let key, _):
      return "[Keyboard: Key > \(key)]"
    }
  }

  static func quoted(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
      .replacingOccurrences(of: "\t", with: "\\t")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  static func targetPath(for observation: SuperSelectorObservation) -> String {
    guard let element = observation.scene.accessibilityElement else {
      return String(
        format: "[Screen: %@ > Point: x=%.0f,y=%.0f]",
        observation.scene.displayIdentifier,
        observation.scene.cursorQuartz.x,
        observation.scene.cursorQuartz.y
      )
    }

    var components: [String] = []
    if let windowTitle = clean(element.windowTitle) {
      components.append("Window: \(windowTitle)")
    } else if let applicationName = clean(element.applicationName) {
      components.append("App: \(applicationName)")
    }

    for node in element.ancestorBreadcrumbNodes.reversed() {
      append(node: node, to: &components)
    }
    append(
      node: AXBreadcrumbNode(
        role: element.role ?? "AXUnknown",
        subrole: element.subrole,
        title: element.title,
        label: element.label,
        help: element.help,
        value: element.value,
        identifier: element.identifier
      ),
      isTarget: true,
      to: &components
    )

    let compacted = compact(components)
    return "[\(compacted.joined(separator: " > "))]"
  }

  static func targetIdentity(for observation: SuperSelectorObservation) -> String {
    guard let element = observation.scene.accessibilityElement else {
      return "screen:\(observation.scene.displayIdentifier)"
    }
    let editableRoles = ["AXTextArea", "AXTextField", "AXSearchField", "AXComboBox"]
    let isInsideEditableControl =
      editableRoles.contains(element.role ?? "")
      || element.ancestorBreadcrumbNodes.contains { editableRoles.contains($0.role) }
    let contentIdentity: [String?] =
      isInsideEditableControl
      ? []
      : [element.title, element.label, element.value]
    let frameIdentity =
      isInsideEditableControl
      ? nil
      : element.frameInQuartzCoordinates.map {
        String(format: "%.0f,%.0f,%.0f,%.0f", $0.minX, $0.minY, $0.width, $0.height)
      }
    return
      ([
        element.bundleIdentifier,
        element.windowIdentifier ?? element.windowTitle,
        element.role,
        element.subrole,
        element.identifier,
        frameIdentity,
        element.ancestorBreadcrumbNodes.reversed().compactMap {
          if isInsideEditableControl, editableRoles.contains($0.role) {
            return [
              $0.role,
              clean($0.title) ?? clean($0.label) ?? clean($0.identifier),
            ].compactMap { $0 }.joined(separator: ":")
          }
          if isInsideEditableControl { return $0.role }
          return clean($0.title) ?? clean($0.label)
        }.joined(separator: ">"),
      ] + contentIdentity).compactMap { $0 }.joined(separator: "\u{1f}")
  }

  private static func append(
    node: AXBreadcrumbNode,
    isTarget: Bool = false,
    to components: inout [String]
  ) {
    let role = normalizedRole(node.role)
    if role == "Application" || role == "Window" { return }

    let name =
      clean(node.title) ?? clean(node.label) ?? clean(node.value)
      ?? (isTarget ? clean(node.identifier) : nil)
    if let name {
      if !isTarget, ["Group", "Scroll Area"].contains(role), name.count > 48 {
        return
      }
      components.append("\(role): \(truncate(name))")
    } else if isTarget || isLandmark(role) {
      components.append(role)
    }
  }

  private static func compact(_ components: [String]) -> [String] {
    var result: [String] = []
    for component in components where result.last != component {
      result.append(component)
    }
    if result.count <= 10 { return result }
    return Array(result.prefix(2)) + ["…"] + Array(result.suffix(7))
  }

  private static func normalizedRole(_ role: String) -> String {
    let raw = role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
    switch raw {
    case "Button": return "Button"
    case "CheckBox": return "Checkbox"
    case "Column": return "Column"
    case "ComboBox": return "Combo Box"
    case "Group": return "Group"
    case "Image": return "Image"
    case "Link": return "Link"
    case "Menu": return "Menu"
    case "MenuBar": return "Menu Bar"
    case "MenuBarItem": return "Menu"
    case "MenuItem": return "Context Menu"
    case "Outline": return "Outline"
    case "PopUpButton": return "Pop-up"
    case "RadioButton": return "Option"
    case "Row": return "Row"
    case "ScrollArea": return "Scroll Area"
    case "Sheet": return "Sheet"
    case "StaticText": return "Text"
    case "TabGroup": return "Tab"
    case "Table": return "Table"
    case "TextArea", "TextField": return "Field"
    case "Toolbar": return "Toolbar"
    case "WebArea": return "Web Area"
    default:
      return raw.replacingOccurrences(
        of: "([a-z])([A-Z])",
        with: "$1 $2",
        options: .regularExpression
      )
    }
  }

  private static func isLandmark(_ role: String) -> Bool {
    ["Menu", "Menu Bar", "Outline", "Tab", "Table", "Toolbar", "Web Area"]
      .contains(role)
  }

  private static func clean(_ value: String?) -> String? {
    guard let value else { return nil }
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return cleaned.isEmpty ? nil : cleaned
  }

  private static func truncate(_ value: String) -> String {
    value.count <= 72 ? value : String(value.prefix(71)) + "…"
  }

  private static func mousePath(action: String, offset: CGPoint) -> String {
    String(
      format: "[Mouse: %@ > offset: x=%.0f,y=%.0f]",
      action,
      offset.x,
      offset.y
    )
  }
}
