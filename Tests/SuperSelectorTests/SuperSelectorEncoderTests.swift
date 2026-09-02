import XCTest

@testable import SuperSelector

final class SuperSelectorEncoderTests: XCTestCase {
  func testComputerUseNodeAPIRendererMatchesAgentFacingGrammar() {
    let tree = UIElementRenderTree(
      applicationName: "Finder",
      bundleIdentifier: "com.apple.finder",
      windowTitle: "Desktop",
      nodes: [
        AccessibilityNode(
          elementIndex: 0, depth: 0, role: "scroll area", name: "desktop",
          enabled: false),
        AccessibilityNode(
          elementIndex: 1, depth: 1, role: "container", name: "desktop",
          focused: true),
        AccessibilityNode(
          elementIndex: 2, depth: 2, role: "image", name: "Archive",
          secondaryActions: ["open"], isTarget: true),
      ],
      truncated: false
    )

    XCTAssertEqual(
      ComputerUseNodeAPIRenderer.render(tree),
      """
      Window: \"Desktop\", App: Finder.
      0 scroll area (disabled) desktop
      \t1 container desktop
      \t\t2 image Archive Secondary Actions: open

      The focused UI element is 1 container desktop
      """
    )
    XCTAssertEqual(tree.targetElementIndex, 2)
    XCTAssertEqual(tree.focusedElementIndex, 1)
  }

  func testComputerUseRenderTreeHighlightsCurrentTargetWithoutPersistingIndex() {
    var target = AXElementSnapshot()
    target.applicationName = "Example"
    target.role = "AXButton"
    target.identifier = "save"
    target.title = "Save"
    target.frameInQuartzCoordinates = CGRect(x: 40, y: 50, width: 80, height: 30)
    let tree = UIElementRenderTree(
      applicationName: "Example",
      bundleIdentifier: "com.example",
      windowTitle: nil,
      nodes: [
        AccessibilityNode(
          elementIndex: 19, depth: 0, role: "button", name: "Save",
          nativeIdentifier: "save", frameQuartz: target.frameInQuartzCoordinates)
      ],
      truncated: false
    ).highlighting(target)

    XCTAssertEqual(tree.targetElementIndex, 19)
    XCTAssertTrue(ComputerUseNodeAPIRenderer.render(tree).contains("19 button Save"))
  }

  func testRecentHistoryExactlyDeduplicatesAndMovesNewestFirst() {
    var history = RecentSelectorHistory(maximumEntries: 3)
    history.record("first", at: Date(timeIntervalSince1970: 1))
    history.record("second", at: Date(timeIntervalSince1970: 2))
    history.record("first", at: Date(timeIntervalSince1970: 2))
    history.record("third", at: Date(timeIntervalSince1970: 3))

    XCTAssertEqual(history.entries.map(\.selector), ["third", "first", "second"])
    XCTAssertEqual(history.entries.map(\.capturedAt.timeIntervalSince1970), [3, 2, 2])
  }

  func testGlobalCoordinatesBecomeLocalOnNonPrimaryDisplay() {
    let secondaryFrame = CGRect(x: -3953, y: 1329, width: 3360, height: 1890)
    let cursor = CGPoint(x: -3000, y: 2500)
    let element = CGRect(x: -3100, y: 2400, width: 200, height: 80)

    XCTAssertEqual(
      SuperSelectorBoxModel.local(cursor, in: secondaryFrame),
      CGPoint(x: 953, y: 1171)
    )
    XCTAssertEqual(
      SuperSelectorBoxModel.local(element, in: secondaryFrame),
      CGRect(x: 853, y: 1071, width: 200, height: 80)
    )
  }

