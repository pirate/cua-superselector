import AppKit
import Foundation

enum SuperSelectorDecodingError: LocalizedError {
  case unsupportedVersion
  case malformedField(String)
  case missingScreenLocation
  case locationOffscreen
  case noMatchingAccessibilityElement
  case ambiguousAccessibilityMatch(Int)

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion:
      return "This app can currently resolve ss3/e1 selectors."
    case .malformedField(let field):
      return "The selector contains a malformed field: \(field.prefix(80))"
    case .missingScreenLocation:
      return "The selector has no screen.absolute point or element frame."
    case .locationOffscreen:
      return "The selector resolves outside the currently connected displays."
    case .noMatchingAccessibilityElement:
      return
        "No visible accessibility element matched the selector's app, role, and identity hints."
    case .ambiguousAccessibilityMatch(let count):
      return
        "The selector matched \(count) accessibility elements equally well, so resolution was declined."
    }
  }
}

enum SuperSelectorDecoder {
  static func decode(_ selector: String) throws -> [Hint] {
    let fields = selector.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "~", omittingEmptySubsequences: false)
    guard fields.first == "ss3/e1" else {
      throw SuperSelectorDecodingError.unsupportedVersion
    }

    return try fields.dropFirst().map { encodedField in
      var components: [Character: String] = [:]
      for encodedComponent in encodedField.split(separator: "|", omittingEmptySubsequences: false) {
        guard let tag = encodedComponent.first else { continue }
        components[tag] = String(encodedComponent.dropFirst())
      }
      guard
        let provider = components["p"].flatMap(unescape),
        let band = components["b"].flatMap(unescape),
        let kind = components["k"].flatMap(unescape),
        let encodedValue = components["v"],
        let value = unescape(encodedValue),
        let type = components["t"].flatMap(Hint.ValueType.init(rawValue:))
      else {
        throw SuperSelectorDecodingError.malformedField(String(encodedField))
      }

      var metadata: [String: String] = [:]
      if let encodedMetadata = components["m"], !encodedMetadata.isEmpty {
        for pair in encodedMetadata.split(separator: ";", omittingEmptySubsequences: false) {
          let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
          guard parts.count == 2,
            let key = unescape(String(parts[0])),
            let value = unescape(String(parts[1]))
          else {
            throw SuperSelectorDecodingError.malformedField(String(encodedField))
          }
          metadata[key] = value
        }
      }

      return Hint(
        provider: provider,
        kind: kind,
        band: band,
        value: value,
        valueType: type,
        metadata: metadata,
        quality: components["q"].flatMap(Double.init) ?? 1,
        privacy: components["r"].flatMap(unescape).flatMap(Hint.Privacy.init(rawValue:))
          ?? .publicData
      )
    }
  }

  private static func unescape(_ value: String) -> String? {
    value.removingPercentEncoding
  }
}

struct ResolvedSelectorTarget {
  let pointAppKit: CGPoint
  let elementFrameAppKit: CGRect?
}

enum SelectorResolver {
  private struct CandidateMatch {
    let snapshot: AXElementSnapshot
    let score: Double
  }

  static func resolve(
    _ selector: String,
    screenFrames: [CGRect] = NSScreen.screens.map(\.frame),
    accessibilityCandidates suppliedCandidates: [AXElementSnapshot]? = nil
  ) throws
    -> ResolvedSelectorTarget
  {
    let hints = try SuperSelectorDecoder.decode(selector)
    let screenHints = hints.filter { $0.provider == "screen.absolute" }
    let accessibilityHints = hints.filter {
      $0.provider == "mac.ax" && $0.kind != "provider.status"
    }

    if !accessibilityHints.isEmpty {
      let bundleIdentifier = accessibilityHints.first { $0.kind == "application.bundle-id" }?.value
      let applicationBundlePath = accessibilityHints.first {
        $0.kind == "application.bundle-path"
      }?.value
      let applicationExecutablePath = accessibilityHints.first {
        $0.kind == "application.executable-path"
      }?.value
      let windowIdentifier = accessibilityHints.first { $0.kind == "window.identifier" }?.value
      let windowTitle = accessibilityHints.first { $0.kind == "window.title" }?.value
      let role = accessibilityHints.first { $0.kind == "semantic.role" }?.value
      let subrole = accessibilityHints.first { $0.kind == "native.subrole" }?.value
      let identifier = accessibilityHints.first { $0.kind == "native.identifier" }?.value
      let identityValues = Set(
        accessibilityHints.filter {
          [
            "semantic.name", "semantic.description", "semantic.help", "semantic.value",
          ].contains($0.kind)
        }.map(\.value)
      )
      let ancestorRolePath = accessibilityHints.first { $0.kind == "ancestor.role-path" }?.value

      if accessibilityHints.contains(where: {
        $0.kind == "state.focused" && $0.value == "true"
      }),
        let focused = AccessibilityInspector.focusedSnapshot(bundleIdentifier: bundleIdentifier),
        let focusedTarget = try? resolveAccessibilityCandidate(
          storedHints: hints,
          candidates: [focused],
          screenFrames: screenFrames
        )
      {
        return focusedTarget
      }

      let candidates =
        suppliedCandidates
        ?? AccessibilityInspector.snapshots(
          bundleIdentifier: bundleIdentifier,
          applicationBundlePath: applicationBundlePath,
          applicationExecutablePath: applicationExecutablePath,
          windowIdentifier: windowIdentifier,
          windowTitle: windowTitle,
          role: role,
          subrole: subrole,
          identifier: identifier,
          identityValues: identityValues,
          ancestorRolePath: identifier == nil && identityValues.isEmpty ? ancestorRolePath : nil
        )
      return try resolveAccessibilityCandidate(
        storedHints: hints,
        candidates: candidates,
        screenFrames: screenFrames
      )
    }

    return try resolveScreenFallback(screenHints: screenHints, screenFrames: screenFrames)
  }

