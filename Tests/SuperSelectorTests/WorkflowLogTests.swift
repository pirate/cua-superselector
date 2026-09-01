import AppKit
import XCTest

@testable import SuperSelector

final class WorkflowLogTests: XCTestCase {
  func testWorkflowActionsPreserveGenericKeyboardAndPointerHIDMetadata() {
    let key = KeyboardHIDEvent(
      virtualKeyCode: 117,
      modifierFlags: UInt64(NSEvent.ModifierFlags([.command, .option]).rawValue),
      text: ""
    )
    let keyAction = SuperSelectorWorkflowAction(
      .key("⌥⌘KeyCode 117", event: key)
    )
    XCTAssertEqual(keyAction.keyboardEvents, [key])

    let pointer = PointerHIDEvent(
      buttonNumber: 7,
      modifierFlags: UInt64(NSEvent.ModifierFlags.control.rawValue),
      clickCount: 3,
      pressure: 0.75
    )
    let pointerAction = SuperSelectorWorkflowAction(
      .click(button: .other(7), offset: CGPoint(x: 4, y: 9), hid: pointer)
    )
    XCTAssertEqual(pointerAction.button, "other:7")
    XCTAssertEqual(pointerAction.pointerEvent, pointer)
  }

  func testScreenshotStoreLoadsOnDemandAndPrunesUnreferencedFiles() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let store = WorkflowScreenshotStore(baseDirectory: base)
    let retainedID = UUID()
    let removedID = UUID()
    try store.store(WorkflowScreenshotAsset(id: retainedID, jpegData: Data([1, 2, 3])))
    try store.store(WorkflowScreenshotAsset(id: removedID, jpegData: Data([4, 5, 6])))

