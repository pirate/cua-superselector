import AppKit
import Foundation

struct SuperSelectorWorkflowLog: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 2

  var schemaVersion = currentSchemaVersion
  var workflows: [SuperSelectorWorkflow] = []
  var screenshotAssets: [UUID: WorkflowScreenshotAsset] = [:]

  mutating func upsert(_ workflow: SuperSelectorWorkflow) {
    workflows.removeAll { $0.id == workflow.id }
    workflows.insert(workflow, at: 0)
  }

  mutating func remove(id: UUID) {
    workflows.removeAll { $0.id == id }
  }

  func jsonData(prettyPrinted: Bool = true) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    return try encoder.encode(self)
  }

  init(jsonData: Data) throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    self = try decoder.decode(Self.self, from: jsonData)
    guard schemaVersion == Self.currentSchemaVersion else {
      throw SuperSelectorWorkflowError.unsupportedSchemaVersion(schemaVersion)
    }
  }

  init(
    workflows: [SuperSelectorWorkflow] = [],
    screenshotAssets: [UUID: WorkflowScreenshotAsset] = [:]
  ) {
    self.workflows = workflows
    self.screenshotAssets = screenshotAssets
  }

  func selecting(_ workflow: SuperSelectorWorkflow) -> Self {
    let ids = Set(workflow.breadcrumbs.compactMap { $0.screenshot?.assetID })
    return Self(
      workflows: [workflow],
      screenshotAssets: screenshotAssets.filter { ids.contains($0.key) }
    )
  }

  func write(to url: URL) throws { try jsonData().write(to: url, options: .atomic) }

  static func read(from url: URL) throws -> Self { try Self(jsonData: Data(contentsOf: url)) }

  func copyJSON(to pasteboard: NSPasteboard) throws {
    pasteboard.clearContents()
    pasteboard.setString(String(decoding: try jsonData(), as: UTF8.self), forType: .string)
  }

  static func read(from pasteboard: NSPasteboard) throws -> Self {
    guard let json = pasteboard.string(forType: .string) else {
      throw SuperSelectorWorkflowError.clipboardHasNoText
    }
    return try Self(jsonData: Data(json.utf8))
  }
}

struct SuperSelectorWorkflow: Codable, Identifiable, Equatable, Sendable {
  var id = UUID()
  var name: String
  var createdAt = Date()
  var updatedAt = Date()
  var breadcrumbs: [SuperSelectorWorkflowStep]
  var finalSelector: String

  init(
    id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date(),
    breadcrumbs: [SuperSelectorWorkflowStep], finalSelector: String
  ) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.breadcrumbs = breadcrumbs
    self.finalSelector = finalSelector
  }

  init(name: String, trail: BreadcrumbTrail, finalSelector: String, at date: Date = Date()) {
    self.init(
      name: name, createdAt: date, updatedAt: date,
      breadcrumbs: trail.links.map(SuperSelectorWorkflowStep.init),
      finalSelector: finalSelector)
  }

  mutating func append(_ step: SuperSelectorWorkflowStep, at date: Date = Date()) {
    breadcrumbs.append(step)
    updatedAt = date
  }

  mutating func replaceStep(at index: Int, with step: SuperSelectorWorkflowStep) throws {
    guard breadcrumbs.indices.contains(index) else {
      throw SuperSelectorWorkflowError.invalidStepIndex(index)
    }
    breadcrumbs[index] = step
    updatedAt = Date()
  }

  mutating func removeStep(at index: Int) throws {
    guard breadcrumbs.indices.contains(index) else {
      throw SuperSelectorWorkflowError.invalidStepIndex(index)
    }
    breadcrumbs.remove(at: index)
    updatedAt = Date()
  }

  func replayPlan(through index: Int) throws -> SuperSelectorReplayPlan {
    guard breadcrumbs.indices.contains(index) else {
      throw SuperSelectorWorkflowError.invalidStepIndex(index)
    }
    return SuperSelectorReplayPlan(
      steps: Array(breadcrumbs.prefix(through: index)),
      highlightSelector: breadcrumbs[index].selector
    )
  }

  var gotoPlan: SuperSelectorReplayPlan {
    SuperSelectorReplayPlan(steps: breadcrumbs, highlightSelector: finalSelector)
  }
}

struct SuperSelectorWorkflowStep: Codable, Identifiable, Equatable, Sendable {
  var id = UUID()
  var selector: String
  var targetPath: String
  var action: SuperSelectorWorkflowAction
  var screenshot: WorkflowScreenshot?
  var occurredAt = Date()

  init(_ link: SuperSelectorBreadcrumbLink) {
    selector = link.selector
    targetPath = link.targetPath
    action = SuperSelectorWorkflowAction(link.interaction)
    screenshot = link.screenshot.map {
      WorkflowScreenshot(
        assetID: $0.id,
        screenFrameQuartz: WorkflowRect($0.screenFrameQuartz),
        targetFrameQuartz: link.elementFrameQuartz.map(WorkflowRect.init),
        pointerQuartz: WorkflowPoint(link.pointerQuartz)
      )
    }
    occurredAt = link.occurredAt
  }

