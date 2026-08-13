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
    candidate.processIdentifier = 123
    candidate.bundleIdentifier = "com.example.browser"
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
}
