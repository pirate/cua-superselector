import AppKit
import ApplicationServices
import Foundation

final class HintEngine {
  private static let bandOrder = [
    "scope",
    "semantic",
    "content",
    "capability",
    "state",
    "structure",
    "geometry",
    "native.mac.ax",
  ]

  private let providers: [any HintProvider]
  private let inspectionQueue = DispatchQueue(
    label: "SuperSelector.AccessibilityInspector", qos: .userInteractive)
  private var inspectionInFlight = false
  private var pendingSample: PendingSample?

  private struct PendingSample {
    let quartzPoint: CGPoint
    let completion: (SuperSelectorObservation) -> Void
  }

  init(
    providers: [any HintProvider] = [
      AbsoluteScreenHintProvider(), WindowRelativeHintProvider(), MacAccessibilityHintProvider(),
    ]
  ) {
    self.providers = providers
  }

  func sample(at quartzPoint: CGPoint, completion: @escaping (SuperSelectorObservation) -> Void) {
    pendingSample = PendingSample(quartzPoint: quartzPoint, completion: completion)
    startPendingSampleIfPossible()
  }

  private func startPendingSampleIfPossible() {
    guard !inspectionInFlight, let request = pendingSample else { return }
    pendingSample = nil
    inspectionInFlight = true

    let quartzPoint = request.quartzPoint
    let trusted = AXIsProcessTrusted()
    let appKitPoint = CoordinateSpaces.appKitPoint(fromQuartz: quartzPoint)
    let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }) ?? NSScreen.main
    let displayFrame = screen?.frame ?? .zero
    let displayID =
      screen.flatMap { screen in
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .stringValue
      } ?? "unknown"

    inspectionQueue.async { [providers] in
      let element = trusted ? AccessibilityInspector.inspect(at: quartzPoint) : nil
      let scene = SceneSnapshot(
        sampledAt: Date(),
        cursorQuartz: quartzPoint,
        cursorAppKit: appKitPoint,
        displayFrameAppKit: displayFrame,
        displayIdentifier: displayID,
        accessibilityTrusted: trusted,
        accessibilityElement: element
      )
      let providerReports = providers.map { $0.report(for: scene) }
      let providerStatusHints = providerReports.map { report in
        Hint(
          provider: report.provider,
          kind: "provider.status",
          band: "state",
          value: report.state.rawValue,
          metadata: report.detail.map { ["detail": $0] } ?? [:]
        )
      }
      let rawHints = providers.flatMap { $0.hints(for: scene) } + providerStatusHints
      let providerRanks = Dictionary(
        uniqueKeysWithValues: providers.enumerated().map { ($0.element.id, $0.offset) })
      let bandRanks = Dictionary(
        uniqueKeysWithValues: Self.bandOrder.enumerated().map { ($0.element, $0.offset) })
      let hints = rawHints.sorted { left, right in
        let leftKey = (
          providerRanks[left.provider] ?? Int.max,
          bandRanks[left.band] ?? Int.max,
          left.band,
          left.kind,
          left.value
        )
        let rightKey = (
          providerRanks[right.provider] ?? Int.max,
          bandRanks[right.band] ?? Int.max,
          right.band,
          right.kind,
          right.value
        )
        return leftKey < rightKey
      }
      let observation = SuperSelectorObservation(
        scene: scene,
        providerReports: providerReports,
        hints: hints,
        compactSelector: SuperSelectorEncoder.encode(hints)
      )
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        request.completion(observation)
        self.inspectionInFlight = false
        self.startPendingSampleIfPossible()
      }
    }
  }
}
