import AppKit
import Foundation

/// The one geometry model shared by generation, live overlays, saved screenshots, and replay.
/// Its canonical coordinate space is Quartz global coordinates (top-left origin).
struct SuperSelectorBoxModel: Sendable, Equatable {
  enum DestinationOrigin { case topLeft, bottomLeft }

  struct Projection {
    let screen: CGRect
    let window: CGRect?
    let target: CGRect?
    let pointer: CGPoint
  }

  let screenQuartz: CGRect
  let windowQuartz: CGRect?
  let targetQuartz: CGRect?
  let pointerQuartz: CGPoint

  init(
    screenQuartz: CGRect,
    windowQuartz: CGRect? = nil,
    targetQuartz: CGRect? = nil,
    pointerQuartz: CGPoint
  ) {
    self.screenQuartz = screenQuartz
    self.windowQuartz = windowQuartz
    self.targetQuartz = targetQuartz
    self.pointerQuartz = pointerQuartz
  }

  init(
    screenAppKit: CGRect,
    windowAppKit: CGRect? = nil,
    targetAppKit: CGRect? = nil,
    pointerAppKit: CGPoint
  ) {
    self.init(
      screenQuartz: CoordinateSpaces.quartzRect(fromAppKit: screenAppKit),
      windowQuartz: windowAppKit.map(CoordinateSpaces.quartzRect(fromAppKit:)),
      targetQuartz: targetAppKit.map(CoordinateSpaces.quartzRect(fromAppKit:)),
      pointerQuartz: CoordinateSpaces.quartzPoint(fromAppKit: pointerAppKit)
    )
  }

  init?(hints: [Hint]) {
    guard
      let pointer = hints.first(where: { $0.kind == "pointer.position.screen" })
        .flatMap({ Self.parsePoint($0.value) })
    else { return nil }
    let target = hints.first(where: { $0.kind == "element.frame.screen" })
      .flatMap({ Self.parseRect($0.value) })
    let display =
      hints.first(where: { $0.kind == "display.id" })?
      .metadata["frame"].flatMap(Self.parseRect)
      .map(CoordinateSpaces.quartzRect(fromAppKit:))
      ?? target
      ?? CGRect(x: pointer.x, y: pointer.y, width: 1, height: 1)
    self.init(
      screenQuartz: display,
      windowQuartz: hints.first(where: { $0.kind == "window.frame.screen" })
        .flatMap({ Self.parseRect($0.value) }),
      targetQuartz: target,
      pointerQuartz: pointer
    )
  }

  var normalizedPointer: CGPoint { normalize(pointerQuartz) }
  var normalizedWindow: CGRect? { windowQuartz.flatMap(visibleRect).map(normalize) }
  var normalizedTarget: CGRect? { targetQuartz.flatMap(visibleRect).map(normalize) }

  func projection(in canvas: CGRect, origin: DestinationOrigin) -> Projection {
    Projection(
      screen: canvas,
      window: normalizedWindow.map { project($0, in: canvas, origin: origin) },
      target: normalizedTarget.map { project($0, in: canvas, origin: origin) },
      pointer: project(normalizedPointer, in: canvas, origin: origin)
    )
  }

  /// Preserves the recorded point's fractional position within its old target box.
  func pointer(retargetedTo newTargetQuartz: CGRect) -> CGPoint {
    guard let targetQuartz, targetQuartz.width > 0, targetQuartz.height > 0 else {
      return CGPoint(x: newTargetQuartz.midX, y: newTargetQuartz.midY)
    }
    let relativeX = clamp((pointerQuartz.x - targetQuartz.minX) / targetQuartz.width)
    let relativeY = clamp((pointerQuartz.y - targetQuartz.minY) / targetQuartz.height)
    return CGPoint(
      x: newTargetQuartz.minX + relativeX * newTargetQuartz.width,
      y: newTargetQuartz.minY + relativeY * newTargetQuartz.height
    )
  }

  static func local(_ point: CGPoint, in parent: CGRect) -> CGPoint {
    CGPoint(x: point.x - parent.minX, y: point.y - parent.minY)
  }

  static func local(_ rect: CGRect, in parent: CGRect) -> CGRect {
    rect.offsetBy(dx: -parent.minX, dy: -parent.minY)
  }

  private func normalize(_ point: CGPoint) -> CGPoint {
    guard valid(screenQuartz), point.x.isFinite, point.y.isFinite else {
      return CGPoint(x: 0.5, y: 0.5)
    }
    return CGPoint(
      x: clamp((point.x - screenQuartz.minX) / screenQuartz.width),
      y: clamp((point.y - screenQuartz.minY) / screenQuartz.height)
    )
  }

  private func normalize(_ rect: CGRect) -> CGRect {
    return CGRect(
      x: (rect.minX - screenQuartz.minX) / screenQuartz.width,
      y: (rect.minY - screenQuartz.minY) / screenQuartz.height,
      width: rect.width / screenQuartz.width,
      height: rect.height / screenQuartz.height
    )
  }

  /// AX can report virtual-desktop or stale frames that span well beyond the display under the
  /// pointer. All consumers project only the portion visible on this model's active display.
  private func visibleRect(_ rect: CGRect) -> CGRect? {
    guard valid(screenQuartz), valid(rect) else { return nil }
    let intersection = rect.standardized.intersection(screenQuartz.standardized)
    guard valid(intersection) else { return nil }
    return intersection
  }

  private func valid(_ rect: CGRect) -> Bool {
    !rect.isNull && !rect.isInfinite
      && rect.origin.x.isFinite && rect.origin.y.isFinite
      && rect.width.isFinite && rect.height.isFinite
      && rect.width > 0 && rect.height > 0
  }

  private func project(
    _ point: CGPoint, in canvas: CGRect, origin: DestinationOrigin
  ) -> CGPoint {
    CGPoint(
      x: canvas.minX + point.x * canvas.width,
      y: origin == .topLeft
        ? canvas.minY + point.y * canvas.height
        : canvas.maxY - point.y * canvas.height
    )
  }

  private func project(_ rect: CGRect, in canvas: CGRect, origin: DestinationOrigin) -> CGRect {
    let y =
      origin == .topLeft
      ? canvas.minY + rect.minY * canvas.height
      : canvas.maxY - (rect.minY + rect.height) * canvas.height
    return CGRect(
      x: canvas.minX + rect.minX * canvas.width,
      y: y,
      width: rect.width * canvas.width,
      height: rect.height * canvas.height
    )
  }

  private func clamp(_ value: CGFloat) -> CGFloat {
    value.isFinite ? min(1, max(0, value)) : 0.5
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
