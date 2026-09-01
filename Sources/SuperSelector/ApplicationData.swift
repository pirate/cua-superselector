import Darwin
import Foundation

struct SuperSelectorDataPaths: Equatable, Sendable {
  static let directoryName = "SuperSelector"

  let rootDirectory: URL

  init(rootDirectory: URL) {
    self.rootDirectory = rootDirectory.standardizedFileURL
  }

  static func canonical(fileManager: FileManager = .default) -> Self {
    let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    return Self(
      rootDirectory: applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
    )
  }

  var workflowLog: URL {
    rootDirectory.appendingPathComponent("workflow-log.json", isDirectory: false)
  }

  var screenshots: URL {
    rootDirectory.appendingPathComponent("screenshots", isDirectory: true)
  }

  var instanceLock: URL {
    rootDirectory.appendingPathComponent("instance.lock", isDirectory: false)
  }

  func prepare(fileManager: FileManager = .default) throws {
    try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
  }
}

enum SuperSelectorInstanceLockError: Error, LocalizedError {
  case alreadyRunning(ownerPID: pid_t?)
  case unavailable(path: String, code: Int32)

  var errorDescription: String? {
    switch self {
    case .alreadyRunning:
      return "Another SuperSelector instance is already using the canonical data directory."
    case .unavailable(let path, let code):
      return "Unable to lock the SuperSelector data directory at \(path) (errno \(code))."
    }
  }
}

/// Prevents separately launched debug, release, and app-bundle binaries from keeping
/// divergent in-memory snapshots and overwriting the same workflow log.
final class SuperSelectorInstanceLock {
  private let descriptor: Int32

  init(lockFile: URL) throws {
    let descriptor = Darwin.open(lockFile.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw SuperSelectorInstanceLockError.unavailable(path: lockFile.path, code: errno)
    }

    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let lockError = errno
      let ownerPID = Self.ownerPID(in: lockFile)
      Darwin.close(descriptor)
      if lockError == EWOULDBLOCK {
        throw SuperSelectorInstanceLockError.alreadyRunning(ownerPID: ownerPID)
      }
      throw SuperSelectorInstanceLockError.unavailable(path: lockFile.path, code: lockError)
    }

    self.descriptor = descriptor
    writeOwnerPID()
  }

  deinit {
    flock(descriptor, LOCK_UN)
    Darwin.close(descriptor)
  }

  private func writeOwnerPID() {
    let value = "\(getpid())\n"
    guard ftruncate(descriptor, 0) == 0, lseek(descriptor, 0, SEEK_SET) >= 0 else { return }
    value.withCString { pointer in
      _ = Darwin.write(descriptor, pointer, strlen(pointer))
    }
    _ = fsync(descriptor)
  }

  private static func ownerPID(in lockFile: URL) -> pid_t? {
    guard let value = try? String(contentsOf: lockFile, encoding: .utf8),
      let rawPID = Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)),
      rawPID > 0
    else { return nil }
    return rawPID
  }
}
