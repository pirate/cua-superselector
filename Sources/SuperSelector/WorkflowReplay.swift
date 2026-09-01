import AppKit
import ApplicationServices
import Foundation

enum WorkflowReplayError: LocalizedError {
  case applicationUnavailable(String)
  case unsupportedMouseButton(String)
  case unsupportedKey(String)

  var errorDescription: String? {
    switch self {
    case .applicationUnavailable(let value):
      return "Replay could not launch or activate \(value)."
    case .unsupportedMouseButton(let value):
      return "Replay does not support mouse button \(value)."
    case .unsupportedKey(let value):
      return "Replay does not recognize key \(value)."
    }
  }
}

final class MacWorkflowReplayer {
  typealias Progress = @MainActor (
    Int, SuperSelectorWorkflowStep, ResolvedSelectorTarget
  ) -> Void

  func execute(
    _ plan: SuperSelectorReplayPlan,
    stepDelay: TimeInterval = 0.18,
    progress: @escaping Progress
  ) async throws {
    try await resetToNormalizedDesktop()
    for (index, step) in plan.steps.enumerated() {
      try Task.checkCancellation()
      try await activateTargetApplication(for: step.selector)
      try await Task.sleep(for: .milliseconds(140))
      let target = try await Task.detached(priority: .userInitiated) {
        try SelectorResolver.resolve(step.selector)
      }.value
      await progress(index, step, target)
      try await Task.sleep(for: .milliseconds(max(120, Int(stepDelay * 1_000))))
      try perform(step.action, at: CoordinateSpaces.quartzPoint(fromAppKit: target.pointAppKit))
      try await Task.sleep(for: .milliseconds(120))
    }
  }

  @MainActor
  func resetToNormalizedDesktop() async throws {
    let ownPID = ProcessInfo.processInfo.processIdentifier
    for application in NSWorkspace.shared.runningApplications
    where application.processIdentifier != ownPID
      && application.activationPolicy == .regular
    {
      application.hide()
    }
    try await Task.sleep(for: .milliseconds(220))
  }

  @MainActor
  private func activateTargetApplication(for selector: String) async throws {
    let hints = try SuperSelectorDecoder.decode(selector)
    let bundleID = hints.first { $0.kind == "application.bundle-id" }?.value
    let bundlePath = hints.first { $0.kind == "application.bundle-path" }?.value
    let applicationName = hints.first { $0.kind == "application.name" }?.value

    if let bundleID,
      let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    {
      running.unhide()
      running.activate(options: [.activateAllWindows])
      return
    }
    if let bundlePath {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      _ = try await NSWorkspace.shared.openApplication(
        at: URL(fileURLWithPath: bundlePath),
        configuration: configuration
      )
      return
    }
    if bundleID != nil || applicationName != nil {
      throw WorkflowReplayError.applicationUnavailable(bundleID ?? applicationName ?? "app")
    }
  }

