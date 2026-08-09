import Foundation
import Security

struct SavedCredential: Codable, Identifiable, Equatable {
    let id: UUID
    var host: String
    var username: String
    var password: String
    var updatedAt: Date

    init(id: UUID = UUID(), host: String, username: String, password: String, updatedAt: Date = Date()) {
        self.id = id
        self.host = host
        self.username = username
        self.password = password
        self.updatedAt = updatedAt
    }
}

extension SavedCredential: CustomDebugStringConvertible {
    var debugDescription: String {
        "SavedCredential(id: \(id), host: \(host), username: \(username), password: <redacted>, updatedAt: \(updatedAt))"
    }
}

enum LoginFieldRole: String {
    case username
    case password
    case other
}

final class CredentialStore {
    static let shared = CredentialStore()

    private enum Keychain {
        static let service = "com.tvb.browser.credentials"
        static let account = "saved-logins"
    }

    private let queue = DispatchQueue(label: "com.tvb.browser.credentials")
    private var credentials: [SavedCredential] = []

    private init() {
        credentials = Self.loadFromKeychain()
    }

    static func normalizedHost(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString), var host = url.host?.lowercased() else {
            return nil
        }
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host.isEmpty ? nil : host
    }

    func allCredentials() -> [SavedCredential] {
        queue.sync { credentials.sorted { $0.updatedAt > $1.updatedAt } }
    }

    func credentials(forHost host: String) -> [SavedCredential] {
        let key = Self.normalizedHost(from: "https://\(host)") ?? host.lowercased()
        return queue.sync {
            credentials
                .filter { $0.host == key }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func hasCredential(host: String, username: String) -> Bool {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = Self.normalizedHost(from: "https://\(host)") ?? Optional(host.lowercased()),
              !trimmedUser.isEmpty else { return false }
        return queue.sync {
            credentials.contains { $0.host == normalized && $0.username == trimmedUser }
        }
    }

    @discardableResult
    func save(host: String, username: String, password: String) -> SavedCredential? {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = Self.normalizedHost(from: "https://\(host)") ?? Optional(host.lowercased()),
              !normalized.isEmpty,
              !trimmedUser.isEmpty,
              !password.isEmpty else { return nil }

        return queue.sync {
            let snapshot = credentials
            var next = credentials
            let saved: SavedCredential

            if let index = next.firstIndex(where: { $0.host == normalized && $0.username == trimmedUser }) {
                next[index].password = password
                next[index].updatedAt = Date()
                saved = next[index]
            } else {
                let item = SavedCredential(host: normalized, username: trimmedUser, password: password)
                next.append(item)
                saved = item
            }

            guard Self.persistToKeychain(next) else {
                credentials = snapshot
                return nil
            }
            credentials = next
            return saved
        }
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        queue.sync {
            let snapshot = credentials
            var next = credentials
            next.removeAll { $0.id == id }
            guard Self.persistToKeychain(next) else {
                credentials = snapshot
                return false
            }
            credentials = next
            return true
        }
    }

    @discardableResult
    func clearAll() -> Bool {
        queue.sync {
            let snapshot = credentials
            guard Self.persistToKeychain([]) else {
                credentials = snapshot
                return false
            }
            credentials = []
            return true
        }
    }

    // MARK: - Keychain

    @discardableResult
    private static func persistToKeychain(_ items: [SavedCredential]) -> Bool {
        guard let data = try? JSONEncoder().encode(items) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keychain.service,
            kSecAttrAccount as String: Keychain.account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    private static func loadFromKeychain() -> [SavedCredential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keychain.service,
            kSecAttrAccount as String: Keychain.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return [] }
        return (try? JSONDecoder().decode([SavedCredential].self, from: data)) ?? []
    }
}
