# Building and running WQManager

## Requirements

- macOS with Xcode **27.2** or later (iOS 26 SDK).
- Deployment target: **iOS 26.0**.
- Simulator for UI work; a physical iOS 26+ device for container access.
- For device builds: a signing identity and an App Group. App Groups require a
  paid Apple Developer account; free provisioning cannot enable them and builds
  expire after 7 days.

## Identifiers used by this repository

| Item | Value |
|---|---|
| Main app bundle ID | `mumu.pduola.WQManager` |
| Share extension bundle ID | `mumu.pduola.WQManager.Share` |
| App Group | `group.mumu.wqmanager` |
| Scheme | `WQManager` |
| Deployment target | `26.0` |
| Marketing version | `0.1` |

If you fork the project, change the bundle identifiers, the App Group, and the
entitlements of **both** targets to your own values. The app and the share
extension must share the same group.

## Simulator build

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project WQManager/WQManager.xcodeproj \
  -scheme WQManager \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/WQManager-DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Install and launch:

```sh
xcrun simctl install booted \
  /tmp/WQManager-DerivedData/Build/Products/Debug-iphonesimulator/WQManager.app
xcrun simctl launch booted mumu.pduola.WQManager
```

On the simulator the sandbox is mostly disabled, so container access and some
icon paths succeed even where a stock device would refuse them. Do not treat
simulator icon results as device evidence.

## Device build

1. Open `WQManager/WQManager.xcodeproj` in Xcode.
2. Select both targets and set your Team under **Signing & Capabilities**.
3. Replace the bundle identifiers and App Group with your own.
4. Keep the App Group capability on both the app and the share extension.
5. Build to your device.

Command-line device builds need a provisioning profile:

```sh
xcodebuild \
  -project WQManager/WQManager.xcodeproj \
  -scheme WQManager \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
  CODE_SIGN_STYLE=Automatic \
  build
```

The repository does not ship signing material. `dist/` (local IPAs and
entitlements) is ignored by Git.

## Tests

```sh
bash tests/run_tests.sh
```

The script compiles the portable parts of the safety, backup store, operation
store and backup archive layers with `clang` and runs them directly. It needs no
simulator, no signing and no network.

## Debug switches

All of these are read from the process environment (set them with
`SIMCTL_CHILD_` on the simulator, or via the scheme on device) and are compiled
only in `DEBUG` builds.

| Variable | Effect |
|---|---|
| `WQM_ICON_DEBUG=1` | verbose icon-resolution logging |
| `WQM_ICON_DIAG=0` | disable the icon diagnostic log file |
| `WQM_ICON_DIAG_ALL=1` | diagnose every scanned app (default: first 12) |
| `WQM_ICON_DIAG_DUMP=1` | dump raw icon records to `Documents/` |
| `WQM_ICON_REMOTE=0` | disable App Store artwork lookup |
| `WQM_UI_FIXTURES=1` | use fixed demo data instead of scanning |
| `WQM_UI_FIXTURES_TAB=n` | open tab `n` (0 apps, 1 backups, 2 cleaner, 3 history, 4 settings) |
| `WQM_UI_HISTORY_EXPAND=1` | expand all history groups |
| `WQM_UI_SETTINGS_DOC=n` | push document row `n` in Settings |

Icon diagnostics are written to `Documents/icon-diag-<timestamp>.log` inside the
app container and are visible through the Files app
(`On My iPhone/WQManager`).

## Troubleshooting

### `Failed to write Objective-C generated asset symbols`

Symptom:

```
Assets.xcassets: error: Failed to write Objective-C generated asset symbols.
You don't have permission to save the file "GeneratedAssetSymbols.h"
in the folder "DerivedSources"
Operation not permitted
```

The asset compiler (`actool`) could not write its generated symbol files into
the build's `DerivedSources` directory. This is a build-environment problem, not
an asset-catalog problem. In order:

1. Quit Xcode and delete the project's DerivedData:
   `rm -rf ~/Library/Developer/Xcode/DerivedData/WQManager-*`
2. Reopen the project and do a clean build.
3. If it persists, restart the build service:
   `pkill -f XCBBuildService`
4. Check disk space and file ownership of
   `DerivedData/WQManager-*/Build/Intermediates.noindex/.../DerivedSources`.
5. As a last resort disable symbol generation:
   `ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS=NO`.

### Third-party icons are letter tiles

Expected on stock devices: iOS refuses third-party icon requests
(`-609`). The app then tries App Store artwork; apps without an App Store ID
remain letter tiles. See the README section "Icons on stock iOS".

### `wq_grant` fails for an app

Container access depends on the App Group + `worse_query` extension trick. Make
sure both targets carry `group.mumu.wqmanager`, the app is signed with a valid
profile, and the device was not logged out/restarted in a way that invalidated
the extension. Re-scan from Settings → "Clear App Index Cache".

### Backups appear but restore refuses

Restore requires the same bundle ID to be installed, closed and identity-verified.
Stale identity data after an app update is handled by re-scanning.