  private func perform(_ action: SuperSelectorWorkflowAction, at point: CGPoint) throws {
    moveMouse(to: point)
    switch action.kind {
    case .hover:
      return
    case .click:
      let button = try mouseButton(action.button ?? "left")
      click(button, at: point, hid: action.pointerEvent)
    case .scroll:
      let event = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .pixel,
        wheelCount: 2,
        wheel1: Int32((action.deltaY ?? 0).rounded()),
        wheel2: Int32((action.deltaX ?? 0).rounded()),
        wheel3: 0
      )
      event?.location = point
      event?.post(tap: .cghidEventTap)
    case .type:
      if let events = action.keyboardEvents, !events.isEmpty {
        for event in events { press(event) }
      } else {
        type(action.value ?? "")
      }
    case .key:
      if let event = action.keyboardEvents?.first {
        press(event)
      } else {
        try press(action.value ?? "")
      }
    }
  }

  private func moveMouse(to point: CGPoint) {
    CGEvent(
      mouseEventSource: nil,
      mouseType: .mouseMoved,
      mouseCursorPosition: point,
      mouseButton: .left
    )?.post(tap: .cghidEventTap)
    usleep(45_000)
  }

  private func click(
    _ button: CGMouseButton, at point: CGPoint, hid: PointerHIDEvent? = nil
  ) {
    let types: (CGEventType, CGEventType) = switch button {
    case .left: (.leftMouseDown, .leftMouseUp)
    case .right: (.rightMouseDown, .rightMouseUp)
    default: (.otherMouseDown, .otherMouseUp)
    }
    let down = CGEvent(
      mouseEventSource: nil,
      mouseType: types.0,
      mouseCursorPosition: point,
      mouseButton: button
    )
    let up = CGEvent(
      mouseEventSource: nil,
      mouseType: types.1,
      mouseCursorPosition: point,
      mouseButton: button
    )
    if let hid {
      let flags = CGEventFlags(rawValue: hid.modifierFlags)
      down?.flags = flags
      up?.flags = flags
      down?.setIntegerValueField(.mouseEventClickState, value: Int64(hid.clickCount))
      up?.setIntegerValueField(.mouseEventClickState, value: Int64(hid.clickCount))
      down?.setDoubleValueField(.mouseEventPressure, value: hid.pressure)
      up?.setDoubleValueField(.mouseEventPressure, value: 0)
    }
    down?.post(tap: .cghidEventTap)
    usleep(55_000)
    up?.post(tap: .cghidEventTap)
  }

  private func mouseButton(_ value: String) throws -> CGMouseButton {
    switch value {
    case "left": return .left
    case "right": return .right
    case "middle": return .center
    case let value where value.hasPrefix("other:"):
      guard let rawValue = UInt32(String(value.dropFirst(6))),
        let button = CGMouseButton(rawValue: rawValue)
      else { throw WorkflowReplayError.unsupportedMouseButton(value) }
      return button
    default: throw WorkflowReplayError.unsupportedMouseButton(value)
    }
  }

  private func type(_ value: String) {
    for chunk in value.utf16.chunked(maximumCount: 16) {
      let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
      down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
      down?.post(tap: .cghidEventTap)
      let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
      up?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
      up?.post(tap: .cghidEventTap)
    }
  }

  private func press(_ description: String) throws {
    var value = description
    var flags: CGEventFlags = []
    while let first = value.first {
      let flag: CGEventFlags?
      switch first {
      case "⌃": flag = .maskControl
      case "⌥": flag = .maskAlternate
      case "⇧": flag = .maskShift
      case "⌘": flag = .maskCommand
      default: flag = nil
      }
      guard let flag else { break }
      flags.insert(flag)
      value.removeFirst()
    }
    let keyCode: CGKeyCode
    switch value.lowercased() {
    case "return": keyCode = 36
    case "tab": keyCode = 48
    case "space": keyCode = 49
    case "delete": keyCode = 51
    case "escape": keyCode = 53
    case "left": keyCode = 123
    case "right": keyCode = 124
    case "down": keyCode = 125
    case "up": keyCode = 126
    case let key where key.count == 1:
      guard let code = Self.characterKeyCodes[key] else {
        if flags.isEmpty { type(key); return }
        throw WorkflowReplayError.unsupportedKey(description)
      }
      keyCode = code
    default: throw WorkflowReplayError.unsupportedKey(description)
    }
    let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
  }

  private func press(_ event: KeyboardHIDEvent) {
    let flags = CGEventFlags(rawValue: event.modifierFlags)
    let down = CGEvent(
      keyboardEventSource: nil,
      virtualKey: CGKeyCode(event.virtualKeyCode),
      keyDown: true
    )
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(18_000)
    let up = CGEvent(
      keyboardEventSource: nil,
      virtualKey: CGKeyCode(event.virtualKeyCode),
      keyDown: false
    )
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
  }

  private static let characterKeyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
    "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
    "n": 45, "m": 46, ".": 47, "`": 50,
  ]
}

private extension String.UTF16View {
  func chunked(maximumCount: Int) -> [[UInt16]] {
    var chunks: [[UInt16]] = []
    var chunk: [UInt16] = []
    for codeUnit in self {
      chunk.append(codeUnit)
      if chunk.count == maximumCount {
        chunks.append(chunk)
        chunk = []
      }
    }
    if !chunk.isEmpty { chunks.append(chunk) }
    return chunks
  }
}