  func testWindowRelativeProviderUsesQuartzTopLeftOrigin() {
    var element = AXElementSnapshot()
    element.frameInQuartzCoordinates = CGRect(x: 130, y: 210, width: 100, height: 40)
    element.windowFrameInQuartzCoordinates = CGRect(x: 100, y: 200, width: 800, height: 600)
    let scene = SceneSnapshot(
      sampledAt: Date(),
      cursorQuartz: CGPoint(x: 150, y: 225),
      cursorAppKit: .zero,
      displayFrameAppKit: .zero,
      displayIdentifier: "test",
      accessibilityTrusted: true,
      accessibilityElement: element
    )

    let hints = Dictionary(
      uniqueKeysWithValues: WindowRelativeHintProvider().hints(for: scene).map { ($0.kind, $0) })
    XCTAssertEqual(hints["window.frame.screen"]?.value, "x=100.0,y=200.0,w=800.0,h=600.0")
    XCTAssertEqual(hints["pointer.position.window"]?.value, "50.0,25.0")
    XCTAssertEqual(hints["element.frame.window"]?.value, "x=30.0,y=10.0,w=100.0,h=40.0")
    XCTAssertEqual(hints["pointer.position.window"]?.valueType, .scalar)
  }

  func testScalarMoveChangesOnlyRawScalarCharacters() {
    let first = SuperSelectorEncoder.encode([
      Hint(
        provider: "screen.absolute",
        kind: "pointer.position.screen",
        band: "geometry",
        value: "100.0,200.0",
        valueType: .scalar,
        metadata: ["origin": "top-left"]
      )
    ])
    let second = SuperSelectorEncoder.encode([
      Hint(
        provider: "screen.absolute",
        kind: "pointer.position.screen",
        band: "geometry",
        value: "101.0,201.0",
        valueType: .scalar,
        metadata: ["origin": "top-left"]
      )
    ])

    XCTAssertEqual(
      first.replacingOccurrences(of: "v100.0%2C200.0", with: "v101.0%2C201.0"),
      second
    )
  }

  func testTextAndMetadataRemainExactAndPrefixPreserving() {
    let selector = SuperSelectorEncoder.encode([
      Hint(
        provider: "mac.ax",
        kind: "semantic.name",
        band: "content",
        value: "Continue to checkout",
        metadata: ["native": "AXTitle"]
      )
    ])

    XCTAssertTrue(selector.hasPrefix("ss3/e1~pmac.ax|bcontent|ksemantic.name|ts|vContinue"))
    XCTAssertTrue(selector.contains("Continue%20to%20checkout"))
    XCTAssertTrue(selector.contains("native=AXTitle"))
  }

  func testSelectorRoundTripsAndScreenOnlySelectorUsesCoordinates() throws {
    let hints = [
      Hint(
        provider: "screen.absolute",
        kind: "pointer.position.screen",
        band: "geometry",
        value: "100.0,200.0",
        valueType: .scalar,
        metadata: ["origin": "top-left", "space": "quartz-global"]
      )
    ]
    let selector = SuperSelectorEncoder.encode(hints)

    let decoded = try SuperSelectorDecoder.decode(selector)
    XCTAssertEqual(decoded.map(\.canonicalRecord), hints.map(\.canonicalRecord))

    let expectedPoint = CGPoint(x: 100, y: CoordinateSpaces.primaryScreenTop - 200)
    let resolved = try SelectorResolver.resolve(
      selector,
      screenFrames: [
        CGRect(x: 0, y: expectedPoint.y - 100, width: 500, height: 200)
      ]
    )
    XCTAssertEqual(resolved.pointAppKit, expectedPoint)
  }

