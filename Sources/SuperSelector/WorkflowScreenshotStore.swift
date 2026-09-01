import Foundation

/// Keeps JPEG payloads out of the observable workflow model and JSON editor.
/// Metadata retains stable asset UUIDs; image bytes are loaded only for the selected step or export.
final class WorkflowScreenshotStore {
  private let directory: URL

  init(baseDirectory: URL) {
    directory = baseDirectory.appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func data(for id: UUID) -> Data? {
    try? Data(contentsOf: url(for: id), options: .mappedIfSafe)
  }

  func store(_ asset: WorkflowScreenshotAsset) throws {
    try asset.jpegData.write(to: url(for: asset.id), options: .atomic)
  }

  func store(_ assets: [UUID: WorkflowScreenshotAsset]) throws {
    for asset in assets.values { try store(asset) }
  }

  func assets(for ids: Set<UUID>) -> [UUID: WorkflowScreenshotAsset] {
    Dictionary(
      uniqueKeysWithValues: ids.compactMap { id in
        data(for: id).map { (id, WorkflowScreenshotAsset(id: id, jpegData: $0)) }
      })
  }

  func prune(retaining ids: Set<UUID>) {
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
    else { return }
    for file in files where file.pathExtension == "jpg" {
      guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
        !ids.contains(id)
      else { continue }
      try? FileManager.default.removeItem(at: file)
    }
  }

  private func url(for id: UUID) -> URL {
    directory.appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
  }
}
