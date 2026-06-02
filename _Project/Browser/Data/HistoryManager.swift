import Foundation

final class HistoryManager {
    static let shared = HistoryManager()
    private init() { load() }

    struct Entry: Codable {
        let url: String
        let title: String
        let date: Date
    }

    private let maxEntries = 100
    private let defaultsKey = "HISTORY"

    private(set) var entries: [Entry] = []

    func add(url: String, title: String) {
        guard !url.isEmpty else { return }
        entries.removeAll { $0.url == url }
        entries.insert(Entry(url: url, title: title.isEmpty ? url : title, date: Date()), at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save()
    }

    func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Persistence

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
            return
        }
        // Migrate from old format: [[url, title], ...]
        if let old = defaults.array(forKey: defaultsKey) as? [[String]] {
            entries = old.compactMap { item -> Entry? in
                guard item.count >= 2, !item[0].isEmpty else { return nil }
                return Entry(url: item[0], title: item[1].isEmpty ? item[0] : item[1], date: Date())
            }
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
