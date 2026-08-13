import AppKit
import ApplicationServices
import Foundation

struct AbsoluteScreenHintProvider: HintProvider {
  let id = "screen.absolute"

  func report(for scene: SceneSnapshot) -> ProviderReport {
    ProviderReport(provider: id, state: .available, detail: nil)
  }

  func hints(for scene: SceneSnapshot) -> [Hint] {
    let display = scene.displayFrameAppKit
    let localX = scene.cursorAppKit.x - display.minX
    let localY = scene.cursorAppKit.y - display.minY
    let normalizedX = display.width > 0 ? localX / display.width : 0
    let normalizedY = display.height > 0 ? localY / display.height : 0

    var result = [
      Hint(
        provider: id,
        kind: "pointer.position.screen",
        band: "geometry",
        value: pointString(scene.cursorQuartz),
        valueType: .scalar,
        metadata: ["space": "quartz-global", "origin": "top-left"]
      ),
      Hint(
        provider: id,
        kind: "pointer.position.display.normalized",
        band: "geometry",
        value: String(format: "%.4f,%.4f", normalizedX, 1 - normalizedY),
        valueType: .scalar,
        metadata: ["display": scene.displayIdentifier]
      ),
      Hint(
        provider: id,
        kind: "display.id",
        band: "scope",
        value: scene.displayIdentifier,
        metadata: ["frame": rectString(display)]
      ),
    ]

    if let elementFrame = scene.elementFrameAppKit {
      let centerX = (elementFrame.midX - display.minX) / max(display.width, 1)
      let centerYFromTop = 1 - ((elementFrame.midY - display.minY) / max(display.height, 1))
      let width = elementFrame.width / max(display.width, 1)
      let height = elementFrame.height / max(display.height, 1)

      result.append(
        Hint(
          provider: id,
          kind: "element.frame.screen",
          band: "geometry",
          value: rectString(CoordinateSpaces.appKitRectToQuartz(elementFrame)),
          valueType: .scalar,
          metadata: ["space": "quartz-global", "origin": "top-left"],
          quality: 0.75
        )
      )
      for bins in [4, 8, 16] {
        let bx = min(bins - 1, max(0, Int(centerX * CGFloat(bins))))
        let by = min(bins - 1, max(0, Int(centerYFromTop * CGFloat(bins))))
        result.append(
          Hint(
            provider: id,
            kind: "element.center.grid.\(bins)",
            band: "geometry",
            value: "\(bx),\(by)",
            valueType: .scalar,
            metadata: ["display": scene.displayIdentifier, "bins": "\(bins)x\(bins)"],
            quality: bins == 16 ? 0.45 : 0.65
          )
        )
      }
      result.append(
        Hint(
          provider: id,
          kind: "element.size.normalized",
          band: "geometry",
          value: String(format: "%.3f,%.3f", width, height),
          valueType: .scalar,
          metadata: ["relativeTo": "display"],
          quality: 0.5
        )
      )
    } else {
      // Without a semantic element, pointer locality is the available target hint.
      // Multiple grids retain useful fuzzy locality without hashing exact pixels.
      for bins in [8, 16, 32, 64] {
        let bx = min(bins - 1, max(0, Int(normalizedX * CGFloat(bins))))
        let by = min(bins - 1, max(0, Int((1 - normalizedY) * CGFloat(bins))))
        result.append(
          Hint(
            provider: id,
            kind: "pointer.grid.\(bins)",
            band: "geometry",
            value: "\(bx),\(by)",
            valueType: .scalar,
            metadata: ["display": scene.displayIdentifier, "fallback": "no-semantic-element"],
            quality: bins <= 16 ? 0.65 : 0.4
          )
        )
      }
    }
    return result
  }
}

struct WindowRelativeHintProvider: HintProvider {
  let id = "window.relative"

  func report(for scene: SceneSnapshot) -> ProviderReport {
    if !scene.accessibilityTrusted {
      return ProviderReport(provider: id, state: .unavailable, detail: "permission-required")
    }
    guard let element = scene.accessibilityElement else {
      return ProviderReport(provider: id, state: .degraded, detail: "no-element-at-pointer")
    }
    guard element.windowFrameInQuartzCoordinates != nil else {
      return ProviderReport(provider: id, state: .degraded, detail: "no-window-frame")
    }
    return ProviderReport(provider: id, state: .available, detail: nil)
  }

  func hints(for scene: SceneSnapshot) -> [Hint] {
    guard let element = scene.accessibilityElement,
      let windowFrame = element.windowFrameInQuartzCoordinates
    else { return [] }

    var hints = [
      Hint(
        provider: id,
        kind: "window.frame.screen",
        band: "geometry",
        value: rectString(windowFrame),
        valueType: .scalar,
        metadata: ["space": "quartz-global", "origin": "top-left"]
      ),
      Hint(
        provider: id,
        kind: "pointer.position.window",
        band: "geometry",
        value: pointString(
          CoordinateSpaces.localPoint(fromGlobal: scene.cursorQuartz, in: windowFrame)),
        valueType: .scalar,
        metadata: ["relativeTo": "window", "origin": "top-left"]
      ),
    ]

    if let elementFrame = element.frameInQuartzCoordinates {
      hints.append(
        Hint(
          provider: id,
          kind: "element.frame.window",
          band: "geometry",
          value: rectString(
            CoordinateSpaces.localRect(fromGlobal: elementFrame, in: windowFrame)),
          valueType: .scalar,
          metadata: ["relativeTo": "window", "origin": "top-left"]
        ))
    }
    return hints
  }
}

