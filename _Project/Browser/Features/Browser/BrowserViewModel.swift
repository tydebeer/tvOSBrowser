import UIKit

enum WebTextFieldRole: String {
    case username
    case password
    case other
}

struct WebTextInputRequest {
    let title: String
    let currentValue: String
    let placeholder: String
    let isSecure: Bool
    let isLoginField: Bool
    let fieldRole: WebTextFieldRole
    let keyboardType: UIKeyboardType
}

struct SavePasswordPrompt {
    let host: String
    let username: String
    let password: String
    let isUpdate: Bool
}

@MainActor
final class BrowserViewModel {

    let webContainer: WebViewContainer

    var onLoadError: ((Error, String?) -> Void)?
    var onStartPageVisibilityChanged: ((Bool) -> Void)?
    var onTextInputRequested: ((WebTextInputRequest) -> Void)?
    var onLoginAutofillRequested: (([SavedCredential], WebTextInputRequest) -> Void)?
    var onSavePasswordRequested: ((SavePasswordPrompt) -> Void)?
    var onVideoFullscreenRequested: (() -> Void)?
    var onVideoFullscreenExitRequested: (() -> Void)?
    var onClickCompleted: (() -> Void)?
    var onBrowsingUnavailable: (() -> Void)?
    /// Fired after a page finishes loading and layout/pointer hooks are installed.
    var onPageReady: (() -> Void)?

    private let settings = SettingsManager.shared
    private let credentials = CredentialStore.shared

    private(set) var isShowingStartPage = true
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    private var pendingLoginHost: String?
    private var pendingLoginUsername: String?
    private var pendingLoginPassword: String?
    private var lastFieldRole: WebTextFieldRole = .other
    private var didAutofill = false
    private var inputTask: Task<Void, Never>?

    init() {
        webContainer = WebViewContainer(userAgent: SettingsManager.defaultUserAgent)
        webContainer.isHidden = true
        bindBridge()
    }

    func refreshTheme() {
        guard !isShowingStartPage else { return }
        let container = webContainer
        Task {
            await container.jsExecutor.refreshThemeStyles()
        }
    }

    func applyPageZoom() {
        webContainer.bridge.setPageZoom(settings.pageZoom)
    }

    func zoomIn() {
        settings.pageZoom += DSMetrics.pageZoomStep
        applyPageZoom()
    }

    func zoomOut() {
        settings.pageZoom -= DSMetrics.pageZoomStep
        applyPageZoom()
    }

    func resetZoom() {
        settings.pageZoom = DSMetrics.pageZoomDefault
        applyPageZoom()
    }

    // MARK: - Navigation

    func load(rawInput: String) {
        guard let url = URLParser.parse(rawInput) else { return }
        clearLoginDraft()
        isShowingStartPage = false
        onStartPageVisibilityChanged?(false)
        webContainer.isHidden = false
        webContainer.bridge.load(url)
    }

    func showStartPage() {
        clearLoginDraft()
        isShowingStartPage = true
        canGoBack = false
        canGoForward = false
        webContainer.isHidden = true
        onStartPageVisibilityChanged?(true)
    }

    func loadHomepage() {
        if settings.hasHomepage {
            load(rawInput: settings.homepage)
        } else {
            showStartPage()
        }
    }

    func goBack()    { webContainer.bridge.goBack() }
    func goForward() { webContainer.bridge.goForward() }
    func reload()    { webContainer.bridge.reload() }

    var currentURL: String? { isShowingStartPage ? nil : webContainer.bridge.currentURL?.absoluteString }
    var currentTitle: String? { isShowingStartPage ? nil : webContainer.bridge.currentTitle }

    // MARK: - Settings Actions

    func setCurrentPageAsHomepage() {
        if let url = currentURL, !url.isEmpty {
            settings.homepage = url
        }
    }

    func clearCache() {
        webContainer.bridge.clearCache()
    }

    func clearCookies() {
        webContainer.bridge.clearCookies {}
    }

