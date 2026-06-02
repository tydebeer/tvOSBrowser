import Foundation

final class FavoritesManager {
    static let shared = FavoritesManager()
    private init() { load() }

    struct Favorite: Codable, Identifiable {
        let id: UUID
        var url: String
        var name: String
    }

    private let defaultsKey = "FAVORITES"
    private(set) var favorites: [Favorite] = []

    func add(url: String, name: String) {
        guard !url.isEmpty else { return }
        let displayName = name.trimmingCharacters(in: .whitespaces).isEmpty ? url : name
        favorites.append(Favorite(id: UUID(), url: url, name: displayName))
        save()
    }

    func remove(id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Favorite].self, from: data) {
            favorites = decoded
            return
        }
        // Migrate from old format: [[url, title], ...]
        if let old = defaults.array(forKey: defaultsKey) as? [[String]] {
            favorites = old.compactMap { item -> Favorite? in
                guard item.count >= 2, !item[0].isEmpty else { return nil }
                let name = item[1].trimmingCharacters(in: .whitespaces).isEmpty ? item[0] : item[1]
                return Favorite(id: UUID(), url: item[0], name: name)
            }
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
