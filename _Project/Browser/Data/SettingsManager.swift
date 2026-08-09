import Foundation
import Security

final class SettingsManager {
    static let shared = SettingsManager()
    private init() {}

    private let defaults = UserDefaults.standard

    // Keys kept identical to the existing app — no migration needed.
    private enum Keys {
        static let homepage          = "homepage"
        static let pageZoom          = "PageZoom"
        static let suppressHints     = "DontShowHintsOnLaunch"
        static let savedURLtoReopen  = "savedURLtoReopen"
        static let userAgent         = "UserAgent"
        static let applicationCookie = "ApplicationCookie"
        static let passwordSaveDeniedHosts = "PasswordSaveDeniedHosts"
        static let searchURLTemplate = "SearchURLTemplate"
        static let preferDarkSites = "PreferDarkSites"
    }

    private enum CookieKeychain {
        static let service = "com.tvb.browser.cookies"
        static let account = "http-cookie-archive"
    }

    /// Fixed Safari desktop UA for all pages.
    static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 12_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Safari/605.1.15"

    /// Default Google search template. `%@` is replaced with a percent-encoded query.
    static let defaultSearchURLTemplate = "https://www.google.com/search?q=%@"

    var homepage: String {
        get { defaults.string(forKey: Keys.homepage) ?? "" }
        set { defaults.set(newValue, forKey: Keys.homepage) }
    }

    var hasHomepage: Bool {
        !homepage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whole-page zoom factor (1.0 = 100%).
    var pageZoom: CGFloat {
        get {
            guard defaults.object(forKey: Keys.pageZoom) != nil else {
                return DSMetrics.pageZoomDefault
            }
            let value = CGFloat(defaults.double(forKey: Keys.pageZoom))
            return min(DSMetrics.pageZoomMax, max(DSMetrics.pageZoomMin, value))
        }
        set {
            let clamped = min(DSMetrics.pageZoomMax, max(DSMetrics.pageZoomMin, newValue))
            defaults.set(Double(clamped), forKey: Keys.pageZoom)
        }
    }

    var suppressHints: Bool {
        get { defaults.bool(forKey: Keys.suppressHints) }
        set { defaults.set(newValue, forKey: Keys.suppressHints) }
    }

    /// Prefer dark appearance for web pages when the site supports it (default off — safer for images on tvOS).
    var preferDarkSites: Bool {
        get {
            guard defaults.object(forKey: Keys.preferDarkSites) != nil else { return false }
            return defaults.bool(forKey: Keys.preferDarkSites)
        }
        set { defaults.set(newValue, forKey: Keys.preferDarkSites) }
    }

    var savedURLtoReopen: String? {
        get { defaults.string(forKey: Keys.savedURLtoReopen) }
        set {
            if let v = newValue { defaults.set(v, forKey: Keys.savedURLtoReopen) }
            else { defaults.removeObject(forKey: Keys.savedURLtoReopen) }
        }
    }

    var searchURLTemplate: String {
        get {
            let stored = defaults.string(forKey: Keys.searchURLTemplate)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty, stored.contains("%@") {
                return stored
            }
            return Self.defaultSearchURLTemplate
        }
        set { defaults.set(newValue, forKey: Keys.searchURLTemplate) }
    }

    func searchURL(forQuery query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return searchURLTemplate.replacingOccurrences(of: "%@", with: encoded)
    }

    func registerUserAgentDefault() {
        defaults.set(SettingsManager.defaultUserAgent, forKey: Keys.userAgent)
        defaults.register(defaults: [Keys.userAgent: SettingsManager.defaultUserAgent])
    }

    // MARK: - Password save deny-list

    func isPasswordSavingDenied(forHost host: String) -> Bool {
        let key = CredentialStore.normalizedHost(from: "https://\(host)") ?? host.lowercased()
        return deniedPasswordHosts().contains(key)
    }

    func denyPasswordSaving(forHost host: String) {
        let key = CredentialStore.normalizedHost(from: "https://\(host)") ?? host.lowercased()
        var set = deniedPasswordHosts()
        set.insert(key)
        defaults.set(Array(set), forKey: Keys.passwordSaveDeniedHosts)
    }

    private func deniedPasswordHosts() -> Set<String> {
        Set(defaults.stringArray(forKey: Keys.passwordSaveDeniedHosts) ?? [])
    }

    // MARK: - Cookie Persistence (Keychain)

    func saveCookies() {
        guard let cookies = HTTPCookieStorage.shared.cookies else { return }
        let data: Data?
        if let secure = try? NSKeyedArchiver.archivedData(withRootObject: cookies, requiringSecureCoding: true) {
            data = secure
        } else {
            data = try? NSKeyedArchiver.archivedData(withRootObject: cookies, requiringSecureCoding: false)
        }
        guard let data else { return }
        _ = Self.persistCookieData(data)
        // Remove legacy UserDefaults blob if present.
        defaults.removeObject(forKey: Keys.applicationCookie)
    }

    func restoreCookies() {
        let data = Self.loadCookieData() ?? defaults.data(forKey: Keys.applicationCookie)
        guard let data, let cookies = unarchiveCookies(from: data) else { return }
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        // Migrate legacy UserDefaults → Keychain once.
        if defaults.data(forKey: Keys.applicationCookie) != nil {
            _ = Self.persistCookieData(data)
            defaults.removeObject(forKey: Keys.applicationCookie)
        }
    }

    private func unarchiveCookies(from data: Data) -> [HTTPCookie]? {
        if let cookies = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, HTTPCookie.self],
            from: data
        ) as? [HTTPCookie] {
            return cookies
        }
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            defer { unarchiver.finishDecoding() }
            return unarchiver.decodeObject(
                of: [NSArray.self, HTTPCookie.self],
                forKey: NSKeyedArchiveRootObjectKey
            ) as? [HTTPCookie]
        } catch {
            return nil
        }
    }

    @discardableResult
    private static func persistCookieData(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: CookieKeychain.service,
            kSecAttrAccount as String: CookieKeychain.account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func loadCookieData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: CookieKeychain.service,
            kSecAttrAccount as String: CookieKeychain.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}
