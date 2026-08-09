import UIKit
import GameController

final class BrowserViewController: GCEventViewController {

    private let viewModel = BrowserViewModel()
    private let contentHost = UIView()
    private let cursorView = CursorView()
    private let clickpadCaptureView = ClickpadCaptureView()
    private let startPageVC = StartPageViewController()
    private lazy var pointer = PointerController(boundsProvider: view)
    private let browserMenu = BrowserMenuPresenter()

    private var lastSelectClickTime: TimeInterval = 0
    private var lastMenuPressTime: TimeInterval = 0
    private var pendingMenuWorkItem: DispatchWorkItem?
    private var isSiteVideoFullscreen = false
    private var didRunStartup = false
    private var didInstallWebContainer = false
    /// Last measured document scroll size (CSS px); used to avoid scrolling into empty canvas.
    private var cachedDocumentSize: CGSize = .zero

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        controllerUserInteractionEnabled = false
        view.backgroundColor = DSColor.background
        setupLayout()
        setupStartPage()
        setupWebContainer()
        setupPointer()
        setupClickpad()
        setupGestures()
        bindCallbacks()
        setupBrowserMenu()
        wireJavaScriptDialogs()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        _ = becomeFirstResponder()
        if !didRunStartup {
            didRunStartup = true
            viewModel.handleStartup()
        }
    }

    private func setupLayout() {
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.backgroundColor = .clear
        view.addSubview(contentHost)

        NSLayoutConstraint.activate([
            contentHost.topAnchor.constraint(equalTo: view.topAnchor),
            contentHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        clickpadCaptureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clickpadCaptureView)
        NSLayoutConstraint.activate([
            clickpadCaptureView.topAnchor.constraint(equalTo: view.topAnchor),
            clickpadCaptureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            clickpadCaptureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            clickpadCaptureView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        view.addSubview(cursorView)
        bringChromeToFront()
    }

    private func setupWebContainer() {
        guard !didInstallWebContainer else { return }
        didInstallWebContainer = true
        let container = viewModel.webContainer
        container.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentHost.topAnchor),
            container.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
        applyPreferDarkSitesToWebView(SettingsManager.shared.preferDarkSites)
    }

    private func setupStartPage() {
        addChild(startPageVC)
        startPageVC.view.translatesAutoresizingMaskIntoConstraints = false
        startPageVC.view.isHidden = true
        view.insertSubview(startPageVC.view, aboveSubview: contentHost)
        NSLayoutConstraint.activate([
            startPageVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            startPageVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            startPageVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            startPageVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        startPageVC.didMove(toParent: self)

        startPageVC.onOpenURL = { [weak self] url in
            self?.viewModel.load(rawInput: url)
        }

        viewModel.onStartPageVisibilityChanged = { [weak self] visible in
            self?.updateStartPageVisibility(visible)
        }
    }

    private func setupBrowserMenu() {
        browserMenu.viewController = self
        browserMenu.onGoForward = { [weak self] in self?.viewModel.goForward() }
        browserMenu.onURLInput = { [weak self] in self?.showURLInput() }
        browserMenu.onReload = { [weak self] in self?.viewModel.reload() }
        browserMenu.onGoStartPage = { [weak self] in self?.viewModel.showStartPage() }
        browserMenu.onLoadHomepage = { [weak self] in self?.viewModel.loadHomepage() }
        browserMenu.onSetHomepage = { [weak self] in self?.viewModel.setCurrentPageAsHomepage() }
        browserMenu.onZoomIn = { [weak self] in
            self?.viewModel.zoomIn()
            self?.syncZoomMenuPercent()
            self?.refreshCachedDocumentSizeAndClampScroll()
        }
        browserMenu.onZoomOut = { [weak self] in
            self?.viewModel.zoomOut()
            self?.syncZoomMenuPercent()
            self?.refreshCachedDocumentSizeAndClampScroll()
        }
        browserMenu.onResetZoom = { [weak self] in
            self?.viewModel.resetZoom()
            self?.syncZoomMenuPercent()
            self?.refreshCachedDocumentSizeAndClampScroll()
        }
        browserMenu.onTogglePreferDarkSites = { [weak self] in
            self?.togglePreferDarkSites()
        }
        browserMenu.onClearCache = { [weak self] in
            self?.showConfirmClear(
                title: "Clear Cache?",
                message: "Cached website data will be removed.",
                confirmTitle: "Clear Cache"
            ) { [weak self] in
                self?.viewModel.clearCache()
            }
        }
        browserMenu.onClearCookies = { [weak self] in
            self?.showConfirmClear(
                title: "Clear Cookies?",
                message: "You may be signed out of websites.",
                confirmTitle: "Clear Cookies"
            ) { [weak self] in
                self?.viewModel.clearCookies()
            }
        }
        browserMenu.onClearHistory = { [weak self] in
            self?.showConfirmClear(
                title: "Clear History?",
                message: "Browsing history will be removed.",
                confirmTitle: "Clear History"
            ) { [weak self] in
                HistoryManager.shared.clear()
                self?.startPageVC.reloadContent()
            }
        }
        browserMenu.onSavedPasswords = { [weak self] in self?.showSavedPasswordsMenu() }
        browserMenu.onDismissed = { [weak self] in self?.reclaimPointerControl() }
    }

    private func updateStartPageVisibility(_ visible: Bool) {
        startPageVC.view.isHidden = !visible
        viewModel.webContainer.isHidden = visible
        if visible {
            startPageVC.reloadContent()
        }
        bringChromeToFront()
    }

    private func bringChromeToFront() {
        view.bringSubviewToFront(startPageVC.view)
        view.bringSubviewToFront(clickpadCaptureView)
        view.bringSubviewToFront(cursorView)
    }

    private func setupClickpad() {
        clickpadCaptureView.onMoved = { [weak self] dx, dy in
            self?.pointer.moveBy(dx: dx, dy: dy)
        }
        clickpadCaptureView.onTapped = { [weak self] in
            self?.fireSelectClick()
        }
        clickpadCaptureView.onScrolled = { [weak self] dx, dy in
            guard let self else { return }
            if self.viewModel.isShowingStartPage {
                self.scrollStartPageBy(dx: dx, dy: dy)
            } else {
                self.scrollWebViewBy(dx: dx, dy: dy)
            }
        }
    }

    private func setupPointer() {
        pointer.onPositionChanged = { [weak self] point in
            self?.cursorView.moveTo(point)
        }
        pointer.onHoverUpdate = { [weak self] _ in
            self?.updatePointerHover()
        }
        pointer.onEdgeScroll = { [weak self] dx, dy in
            self?.scrollWebViewBy(dx: dx, dy: dy)
        }
        pointer.resetToCenter()
        updatePointerHover()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pointer.clampToBounds()
    }

    private func setupGestures() {
        let selectTap = UITapGestureRecognizer(target: self, action: #selector(handleSelectTap))
        selectTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(selectTap)
    }

    @objc private func handleSelectTap(_ gr: UITapGestureRecognizer) {
        guard gr.state == .ended else { return }
        fireSelectClick()
    }

    private func fireSelectClick() {
        reclaimPointerControl()
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSelectClickTime > 0.35 else { return }
        lastSelectClickTime = now
        handlePointerSelectPress()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .select }) {
            clickpadCaptureView.beginClickHold()
            return
        }

        guard presentedViewController == nil,
              let press = presses.first,
              isDirectionalPress(press.type) else {
            super.pressesBegan(presses, with: event)
            return
        }

        reclaimPointerControl()
        pointer.beginDirectionalPress(press.type)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let press = presses.first, isDirectionalPress(press.type) {
            pointer.endDirectionalPress()
            return
        }

        guard let press = presses.first else {
            super.pressesEnded(presses, with: event)
            return
        }

        switch press.type {
        case .menu:
            handleMenuPress()
        case .select:
            let scrolled = clickpadCaptureView.didScrollWhileClickHeld
            clickpadCaptureView.endClickHold()
            if presentedViewController == nil, !scrolled {
                fireSelectClick()
            }
        case .playPause:
            viewModel.toggleMediaPlayback()
        default:
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .select }) {
            clickpadCaptureView.endClickHold()
        }
        pointer.cancelDirectionalPress()
        super.pressesCancelled(presses, with: event)
    }

    private func isDirectionalPress(_ type: UIPress.PressType) -> Bool {
        switch type {
        case .upArrow, .downArrow, .leftArrow, .rightArrow: return true
        default: return false
        }
    }

    private func scrollWebViewBy(dx: CGFloat, dy: CGFloat) {
        let bridge = viewModel.webContainer.bridge
        let sv = bridge.scrollView
        let zoom = max(bridge.pageZoom(), CGFloat(0.01))
        let doc = cachedDocumentSize
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        if doc.width > 1, doc.height > 1 {
            // Prefer real document size so inflated WK contentSize can't scroll into blank canvas.
            contentWidth = min(sv.contentSize.width, doc.width * zoom)
            contentHeight = min(sv.contentSize.height, doc.height * zoom)
        } else {
            contentWidth = sv.contentSize.width
            contentHeight = sv.contentSize.height
        }
        let maxX = max(0, contentWidth - sv.bounds.width)
        let maxY = max(0, contentHeight - sv.bounds.height)
        sv.contentOffset = CGPoint(
            x: min(max(sv.contentOffset.x + dx, 0), maxX),
            y: min(max(sv.contentOffset.y + dy, 0), maxY)
        )
        Task {
            await viewModel.webContainer.jsExecutor.noteUserScrolling()
        }
    }

    private func syncZoomMenuPercent() {
        let percent = Int((SettingsManager.shared.pageZoom * 100).rounded())
        browserMenu.updateZoomPercent(percent)
    }

    private func togglePreferDarkSites() {
        let settings = SettingsManager.shared
        settings.preferDarkSites.toggle()
        let isOn = settings.preferDarkSites
        browserMenu.setPreferDarkSitesSelected(isOn)
        applyPreferDarkSitesToWebView(isOn)
        Task {
            await viewModel.webContainer.jsExecutor.applyPreferDarkSites(isOn)
        }
    }

    private func applyPreferDarkSitesToWebView(_ enabled: Bool) {
        viewModel.webContainer.bridge.webView.overrideUserInterfaceStyle = enabled ? .dark : .unspecified
    }

    private func refreshCachedDocumentSizeAndClampScroll() {
        Task { @MainActor in
            let size = await viewModel.webContainer.jsExecutor.documentScrollSize()
            guard size.width > 1 || size.height > 1 else { return }
            self.cachedDocumentSize = size
            let bridge = self.viewModel.webContainer.bridge
            let sv = bridge.scrollView
            let zoom = max(bridge.pageZoom(), CGFloat(0.01))
            let maxX = max(0, min(sv.contentSize.width, size.width * zoom) - sv.bounds.width)
            let maxY = max(0, min(sv.contentSize.height, size.height * zoom) - sv.bounds.height)
            let x = min(max(sv.contentOffset.x, 0), maxX)
            let y = min(max(sv.contentOffset.y, 0), maxY)
            if abs(x - sv.contentOffset.x) > 0.5 || abs(y - sv.contentOffset.y) > 0.5 {
                sv.contentOffset = CGPoint(x: x, y: y)
            }
        }
    }

    private func scrollStartPageBy(dx: CGFloat, dy: CGFloat) {
        startPageVC.scrollBy(dx: dx, dy: dy)
    }

    private func updatePointerHover() {
        let pointerPosition = pointer.position

        if viewModel.isShowingStartPage {
            let local = startPageVC.view.convert(pointerPosition, from: view)
            startPageVC.updatePointer(at: local)
            return
        }

        pointer.applyEdgeScrollIfNeeded()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.webContainer.jsExecutor.schedulePointerUpdate(at: pointerPosition)
        }
    }

    private func handlePointerSelectPress() {
        let pointerPosition = pointer.position

        if viewModel.isShowingStartPage {
            let local = startPageVC.view.convert(pointerPosition, from: view)
            _ = startPageVC.handlePointerClick(at: local)
            return
        }

        viewModel.handlePointerClick(at: pointerPosition)
    }

    private func bindCallbacks() {
        viewModel.onLoadError = { [weak self] error, requestURL in
            self?.showLoadError(error, requestURL: requestURL)
        }
        viewModel.onTextInputRequested = { [weak self] request in
            self?.showWebTextInput(request)
        }
        viewModel.onLoginAutofillRequested = { [weak self] credentials, request in
            self?.showLoginAutofillPicker(credentials: credentials, request: request)
        }
        viewModel.onSavePasswordRequested = { [weak self] prompt in
            self?.showSavePasswordPrompt(prompt)
        }
        viewModel.onVideoFullscreenRequested = { [weak self] in
            self?.enterSiteVideoFullscreen()
        }
        viewModel.onVideoFullscreenExitRequested = { [weak self] in
            self?.exitSiteVideoFullscreen()
        }
        viewModel.onClickCompleted = { [weak self] in
            self?.reclaimPointerControl()
        }
        viewModel.onBrowsingUnavailable = { [weak self] in
            self?.showBrowsingUnavailable()
        }
        viewModel.onPageReady = { [weak self] in
            self?.refreshCachedDocumentSizeAndClampScroll()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.cancelPendingWork()
    }

    private func wireJavaScriptDialogs() {
        let bridge = viewModel.webContainer.bridge
        bridge.onJavaScriptAlert = { [weak self] message, completion in
            guard let self else {
                completion()
                return
            }
            if self.presentedViewController != nil {
                completion()
                return
            }
            var didComplete = false
            let finish = {
                guard !didComplete else { return }
                didComplete = true
                completion()
            }
            let menu = SafariMenuViewController(
                title: "Alert",
                sections: [
                    SafariMenuSection(title: message, rows: [
                        SafariMenuRow(title: "OK", symbol: "checkmark", action: {})
                    ])
                ]
            )
            menu.onDismiss = { [weak self] in
                finish()
                self?.reclaimPointerControl()
            }
            self.present(menu, animated: false)
        }
        bridge.onJavaScriptConfirm = { [weak self] message, completion in
            guard let self else {
                completion(false)
                return
            }
            if self.presentedViewController != nil {
                completion(false)
                return
            }
            var didComplete = false
            var chosenResult = false
            let finish = {
                guard !didComplete else { return }
                didComplete = true
                completion(chosenResult)
            }
            let menu = SafariMenuViewController(
                title: "Confirm",
                sections: [
                    SafariMenuSection(title: message, rows: [
                        SafariMenuRow(title: "OK", symbol: "checkmark", action: {
                            chosenResult = true
                        }),
                        SafariMenuRow(title: "Cancel", symbol: "xmark", action: {
                            chosenResult = false
                        }),
                    ])
                ]
            )
            menu.onDismiss = { [weak self] in
                finish()
                self?.reclaimPointerControl()
            }
            self.present(menu, animated: false)
        }
    }

    private func reclaimPointerControl() {
        _ = becomeFirstResponder()
        view.becomeFirstResponder()
    }

    private func enterSiteVideoFullscreen() {
        isSiteVideoFullscreen = true
        view.backgroundColor = .black
        contentHost.backgroundColor = .black
        viewModel.webContainer.backgroundColor = .black
        reclaimPointerControl()
    }

    private func exitSiteVideoFullscreen() {
        guard isSiteVideoFullscreen else {
            viewModel.exitVideoFullscreen()
            return
        }
        isSiteVideoFullscreen = false
        viewModel.exitVideoFullscreen()
        view.backgroundColor = DSColor.background
        contentHost.backgroundColor = .clear
        viewModel.webContainer.applyCanvasColors()
        reclaimPointerControl()
    }

    private func handleMenuPress() {
        if presentedViewController != nil {
            pendingMenuWorkItem?.cancel()
            pendingMenuWorkItem = nil
            lastMenuPressTime = 0
            dismiss(animated: true)
            reclaimPointerControl()
            return
        }

        if isSiteVideoFullscreen {
            pendingMenuWorkItem?.cancel()
            pendingMenuWorkItem = nil
            lastMenuPressTime = 0
            exitSiteVideoFullscreen()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMenuPressTime <= DSMetrics.menuDoublePressInterval {
            pendingMenuWorkItem?.cancel()
            pendingMenuWorkItem = nil
            lastMenuPressTime = 0
            showBrowserMenu()
            return
        }

        lastMenuPressTime = now
        pendingMenuWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingMenuWorkItem = nil
            self?.lastMenuPressTime = 0
            self?.handleSingleMenuPress()
        }
        pendingMenuWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DSMetrics.menuDoublePressInterval,
            execute: work
        )
    }

    private func handleSingleMenuPress() {
        if viewModel.webContainer.bridge.canGoBack {
            viewModel.goBack()
        } else if !viewModel.isShowingStartPage {
            viewModel.showStartPage()
        }
    }

    private func showBrowserMenu() {
        browserMenu.present(
            pageTitle: viewModel.currentTitle,
            currentURL: viewModel.currentURL,
            canGoForward: viewModel.canGoForward,
            hasPage: !viewModel.isShowingStartPage && (viewModel.currentURL?.isEmpty == false),
            isShowingStartPage: viewModel.isShowingStartPage
        )
    }

    private func showWebTextInput(_ request: WebTextInputRequest) {
        guard presentedViewController == nil else { return }
        let sheet = SafariAddressSheetViewController()
        sheet.sheetTitle = request.title
        sheet.placeholder = request.placeholder
        sheet.initialText = request.currentValue
        sheet.submitButtonTitle = "Go"
        sheet.isSecureTextEntry = request.isSecure
        sheet.keyboardType = request.keyboardType
        sheet.onSubmit = { [weak self] text in
            self?.viewModel.submitTextInput(text)
            self?.reclaimPointerControl()
        }
        present(sheet, animated: false)
    }

    private func showLoginAutofillPicker(credentials: [SavedCredential], request: WebTextInputRequest) {
        guard presentedViewController == nil else { return }

        var rows: [SafariMenuRow] = []
        if credentials.count == 1, let only = credentials.first {
            rows.append(SafariMenuRow(title: "Use Saved Login", subtitle: only.username, symbol: "key.fill", action: { [weak self] in
                self?.viewModel.applySavedLogin(only)
                self?.reclaimPointerControl()
            }))
        } else {
            for cred in credentials {
                rows.append(SafariMenuRow(title: cred.username, subtitle: cred.host, symbol: "person.fill", action: { [weak self] in
                    self?.viewModel.applySavedLogin(cred)
                    self?.reclaimPointerControl()
                }))
            }
        }
        rows.append(SafariMenuRow(title: "Enter Manually", symbol: "keyboard", action: { [weak self] in
            self?.showWebTextInput(request)
        }))

        let menu = SafariMenuViewController(
            title: "Saved Login",
            sections: [SafariMenuSection(title: nil, rows: rows)]
        )
        menu.onDismiss = { [weak self] in self?.reclaimPointerControl() }
        present(menu, animated: false)
    }

    private func showSavePasswordPrompt(_ prompt: SavePasswordPrompt) {
        guard presentedViewController == nil else { return }
        let primaryTitle = prompt.isUpdate ? "Update Password" : "Save Password"
        let menu = SafariMenuViewController(
            title: prompt.isUpdate ? "Update Password?" : "Save Password?",
            sections: [
                SafariMenuSection(title: prompt.host, rows: [
                    SafariMenuRow(title: primaryTitle, subtitle: prompt.username, symbol: "key.fill", action: { [weak self] in
                        self?.viewModel.savePassword(
                            host: prompt.host,
                            username: prompt.username,
                            password: prompt.password
                        )
                        self?.reclaimPointerControl()
                    }),
                    SafariMenuRow(title: "Not Now", symbol: "xmark", action: { [weak self] in
                        self?.reclaimPointerControl()
                    }),
                    SafariMenuRow(title: "Never for This Site", symbol: "eye.slash", style: .destructive, action: { [weak self] in
                        self?.viewModel.neverSavePasswords(forHost: prompt.host)
                        self?.reclaimPointerControl()
                    }),
                ])
            ]
        )
        menu.onDismiss = { [weak self] in self?.reclaimPointerControl() }
        present(menu, animated: false)
    }

    private func showSavedPasswordsMenu() {
        guard presentedViewController == nil else { return }
        let all = viewModel.allSavedCredentials()
        var rows: [SafariMenuRow] = []

        if all.isEmpty {
            rows.append(SafariMenuRow(title: "No Saved Passwords", style: .disabled))
        } else {
            for cred in all {
                rows.append(SafariMenuRow(
                    title: cred.username,
                    subtitle: cred.host,
                    symbol: "key",
                    action: { [weak self] in
                        self?.showDeleteCredentialConfirm(cred)
                    }
                ))
            }
            rows.append(SafariMenuRow(
                title: "Clear All Saved Passwords",
                symbol: "trash",
                style: .destructive,
                action: { [weak self] in
                    self?.showClearAllPasswordsConfirm()
                }
            ))
        }

        let menu = SafariMenuViewController(
            title: "Saved Passwords",
            sections: [SafariMenuSection(title: nil, rows: rows)]
        )
        menu.onDismiss = { [weak self] in self?.reclaimPointerControl() }
        present(menu, animated: false)
    }

    private func showDeleteCredentialConfirm(_ credential: SavedCredential) {
        guard presentedViewController == nil else { return }
        let menu = SafariMenuViewController(
            title: "Delete Password?",
            sections: [
                SafariMenuSection(title: "\(credential.username) · \(credential.host)", rows: [
                    SafariMenuRow(title: "Delete", symbol: "trash", style: .destructive, action: { [weak self] in
                        self?.viewModel.deleteCredential(id: credential.id)
                        self?.showSavedPasswordsMenu()
                    }),
                    SafariMenuRow(title: "Cancel", symbol: "xmark", action: { [weak self] in
                        self?.showSavedPasswordsMenu()
                    }),
                ])
            ]
        )
        menu.onDismiss = { [weak self] in self?.reclaimPointerControl() }
        present(menu, animated: false)
    }

    private func showClearAllPasswordsConfirm() {
        guard presentedViewController == nil else { return }
        let menu = SafariMenuViewController(
            title: "Clear All Passwords?",
            sections: [
                SafariMenuSection(title: "This cannot be undone", rows: [
                    SafariMenuRow(title: "Clear All", symbol: "trash", style: .destructive, action: { [weak self] in
                        self?.viewModel.clearAllSavedPasswords()
                        self?.showSavedPasswordsMenu()
                    }),
                    SafariMenuRow(title: "Cancel", symbol: "xmark", action: { [weak self] in
                        self?.showSavedPasswordsMenu()
                    }),
                ])
            ]
        )
        menu.onDismiss = { [weak self] in self?.reclaimPointerControl() }
        present(menu, animated: false)
    }

    private func showBrowsingUnavailable() {
        guard presentedViewController == nil else { return }
        let menu = SafariMenuViewController(
            title: "Browsing Unavailable",
            sections: [
                SafariMenuSection(
                    title: "WebKit could not be loaded on this device.",
                    rows: [
                        SafariMenuRow(title: "OK", symbol: "xmark", action: { [weak self] in
                            self?.reclaimPointerControl()
                        })
                    ]
                )
            ]
        )
        menu.onDismiss = { [weak self] in self?.reclaimPointerControl() }
        present(menu, animated: false)
    }

    private func showConfirmClear(
        title: String,
        message: String,
        confirmTitle: String,
        action: @escaping () -> Void
    ) {
        guard presentedViewController == nil else { return }
        let menu = SafariMenuViewController(
            title: title,
            sections: [
                SafariMenuSection(title: message, rows: [
                    SafariMenuRow(title: confirmTitle, symbol: "trash", style: .destructive, action: { [weak self] in
                        action()
                        self?.reclaimPointerControl()
                    }),
                    SafariMenuRow(title: "Cancel", symbol: "xmark", action: { [weak self] in
                        self?.reclaimPointerControl()
                    }),
                ])
            ]
        )
        menu.onDismiss = { [weak self] in self?.reclaimPointerControl() }
        present(menu, animated: false)
    }

    private func showURLInput() {
        NativeTextPrompt.presentAddressPrompt(
            from: self,
            initialText: viewModel.currentURL ?? "",
            onGo: { [weak self] text in
                self?.viewModel.load(rawInput: text)
                self?.reclaimPointerControl()
            },
            onSearch: { [weak self] text in
                guard let self else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.reclaimPointerControl()
                    return
                }
                self.viewModel.load(rawInput: self.viewModel.searchURL(forQuery: trimmed))
                self.reclaimPointerControl()
            },
            onCancel: { [weak self] in
                self?.reclaimPointerControl()
            }
        )
    }

    private func showLoadError(_ error: Error, requestURL: String?) {
        var rows: [SafariMenuRow] = []
        if let url = requestURL, !url.isEmpty {
            rows.append(SafariMenuRow(title: "Search Google", symbol: "magnifyingglass", action: { [weak self] in
                let clean = url
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                    .replacingOccurrences(of: "www.", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard let self else { return }
                self.viewModel.load(rawInput: self.viewModel.searchURL(forQuery: clean))
            }))
        }
        rows.append(SafariMenuRow(title: "Reload Page", symbol: "arrow.clockwise", action: { [weak self] in
            self?.viewModel.reload()
        }))
        rows.append(SafariMenuRow(title: "Open Browser Menu", symbol: "list.bullet", action: { [weak self] in
            self?.showBrowserMenu()
        }))

        let menu = SafariMenuViewController(
            title: "Could Not Load Page",
            sections: [
                SafariMenuSection(title: error.localizedDescription, rows: rows)
            ]
        )
        menu.onDismiss = { [weak self] in self?.reclaimPointerControl() }
        present(menu, animated: false)
    }
}
