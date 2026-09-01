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

struct ResolvedSelectorTarget: Sendable {
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
      let hasStrongSemanticAncestor = hasStrongSemanticAncestorEvidence(accessibilityHints)

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
          ancestorRolePath: identifier == nil && identityValues.isEmpty
            && !hasStrongSemanticAncestor ? ancestorRolePath : nil
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
      for storedHint in storedAccessibilityHints where storedHint.kind != "ancestor.node" {
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
      score += semanticAncestorMatchScore(
        storedHints: storedAccessibilityHints,
        candidateHints: candidateHints
      )
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

    if hasStrongSemanticAncestorEvidence(storedByKind["ancestor.node", default: []]) {
      return semanticAncestorMatchScore(
        storedHints: storedByKind["ancestor.node", default: []],
        candidateHints: candidateByKind["ancestor.node", default: []]
      ) >= 8
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

  private static func hasStrongSemanticAncestorEvidence(_ hints: [Hint]) -> Bool {
    semanticAncestorNodes(hints)
      .contains { hint in
        ancestorIdentityFields(hint).contains { key, _ in ancestorFieldWeight(key) >= 8 }
      }
  }

  private static func semanticAncestorMatchScore(
    storedHints: [Hint], candidateHints: [Hint]
  ) -> Double {
    let storedNodes = semanticAncestorNodes(storedHints)
    let candidateNodes = semanticAncestorNodes(candidateHints)
    var unusedCandidates = Set(candidateNodes.indices)
    var total = 0.0

    for stored in storedNodes {
      let storedFields = ancestorIdentityFields(stored)
      guard !storedFields.isEmpty else { continue }
      var best: (index: Int, score: Double)?
      for index in unusedCandidates where candidateNodes[index].value == stored.value {
        let candidateFields = ancestorIdentityFields(candidateNodes[index])
        let score = storedFields.reduce(0.0) { partial, field in
          guard let candidateValue = candidateFields[field.key] else { return partial }
          return partial
            + ancestorFieldMatchScore(
              key: field.key, stored: field.value, candidate: candidateValue)
        }
        if score > (best?.score ?? 0) { best = (index, score) }
      }
      if let best {
        unusedCandidates.remove(best.index)
        total += best.score
      }
    }
    return total
  }

  private static func semanticAncestorNodes(_ hints: [Hint]) -> [Hint] {
    hints.filter {
      $0.kind == "ancestor.node" && !["application", "window"].contains($0.value)
    }
  }

  private static func ancestorIdentityFields(_ hint: Hint) -> [String: String] {
    let directKeys: Set<String> = [
      "identifier", "label", "title", "help", "subrole", "role-description",
    ]
    return hint.metadata.reduce(into: [:]) { result, field in
      let key = field.key.lowercased()
      guard directKeys.contains(key) || key.hasPrefix("semantic.") else { return }
      let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { result[key] = value }
    }
  }

  private static func ancestorFieldMatchScore(
    key: String, stored: String, candidate: String
  ) -> Double {
    if key.contains("class") {
      let storedClasses = Set(stored.lowercased().split(whereSeparator: { $0.isWhitespace }))
      let candidateClasses = Set(candidate.lowercased().split(whereSeparator: { $0.isWhitespace }))
      return storedClasses.isDisjoint(with: candidateClasses) ? 0 : ancestorFieldWeight(key)
    }
    return stored == candidate ? ancestorFieldWeight(key) : 0
  }

  private static func ancestorFieldWeight(_ key: String) -> Double {
    let lowered = key.lowercased()
    if lowered == "identifier" || lowered.contains("domidentifier") { return 24 }
    if lowered == "label" || lowered == "title" || lowered.contains("arialabel") { return 14 }
    if lowered.contains("placeholder") { return 10 }
    if lowered == "help" || lowered.contains("description") { return 8 }
    if lowered == "subrole" { return 6 }
    if lowered.contains("url") || lowered.contains("document") { return 6 }
    if lowered.contains("class") { return 4 }
    if lowered == "role-description" { return 2 }
    return 5
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
    case "ancestor.node": return 0
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
    let pointQuartz =
      SuperSelectorBoxModel(hints: storedScreenHints)?
      .pointer(retargetedTo: candidateFrameQuartz)
      ?? CGPoint(x: candidateFrameQuartz.midX, y: candidateFrameQuartz.midY)
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
    guard let boxModel = SuperSelectorBoxModel(hints: screenHints) else {
      throw SuperSelectorDecodingError.missingScreenLocation
    }
    let frame = boxModel.targetQuartz.map(CoordinateSpaces.appKitRect(fromQuartz:))
    let point = CoordinateSpaces.appKitPoint(fromQuartz: boxModel.pointerQuartz)
    guard screenFrames.contains(where: { $0.contains(point) }) else {
      throw SuperSelectorDecodingError.locationOffscreen
    }
    return ResolvedSelectorTarget(pointAppKit: point, elementFrameAppKit: frame)
  }

}
