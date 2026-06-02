import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        SettingsManager.shared.registerUserAgentDefault()
        SettingsManager.shared.restoreCookies()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        SettingsManager.shared.saveCookies()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        SettingsManager.shared.saveCookies()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        SettingsManager.shared.restoreCookies()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        SettingsManager.shared.saveCookies()
    }

    // MARK: - Scene support

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