    XCTAssertEqual(store.data(for: retainedID), Data([1, 2, 3]))
    store.prune(retaining: [retainedID])
    XCTAssertEqual(store.data(for: retainedID), Data([1, 2, 3]))
    XCTAssertNil(store.data(for: removedID))
  }

  func testJSONRoundTripAndFileImportExport() throws {
    let log = sampleLog()
    let decoded = try SuperSelectorWorkflowLog(jsonData: log.jsonData())

    XCTAssertEqual(decoded, log)
    XCTAssertTrue(
      String(decoding: try log.jsonData(), as: UTF8.self).contains("\"schemaVersion\" : 2"))

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }
    try log.write(to: url)
    XCTAssertEqual(try SuperSelectorWorkflowLog.read(from: url), log)
  }

  func testClipboardImportExport() throws {
    let pasteboard = NSPasteboard(name: .init("workflow-log-tests-\(UUID())"))
    let log = sampleLog()

    try log.copyJSON(to: pasteboard)

    XCTAssertEqual(try SuperSelectorWorkflowLog.read(from: pasteboard), log)
  }

  func testReplayToIndexAlwaysResetsAndUsesForwardPrefix() throws {
    let workflow = sampleWorkflow()

    let plan = try workflow.replayPlan(through: 0)

    XCTAssertEqual(plan.reset, .normalizedEmptyDesktop)
    XCTAssertEqual(plan.steps.map(\.selector), ["ss3/first"])
    XCTAssertEqual(plan.highlightSelector, "ss3/first")
    XCTAssertEqual(workflow.gotoPlan.steps, workflow.breadcrumbs)
    XCTAssertEqual(workflow.gotoPlan.highlightSelector, "ss3/final")
    XCTAssertThrowsError(try workflow.replayPlan(through: 2))
  }

  func testEditingAndLogUpsert() throws {
    var workflow = sampleWorkflow()
    let replacement = SuperSelectorWorkflowStep(
      selector: "ss3/edited", targetPath: "[Button: Edited]",
      action: .init(kind: .click, offset: .init(x: 2, y: 3), button: "left"))

    try workflow.replaceStep(at: 0, with: replacement)
    workflow.append(
      .init(selector: "ss3/key", targetPath: "[Field]", action: .init(kind: .key, value: "return")))
    try workflow.removeStep(at: 1)
    var log = SuperSelectorWorkflowLog()
    log.upsert(workflow)
    var renamed = workflow
    renamed.name = "Renamed"
    log.upsert(renamed)

    XCTAssertEqual(log.workflows.count, 1)
    XCTAssertEqual(log.workflows[0].name, "Renamed")
    XCTAssertEqual(log.workflows[0].breadcrumbs.map(\.selector), ["ss3/edited", "ss3/key"])
  }

  func testBreadcrumbInteractionConvertsToEditableAction() {
    let action = SuperSelectorWorkflowAction(
      .scroll(offset: CGPoint(x: 4, y: 5), deltaX: 1.5, deltaY: -7))

    XCTAssertEqual(action.kind, .scroll)
    XCTAssertEqual(action.offset, WorkflowPoint(x: 4, y: 5))
    XCTAssertEqual(action.deltaX, 1.5)
    XCTAssertEqual(action.deltaY, -7)
  }

  func testSharedBoxModelProjectsAndRetargetsRecordedPoint() {
    let model = SuperSelectorBoxModel(
      screenQuartz: CGRect(x: 100, y: 200, width: 1000, height: 500),
      targetQuartz: CGRect(x: 300, y: 300, width: 200, height: 100),
      pointerQuartz: CGPoint(x: 350, y: 350)
    )

    let topLeft = model.projection(
      in: CGRect(x: 0, y: 0, width: 500, height: 250),
      origin: .topLeft
    )
    let bottomLeft = model.projection(
      in: CGRect(x: 0, y: 0, width: 500, height: 250),
      origin: .bottomLeft
    )

    XCTAssertEqual(topLeft.pointer, CGPoint(x: 125, y: 75))
    XCTAssertEqual(bottomLeft.pointer, CGPoint(x: 125, y: 175))
    let cursorMovedDown = SuperSelectorBoxModel(
      screenQuartz: model.screenQuartz,
      targetQuartz: model.targetQuartz,
      pointerQuartz: CGPoint(x: 350, y: 450)
    ).projection(
      in: CGRect(x: 0, y: 0, width: 500, height: 250),
      origin: .topLeft
    )
    XCTAssertGreaterThan(cursorMovedDown.pointer.y, topLeft.pointer.y)
    XCTAssertEqual(
      model.pointer(retargetedTo: CGRect(x: 800, y: 600, width: 400, height: 200)),
      CGPoint(x: 900, y: 700)
    )
  }

  func testBoxModelClipsStaleAndVirtualDesktopFramesToActiveDisplay() {
    let canvas = CGRect(x: 10, y: 20, width: 500, height: 250)
    let projection = SuperSelectorBoxModel(
      screenQuartz: CGRect(x: 100, y: 200, width: 1000, height: 500),
      windowQuartz: CGRect(x: -4_000, y: -4_000, width: 12_000, height: 12_000),
      targetQuartz: CGRect(x: 1_050, y: 650, width: 200, height: 100),
      pointerQuartz: CGPoint(x: 9_000, y: -9_000)
    ).projection(in: canvas, origin: .topLeft)

    XCTAssertEqual(projection.window, canvas)
    XCTAssertEqual(projection.target, CGRect(x: 485, y: 245, width: 25, height: 25))
    XCTAssertEqual(projection.pointer, CGPoint(x: canvas.maxX, y: canvas.minY))

    let outside = SuperSelectorBoxModel(
      screenQuartz: CGRect(x: 100, y: 200, width: 1000, height: 500),
      targetQuartz: CGRect(x: 2_000, y: 2_000, width: 100, height: 100),
      pointerQuartz: CGPoint(x: 200, y: 300)
    ).projection(in: canvas, origin: .topLeft)
    XCTAssertNil(outside.target)
  }

  private func sampleWorkflow() -> SuperSelectorWorkflow {
    SuperSelectorWorkflow(
      name: "Checkout",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      breadcrumbs: [
        .init(
          selector: "ss3/first", targetPath: "[Button: Buy]",
          action: .init(kind: .click, offset: .init(x: 12, y: 8), button: "left"),
          screenshot: WorkflowScreenshot(
            assetID: sampleScreenshotID,
            screenFrameQuartz: .init(x: 0, y: 0, width: 1440, height: 900),
            targetFrameQuartz: .init(x: 100, y: 120, width: 80, height: 32),
            pointerQuartz: .init(x: 125, y: 136)
          ),
          occurredAt: Date(timeIntervalSince1970: 1.5)),
        .init(
          selector: "ss3/second", targetPath: "[Field: Email]",
          action: .init(kind: .type, value: "dev@openai.com"),
          occurredAt: Date(timeIntervalSince1970: 1.75)),
      ],
      finalSelector: "ss3/final")
  }

  private var sampleScreenshotID: UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  }

  private func sampleLog() -> SuperSelectorWorkflowLog {
    SuperSelectorWorkflowLog(
      workflows: [sampleWorkflow()],
      screenshotAssets: [
        sampleScreenshotID: WorkflowScreenshotAsset(
          id: sampleScreenshotID,
          jpegData: Data([0xff, 0xd8, 0xff, 0xd9])
        )
      ]
    )
  }
}
