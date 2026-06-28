import Foundation

final class SettingsManager {
    static let shared = SettingsManager()
    private init() {}

    private let defaults = UserDefaults.standard

    // Keys kept identical to the existing app — no migration needed.
    private enum Keys {
        static let homepage          = "homepage"
        static let textFontSize      = "TextFontSize"
        static let isMobileMode      = "MobileMode"
        static let showNavBar        = "ShowTopNavigationBar"
        static let suppressHints     = "DontShowHintsOnLaunch"
        static let savedURLtoReopen  = "savedURLtoReopen"
        static let userAgent         = "UserAgent"
        static let applicationCookie = "ApplicationCookie"
        static let appTheme          = "AppTheme"
    }

    static let mobileUserAgent  = "Mozilla/5.0 (iPad; CPU OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 12_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Safari/605.1.15"

    var homepage: String {
        get { defaults.string(forKey: Keys.homepage) ?? "https://flixtor.to/watch/tv/4616594/hilda/season/1/episode/8" }
        set { defaults.set(newValue, forKey: Keys.homepage) }
    }

    var textFontSize: Int {
        get {
            let v = defaults.integer(forKey: Keys.textFontSize)
            return v == 0 ? 100 : min(200, max(50, v))
        }
        set { defaults.set(min(200, max(50, newValue)), forKey: Keys.textFontSize) }
    }

    var isMobileMode: Bool {
        get { defaults.bool(forKey: Keys.isMobileMode) }
        set { defaults.set(newValue, forKey: Keys.isMobileMode) }
    }

    var showNavBar: Bool {
        get {
            guard defaults.object(forKey: Keys.showNavBar) != nil else { return true }
            return defaults.bool(forKey: Keys.showNavBar)
        }
        set { defaults.set(newValue, forKey: Keys.showNavBar) }
    }

    var suppressHints: Bool {
        get { defaults.bool(forKey: Keys.suppressHints) }
        set { defaults.set(newValue, forKey: Keys.suppressHints) }
    }

    var appTheme: AppTheme {
        get {
            guard let raw = defaults.string(forKey: Keys.appTheme),
                  let theme = AppTheme(rawValue: raw) else { return .system }
            return theme
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appTheme)
            ThemeManager.applyToAllWindows()
        }
    }

    var savedURLtoReopen: String? {
        get { defaults.string(forKey: Keys.savedURLtoReopen) }
        set {
            if let v = newValue { defaults.set(v, forKey: Keys.savedURLtoReopen) }
            else { defaults.removeObject(forKey: Keys.savedURLtoReopen) }
        }
    }

    var activeUserAgent: String {
        isMobileMode ? SettingsManager.mobileUserAgent : SettingsManager.desktopUserAgent
    }

    func registerUserAgentDefault() {
        defaults.register(defaults: [Keys.userAgent: activeUserAgent])
    }

    // MARK: - Cookie Persistence

    func saveCookies() {
        guard let cookies = HTTPCookieStorage.shared.cookies else { return }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: cookies, requiringSecureCoding: false) {
            defaults.set(data, forKey: Keys.applicationCookie)
        }
    }

    func restoreCookies() {
        guard let data = defaults.data(forKey: Keys.applicationCookie),
              let cookies = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, HTTPCookie.self], from: data) as? [HTTPCookie]
        else { return }
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
}
