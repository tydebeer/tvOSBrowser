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
    private var cursorIdleHideWorkItem: DispatchWorkItem?
    private var isSiteVideoFullscreen = false
    private var isPointerOverVideo = false
    private var hoverObserver: NSObjectProtocol?
    /// Second Select on a video is treated as double-click (skip mousedown).
    private var pendingVideoDoubleClick = false
    private var didRunStartup = false
    private var didInstallWebContainer = false
    /// Blocks overlapping chrome presents (menu + subtitles, double Menu, etc.).
    private var isPresentingChrome = false
    /// Swallow Menu after a sheet closes so Back doesn't also exit video fullscreen.
    private var ignoreMenuUntil: TimeInterval = 0
    private weak var videoSettingsMenu: SafariMenuViewController?
    /// Last measured document scroll size (CSS px); used to avoid scrolling into empty canvas.
    private var cachedDocumentSize: CGSize = .zero
    private var pointerPressBeganAt: TimeInterval = 0

    override var canBecomeFirstResponder: Bool { true }

    /// Remote-pad touches begin in the focused view; keep the clickpad focused
    /// unless a sheet is up — otherwise Up is stolen from the Video menu.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let presented = presentedViewController {
            return [presented]
        }
        return [clickpadCaptureView]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // true → Siri Remote clickpad reaches UIKit (ClickpadCaptureView).
        // false would route input only to Game Controller profiles, so the pad wouldn't move the cursor.
        controllerUserInteractionEnabled = true
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pauseMediaForBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @objc private func pauseMediaForBackground() {
        viewModel.pauseAllMedia()
        if isSiteVideoFullscreen {
            exitSiteVideoFullscreen()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        _ = becomeFirstResponder()
        reclaimPointerControl()
        applyPreferDarkAppearance(SettingsManager.shared.preferDarkSites)
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
        applyPreferDarkAppearance(SettingsManager.shared.preferDarkSites)
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
        browserMenu.presentMenu = { [weak self] menu in
            self?.presentChrome(menu) ?? false
        }
        browserMenu.onGoForward = { [weak self] in self?.viewModel.goForward() }
        browserMenu.onURLInput = { [weak self] in self?.showURLInput() }
        browserMenu.onSearch = { [weak self] in self?.showSearch() }
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
        browserMenu.onMouseSpeedIn = { [weak self] in
            self?.viewModel.mouseSpeedIn()
            self?.syncMouseSpeedMenuPercent()
        }
        browserMenu.onMouseSpeedOut = { [weak self] in
            self?.viewModel.mouseSpeedOut()
            self?.syncMouseSpeedMenuPercent()
        }
        browserMenu.onResetMouseSpeed = { [weak self] in
            self?.viewModel.resetMouseSpeed()
            self?.syncMouseSpeedMenuPercent()
        }
        browserMenu.onTogglePreferDarkSites = { [weak self] in
            self?.togglePreferDarkSites()
        }
        browserMenu.onSelectPointerInput = { [weak self] mode in
            self?.selectPointerInput(mode)
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
            guard let self, SettingsManager.shared.usesTrackpadPointer else { return }
            self.noteCursorActivity()
            self.pointer.moveBy(dx: dx, dy: dy)
        }
        clickpadCaptureView.onTapped = { [weak self] in
            guard SettingsManager.shared.usesTrackpadPointer else { return }
            self?.fireSelectClick()
        }
        clickpadCaptureView.onScrolled = { [weak self] dx, dy in
            guard let self, SettingsManager.shared.usesTrackpadPointer else { return }
            self.noteCursorActivity()
            if self.viewModel.isShowingStartPage {
                self.scrollStartPageBy(dx: dx, dy: dy)
            } else {
                self.scrollWebViewBy(dx: dx, dy: dy)
            }
        }
        clickpadCaptureView.onDirectionalPressBegan = { [weak self] type in
            self?.handleDirectionalPressBegan(type)
        }
        clickpadCaptureView.onDirectionalPressEnded = { [weak self] in
            self?.pointer.endDirectionalPress()
        }
    }

    private func setupPointer() {
        pointer.onPositionChanged = { [weak self] point in
            guard let self else { return }
            self.cursorView.moveTo(point)
            if self.isSiteVideoFullscreen {
                self.noteCursorActivity()
            }
        }
        pointer.onHoverUpdate = { [weak self] _ in
            self?.updatePointerHover()
        }
        pointer.onEdgeScroll = { [weak self] dx, dy in
            self?.scrollWebViewBy(dx: dx, dy: dy)
        }
        pointer.resetToCenter()
        updatePointerHover()
        hoverObserver = NotificationCenter.default.addObserver(
            forName: .cursorHoverStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let over: Bool
            if let b = note.userInfo?[CursorHoverKey.overVideo] as? Bool {
                over = b
            } else if let n = note.userInfo?[CursorHoverKey.overVideo] as? NSNumber {
                over = n.boolValue
            } else {
                over = false
            }
            self?.isPointerOverVideo = over
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pointer.clampToBounds()
    }

    private func setupGestures() {
        // Select is handled via pressesBegan/Ended (press-drag-release). No tap recognizer —
        // it would double-fire a second click after pointerUp.
    }

    private func fireSelectClick() {
        reclaimPointerControl()
        noteCursorActivity()
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSelectClickTime > DSMetrics.pointerClickDebounce else { return }
        lastSelectClickTime = now
        handlePointerSelectPress()
    }

    private var isLikelyVideoDoubleClick: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSelectClickTime <= DSMetrics.menuDoublePressInterval else { return false }
        return isPointerOverVideo || viewModel.lastClickWasVideoSurface || isSiteVideoFullscreen
    }

    private func beginPointerPress() {
        reclaimPointerControl()
        noteCursorActivity()
        clickpadCaptureView.beginClickHold()
        pointerPressBeganAt = ProcessInfo.processInfo.systemUptime
        if viewModel.isShowingStartPage { return }
        if isLikelyVideoDoubleClick {
            pendingVideoDoubleClick = true
            return
        }
        pendingVideoDoubleClick = false
        viewModel.handlePointerDown(at: pointer.position)
    }

    private func endPointerPress(cancelled: Bool = false) {
        let dragged = clickpadCaptureView.didDragWhileClickHeld
        let videoDouble = pendingVideoDoubleClick
        pendingVideoDoubleClick = false
        clickpadCaptureView.endClickHold()
        if cancelled {
            if !viewModel.isShowingStartPage, !videoDouble {
                viewModel.handlePointerUp(at: pointer.position, fireClick: false)
            }
            return
        }
        if viewModel.isShowingStartPage {
            if !dragged {
                let now = ProcessInfo.processInfo.systemUptime
                guard now - lastSelectClickTime > DSMetrics.pointerClickDebounce else { return }
                lastSelectClickTime = now
                handlePointerSelectPress()
            }
            return
        }
        if videoDouble {
            lastSelectClickTime = 0
            guard !dragged else { return }
            if isSiteVideoFullscreen {
                exitSiteVideoFullscreen()
            } else {
                viewModel.enterVideoFullscreen(at: pointer.position)
            }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if !dragged {
            if now - lastSelectClickTime <= DSMetrics.pointerClickDebounce {
                viewModel.handlePointerUp(at: pointer.position, fireClick: false)
                return
            }
            if now - pointerPressBeganAt >= DSMetrics.pointerPeekHold {
                lastSelectClickTime = now
                viewModel.handlePointerUp(at: pointer.position, fireClick: false)
                showCardPeekActions()
                return
            }
            lastSelectClickTime = now
        }
        viewModel.handlePointerUp(at: pointer.position, fireClick: !dragged)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Do not call super for Menu — UIKit would treat it as system back and
        // break our single/double-press handling.
        if presses.contains(where: { $0.type == .menu }) {
            return
        }

        if presses.contains(where: { $0.type == .select }) {
            beginPointerPress()
            return
        }

        let arrows = presses.filter { isDirectionalPress($0.type) }
        guard presentedViewController == nil, !arrows.isEmpty else {
            super.pressesBegan(presses, with: event)
            return
        }

        for press in arrows {
            handleDirectionalPressBegan(press.type)
        }
    }

    private func handleDirectionalPressBegan(_ type: UIPress.PressType) {
        guard presentedViewController == nil, isDirectionalPress(type) else { return }

        if isSiteVideoFullscreen, type == .leftArrow || type == .rightArrow {
            let delta = type == .leftArrow
                ? -DSMetrics.videoFullscreenSeekSeconds
                : DSMetrics.videoFullscreenSeekSeconds
            noteCursorActivity()
            viewModel.seekFullscreenVideo(by: delta)
            return
        }

        if isSiteVideoFullscreen, type == .upArrow {
            noteCursorActivity()
            showVideoSettings()
            return
        }

        guard !SettingsManager.shared.usesTrackpadPointer else { return }

        noteCursorActivity()
        pointer.beginDirectionalPress(type)
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
            if presentedViewController == nil {
                endPointerPress()
            } else {
                clickpadCaptureView.endClickHold()
            }
        case .playPause:
            noteCursorActivity()
            viewModel.toggleMediaPlayback()
        default:
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .select }) {
            endPointerPress(cancelled: true)
        }
        // Don't forward Menu cancels to super — same reason as pressesBegan.
        if presses.contains(where: { $0.type == .menu }) {
            pointer.cancelDirectionalPress()
            return
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
        let point = pointer.position
        Task {
            await viewModel.webContainer.jsExecutor.noteUserScrolling()
            await viewModel.webContainer.jsExecutor.dispatchWheel(deltaX: dx, deltaY: dy, at: point)
        }
    }

    private func syncZoomMenuPercent() {
        let percent = Int((SettingsManager.shared.pageZoom * 100).rounded())
        browserMenu.updateZoomPercent(percent)
    }

    private func syncMouseSpeedMenuPercent() {
        let percent = Int((SettingsManager.shared.mouseSpeed * 100).rounded())
        browserMenu.updateMouseSpeedPercent(percent)
    }

    private func syncCaptionSizeMenuPercent() {
        let percent = Int((SettingsManager.shared.captionSize * 100).rounded())
        videoSettingsMenu?.updateCaptionSizePercent(percent)
    }

    private func selectCaptionFont(_ font: CaptionFont) {
        SettingsManager.shared.captionFont = font
        videoSettingsMenu?.setCaptionFont(font)
        applyCaptionStyle()
    }

    private func selectCaptionColor(_ color: CaptionColor) {
        SettingsManager.shared.captionColor = color
        videoSettingsMenu?.setCaptionColor(color)
        applyCaptionStyle()
    }

    private func applyCaptionStyle() {
        Task {
            await viewModel.webContainer.jsExecutor.applyCaptionStyle()
        }
    }

    private func selectPointerInput(_ mode: PointerInputMode) {
        SettingsManager.shared.pointerInputMode = mode
        browserMenu.setPointerInputMode(mode)
        if mode == .trackpad {
            pointer.cancelDirectionalPress()
        }
    }

    private func togglePreferDarkSites() {
        let settings = SettingsManager.shared
        settings.preferDarkSites.toggle()
        let isOn = settings.preferDarkSites
        browserMenu.setPreferDarkSitesSelected(isOn)
        applyPreferDarkAppearance(isOn)
        Task {
            await viewModel.webContainer.jsExecutor.applyPreferDarkSites(isOn)
        }
    }

    private func applyPreferDarkAppearance(_ enabled: Bool) {
        let style: UIUserInterfaceStyle = enabled ? .dark : .unspecified
        view.window?.overrideUserInterfaceStyle = style
        overrideUserInterfaceStyle = style
        startPageVC.overrideUserInterfaceStyle = style
        viewModel.webContainer.bridge.webView.overrideUserInterfaceStyle = style
        view.backgroundColor = DSColor.background
        startPageVC.applyAppearance()
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
            if !self.presentChrome(menu) {
                finish()
            }
        }
        bridge.onJavaScriptConfirm = { [weak self] message, completion in
            guard let self else {
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
            if !self.presentChrome(menu) {
                finish()
            }
        }
    }

    private func reclaimPointerControl() {
        guard presentedViewController == nil else { return }
        _ = becomeFirstResponder()
        view.becomeFirstResponder()
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    /// Single gate for sheets/menus so two presents can't race in the same turn.
    @discardableResult
    private func presentChrome(_ child: UIViewController) -> Bool {
        assert(Thread.isMainThread)
        guard presentedViewController == nil, !isPresentingChrome else { return false }
        isPresentingChrome = true
        clickpadCaptureView.allowsFocus = false

        if let menu = child as? SafariMenuViewController {
            let prior = menu.onDismiss
            menu.onDismiss = { [weak self] in
                self?.noteChromeDismissed()
                prior?()
            }
        }

        present(child, animated: false)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        return true
    }

    private func noteChromeDismissed() {
        ignoreMenuUntil = ProcessInfo.processInfo.systemUptime + DSMetrics.menuDoublePressInterval
        if presentedViewController != nil {
            isPresentingChrome = true
            clickpadCaptureView.allowsFocus = false
            return
        }
        isPresentingChrome = false
        clickpadCaptureView.allowsFocus = true
        reclaimPointerControl()
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        // System search/address alerts present a keyboard window. Forcing a
        // non-animated dismiss here closes that keyboard immediately.
        if presentedViewController is UIAlertController {
            super.dismiss(animated: flag) { [weak self] in
                completion?()
                if self?.presentedViewController == nil {
                    self?.noteChromeDismissed()
                }
            }
            return
        }
        super.dismiss(animated: false) { [weak self] in
            completion?()
            if self?.presentedViewController == nil {
                self?.noteChromeDismissed()
            }
        }
    }

    private func enterSiteVideoFullscreen() {
        isSiteVideoFullscreen = true
        view.backgroundColor = .black
        contentHost.backgroundColor = .black
        viewModel.webContainer.backgroundColor = .black
        reclaimPointerControl()
        noteCursorActivity()
    }

    /// Clears chrome FS state if the page no longer has an active FS video.
    private func exitSiteVideoFullscreen() {
        guard isSiteVideoFullscreen else {
            viewModel.exitVideoFullscreen()
            return
        }
        isSiteVideoFullscreen = false
        cursorIdleHideWorkItem?.cancel()
        cursorIdleHideWorkItem = nil
        cursorView.setCursorVisible(true, animated: false)
        viewModel.exitVideoFullscreen()
        view.backgroundColor = DSColor.background
        contentHost.backgroundColor = .clear
        viewModel.webContainer.applyCanvasColors()
        reclaimPointerControl()
    }

    private func noteCursorActivity() {
        cursorView.setCursorVisible(true, animated: true)
        cursorIdleHideWorkItem?.cancel()
        cursorIdleHideWorkItem = nil
        guard isSiteVideoFullscreen else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isSiteVideoFullscreen else { return }
            self.cursorView.setCursorVisible(false, animated: true)
        }
        cursorIdleHideWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DSMetrics.cursorFullscreenIdleHideDelay,
            execute: work
        )
    }

    private func showVideoSettings() {
        guard isSiteVideoFullscreen, presentedViewController == nil, !isPresentingChrome else { return }
        applyCaptionStyle()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isSiteVideoFullscreen, self.presentedViewController == nil, !self.isPresentingChrome else { return }
            let snap = await self.viewModel.videoSettingsSnapshot()
            self.presentVideoSettings(
                tracks: snap.tracks,
                selectedIndex: snap.selectedIndex,
                rate: snap.rate,
                muted: snap.muted
            )
        }
    }

    private func presentVideoSettings(
        tracks: [[String: Any]],
        selectedIndex: Int,
        rate: Double,
        muted: Bool
    ) {
        guard presentedViewController == nil, !isPresentingChrome else { return }

        var speedRows: [SafariMenuRow] = []
        let speedTitles = DSMetrics.videoPlaybackRates.map { Self.videoRateTitle($0) }
        for option in DSMetrics.videoPlaybackRates {
            let selected = abs(option - rate) < 0.01
            speedRows.append(SafariMenuRow(
                title: Self.videoRateTitle(option),
                symbol: selected ? "checkmark.circle.fill" : "circle",
                style: selected ? .selected : .normal,
                dismissesOnSelect: false,
                action: { [weak self] in
                    self?.viewModel.setVideoPlaybackRate(option)
                    self?.videoSettingsMenu?.setExclusiveSelection(
                        selectedTitle: Self.videoRateTitle(option),
                        titles: speedTitles
                    )
                }
            ))
        }

        let audioRows = [
            SafariMenuRow(
                title: muted ? "Unmute" : "Mute",
                symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                dismissesOnSelect: false,
                action: { [weak self] in
                    guard let self else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let snap = await self.viewModel.videoSettingsSnapshot()
                        self.viewModel.setVideoMuted(!snap.muted)
                    }
                }
            )
        ]

        var subtitleRows: [SafariMenuRow] = []
        var subtitleTitles: [String] = []
        if tracks.isEmpty {
            subtitleRows.append(SafariMenuRow(
                title: "No Subtitles Found",
                subtitle: "This video has no subtitle or caption tracks",
                symbol: "captions.bubble",
                style: .disabled
            ))
        } else {
            let offSelected = selectedIndex < 0
            subtitleTitles.append("Off")
            subtitleRows.append(SafariMenuRow(
                title: "Off",
                symbol: "captions.bubble",
                style: offSelected ? .selected : .normal,
                dismissesOnSelect: false,
                action: { [weak self] in
                    self?.viewModel.setFullscreenSubtitleTrack(index: -1)
                    self?.videoSettingsMenu?.setExclusiveSelection(selectedTitle: "Off", titles: subtitleTitles)
                }
            ))
            for track in tracks {
                let index = (track["index"] as? NSNumber)?.intValue
                    ?? (track["index"] as? Int)
                    ?? -1
                guard index >= 0 else { continue }
                let label = (track["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = (label?.isEmpty == false) ? label! : "Track \(index + 1)"
                let kind = (track["kind"] as? String) ?? "subtitles"
                let isOn = index == selectedIndex
                subtitleTitles.append(title)
                subtitleRows.append(SafariMenuRow(
                    title: title,
                    subtitle: kind.capitalized,
                    symbol: isOn ? "checkmark.circle.fill" : "circle",
                    style: isOn ? .selected : .normal,
                    dismissesOnSelect: false,
                    action: { [weak self] in
                        self?.viewModel.setFullscreenSubtitleTrack(index: index)
                        self?.videoSettingsMenu?.setExclusiveSelection(selectedTitle: title, titles: subtitleTitles)
                    }
                ))
            }
        }

        let settings = SettingsManager.shared
        let captionPercent = Int((settings.captionSize * 100).rounded())
        let captionFont = settings.captionFont
        let captionColor = settings.captionColor
        var captionRows: [SafariMenuRow] = [
            .zoomStepper(
                title: "Caption Size",
                percent: captionPercent,
                onZoomOut: { [weak self] in
                    self?.viewModel.captionSizeOut()
                    self?.syncCaptionSizeMenuPercent()
                    self?.applyCaptionStyle()
                },
                onZoomIn: { [weak self] in
                    self?.viewModel.captionSizeIn()
                    self?.syncCaptionSizeMenuPercent()
                    self?.applyCaptionStyle()
                }
            ),
            SafariMenuRow(
                title: "Reset Caption Size",
                symbol: "arrow.counterclockwise",
                dismissesOnSelect: false,
                action: { [weak self] in
                    self?.viewModel.resetCaptionSize()
                    self?.syncCaptionSizeMenuPercent()
                    self?.applyCaptionStyle()
                }
            ),
        ]
        captionRows.append(contentsOf: CaptionFont.allCases.map { font in
            SafariMenuRow(
                title: font.menuTitle,
                symbol: "textformat",
                style: captionFont == font ? .selected : .normal,
                dismissesOnSelect: false,
                action: { [weak self] in self?.selectCaptionFont(font) }
            )
        })
        captionRows.append(contentsOf: CaptionColor.allCases.map { color in
            SafariMenuRow(
                title: color.menuTitle,
                symbol: "paintpalette",
                style: captionColor == color ? .selected : .normal,
                dismissesOnSelect: false,
                action: { [weak self] in self?.selectCaptionColor(color) }
            )
        })

        let menu = SafariMenuViewController(
            title: "Video",
            sections: [
                SafariMenuSection(title: "Subtitles", rows: subtitleRows),
                SafariMenuSection(title: "Caption Style", rows: captionRows),
                SafariMenuSection(title: "Speed", rows: speedRows),
                SafariMenuSection(title: "Audio", rows: audioRows),
            ]
        )
        menu.onDismiss = { [weak self] in
            self?.videoSettingsMenu = nil
            self?.reclaimPointerControl()
            self?.noteCursorActivity()
        }
        videoSettingsMenu = menu
        presentChrome(menu)
    }

    private static func videoRateTitle(_ rate: Double) -> String {
        if rate.rounded() == rate {
            return "\(Int(rate))×"
        }
        return String(format: "%g×", rate)
    }

    private func showCardPeekActions() {
        let point = pointer.position
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.forceCardHover(at: point)
            try? await Task.sleep(nanoseconds: UInt64(DSMetrics.pointerClickDebounce * 1_000_000_000))
            let snap = await self.viewModel.inspectHoverCard(at: point)
            self.presentCardPeekActions(
                title: snap.title,
                summary: snap.summary,
                youtube: snap.youtube,
                favorite: snap.favorite
            )
        }
    }

    private func presentCardPeekActions(
        title: String,
        summary: String,
        youtube: [[String: Any]],
        favorite: [[String: Any]]
    ) {
        guard presentedViewController == nil, !isPresentingChrome else { return }

        var youtubeRows: [SafariMenuRow] = []
        for item in youtube {
            let id = (item["id"] as? String) ?? ""
            let href = (item["href"] as? String) ?? ""
            let label = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rowTitle = (label?.isEmpty == false) ? label! : "YouTube"
            youtubeRows.append(SafariMenuRow(
                title: rowTitle,
                subtitle: href.isEmpty ? nil : href,
                symbol: "play.rectangle.fill",
                action: { [weak self] in
                    if !id.isEmpty {
                        self?.viewModel.activateCardAction(id: id)
                    } else if !href.isEmpty {
                        self?.viewModel.load(rawInput: href)
                    }
                }
            ))
        }
        if youtubeRows.isEmpty {
            youtubeRows.append(SafariMenuRow(
                title: "No YouTube Found",
                subtitle: "This card has no YouTube link we can see",
                symbol: "play.rectangle",
                style: .disabled
            ))
        }

        var favoriteRows: [SafariMenuRow] = []
        for item in favorite {
            let id = (item["id"] as? String) ?? ""
            let label = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rowTitle = (label?.isEmpty == false) ? label! : "Favorite"
            favoriteRows.append(SafariMenuRow(
                title: rowTitle,
                symbol: "heart.fill",
                action: { [weak self] in
                    guard !id.isEmpty else { return }
                    self?.viewModel.activateCardAction(id: id)
                }
            ))
        }
        if favoriteRows.isEmpty {
            favoriteRows.append(SafariMenuRow(
                title: "No Favorite Found",
                subtitle: "This card has no favorite or watchlist button we can see",
                symbol: "heart",
                style: .disabled
            ))
        }

        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let blurb = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [SafariMenuSection] = []
        if !blurb.isEmpty {
            sections.append(SafariMenuSection(title: "Summary", rows: [
                SafariMenuRow(
                    title: blurb,
                    symbol: "info.circle",
                    dismissesOnSelect: false
                )
            ]))
        }
        sections.append(SafariMenuSection(title: "YouTube", rows: youtubeRows))
        sections.append(SafariMenuSection(title: "Favorite", rows: favoriteRows))

        let menu = SafariMenuViewController(
            title: heading.isEmpty ? "Card" : heading,
            sections: sections
        )
        menu.onDismiss = { [weak self] in
            self?.reclaimPointerControl()
        }
        presentChrome(menu)
    }

    private func handleMenuPress() {
        if ProcessInfo.processInfo.systemUptime < ignoreMenuUntil {
            return
        }

        if presentedViewController != nil || isPresentingChrome {
            pendingMenuWorkItem?.cancel()
            pendingMenuWorkItem = nil
            lastMenuPressTime = 0
            if presentedViewController != nil {
                dismiss(animated: false)
            } else {
                noteChromeDismissed()
            }
            return
        }

        if isSiteVideoFullscreen {
            pendingMenuWorkItem?.cancel()
            pendingMenuWorkItem = nil
            lastMenuPressTime = 0
            exitSiteVideoFullscreen()
            Task { @MainActor [weak self] in
                _ = await self?.viewModel.dismissSiteOverlay()
            }
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await self.viewModel.dismissSiteOverlay() {
                self.pendingMenuWorkItem?.cancel()
                self.pendingMenuWorkItem = nil
                self.lastMenuPressTime = 0
            }
        }
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
        guard presentedViewController == nil, !isPresentingChrome else { return }
        browserMenu.present(
            pageTitle: viewModel.currentTitle,
            currentURL: viewModel.currentURL,
            canGoForward: viewModel.canGoForward,
            hasPage: !viewModel.isShowingStartPage && (viewModel.currentURL?.isEmpty == false),
            isShowingStartPage: viewModel.isShowingStartPage
        )
    }

    private func showWebTextInput(_ request: WebTextInputRequest) {
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
        presentChrome(sheet)
    }

    private func showLoginAutofillPicker(credentials: [SavedCredential], request: WebTextInputRequest) {
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
        presentChrome(menu)
    }

    private func showSavePasswordPrompt(_ prompt: SavePasswordPrompt) {
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
        presentChrome(menu)
    }

    private func showSavedPasswordsMenu() {
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
        presentChrome(menu)
    }

    private func showDeleteCredentialConfirm(_ credential: SavedCredential) {
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
        presentChrome(menu)
    }

    private func showClearAllPasswordsConfirm() {
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
        presentChrome(menu)
    }

    private func showBrowsingUnavailable() {
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
        presentChrome(menu)
    }

    private func showConfirmClear(
        title: String,
        message: String,
        confirmTitle: String,
        action: @escaping () -> Void
    ) {
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
        presentChrome(menu)
    }

    private func showURLInput() {
        presentPromptAfterMenu { [weak self] in
            guard let self else { return }
            NativeTextPrompt.presentAddressPrompt(
                from: self,
                initialText: self.viewModel.currentURL ?? "",
                onGo: { [weak self] text in
                    self?.noteChromeDismissed()
                    self?.viewModel.load(rawInput: text)
                    self?.reclaimPointerControl()
                },
                onSearch: { [weak self] text in
                    guard let self else { return }
                    self.noteChromeDismissed()
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        self.reclaimPointerControl()
                        return
                    }
                    self.viewModel.load(rawInput: self.viewModel.searchURL(forQuery: trimmed))
                    self.reclaimPointerControl()
                },
                onCancel: { [weak self] in
                    self?.noteChromeDismissed()
                    self?.reclaimPointerControl()
                }
            )
        }
    }

    private func showSearch() {
        presentPromptAfterMenu { [weak self] in
            guard let self else { return }
            let sheet = SafariAddressSheetViewController()
            sheet.sheetTitle = "Search"
            sheet.placeholder = "Search"
            sheet.initialText = ""
            sheet.submitButtonTitle = "Search"
            sheet.keyboardType = .webSearch
            sheet.onSubmit = { [weak self] text in
                guard let self else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.reclaimPointerControl()
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let usedSite = await self.viewModel.submitSiteSearch(trimmed)
                    if !usedSite {
                        self.viewModel.load(rawInput: self.viewModel.searchURL(forQuery: trimmed))
                    }
                    self.reclaimPointerControl()
                }
            }
            _ = self.presentChrome(sheet)
        }
    }

    /// Wait out the Menu row's Select press so it cannot tap Search/Go on the prompt.
    private func presentPromptAfterMenu(_ present: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMetrics.pointerClickDebounce) { [weak self] in
            guard let self, self.presentedViewController == nil else { return }
            present()
        }
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
        presentChrome(menu)
    }
}