  func testAccessibilityResolutionUsesMovedFrameAndPreservesClickOffset() throws {
    let hints = [
      Hint(
        provider: "screen.absolute",
        kind: "pointer.position.screen",
        band: "geometry",
        value: "125.0,240.0",
        valueType: .scalar
      ),
      Hint(
        provider: "screen.absolute",
        kind: "element.frame.screen",
        band: "geometry",
        value: "x=100.0,y=200.0,w=100.0,h=80.0",
        valueType: .scalar
      ),
      Hint(
        provider: "mac.ax",
        kind: "application.bundle-id",
        band: "scope",
        value: "com.example.browser"
      ),
      Hint(
        provider: "mac.ax",
        kind: "window.identifier",
        band: "scope",
        value: "settings-window"
      ),
      Hint(
        provider: "mac.ax",
        kind: "window.title",
        band: "scope",
        value: "Settings"
      ),
      Hint(
        provider: "mac.ax",
        kind: "semantic.role",
        band: "semantic",
        value: "button"
      ),
      Hint(
        provider: "mac.ax",
        kind: "semantic.name",
        band: "content",
        value: "Continue"
      ),
    ]
    let movedFrame = CGRect(x: 300, y: 700, width: 200, height: 120)
    var candidate = AXElementSnapshot()
    candidate.bundleIdentifier = "com.example.browser"
    candidate.windowIdentifier = "settings-window"
    candidate.windowTitle = "Settings"
    candidate.role = "AXButton"
    candidate.title = "Continue"
    candidate.frameInQuartzCoordinates = movedFrame

    let expectedQuartzPoint = CGPoint(x: 350, y: 760)
    let expectedAppKitPoint = CoordinateSpaces.appKitPoint(fromQuartz: expectedQuartzPoint)
    let result = try SelectorResolver.resolve(
      SuperSelectorEncoder.encode(hints),
      screenFrames: [
        CGRect(x: 0, y: expectedAppKitPoint.y - 200, width: 1000, height: 400)
      ],
      accessibilityCandidates: [candidate]
    )

    XCTAssertEqual(result.pointAppKit, expectedAppKitPoint)
    XCTAssertEqual(
      result.elementFrameAppKit,
      CoordinateSpaces.appKitRect(fromQuartz: movedFrame)
    )
  }

  func testGeometryCannotBreakAnIdentityTie() throws {
    let hints = [
      Hint(
        provider: "screen.absolute",
        kind: "pointer.position.screen",
        band: "geometry",
        value: "110.0,110.0",
        valueType: .scalar
      ),
      Hint(
        provider: "mac.ax",
        kind: "application.bundle-id",
        band: "scope",
        value: "com.example.app"
      ),
      Hint(
        provider: "mac.ax",
        kind: "semantic.role",
        band: "semantic",
        value: "button"
      ),
      Hint(
        provider: "mac.ax",
        kind: "semantic.name",
        band: "content",
        value: "Save"
      ),
    ]
    var first = AXElementSnapshot()
    first.bundleIdentifier = "com.example.app"
    first.role = "AXButton"
    first.title = "Save"
    first.frameInQuartzCoordinates = CGRect(x: 100, y: 100, width: 100, height: 40)
    var second = first
    second.frameInQuartzCoordinates = CGRect(x: 900, y: 700, width: 100, height: 40)

    XCTAssertThrowsError(
      try SelectorResolver.resolve(
        SuperSelectorEncoder.encode(hints),
        screenFrames: [CGRect(x: -2000, y: -2000, width: 5000, height: 5000)],
        accessibilityCandidates: [first, second]
      )
    ) { error in
      guard case SuperSelectorDecodingError.ambiguousAccessibilityMatch(2) = error else {
        return XCTFail("Expected an ambiguous match, got \(error)")
      }
    }
  }