    func handlePointerClick(at screenPoint: CGPoint) {
        guard screenPoint.y >= 0 else { return }
        inputTask?.cancel()
        inputTask = Task { [weak self] in
            guard let self else { return }
            let result = try? await self.webContainer.jsExecutor.click(at: screenPoint)
            guard !Task.isCancelled else { return }
            self.onClickCompleted?()
            guard let result else { return }
            let kind = result["kind"] as? String

            if kind == "videoFullscreen" {
                self.onVideoFullscreenRequested?()
                return
            }
            if kind == "videoFullscreenExit" {
                self.onVideoFullscreenExitRequested?()
                return
            }
            guard kind == "input" else { return }

            let inputType = (result["inputType"] as? String) ?? "text"
            let isSecure: Bool
            if let b = result["isSecure"] as? Bool {
                isSecure = b
            } else if let n = result["isSecure"] as? NSNumber {
                isSecure = n.boolValue
            } else {
                isSecure = inputType == "password"
            }
            let roleString = (result["fieldRole"] as? String) ?? ""
            let fieldRole = WebTextFieldRole(rawValue: roleString) ?? (isSecure ? .password : .other)
            let isLoginField: Bool
            if let b = result["isLoginField"] as? Bool {
                isLoginField = b
            } else if let n = result["isLoginField"] as? NSNumber {
                isLoginField = n.boolValue
            } else {
                isLoginField = fieldRole == .username || fieldRole == .password
            }
            let value = (result["value"] as? String) ?? ""
            let placeholder = (result["placeholder"] as? String) ?? ""
            let label = (result["label"] as? String) ?? ""
            let title = Self.inputSheetTitle(
                label: label,
                placeholder: placeholder,
                inputType: inputType,
                isSecure: isSecure
            )

            let request = WebTextInputRequest(
                title: title,
                currentValue: value,
                placeholder: placeholder.isEmpty ? title : placeholder.capitalized,
                isSecure: isSecure,
                isLoginField: isLoginField,
                fieldRole: fieldRole,
                keyboardType: Self.keyboardType(for: inputType)
            )

            self.lastFieldRole = fieldRole

            if isLoginField, let host = CredentialStore.normalizedHost(from: self.currentURL) {
                let saved = self.credentials.credentials(forHost: host)
                if !saved.isEmpty {
                    self.onLoginAutofillRequested?(saved, request)
                    return
                }
            }
            self.onTextInputRequested?(request)
        }
    }

    func submitTextInput(_ text: String) {
        let host = CredentialStore.normalizedHost(from: currentURL)
        let role = lastFieldRole

        inputTask?.cancel()
        inputTask = Task { [weak self] in
            guard let self else { return }
            await self.webContainer.jsExecutor.fillActiveInput(with: text)
            guard !Task.isCancelled else { return }

            switch role {
            case .username:
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let host, !trimmed.isEmpty else { return }
                self.pendingLoginHost = host
                self.pendingLoginUsername = trimmed
                if let password = self.pendingLoginPassword, !password.isEmpty {
                    self.maybeOfferSave(host: host, username: trimmed, password: password)
                }
            case .password:
                guard let host, !text.isEmpty else { return }
                self.pendingLoginPassword = text
                self.didAutofill = false
                if let username = self.pendingLoginUsername,
                   !username.isEmpty,
                   self.pendingLoginHost == host {
                    self.maybeOfferSave(host: host, username: username, password: text)
                }
            case .other:
                break
            }
        }
    }

    func cancelTextInput() {
        // Sheet dismissed without submit — do not clear draft (user may reopen password).
    }

    func applySavedLogin(_ credential: SavedCredential) {
        inputTask?.cancel()
        inputTask = Task { [weak self] in
            guard let self else { return }
            await self.webContainer.jsExecutor.fillLogin(
                username: credential.username,
                password: credential.password
            )
            guard !Task.isCancelled else { return }
            self.pendingLoginHost = credential.host
            self.pendingLoginUsername = credential.username
            self.pendingLoginPassword = nil
            self.didAutofill = true
        }
    }

    @discardableResult
    func savePassword(host: String, username: String, password: String) -> Bool {
        let ok = credentials.save(host: host, username: username, password: password) != nil
        if ok {
            clearLoginDraft()
        }
        return ok
    }