struct MacAccessibilityHintProvider: HintProvider {
  let id = "mac.ax"

  func report(for scene: SceneSnapshot) -> ProviderReport {
    if !scene.accessibilityTrusted {
      return ProviderReport(provider: id, state: .unavailable, detail: "permission-required")
    }
    if scene.accessibilityElement == nil {
      return ProviderReport(provider: id, state: .degraded, detail: "no-element-at-pointer")
    }
    return ProviderReport(provider: id, state: .available, detail: nil)
  }

  func hints(for scene: SceneSnapshot) -> [Hint] {
    guard let element = scene.accessibilityElement else { return [] }

    var result: [Hint] = []
    if let bundle = element.bundleIdentifier {
      result.append(Hint(provider: id, kind: "application.bundle-id", band: "scope", value: bundle))
    }
    if let name = element.applicationName {
      result.append(
        Hint(
          provider: id,
          kind: "application.name",
          band: "scope",
          value: name,
          quality: 0.7,
          privacy: .sensitive
        )
      )
    }
    if let bundlePath = element.applicationBundlePath {
      result.append(
        Hint(
          provider: id,
          kind: "application.bundle-path",
          band: "scope",
          value: bundlePath
        ))
    }
    if let executablePath = element.applicationExecutablePath {
      result.append(
        Hint(
          provider: id,
          kind: "application.executable-path",
          band: "scope",
          value: executablePath
        ))
    }
    if let windowIdentifier = element.windowIdentifier {
      result.append(
        Hint(
          provider: id,
          kind: "window.identifier",
          band: "scope",
          value: windowIdentifier
        ))
    }
    if let windowTitle = element.windowTitle {
      result.append(
        Hint(
          provider: id,
          kind: "window.title",
          band: "scope",
          value: windowTitle,
          privacy: .sensitive
        ))
    }

    if let role = element.role {
      result.append(
        Hint(provider: id, kind: "semantic.role", band: "semantic", value: normalizedRole(role)))
      result.append(Hint(provider: id, kind: "native.role", band: "native.mac.ax", value: role))
    }
    if let subrole = element.subrole {
      result.append(
        Hint(provider: id, kind: "native.subrole", band: "native.mac.ax", value: subrole))
    }
    if let identifier = element.identifier {
      result.append(
        Hint(
          provider: id, kind: "native.identifier", band: "native.mac.ax", value: identifier,
          privacy: .sensitive))
    }
    appendContent("semantic.name", element.title ?? element.label, quality: 1, to: &result)
    appendContent("semantic.description", element.label, quality: 0.75, to: &result)
    appendContent("semantic.help", element.help, quality: 0.55, to: &result)
    appendContent("semantic.value", element.value, quality: 0.65, to: &result)

    for action in element.actions {
      result.append(
        Hint(
          provider: id,
          kind: "capability.action",
          band: "capability",
          value: normalizedAction(action),
          metadata: ["native": action]
        )
      )
    }
    appendState("state.enabled", element.enabled, to: &result)
    appendState("state.focused", element.focused, to: &result)
    appendState("state.selected", element.selected, to: &result)

    if !element.ancestorRoles.isEmpty {
      result.append(
        Hint(
          provider: id,
          kind: "ancestor.role-path",
          band: "structure",
          value: element.ancestorRoles.reversed().map(normalizedRole).joined(separator: ">"),
          metadata: ["depth": String(element.ancestorRoles.count)],
          quality: 0.8
        )
      )
      let uniqueAncestorRoles = Set(element.ancestorRoles.map(normalizedRole)).sorted()
      for role in uniqueAncestorRoles {
        result.append(
          Hint(
            provider: id,
            kind: "ancestor.contains-role",
            band: "structure",
            value: role,
            quality: 0.55
          )
        )
      }
    }
    return result
  }

  private func appendContent(
    _ kind: String, _ value: String?, quality: Double, to hints: inout [Hint]
  ) {
    guard let value, !value.isEmpty else { return }
    hints.append(
      Hint(
        provider: id,
        kind: kind,
        band: "content",
        value: value,
        quality: quality,
        privacy: .sensitive
      )
    )
  }

  private func appendState(_ kind: String, _ value: Bool?, to hints: inout [Hint]) {
    guard let value else { return }
    hints.append(
      Hint(
        provider: id,
        kind: kind,
        band: "state",
        value: String(value),
        valueType: .scalar
      ))
  }

  private func normalizedRole(_ role: String) -> String {
    role.replacingOccurrences(of: "AX", with: "").lowercased()
  }

  private func normalizedAction(_ action: String) -> String {
    switch action {
    case kAXPressAction: return "invoke"
    case kAXConfirmAction: return "confirm"
    case kAXIncrementAction: return "increment"
    case kAXDecrementAction: return "decrement"
    case kAXShowMenuAction: return "show-menu"
    default: return action.replacingOccurrences(of: "AX", with: "").lowercased()
    }
  }
}

private func pointString(_ point: CGPoint) -> String {
  String(format: "%.1f,%.1f", point.x, point.y)
}

private func rectString(_ rect: CGRect) -> String {
  String(format: "x=%.1f,y=%.1f,w=%.1f,h=%.1f", rect.minX, rect.minY, rect.width, rect.height)
}

extension CoordinateSpaces {
  static func appKitRectToQuartz(_ rect: CGRect) -> CGRect {
    CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
  }
}