  func testSemanticAncestorIdentitySurvivesAnonymousNestingChanges() throws {
    let hints = [
      Hint(
        provider: "screen.absolute", kind: "pointer.position.screen", band: "geometry",
        value: "120.0,120.0", valueType: .scalar),
      Hint(
        provider: "mac.ax", kind: "application.bundle-id", band: "scope",
        value: "com.example.app"),
      Hint(provider: "mac.ax", kind: "semantic.role", band: "semantic", value: "button"),
      Hint(
        provider: "mac.ax", kind: "ancestor.role-path", band: "structure",
        value: "group>group>group"),
      Hint(
        provider: "mac.ax", kind: "ancestor.node", band: "structure", value: "group",
        metadata: ["depth": "2", "semantic.AXDOMIdentifier": "checkout-panel"]),
    ]
    var wrong = AXElementSnapshot()
    wrong.bundleIdentifier = "com.example.app"
    wrong.role = "AXButton"
    wrong.frameInQuartzCoordinates = CGRect(x: 100, y: 100, width: 100, height: 40)
    wrong.ancestorBreadcrumbNodes = [
      AXBreadcrumbNode(
        role: "AXGroup", semanticAttributes: ["AXDOMIdentifier": "settings-panel"])
    ]
    var matching = wrong
    matching.frameInQuartzCoordinates = CGRect(x: 500, y: 400, width: 120, height: 50)
    matching.ancestorBreadcrumbNodes = [
      AXBreadcrumbNode(
        role: "AXGroup", semanticAttributes: ["AXDOMIdentifier": "checkout-panel"])
    ]

    let result = try SelectorResolver.resolve(
      SuperSelectorEncoder.encode(hints),
      screenFrames: [CGRect(x: -2_000, y: -2_000, width: 5_000, height: 5_000)],
      accessibilityCandidates: [wrong, matching]
    )

    XCTAssertEqual(
      result.elementFrameAppKit,
      CoordinateSpaces.appKitRect(fromQuartz: matching.frameInQuartzCoordinates!)
    )
  }

  func testMacProviderEmitsStableApplicationScopeWithoutProcessID() {
    var element = AXElementSnapshot()
    element.applicationName = "Example"
    element.bundleIdentifier = "com.example.app"
    element.applicationBundlePath = "/Applications/Example.app"
    element.applicationExecutablePath = "/Applications/Example.app/Contents/MacOS/Example"
    element.windowIdentifier = "settings"
    element.windowTitle = "Settings"
    element.role = "AXButton"
    element.title = "Save"
    element.ancestorBreadcrumbNodes = [
      AXBreadcrumbNode(
        role: "AXGroup", subrole: "AXTabGroup", roleDescription: "tab group", title: "Advanced",
        semanticAttributes: [
          "AXDOMIdentifier": "advanced-pane", "AXDOMClassList": "pane active",
        ]),
      AXBreadcrumbNode(role: "AXGroup", label: "Preferences", identifier: "prefs-root"),
      AXBreadcrumbNode(role: "AXWindow", title: "Settings"),
    ]

    let scene = SceneSnapshot(
      sampledAt: Date(),
      cursorQuartz: .zero,
      cursorAppKit: .zero,
      displayFrameAppKit: .zero,
      displayIdentifier: "test",
      accessibilityTrusted: true,
      accessibilityElement: element
    )
    let hints = MacAccessibilityHintProvider().hints(for: scene)

    XCTAssertFalse(hints.contains { $0.kind == "process.id" })
    XCTAssertEqual(
      hints.first { $0.kind == "application.bundle-id" }?.value,
      "com.example.app"
    )
    XCTAssertEqual(hints.first { $0.kind == "window.identifier" }?.value, "settings")
    let tree = hints.filter { $0.kind == "ancestor.node" }
    XCTAssertEqual(tree.map(\.value), ["window", "group", "group"])
    XCTAssertEqual(tree.map { $0.metadata["depth"] }, ["0", "1", "2"])
    XCTAssertEqual(tree[1].metadata["label"], "Preferences")
    XCTAssertEqual(tree[1].metadata["identifier"], "prefs-root")
    XCTAssertEqual(tree[2].metadata["subrole"], "tabgroup")
    XCTAssertEqual(tree[2].metadata["role-description"], "tab group")
    XCTAssertEqual(tree[2].metadata["semantic.AXDOMIdentifier"], "advanced-pane")
    XCTAssertEqual(tree[2].metadata["semantic.AXDOMClassList"], "pane active")
  }