  init(
    id: UUID = UUID(), selector: String, targetPath: String,
    action: SuperSelectorWorkflowAction, screenshot: WorkflowScreenshot? = nil,
    occurredAt: Date = Date()
  ) {
    self.id = id
    self.selector = selector
    self.targetPath = targetPath
    self.action = action
    self.screenshot = screenshot
    self.occurredAt = occurredAt
  }
}

struct WorkflowScreenshot: Codable, Equatable, Sendable {
  var assetID: UUID
  var screenFrameQuartz: WorkflowRect
  var targetFrameQuartz: WorkflowRect?
  var pointerQuartz: WorkflowPoint

  var boxModel: SuperSelectorBoxModel {
    SuperSelectorBoxModel(
      screenQuartz: screenFrameQuartz.cgRect,
      targetQuartz: targetFrameQuartz?.cgRect,
      pointerQuartz: CGPoint(x: pointerQuartz.x, y: pointerQuartz.y)
    )
  }
}

struct WorkflowScreenshotAsset: Codable, Equatable, Sendable {
  var id: UUID
  var jpegData: Data
}

struct WorkflowRect: Codable, Equatable, Sendable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  init(x: Double, y: Double, width: Double, height: Double) {
    (self.x, self.y, self.width, self.height) = (x, y, width, height)
  }

  init(_ rect: CGRect) {
    self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
  }

  var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct SuperSelectorWorkflowAction: Codable, Equatable, Sendable {
  enum Kind: String, Codable, Sendable { case hover, click, scroll, type, key }

  var kind: Kind
  var offset: WorkflowPoint?
  var button: String?
  var deltaX: Double?
  var deltaY: Double?
  var value: String?
  var keyboardEvents: [KeyboardHIDEvent]?
  var pointerEvent: PointerHIDEvent?
  var scrollEvent: ScrollHIDEvent?

  init(_ interaction: BreadcrumbInteraction) {
    switch interaction {
    case .hover(let point):
      self.init(kind: .hover, offset: WorkflowPoint(point))
    case .click(let button, let point, let hid):
      self.init(
        kind: .click, offset: WorkflowPoint(point), button: button.storageName,
        pointerEvent: hid)
    case .scroll(let point, let deltaX, let deltaY, let hid):
      self.init(
        kind: .scroll, offset: WorkflowPoint(point), deltaX: deltaX, deltaY: deltaY,
        scrollEvent: hid)
    case .type(let text, let events):
      self.init(kind: .type, value: text, keyboardEvents: events)
    case .key(let key, let event):
      self.init(kind: .key, value: key, keyboardEvents: event.map { [$0] })
    }
  }

  init(
    kind: Kind, offset: WorkflowPoint? = nil, button: String? = nil,
    deltaX: Double? = nil, deltaY: Double? = nil, value: String? = nil,
    keyboardEvents: [KeyboardHIDEvent]? = nil, pointerEvent: PointerHIDEvent? = nil,
    scrollEvent: ScrollHIDEvent? = nil
  ) {
    self.kind = kind
    self.offset = offset
    self.button = button
    self.deltaX = deltaX
    self.deltaY = deltaY
    self.value = value
    self.keyboardEvents = keyboardEvents
    self.pointerEvent = pointerEvent
    self.scrollEvent = scrollEvent
  }
}

struct WorkflowPoint: Codable, Equatable, Sendable {
  var x: Double
  var y: Double

  init(x: Double, y: Double) { (self.x, self.y) = (x, y) }
  init(_ point: CGPoint) { (x, y) = (point.x, point.y) }
}

struct SuperSelectorReplayPlan: Equatable, Sendable {
  enum Reset: Equatable, Sendable { case normalizedEmptyDesktop }

  let reset: Reset = .normalizedEmptyDesktop
  let steps: [SuperSelectorWorkflowStep]
  let highlightSelector: String
}

enum SuperSelectorWorkflowError: Error, Equatable, LocalizedError {
  case invalidStepIndex(Int)
  case unsupportedSchemaVersion(Int)
  case clipboardHasNoText

  var errorDescription: String? {
    switch self {
    case .invalidStepIndex(let index):
      return "Workflow step \(index + 1) does not exist."
    case .unsupportedSchemaVersion(let version):
      return "Workflow schema version \(version) is not supported."
    case .clipboardHasNoText:
      return "The clipboard does not contain workflow JSON."
    }
  }
}

private extension BreadcrumbMouseButton {
  var storageName: String {
    switch self {
    case .left: return "left"
    case .right: return "right"
    case .middle: return "middle"
    case .other(let number): return "other:\(number)"
    }
  }
}
