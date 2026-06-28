import UIKit
import GameController

final class BrowserViewController: GCEventViewController {

    private enum RingNavigation {
        static let pointerSpeed: CGFloat = 300
        static let tapNudge: CGFloat = 8
        static let holdDelay: TimeInterval = 0.1
    }

    private enum EdgeScroll {
        static let margin: CGFloat = 56
        static let speed: CGFloat = 12
    }

    private let viewModel = BrowserViewModel()
    private let navBar = NavigationBarView()
    private let cursorView = CursorView()
    private let clickpadCaptureView = ClickpadCaptureView()
    private let startPageVC = StartPageViewController()

    private let quickMenu    = QuickMenuPresenter()
    private let advancedMenu = AdvancedMenuPresenter()

    private var navBarTopConstraint: NSLayoutConstraint!
    private var webContainerTopConstraint: NSLayoutConstraint!

    private var pointerPosition = CGPoint.zero
    private var moveDisplayLink: CADisplayLink?
    private var moveVelocity = CGPoint.zero
    private var holdDelayTimer: Timer?
    private var isContinuousMoveActive = false

    override func viewDidLoad() {
        super.viewDidLoad()
        controllerUserInteractionEnabled = false
        view.backgroundColor = DSColor.background
        setupLayout()
        setupStartPage()
        setupPointer()
        setupClickpad()
        setupNavBar()
        setupGestures()
        setupMenuPresenters()
        bindViewModel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.becomeFirstResponder()
        viewModel.handleStartup()

        if !SettingsManager.shared.suppressHints {
            advancedMenu.showHints()
        }
    }

    deinit {
        holdDelayTimer?.invalidate()
        stopSmoothMove()
    }

    private func setupLayout() {
        let wc = viewModel.webContainer
        wc.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wc)

        view.addSubview(navBar)
        navBarTopConstraint = navBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        webContainerTopConstraint = wc.topAnchor.constraint(equalTo: view.topAnchor)

        NSLayoutConstraint.activate([
            navBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navBar.heightAnchor.constraint(equalToConstant: NavigationBarView.barHeight),
            navBarTopConstraint,

            wc.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wc.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wc.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webContainerTopConstraint,
        ])

        applyNavBarVisibility(animated: false)
        startPageTopConstraint.constant = SettingsManager.shared.showNavBar ? NavigationBarView.barHeight : 0

        clickpadCaptureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clickpadCaptureView)
        NSLayoutConstraint.activate([
            clickpadCaptureView.topAnchor.constraint(equalTo: view.topAnchor),
            clickpadCaptureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            clickpadCaptureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            clickpadCaptureView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        view.addSubview(cursorView)
        view.bringSubviewToFront(navBar)
        view.bringSubviewToFront(cursorView)
    }

    private var startPageTopConstraint: NSLayoutConstraint!

    private func setupStartPage() {
        addChild(startPageVC)
        startPageVC.view.translatesAutoresizingMaskIntoConstraints = false
        startPageVC.view.isHidden = true
        view.insertSubview(startPageVC.view, aboveSubview: viewModel.webContainer)
        startPageTopConstraint = startPageVC.view.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            startPageTopConstraint,
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

    private func updateStartPageVisibility(_ visible: Bool) {
        startPageVC.view.isHidden = !visible
        if visible {
            startPageVC.reloadContent()
            view.bringSubviewToFront(startPageVC.view)
            view.bringSubviewToFront(navBar)
            view.bringSubviewToFront(cursorView)
        }
    }

    private func setupClickpad() {
        clickpadCaptureView.onMoved = { [weak self] dx, dy in
            self?.movePointerBy(dx: dx, dy: dy)
        }
    }

    private func setupPointer() {
        let bridge = viewModel.webContainer.bridge
        let sv = bridge.scrollView
        sv.isScrollEnabled = false
        sv.panGestureRecognizer.isEnabled = false
        bridge.webView.isUserInteractionEnabled = false

        pointerPosition = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        cursorView.moveTo(pointerPosition)
        updatePointerHover()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pointerPosition = clampedPointerPosition(pointerPosition)
        cursorView.moveTo(pointerPosition)
    }

    private func applyNavBarVisibility(animated: Bool) {
        let visible = SettingsManager.shared.showNavBar
        let offset = visible ? NavigationBarView.barHeight : 0

        if animated {
            UIView.animate(withDuration: DSMotion.durationBase) {
                self.webContainerTopConstraint.constant = offset
                self.startPageTopConstraint.constant = offset
                self.view.layoutIfNeeded()
            }
        } else {
            webContainerTopConstraint.constant = offset
            startPageTopConstraint.constant = offset
        }
        navBar.setHidden(!visible, animated: animated)
    }

    private var webViewOriginY: CGFloat {
        SettingsManager.shared.showNavBar ? NavigationBarView.barHeight : 0
    }

    private func setupNavBar() {
        navBar.onBack       = { [weak self] in self?.viewModel.goBack() }
        navBar.onForward    = { [weak self] in self?.viewModel.goForward() }
        navBar.onReload     = { [weak self] in self?.viewModel.reload() }
        navBar.onHome       = { [weak self] in self?.viewModel.loadHomepage() }
        navBar.onURLTapped  = { [weak self] in self?.showURLInput() }
        navBar.onFullscreen = { [weak self] in
            self?.viewModel.toggleNavBar()
            self?.applyNavBarVisibility(animated: true)
        }
        navBar.onMenu       = { [weak self] in self?.showAdvancedMenu() }
    }

    private func setupGestures() {
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTapSelect))
        singleTap.numberOfTapsRequired = 1
        singleTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(singleTap)

        let ppDouble = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapPlayPause))
        ppDouble.numberOfTapsRequired = 2
        ppDouble.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        view.addGestureRecognizer(ppDouble)
    }

    @objc private func handleSingleTapSelect(_ gr: UITapGestureRecognizer) {
        guard gr.state == .ended else { return }
        handlePointerSelectPress()
    }

    @objc private func handleDoubleTapPlayPause(_ gr: UITapGestureRecognizer) {
        if gr.state == .ended { showAdvancedMenu() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard presentedViewController == nil,
              let press = presses.first,
              isDirectionalPress(press.type) else {
            super.pressesBegan(presses, with: event)
            return
        }

        moveVelocity = moveVelocity(for: press.type)
        isContinuousMoveActive = false
        holdDelayTimer?.invalidate()
        holdDelayTimer = Timer.scheduledTimer(
            withTimeInterval: RingNavigation.holdDelay,
            repeats: false
        ) { [weak self] _ in
            self?.isContinuousMoveActive = true
            self?.startSmoothMove()
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let press = presses.first, isDirectionalPress(press.type) {
            holdDelayTimer?.invalidate()
            holdDelayTimer = nil
            if !isContinuousMoveActive {
                applyTapNudge()
            }
            stopSmoothMove()
            isContinuousMoveActive = false
            return
        }

        guard let press = presses.first else {
            super.pressesEnded(presses, with: event)
            return
        }

        switch press.type {
        case .menu:
            if presentedViewController != nil {
                dismiss(animated: true)
            } else if viewModel.webContainer.bridge.canGoBack {
                viewModel.goBack()
            } else {
                confirmExit()
            }
        case .select:
            super.pressesEnded(presses, with: event)
        case .playPause:
            if presentedViewController != nil {
                dismiss(animated: true)
            } else {
                showQuickMenu()
            }
        default:
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        holdDelayTimer?.invalidate()
        holdDelayTimer = nil
        isContinuousMoveActive = false
        stopSmoothMove()
        super.pressesCancelled(presses, with: event)
    }

    private func isDirectionalPress(_ type: UIPress.PressType) -> Bool {
        switch type {
        case .upArrow, .downArrow, .leftArrow, .rightArrow: return true
        default: return false
        }
    }

    private func moveVelocity(for type: UIPress.PressType) -> CGPoint {
        switch type {
        case .upArrow:    return CGPoint(x: 0, y: -RingNavigation.pointerSpeed)
        case .downArrow:  return CGPoint(x: 0, y: RingNavigation.pointerSpeed)
        case .leftArrow:  return CGPoint(x: -RingNavigation.pointerSpeed, y: 0)
        case .rightArrow: return CGPoint(x: RingNavigation.pointerSpeed, y: 0)
        default:          return .zero
        }
    }

    private func startSmoothMove() {
        guard moveDisplayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleMoveTick(_:)))
        if #available(tvOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        moveDisplayLink = link
    }

    private func stopSmoothMove() {
        moveDisplayLink?.invalidate()
        moveDisplayLink = nil
        moveVelocity = .zero
    }

    @objc private func handleMoveTick(_ link: CADisplayLink) {
        let dt = max(CGFloat(link.duration), 1.0 / 120.0)
        movePointerBy(dx: moveVelocity.x * dt, dy: moveVelocity.y * dt)
    }

    private func applyTapNudge() {
        let step = RingNavigation.tapNudge
        if moveVelocity.y < 0 { movePointerBy(dx: 0, dy: -step) }
        else if moveVelocity.y > 0 { movePointerBy(dx: 0, dy: step) }
        else if moveVelocity.x < 0 { movePointerBy(dx: -step, dy: 0) }
        else if moveVelocity.x > 0 { movePointerBy(dx: step, dy: 0) }
    }

    private func movePointerBy(dx: CGFloat, dy: CGFloat) {
        pointerPosition = clampedPointerPosition(
            CGPoint(x: pointerPosition.x + dx, y: pointerPosition.y + dy)
        )
        cursorView.moveTo(pointerPosition)
        updatePointerHover()
        if !viewModel.isShowingStartPage {
            applyEdgeScrollIfNeeded()
        }
    }

    private func applyEdgeScrollIfNeeded() {
        let margin = EdgeScroll.margin
        let bounds = view.bounds
        var scrollDx: CGFloat = 0
        var scrollDy: CGFloat = 0

        if pointerPosition.y < margin {
            scrollDy = -EdgeScroll.speed * (1 - pointerPosition.y / margin)
        } else if pointerPosition.y > bounds.height - margin {
            let overflow = pointerPosition.y - (bounds.height - margin)
            scrollDy = EdgeScroll.speed * min(overflow / margin, 1)
        }

        if pointerPosition.x < margin {
            scrollDx = -EdgeScroll.speed * (1 - pointerPosition.x / margin)
        } else if pointerPosition.x > bounds.width - margin {
            let overflow = pointerPosition.x - (bounds.width - margin)
            scrollDx = EdgeScroll.speed * min(overflow / margin, 1)
        }

        guard scrollDx != 0 || scrollDy != 0 else { return }
        scrollWebViewBy(dx: scrollDx, dy: scrollDy)
    }

    private func scrollWebViewBy(dx: CGFloat, dy: CGFloat) {
        let sv = viewModel.webContainer.bridge.scrollView
        let maxX = max(0, sv.contentSize.width - sv.bounds.width)
        let maxY = max(0, sv.contentSize.height - sv.bounds.height)
        sv.contentOffset = CGPoint(
            x: min(max(sv.contentOffset.x + dx, 0), maxX),
            y: min(max(sv.contentOffset.y + dy, 0), maxY)
        )
    }

    private func clampedPointerPosition(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), view.bounds.width),
            y: min(max(point.y, 0), view.bounds.height)
        )
    }

    private func updatePointerHover() {
        let navBarHeight = webViewOriginY

        if pointerPosition.y < navBarHeight {
            let navBarPoint = view.convert(pointerPosition, to: navBar)
            navBar.setAddressBarFocused(navBar.hitTestAddressBar(at: navBarPoint))
            highlightNavBarButton(at: navBarPoint)
            NotificationCenter.default.post(
                name: .cursorHoverStateChanged,
                object: nil,
                userInfo: [CursorHoverKey.isClickable: true]
            )
            return
        }

        navBar.setAddressBarFocused(false)

        if viewModel.isShowingStartPage {
            startPageVC.updatePointer(at: pointerPosition)
            return
        }

        let webPoint = CGPoint(x: pointerPosition.x, y: pointerPosition.y - navBarHeight)
        Task {
            await viewModel.webContainer.jsExecutor.schedulePointerUpdate(at: webPoint)
        }
    }

    private func highlightNavBarButton(at point: CGPoint) {
        let buttons: [SafariIconButton] = [
            navBar.backButton, navBar.refreshButton, navBar.forwardButton,
            navBar.homeButton, navBar.fullscreenButton, navBar.menuButton
        ]
        for btn in buttons {
            btn.setHighlighted(btn.frame.contains(point))
        }
    }

    private func handlePointerSelectPress() {
        let navBarHeight = webViewOriginY
        if pointerPosition.y < navBarHeight {
            handleNavBarPointerClick()
            return
        }

        if viewModel.isShowingStartPage {
            _ = startPageVC.handlePointerClick(at: pointerPosition)
            return
        }

        viewModel.handlePointerClick(at: pointerPosition, webViewOriginY: navBarHeight)
    }

    private func handleNavBarPointerClick() {
        let navBarPoint = view.convert(pointerPosition, to: navBar)

        if navBar.hitTestReloadInPill(at: navBarPoint) {
            viewModel.reload()
            return
        }
        if navBar.hitTestAddressBar(at: navBarPoint) {
            showURLInput()
            return
        }

        if navBar.backButton.frame.contains(navBarPoint) {
            viewModel.goBack()
        } else if navBar.refreshButton.frame.contains(navBarPoint) {
            viewModel.reload()
        } else if navBar.forwardButton.frame.contains(navBarPoint) {
            viewModel.goForward()
        } else if navBar.homeButton.frame.contains(navBarPoint) {
            viewModel.loadHomepage()
        } else if navBar.fullscreenButton.frame.contains(navBarPoint) {
            viewModel.toggleNavBar()
            applyNavBarVisibility(animated: true)
        } else if navBar.menuButton.frame.contains(navBarPoint) {
            showAdvancedMenu()
        }
    }

    private func setupMenuPresenters() {
        quickMenu.viewController    = self
        advancedMenu.viewController = self

        quickMenu.onURLInput    = { [weak self] in self?.showURLInput() }
        quickMenu.onReload      = { [weak self] in self?.viewModel.reload() }
        quickMenu.onGoForward   = { [weak self] in self?.viewModel.goForward() }

        advancedMenu.onLoadHomepage     = { [weak self] in self?.viewModel.loadHomepage() }
        advancedMenu.onSetHomepage      = { [weak self] in self?.viewModel.setCurrentPageAsHomepage() }
        advancedMenu.onToggleNavBar     = { [weak self] in
            self?.viewModel.toggleNavBar()
            self?.applyNavBarVisibility(animated: true)
        }
        advancedMenu.onToggleMobileMode = { [weak self] in self?.viewModel.toggleMobileMode() }
        advancedMenu.onIncreaseFontSize = { [weak self] in self?.viewModel.increaseFontSize() }
        advancedMenu.onDecreaseFontSize = { [weak self] in self?.viewModel.decreaseFontSize() }
        advancedMenu.onClearCache       = { [weak self] in self?.viewModel.clearCache() }
        advancedMenu.onClearCookies     = { [weak self] in self?.viewModel.clearCookies() }
        advancedMenu.onShowHints        = { [weak self] in self?.advancedMenu.showHints() }
        advancedMenu.onOpenFavorite     = { [weak self] url in self?.viewModel.load(rawInput: url) }
        advancedMenu.onOpenHistory      = { [weak self] url in self?.viewModel.load(rawInput: url) }
        advancedMenu.onThemeChanged     = { ThemeManager.applyToAllWindows() }

        advancedMenu.currentURLProvider   = { [weak self] in self?.viewModel.currentURL }
        advancedMenu.currentTitleProvider = { [weak self] in self?.viewModel.currentTitle }

        viewModel.onLoadError = { [weak self] error, requestURL in
            self?.showLoadError(error, requestURL: requestURL)
        }
    }

    private func showQuickMenu() {
        quickMenu.present(
            pageTitle: viewModel.currentTitle,
            canGoForward: viewModel.webContainer.bridge.canGoForward,
            hasPage: viewModel.currentURL != nil
        )
    }

    private func showAdvancedMenu() {
        let settings = SettingsManager.shared
        advancedMenu.present(
            navBarVisible: settings.showNavBar,
            isMobileMode: settings.isMobileMode,
            currentURL: viewModel.currentURL
        )
    }

    private func showURLInput() {
        let sheet = SafariAddressSheetViewController()
        sheet.initialText = viewModel.currentURL ?? ""
        sheet.onSubmit = { [weak self] text in
            self?.viewModel.load(rawInput: text)
        }
        present(sheet, animated: false)
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
                self?.viewModel.load(rawInput: "https://www.google.com/search?q=\(clean)")
            }))
        }
        rows.append(SafariMenuRow(title: "Reload Page", symbol: "arrow.clockwise", action: { [weak self] in
            self?.viewModel.reload()
        }))

        let menu = SafariMenuViewController(
            title: "Could Not Load Page",
            sections: [
                SafariMenuSection(title: error.localizedDescription, rows: rows)
            ]
        )
        present(menu, animated: false)
    }

    private func confirmExit() {
        let menu = SafariMenuViewController(
            title: "Exit Browser?",
            sections: [
                SafariMenuSection(title: nil, rows: [
                    SafariMenuRow(title: "Exit", symbol: "xmark.circle", style: .destructive, action: {
                        UIApplication.shared.perform(NSSelectorFromString("suspend"))
                    }),
                    SafariMenuRow(title: "Cancel", symbol: "arrow.uturn.backward", action: {}),
                ])
            ]
        )
        present(menu, animated: false)
    }

    private func bindViewModel() {
        viewModel.navBarViewModel.onStateChanged = { [weak self] in
            guard let self else { return }
            self.navBar.apply(viewModel: self.viewModel.navBarViewModel)
        }
    }
}