    func neverSavePasswords(forHost host: String) {
        settings.denyPasswordSaving(forHost: host)
        clearLoginDraft()
    }

    func deleteCredential(id: UUID) {
        _ = credentials.delete(id: id)
    }

    func clearAllSavedPasswords() {
        _ = credentials.clearAll()
    }

    func allSavedCredentials() -> [SavedCredential] {
        credentials.allCredentials()
    }

    func searchURL(forQuery query: String) -> String {
        settings.searchURL(forQuery: query)
    }

    func exitVideoFullscreen() {
        Task {
            await webContainer.jsExecutor.exitVideoFullscreen()
        }
    }

    func seekFullscreenVideo(by seconds: Double) {
        Task {
            _ = await webContainer.jsExecutor.seekFullscreenVideo(by: seconds)
        }
    }

    func toggleMediaPlayback() {
        guard !isShowingStartPage else { return }
        Task {
            await webContainer.jsExecutor.toggleMediaPlayback()
        }
    }

    func cancelPendingWork() {
        inputTask?.cancel()
        inputTask = nil
    }

    private func maybeOfferSave(host: String, username: String, password: String) {
        if settings.isPasswordSavingDenied(forHost: host) { return }
        if didAutofill { return }
        let isUpdate = credentials.hasCredential(host: host, username: username)
        onSavePasswordRequested?(SavePasswordPrompt(
            host: host,
            username: username,
            password: password,
            isUpdate: isUpdate
        ))
    }

    private func clearLoginDraft() {
        pendingLoginHost = nil
        pendingLoginUsername = nil
        pendingLoginPassword = nil
        didAutofill = false
        lastFieldRole = .other
    }

    private static func inputSheetTitle(
        label: String,
        placeholder: String,
        inputType: String,
        isSecure: Bool
    ) -> String {
        if !label.isEmpty { return label.capitalized }
        if !placeholder.isEmpty { return placeholder.capitalized }
        if isSecure || inputType == "password" { return "Password" }
        if inputType == "email" { return "Email" }
        return "Text"
    }

    private static func keyboardType(for inputType: String) -> UIKeyboardType {
        switch inputType {
        case "email": return .emailAddress
        case "number", "tel": return .numberPad
        case "url": return .URL
        case "password": return .default
        default: return .default
        }
    }

    // MARK: - Startup

    func handleStartup() {
        settings.savedURLtoReopen = nil
        if !webContainer.bridge.isAvailable {
            onBrowsingUnavailable?()
        }
        showStartPage()
    }

    // MARK: - Bridge Binding

    private func bindBridge() {
        let bridge = webContainer.bridge

        bridge.onStartLoad = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.clearLoginDraft()
                self.isShowingStartPage = false
                self.webContainer.isHidden = false
                self.onStartPageVisibilityChanged?(false)
            }
        }

        bridge.onFinishLoad = { [weak self] url, title in
            HistoryManager.shared.add(url: url, title: title)
            Task { @MainActor in
                guard let self else { return }
                self.isShowingStartPage = false
                self.canGoBack = self.webContainer.bridge.canGoBack
                self.canGoForward = self.webContainer.bridge.canGoForward
                self.webContainer.isHidden = false

                let sv = self.webContainer.bridge.scrollView
                sv.contentOffset = .zero
                if sv.minimumZoomScale <= 1, sv.maximumZoomScale >= 1 {
                    sv.zoomScale = 1
                }
                self.applyPageZoom()
                self.webContainer.bridge.webView.overrideUserInterfaceStyle =
                    SettingsManager.shared.preferDarkSites ? .dark : .unspecified
                Task {
                    await self.webContainer.jsExecutor.installPageLayoutFix()
                    await self.webContainer.jsExecutor.installPointerStyles()
                    self.onPageReady?()
                }
            }
        }

        bridge.onFailLoad = { [weak self] error, requestURL in
            Task { @MainActor in
                self?.onLoadError?(error, requestURL)
            }
        }

        bridge.onUpdateNavigation = { [weak self] canGoBack, canGoForward in
            Task { @MainActor in
                self?.canGoBack = canGoBack
                self?.canGoForward = canGoForward
            }
        }
    }
}
