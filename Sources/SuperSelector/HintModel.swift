import AppKit
import Foundation

struct Hint: Sendable {
  enum ValueType: String, Sendable {
    case scalar = "n"
    case text = "s"
  }

  let provider: String
  let kind: String
  let band: String
  let value: String
  var valueType: ValueType = .text
  var metadata: [String: String] = [:]
  var quality: Double = 1
  var privacy: Privacy = .publicData

  enum Privacy: String, Sendable {
    case publicData = "public"
    case sensitive
    case secret
  }

  var canonicalToken: String {
    "\(kind)=\(value.trimmingCharacters(in: .whitespacesAndNewlines))"
  }

  var canonicalRecord: String {
    let details = metadata.sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: "\u{1f}")
    return [
      provider,
      kind,
      band,
      value,
      details,
      String(format: "%.6f", quality),
      privacy.rawValue,
    ].joined(separator: "\u{1e}")
  }

  var displayLine: String {
    let details =
      metadata.isEmpty
      ? ""
      : "  {\(metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))}"
    let privacySuffix = privacy == .publicData ? "" : "  [\(privacy.rawValue)]"
    return "◆ [\(provider)] \(kind) = \(value)\(privacySuffix)\(details)"
  }
}

struct AXElementSnapshot: Sendable {
  var processIdentifier: pid_t = 0
  var applicationName: String?
  var bundleIdentifier: String?
  var role: String?
  var subrole: String?
  var identifier: String?
  var title: String?
  var label: String?
  var help: String?
  var value: String?
  var enabled: Bool?
  var focused: Bool?
  var selected: Bool?
  var frameInQuartzCoordinates: CGRect?
  var actions: [String] = []
  var ancestorRoles: [String] = []
}

struct SceneSnapshot: Sendable {
  let sampledAt: Date
  let cursorQuartz: CGPoint
  let cursorAppKit: CGPoint
  let displayFrameAppKit: CGRect
  let displayIdentifier: String
  let accessibilityTrusted: Bool
  let accessibilityElement: AXElementSnapshot?

  var elementFrameAppKit: CGRect? {
    guard let rect = accessibilityElement?.frameInQuartzCoordinates else { return nil }
    return CoordinateSpaces.appKitRect(fromQuartz: rect)
  }
}

struct SuperSelectorObservation: Sendable {
  let scene: SceneSnapshot
  let providerReports: [ProviderReport]
  let hints: [Hint]
  let compactSelector: String
}

struct ProviderReport: Sendable {
  enum State: String, Sendable {
    case available
    case degraded
    case unavailable
  }

  let provider: String
  let state: State
  let detail: String?
}

protocol HintProvider {
  var id: String { get }
  func report(for scene: SceneSnapshot) -> ProviderReport
  func hints(for scene: SceneSnapshot) -> [Hint]
}

enum CoordinateSpaces {
  static var primaryScreenTop: CGFloat {
    NSScreen.screens.first?.frame.maxY ?? 0
  }

  static func appKitPoint(fromQuartz point: CGPoint) -> CGPoint {
    CGPoint(x: point.x, y: primaryScreenTop - point.y)
  }

  static func appKitRect(fromQuartz rect: CGRect) -> CGRect {
    CGRect(
      x: rect.minX,
      y: primaryScreenTop - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }

  static func localPoint(fromGlobal point: CGPoint, in windowFrame: CGRect) -> CGPoint {
    CGPoint(x: point.x - windowFrame.minX, y: point.y - windowFrame.minY)
  }

  static func localRect(fromGlobal rect: CGRect, in windowFrame: CGRect) -> CGRect {
    rect.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)
  }
}

enum SuperSelectorEncoder {
  static func encode(_ hints: [Hint]) -> String {
    let fields = hints.map { hint -> String in
      let metadata = hint.metadata.sorted { $0.key < $1.key }
        .map { "\(escape($0.key))=\(escape($0.value))" }
        .joined(separator: ";")
      let quality = String(format: "%.6f", hint.quality)
      return [
        "p\(escape(hint.provider))",
        "b\(escape(hint.band))",
        "k\(escape(hint.kind))",
        "t\(hint.valueType.rawValue)",
        "v\(escape(hint.value))",
        "m\(metadata)",
        "q\(quality)",
        "r\(escape(hint.privacy.rawValue))",
      ].joined(separator: "|")
    }
    return (["ss3/e1"] + fields).joined(separator: "~")
  }

  private static func escape(_ value: String) -> String {
    let unreserved = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
    return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
  }
}