  func testBreadcrumbRendererUsesNamedAXAncestry() {
    var element = AXElementSnapshot()
    element.applicationName = "System Settings"
    element.windowTitle = "System Settings"
    element.role = "AXStaticText"
    element.value = "C02EXAMPLE"
    element.ancestorBreadcrumbNodes = [
      AXBreadcrumbNode(role: "AXRow", title: "Serial number"),
      AXBreadcrumbNode(role: "AXGroup", title: "About"),
      AXBreadcrumbNode(role: "AXGroup", title: "General"),
      AXBreadcrumbNode(role: "AXWindow", title: "System Settings"),
    ]

    let path = BreadcrumbRenderer.targetPath(for: observation(with: element))

    XCTAssertEqual(
      path,
      "[Window: System Settings > Group: General > Group: About > Row: Serial number > Text: C02EXAMPLE]"
    )
  }

  func testBreadcrumbTrailIncludesClickStepsAndLiveTarget() {
    var logo = AXElementSnapshot()
    logo.applicationName = "Brave Browser"
    logo.windowTitle = "Brave"
    logo.role = "AXImage"
    logo.title = "Logo"
    logo.frameInQuartzCoordinates = CGRect(x: 100, y: 200, width: 80, height: 60)

    var menuItem = AXElementSnapshot()
    menuItem.applicationName = "Brave Browser"
    menuItem.role = "AXMenuItem"
    menuItem.title = "Save Image As…"

    var trail = BreadcrumbTrail()
    trail.recordClick(
      observation: observation(with: logo),
      button: .right,
      at: CGPoint(x: 124, y: 229)
    )
    let menuObservation = observation(with: menuItem)
    trail.updateLive(observation: menuObservation)
    let rendered = trail.rendered(current: menuObservation)

    XCTAssertTrue(rendered.contains("[Window: Brave > Image: Logo]"))
    XCTAssertTrue(rendered.contains("[Mouse: Right Click > offset: x=24,y=29]"))
    XCTAssertTrue(rendered.contains("[App: Brave Browser > Context Menu: Save Image As…]"))
    XCTAssertTrue(rendered.contains("[Mouse: Hover > offset: x=-100,y=-200]"))
    XCTAssertEqual(rendered.components(separatedBy: "\n").count, 2)
    XCTAssertEqual(trail.links.first?.selector, "ss3/e1")
    XCTAssertNil(trail.links.first?.previousIndex)
    XCTAssertEqual(trail.currentLiveLink?.selector, "ss3/e1")
    XCTAssertEqual(trail.currentLiveLink?.previousIndex, 0)
  }

  func testBreadcrumbLinksTrackHoverTypingAndCoalescedScrollHistory() {
    var first = AXElementSnapshot()
    first.windowTitle = "Demo"
    first.role = "AXButton"
    first.title = "Export"
    first.frameInQuartzCoordinates = CGRect(x: 100, y: 200, width: 80, height: 40)
    var second = AXElementSnapshot()
    second.windowTitle = "Demo"
    second.role = "AXTextField"
    second.title = "Report name"
    second.frameInQuartzCoordinates = CGRect(x: 400, y: 500, width: 180, height: 40)
    let firstObservation = observation(with: first, cursorQuartz: CGPoint(x: 110, y: 215))
    let secondObservation = observation(with: second, cursorQuartz: CGPoint(x: 430, y: 540))
    let start = Date(timeIntervalSince1970: 100)

    var trail = BreadcrumbTrail()
    trail.updateLive(observation: firstObservation, at: start)
    trail.updateLive(observation: secondObservation, at: start.addingTimeInterval(0.3))
    trail.recordText("A", observation: secondObservation, occurredAt: start.addingTimeInterval(1))
    trail.recordText("B", observation: secondObservation, occurredAt: start.addingTimeInterval(1.2))
    trail.recordScroll(
      observation: secondObservation,
      at: CGPoint(x: 440, y: 550),
      deltaX: 0,
      deltaY: -2,
      occurredAt: start.addingTimeInterval(2)
    )
    trail.recordScroll(
      observation: secondObservation,
      at: CGPoint(x: 440, y: 550),
      deltaX: 1,
      deltaY: -3,
      occurredAt: start.addingTimeInterval(2.1)
    )

    XCTAssertEqual(trail.links.count, 3)
    XCTAssertEqual(trail.links[0].interaction, .hover(offset: CGPoint(x: 10, y: 15)))
    XCTAssertEqual(trail.links[1].interaction, .type("AB"))
    XCTAssertEqual(trail.links[1].previousIndex, 0)
    XCTAssertEqual(
      trail.links[2].interaction,
      .scroll(offset: CGPoint(x: 40, y: 50), deltaX: 1, deltaY: -5)
    )
    XCTAssertEqual(trail.links[2].previousIndex, 1)
    XCTAssertEqual(
      trail.rendered(current: secondObservation).components(separatedBy: "\n").count,
      4
    )
    XCTAssertEqual(trail.currentLiveLink?.previousIndex, 2)
  }

