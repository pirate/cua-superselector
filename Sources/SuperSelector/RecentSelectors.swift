import Foundation

struct RecentSelectorEntry {
  let id: UUID
  let selector: String
  let capturedAt: Date
}

struct RecentSelectorHistory {
  let maximumEntries: Int
  private(set) var entries: [RecentSelectorEntry] = []

  init(maximumEntries: Int = 15) {
    self.maximumEntries = maximumEntries
  }

  mutating func record(_ selector: String, at date: Date = Date()) {
    entries.removeAll { $0.selector == selector }
    entries.insert(
      RecentSelectorEntry(id: UUID(), selector: selector, capturedAt: date),
      at: 0
    )
    if entries.count > maximumEntries {
      entries.removeLast(entries.count - maximumEntries)
    }
  }
}
