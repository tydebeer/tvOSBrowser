# tvOS Browser

Web browser for Apple TV, using WKWebView loaded at runtime.

**Sideload only.** tvOS does not expose WKWebView as a public API. This project uses private WebKit APIs (`dlopen` / `NSClassFromString`) and is **not App Store eligible**. Provided as-is with no warranty.

![tvOS Browser](screen01.jpg)

## Requirements

- Xcode with tvOS SDK
- Apple TV (device or simulator)
- Deployment target: tvOS 15.0+

## Project layout

```
_Project/
  Browser.xcodeproj
  Browser/                 # App sources
    App/                   # AppDelegate, SceneDelegate
    Features/              # Browser, StartPage, Input, Menus, WebView
    Data/                  # Settings, history, favorites, credentials
    DesignSystem/          # Colors, typography, metrics, motion
    Components/            # Shared UI (sheets, buttons)
  BrowserTests/            # Unit tests
```

## Install

1. Open `_Project/Browser.xcodeproj` in Xcode.
2. Set your **Team** under Signing & Capabilities.
3. Change the **Bundle Identifier** if needed.
4. Select your Apple TV and Run.

Wireless pairing tip: [connect Apple TV to Xcode over Wi‑Fi](http://www.redmondpie.com/how-to-wirelessly-connect-apple-tv-4k-to-xcode-on-mac/).

## How to use

| Control | Action |
|--------|--------|
| Ring / clickpad | Move pointer |
| Pointer at screen edge | Scroll page |
| Select | Click under pointer |
| Menu (single) | Back / Start Page |
| Menu (double) | Browser Menu |
| Play/Pause | Toggle media playback |

Cold launch always opens the **Start Page** (favorites and history). Enter a URL from the Start Page or from Browser Menu → **Search or Enter Website Name**.

### Browser Menu

- Navigation: Start Page, forward, reload, homepage, add favorite
- Zoom: in / out / actual size
- Passwords: saved logins (Keychain)
- Data: clear history, cache, cookies (with confirmation)
- Exit

### Saved passwords

- Stored in Keychain (`WhenUnlockedThisDeviceOnly`)
- After entering a password in the app sheet: **Save** / **Update** / **Not Now** / **Never for This Site**
- Focusing a login field offers autofill when credentials exist for that host

## Networking

`NSAllowsArbitraryLoads` is enabled so the browser can load `http://` as well as `https://`. Addresses typed without a scheme default to `https://`.

## Tests

```bash
cd _Project
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Browser.xcodeproj -scheme Browser \
  -destination 'platform=tvOS Simulator,name=Apple TV' test
```

CI runs the same command via GitHub Actions (`.github/workflows/ci.yml`).

## License / disclaimer

Use at your own risk. Private API usage means this app cannot be distributed through the App Store.