  func testMouseOffsetsUsePreviousLinkedTargetOrigin() {
    var first = AXElementSnapshot()
    first.windowTitle = "Demo"
    first.role = "AXButton"
    first.title = "First"
    first.frameInQuartzCoordinates = CGRect(x: 100, y: 200, width: 80, height: 40)
    var second = AXElementSnapshot()
    second.windowTitle = "Demo"
    second.role = "AXButton"
    second.title = "Second"
    second.frameInQuartzCoordinates = CGRect(x: 700, y: 800, width: 80, height: 40)
    let start = Date(timeIntervalSince1970: 100)

    var trail = BreadcrumbTrail()
    trail.recordClick(
      observation: observation(with: first, cursorQuartz: CGPoint(x: 124, y: 229)),
      button: .left,
      at: CGPoint(x: 124, y: 229),
      occurredAt: start
    )
    trail.recordClick(
      observation: observation(with: second, cursorQuartz: CGPoint(x: 730, y: 840)),
      button: .right,
      at: CGPoint(x: 730, y: 840),
      occurredAt: start.addingTimeInterval(0.1)
    )

    XCTAssertEqual(
      trail.links[0].interaction,
      .click(button: .left, offset: CGPoint(x: 24, y: 29))
    )
    XCTAssertEqual(
      trail.links[1].interaction,
      .click(button: .right, offset: CGPoint(x: 630, y: 640))
    )
    XCTAssertEqual(trail.links[1].previousIndex, 0)
  }

  func testTypingCoalescesWhenEditableContentChanges() {
    var first = AXElementSnapshot()
    first.windowTitle = "Editor"
    first.role = "AXStaticText"
    first.value = "A"
    first.ancestorBreadcrumbNodes = [
      AXBreadcrumbNode(role: "AXTextArea", identifier: "editor")
    ]
    var second = first
    second.value = "AB"
    let start = Date(timeIntervalSince1970: 100)

    var trail = BreadcrumbTrail()
    trail.recordText("A", observation: observation(with: first), occurredAt: start)
    trail.recordText(
      "B",
      observation: observation(with: second),
      occurredAt: start.addingTimeInterval(0.2)
    )

    XCTAssertEqual(trail.links.count, 1)
    XCTAssertEqual(trail.links[0].interaction, .type("AB"))
  }

  func testStationaryAXTargetChurnDoesNotCreateHoverHistory() {
    var text = AXElementSnapshot()
    text.windowTitle = "Browser"
    text.role = "AXStaticText"
    text.title = "Logo"
    var group = AXElementSnapshot()
    group.windowTitle = "Browser"
    group.role = "AXGroup"
    let cursor = CGPoint(x: 100, y: 100)
    let start = Date(timeIntervalSince1970: 100)

    var trail = BreadcrumbTrail()
    trail.updateLive(
      observation: observation(with: text, cursorQuartz: cursor),
      at: start
    )
    trail.updateLive(
      observation: observation(with: group, cursorQuartz: cursor),
      at: start.addingTimeInterval(0.4)
    )

    XCTAssertTrue(trail.links.isEmpty)
    XCTAssertEqual(trail.currentLiveLink?.targetPath, "[Window: Browser > Group]")
  }