  private static func resolveAccessibilityCandidate(
    storedHints: [Hint],
    candidates: [AXElementSnapshot],
    screenFrames: [CGRect]
  ) throws -> ResolvedSelectorTarget {
    let storedAccessibilityHints = storedHints.filter {
      $0.provider == "mac.ax" && $0.kind != "provider.status"
    }
    let storedByKind = Dictionary(grouping: storedAccessibilityHints, by: \.kind)
    // Resolve position-independent AX identity before consulting any geometry.
    // A window can move between displays, and the old selector geometry must not
    // remove or favor an otherwise exact live accessibility candidate.
    let framedCandidates = candidates.filter { candidate in
      guard let quartzFrame = candidate.frameInQuartzCoordinates else { return false }
      return quartzFrame.width > 0 && quartzFrame.height > 0
    }

    var matches: [CandidateMatch] = []
    for candidate in framedCandidates {
      let candidateHints = accessibilityHints(for: candidate)
      let candidateByKind = Dictionary(grouping: candidateHints, by: \.kind)
      guard
        satisfiesHardIdentity(
          storedByKind: storedByKind,
          candidateByKind: candidateByKind
        )
      else { continue }

      var score = 0.0
      for storedHint in storedAccessibilityHints {
        guard
          let exact = candidateByKind[storedHint.kind]?.first(where: {
            $0.value == storedHint.value
          })
        else { continue }
        var contribution = hintWeight(storedHint) * max(storedHint.quality, 0.1)
        if exact.metadata == storedHint.metadata {
          contribution += 0.25
        }
        score += contribution
      }
      matches.append(CandidateMatch(snapshot: candidate, score: score))
    }

    guard !matches.isEmpty else {
      throw SuperSelectorDecodingError.noMatchingAccessibilityElement
    }
    matches.sort { left, right in
      if left.score != right.score { return left.score > right.score }
      return frameOrderingKey(left.snapshot) < frameOrderingKey(right.snapshot)
    }
    let bestScore = matches[0].score
    let tied = matches.filter { abs($0.score - bestScore) < 0.000_001 }
    guard tied.count == 1 else {
      throw SuperSelectorDecodingError.ambiguousAccessibilityMatch(tied.count)
    }
    guard let candidateFrame = tied[0].snapshot.frameInQuartzCoordinates else {
      throw SuperSelectorDecodingError.noMatchingAccessibilityElement
    }
    return try target(
      candidateFrameQuartz: candidateFrame,
      storedScreenHints: storedHints.filter { $0.provider == "screen.absolute" },
      screenFrames: screenFrames
    )
  }

  private static func satisfiesHardIdentity(
    storedByKind: [String: [Hint]],
    candidateByKind: [String: [Hint]]
  ) -> Bool {
    func matches(_ kind: String) -> Bool {
      guard let stored = storedByKind[kind], !stored.isEmpty else { return true }
      let candidateValues = Set(candidateByKind[kind, default: []].map(\.value))
      return stored.contains { candidateValues.contains($0.value) }
    }

    for hardKind in [
      "application.bundle-id", "application.bundle-path", "application.executable-path",
      "application.name", "window.identifier", "semantic.role", "native.role", "native.subrole",
    ] where !matches(hardKind) {
      return false
    }

    if storedByKind["native.identifier"]?.isEmpty == false {
      return matches("native.identifier")
    }

    let textualIdentityKinds = [
      "semantic.name", "semantic.description", "semantic.help", "semantic.value",
    ].filter { storedByKind[$0]?.isEmpty == false }
    if !textualIdentityKinds.isEmpty {
      return textualIdentityKinds.contains(where: matches)
    }

    if storedByKind["ancestor.role-path"]?.isEmpty == false {
      return matches("ancestor.role-path")
    }
    return false
  }

