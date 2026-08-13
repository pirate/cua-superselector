import XCTest

@testable import SuperSelector

final class SuperSelectorEncoderTests: XCTestCase {
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
      CoordinateSpaces.localPoint(fromGlobal: cursor, in: secondaryFrame),
      CGPoint(x: 953, y: 1171)
    )
    XCTAssertEqual(
      CoordinateSpaces.localRect(fromGlobal: element, in: secondaryFrame),
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
  }
}