  func testPausedTrailDoesNotBridgeHoverMovementAcrossPause() {
    var firstElement = AXElementSnapshot()
    firstElement.role = "AXButton"
    firstElement.title = "First"
    firstElement.frameInQuartzCoordinates = CGRect(x: 80, y: 80, width: 80, height: 40)
    var secondElement = AXElementSnapshot()
    secondElement.role = "AXButton"
    secondElement.title = "Second"
    secondElement.frameInQuartzCoordinates = CGRect(x: 480, y: 480, width: 80, height: 40)
    var trail = BreadcrumbTrail()
    let first = observation(with: firstElement, cursorQuartz: CGPoint(x: 100, y: 100))
    let second = observation(with: secondElement, cursorQuartz: CGPoint(x: 500, y: 500))
    trail.updateLive(observation: first, at: Date(timeIntervalSince1970: 1))
    trail.suspendLiveTarget()
    trail.updateLive(observation: second, at: Date(timeIntervalSince1970: 10))

    XCTAssertTrue(trail.links.isEmpty)
  }

  func testBreadcrumbScreenshotCacheFollowsPointerAcrossDisplays() {
    var element = AXElementSnapshot()
    element.role = "AXGroup"
    element.title = "Desktop"
    let firstPoint = CGPoint(x: 100, y: 100)
    let secondPoint = CGPoint(x: 1_100, y: 100)
    let firstObservation = observation(with: element, cursorQuartz: firstPoint)
    let secondObservation = observation(with: element, cursorQuartz: secondPoint)
    let firstScreenshot = BreadcrumbScreenshot(
      jpegData: Data([1]),
      screenFrameQuartz: CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
    )
    let secondScreenshot = BreadcrumbScreenshot(
      jpegData: Data([2]),
      screenFrameQuartz: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000)
    )
    let start = Date(timeIntervalSince1970: 100)

    var trail = BreadcrumbTrail()
    trail.updateLive(observation: firstObservation, screenshot: firstScreenshot, at: start)
    XCTAssertEqual(trail.screenshot(for: firstObservation, at: firstPoint), firstScreenshot)
    XCTAssertNil(trail.screenshot(for: firstObservation, at: secondPoint))

    trail.updateLive(
      observation: secondObservation,
      at: start.addingTimeInterval(0.3)
    )
    XCTAssertNil(trail.screenshot(for: secondObservation))
    XCTAssertTrue(
      trail.needsScreenshot(for: secondObservation, at: start.addingTimeInterval(0.3)))

    trail.updateLive(
      observation: secondObservation,
      screenshot: secondScreenshot,
      at: start.addingTimeInterval(0.3)
    )
    XCTAssertEqual(trail.screenshot(for: secondObservation), secondScreenshot)
    XCTAssertFalse(
      trail.needsScreenshot(for: secondObservation, at: start.addingTimeInterval(0.6)))
  }

  func testDoubleEscapeResetRequiresTwoConsecutiveQuickPresses() {
    var detector = DoubleEscapeResetDetector(maximumInterval: 0.8)
    let start = Date(timeIntervalSince1970: 100)

    XCTAssertFalse(detector.registerEscape(at: start))
    XCTAssertTrue(detector.registerEscape(at: start.addingTimeInterval(0.4)))
    XCTAssertFalse(detector.registerEscape(at: start.addingTimeInterval(0.5)))
    detector.registerOtherKey()
    XCTAssertFalse(detector.registerEscape(at: start.addingTimeInterval(0.6)))
    XCTAssertFalse(detector.registerEscape(at: start.addingTimeInterval(2)))
  }

  private func observation(
    with element: AXElementSnapshot,
    cursorQuartz: CGPoint = .zero
  ) -> SuperSelectorObservation {
    let scene = SceneSnapshot(
      sampledAt: Date(),
      cursorQuartz: cursorQuartz,
      cursorAppKit: .zero,
      displayFrameAppKit: .zero,
      displayIdentifier: "test",
      accessibilityTrusted: true,
      accessibilityElement: element
    )
    return SuperSelectorObservation(
      scene: scene,
      providerReports: [],
      hints: [],
      compactSelector: "ss3/e1"
    )
  }
}