  private static func accessibilityHints(for candidate: AXElementSnapshot) -> [Hint] {
    let quartzPoint =
      candidate.frameInQuartzCoordinates.map {
        CGPoint(x: $0.midX, y: $0.midY)
      } ?? .zero
    let scene = SceneSnapshot(
      sampledAt: Date(),
      cursorQuartz: quartzPoint,
      cursorAppKit: CoordinateSpaces.appKitPoint(fromQuartz: quartzPoint),
      displayFrameAppKit: .zero,
      displayIdentifier: "resolver",
      accessibilityTrusted: true,
      accessibilityElement: candidate
    )
    return MacAccessibilityHintProvider().hints(for: scene)
  }

  private static func hintWeight(_ hint: Hint) -> Double {
    switch hint.kind {
    case "native.identifier": return 20
    case "window.identifier": return 18
    case "semantic.name": return 16
    case "application.bundle-id": return 12
    case "application.bundle-path", "application.executable-path": return 10
    case "semantic.description": return 10
    case "window.title": return 8
    case "semantic.role", "native.role": return 8
    case "native.subrole": return 7
    case "ancestor.role-path": return 6
    case "semantic.help": return 5
    case "application.name": return 4
    case "semantic.value": return 3
    case "ancestor.contains-role": return 2
    case "capability.action": return 1
    case "state.enabled", "state.focused", "state.selected": return 0
    default: return 1
    }
  }

  private static func frameOrderingKey(_ snapshot: AXElementSnapshot) -> String {
    guard let frame = snapshot.frameInQuartzCoordinates else { return "" }
    return String(
      format: "%020.4f:%020.4f:%020.4f:%020.4f", frame.minY, frame.minX, frame.width, frame.height)
  }

  private static func target(
    candidateFrameQuartz: CGRect,
    storedScreenHints: [Hint],
    screenFrames: [CGRect]
  ) throws -> ResolvedSelectorTarget {
    let storedFrame = storedScreenHints.first { $0.kind == "element.frame.screen" }
      .flatMap { parseRect($0.value) }
    let storedPoint = storedScreenHints.first { $0.kind == "pointer.position.screen" }
      .flatMap { parsePoint($0.value) }

    let relativeX: CGFloat
    let relativeY: CGFloat
    if let storedFrame, let storedPoint, storedFrame.width > 0, storedFrame.height > 0 {
      relativeX = min(1, max(0, (storedPoint.x - storedFrame.minX) / storedFrame.width))
      relativeY = min(1, max(0, (storedPoint.y - storedFrame.minY) / storedFrame.height))
    } else {
      relativeX = 0.5
      relativeY = 0.5
    }

    let pointQuartz = CGPoint(
      x: candidateFrameQuartz.minX + relativeX * candidateFrameQuartz.width,
      y: candidateFrameQuartz.minY + relativeY * candidateFrameQuartz.height
    )
    let pointAppKit = CoordinateSpaces.appKitPoint(fromQuartz: pointQuartz)
    let frameAppKit = CoordinateSpaces.appKitRect(fromQuartz: candidateFrameQuartz)
    guard screenFrames.contains(where: { $0.contains(pointAppKit) }) else {
      throw SuperSelectorDecodingError.locationOffscreen
    }
    return ResolvedSelectorTarget(
      pointAppKit: pointAppKit,
      elementFrameAppKit: frameAppKit
    )
  }

  private static func resolveScreenFallback(
    screenHints: [Hint],
    screenFrames: [CGRect]
  ) throws -> ResolvedSelectorTarget {

    let quartzFrame = screenHints.first { $0.kind == "element.frame.screen" }
      .flatMap { parseRect($0.value) }
    let quartzPoint = screenHints.first { $0.kind == "pointer.position.screen" }
      .flatMap { parsePoint($0.value) }

    let frame = quartzFrame.map(CoordinateSpaces.appKitRect(fromQuartz:))
    let point =
      quartzPoint.map(CoordinateSpaces.appKitPoint(fromQuartz:))
      ?? frame.map { CGPoint(x: $0.midX, y: $0.midY) }
    guard let point else { throw SuperSelectorDecodingError.missingScreenLocation }
    guard screenFrames.contains(where: { $0.contains(point) }) else {
      throw SuperSelectorDecodingError.locationOffscreen
    }
    return ResolvedSelectorTarget(pointAppKit: point, elementFrameAppKit: frame)
  }

  private static func parsePoint(_ value: String) -> CGPoint? {
    let parts = value.split(separator: ",", omittingEmptySubsequences: false)
    guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
    return CGPoint(x: x, y: y)
  }

  private static func parseRect(_ value: String) -> CGRect? {
    var values: [String: Double] = [:]
    for component in value.split(separator: ",") {
      let pair = component.split(separator: "=", maxSplits: 1)
      guard pair.count == 2, let number = Double(pair[1]) else { return nil }
      values[String(pair[0])] = number
    }
    guard let x = values["x"], let y = values["y"], let width = values["w"],
      let height = values["h"]
    else { return nil }
    return CGRect(x: x, y: y, width: width, height: height)
  }
}
