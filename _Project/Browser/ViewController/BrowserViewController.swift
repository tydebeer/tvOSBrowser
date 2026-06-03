import UIKit

// Thin orchestration layer. Owns the view hierarchy, gesture recognizers,
// and remote press handling. All business logic lives in BrowserViewModel.

final class BrowserViewController: UIViewController {

    // MARK: - Properties

    private let viewModel = BrowserViewModel()
    private let navBar = NavigationBarView()
    private let cursorView = CursorView()
    private var cursorController: CursorController!

    private let quickMenu    = QuickMenuPresenter()
    private let advancedMenu = AdvancedMenuPresenter()

    private var navBarTopConstraint: NSLayoutConstraint!
    private var webContainerTopConstraint: NSLayoutConstraint!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupLayout()
        setupCursor()
        setupNavBar()
        setupGestures()
        setupMenuPresenters()
        bindViewModel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.handleStartup()

        let settings = SettingsManager.shared
        if !settings.suppressHints {
            advancedMenu.showHints()
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        // Web container
        let wc = viewModel.webContainer
        wc.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wc)

        // Navigation bar
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

        // Cursor on top of everything
        view.addSubview(cursorView)
    }

    private func applyNavBarVisibility(animated: Bool) {
        let visible = SettingsManager.shared.showNavBar
        let offset = visible ? NavigationBarView.barHeight : 0

        if animated {
            UIView.animate(withDuration: 0.2) {
                self.webContainerTopConstraint.constant = offset
                self.view.layoutIfNeeded()
            }
        } else {
            webContainerTopConstraint.constant = offset
        }
        navBar.setHidden(!visible, animated: animated)

        // Update cursor controller's webview origin
        cursorController?.webViewOriginY = offset
    }

    // MARK: - Cursor

    private func setupCursor() {
        cursorController = CursorController(
            viewBounds: view.bounds,
            jsExecutor: viewModel.webContainer.jsExecutor
        )
        cursorController.onPositionChanged = { [weak self] point in
            self?.cursorView.moveTo(point)
        }
        cursorController.onModeChanged = { [weak self] mode in
            guard let self else { return }
            let sv = self.viewModel.webContainer.bridge.scrollView
            switch mode {
            case .cursor:
                sv.isScrollEnabled = false
                self.viewModel.webContainer.bridge.webView.isUserInteractionEnabled = false
                self.cursorView.isHidden = false
            case .scroll:
                sv.isScrollEnabled = true
                self.viewModel.webContainer.bridge.webView.isUserInteractionEnabled = true
                self.cursorView.isHidden = true
            }
        }

        cursorView.center = view.center
        view.bringSubviewToFront(cursorView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cursorController.updateBounds(view.bounds)
    }

    // MARK: - Nav Bar

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

    // MARK: - Gestures

    private func setupGestures() {
        // Double-tap Select: toggle cursor/scroll mode
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapSelect))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(doubleTap)

        // Double-tap Play/Pause: advanced menu
        let ppDouble = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapPlayPause))
        ppDouble.numberOfTapsRequired = 2
        ppDouble.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        view.addGestureRecognizer(ppDouble)
    }

    @objc private func handleDoubleTapSelect(_ gr: UITapGestureRecognizer) {
        if gr.state == .ended { cursorController.toggleMode() }
    }

    @objc private func handleDoubleTapPlayPause(_ gr: UITapGestureRecognizer) {
        if gr.state == .ended { showAdvancedMenu() }
    }

    // MARK: - Remote Button Handling

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
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
            guard cursorController.mode == .cursor else { return }
            handleCursorSelectPress()

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

    private func handleCursorSelectPress() {
        let cursorPos = cursorController.position
        let navBarHeight = SettingsManager.shared.showNavBar ? NavigationBarView.barHeight : 0

        // Check if cursor is over nav bar buttons
        if cursorPos.y < navBarHeight {
            handleNavBarCursorClick(cursorPos: cursorPos)
            return
        }

        viewModel.handleCursorClick(at: cursorPos, webViewOriginY: navBarHeight)
    }

    private func handleNavBarCursorClick(cursorPos: CGPoint) {
        // Convert cursor position to nav bar coordinate space
        let navBarPoint = view.convert(cursorPos, to: navBar)
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

    // MARK: - Touch (Cursor movement)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        cursorController.touchesBegan()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: view)
        cursorController.touchesMoved(location: location)
    }

    // MARK: - Menus

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
        advancedMenu.onToggleScaleToFit = { [weak self] in self?.viewModel.toggleScaleToFit() }
        advancedMenu.onIncreaseFontSize = { [weak self] in self?.viewModel.increaseFontSize() }
        advancedMenu.onDecreaseFontSize = { [weak self] in self?.viewModel.decreaseFontSize() }
        advancedMenu.onClearCache       = { [weak self] in self?.viewModel.clearCache() }
        advancedMenu.onClearCookies     = { [weak self] in self?.viewModel.clearCookies() }
        advancedMenu.onShowHints        = { [weak self] in self?.advancedMenu.showHints() }
        advancedMenu.onOpenFavorite     = { [weak self] url in self?.viewModel.load(rawInput: url) }
        advancedMenu.onOpenHistory      = { [weak self] url in self?.viewModel.load(rawInput: url) }

        advancedMenu.currentURLProvider   = { [weak self] in self?.viewModel.currentURL }
        advancedMenu.currentTitleProvider = { [weak self] in self?.viewModel.currentTitle }

        viewModel.onRequestTextInput = { [weak self] fieldInfo, point, scale in
            self?.showTextInput(for: fieldInfo, at: point, scale: scale)
        }
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
            scaleToFit: settings.scaleToFit,
            currentURL: viewModel.currentURL
        )
    }

    // MARK: - URL Input

    private func showURLInput() {
        let alert = UIAlertController(title: "Enter URL or Search", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.keyboardType = .URL
            tf.placeholder = "URL or search terms"
            tf.text = self.viewModel.currentURL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Go", style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            self?.viewModel.load(rawInput: text)
        })
        alert.addAction(UIAlertAction(title: "Search Google", style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            self?.viewModel.load(rawInput: "https://www.google.com/search?q=\(query)")
        })
        alert.addAction(UIAlertAction(title: nil, style: .cancel))
        present(alert, animated: true) {
            alert.textFields?.first?.selectAll(nil)
        }
    }

    // MARK: - Text Field Input

    private func showTextInput(for field: JavaScriptExecutor.FieldInfo, at point: CGPoint, scale: CGFloat) {
        let title = field.title.isEmpty ? "Input" : field.title.capitalized
        let placeholder = field.placeholder.isEmpty ? "Enter value" : field.placeholder.capitalized
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = placeholder
            tf.text = field.value
            tf.isSecureTextEntry = field.type == "password"
            tf.keyboardType = Self.keyboardType(for: field.type)
        }
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self, weak alert] _ in
            let value = alert?.textFields?.first?.text ?? ""
            self?.viewModel.submitTextInput(value: value, at: point, scale: scale, submit: false)
        })
        alert.addAction(UIAlertAction(title: "Submit", style: .default) { [weak self, weak alert] _ in
            let value = alert?.textFields?.first?.text ?? ""
            self?.viewModel.submitTextInput(value: value, at: point, scale: scale, submit: true)
        })
        alert.addAction(UIAlertAction(title: nil, style: .cancel))
        present(alert, animated: true) {
            if field.value.isEmpty { alert.textFields?.first?.becomeFirstResponder() }
        }
    }

    private static func keyboardType(for fieldType: String) -> UIKeyboardType {
        switch fieldType {
        case "email":    return .emailAddress
        case "url":      return .URL
        case "tel", "number", "date", "datetime", "datetime-local": return .numbersAndPunctuation
        default:         return .default
        }
    }

    // MARK: - Error Handling

    private func showLoadError(_ error: Error, requestURL: String?) {
        let alert = UIAlertController(
            title: "Could Not Load Page",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        if let url = requestURL, !url.isEmpty {
            alert.addAction(UIAlertAction(title: "Search Google", style: .default) { [weak self] _ in
                let clean = url
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                    .replacingOccurrences(of: "www.", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                self?.viewModel.load(rawInput: "https://www.google.com/search?q=\(clean)")
            })
        }
        alert.addAction(UIAlertAction(title: "Reload", style: .default) { [weak self] _ in
            self?.viewModel.reload()
        })
        alert.addAction(UIAlertAction(title: nil, style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Exit

    private func confirmExit() {
        let alert = UIAlertController(title: "Exit tvOS Browser?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Exit", style: .destructive) { _ in
            // Graceful suspension — preferred over exit()
            UIApplication.shared.perform(NSSelectorFromString("suspend"))
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Bind ViewModel

    private func bindViewModel() {
        viewModel.navBarViewModel.onStateChanged = { [weak self] in
            guard let self else { return }
            self.navBar.apply(viewModel: self.viewModel.navBarViewModel)
        }
    }
}
