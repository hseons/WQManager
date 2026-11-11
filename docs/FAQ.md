# FAQ

## General

### Does WQManager require a jailbreak?

No. It relies on the container-query + sandbox-extension technique published by
WQFiles and `worse_query`. That also means it can only reach data containers —
not system data, SpringBoard caches, daemons or the Keychain.

### Which iOS versions are supported?

iOS 26.0 and later. The app is built with Xcode 27.2 / iOS 26 SDK.

### Does it work on iPad?

The UI is Universal and the app runs on iPad, but the device was primarily
tested on iPhone. Container access is the same.

### Is my data uploaded anywhere?

No. Everything is local. The only network request is Apple's public iTunes
Lookup for App Store artwork, and only for apps that need an icon. You can
disable it by launching with `WQM_ICON_REMOTE=0` in a debug build.

## Icons

### Why do some third-party apps show a letter instead of an icon?

Stock iOS refuses third-party icon requests to unentitled apps
(`-609 "Client is disallowed from making such an icon request"`). WQManager
discards the shared grey placeholder the system returns, then tries App Store
artwork by bundle ID. Apps installed through third-party signing services have
no App Store ID, so they fall back to a letter tile. A platform limitation, not
a bug.

### Does the app keep retrying icons every launch?

Resolved icons are cached in memory and on disk for 7 days. Failed App Store
lookups are negatively cached for 7 days so the app does not hammer the network.

## Backups and restore

### What is a quick backup vs. a full backup?

Quick: `Documents` + `Library`. Full: also `tmp`. `Library/Caches` can contain
offline content, so a quick backup is not automatically "cache-free".

### Can I restore a backup to a different app?

No. Restore is deliberately restricted to the same Bundle ID, same app installed
on the same device. Cross-app transplantation is not implemented.

### Can I move a backup to another device?

Yes — export the `.wqbackup` package, transfer it, and import it on the other
device. The target app and bundle ID must match.

### Is the backup encrypted?

Not by WQManager. The package is a plain folder/package protected by iOS file
protection. If it contains sensitive data, store exports in encrypted storage.

### Why does restore ask me to close the app?

Writing into a live container while the app has files open can corrupt state.
WQManager verifies the target process is gone before writing, takes a safety
backup, and writes a recovery journal so an interrupted restore can be rolled
back or recovered.

## Cleaning

### Which directories are cleaned?

Only `Library/Caches` and `tmp` of the selected app. Each can be selected
separately. System data, App Groups, Safari data, crash reports and the Keychain
are out of scope.

### Why is the cleaned size smaller than what iOS Settings shows?

iOS Settings includes other categories (documents, app bundles, shared
containers). WQManager only reports the cache and temporary directories it is
allowed to touch.

### Can I skip the typed confirmation?

Yes: Settings → Data → "Clean confirmation". When off, cleaning still requires
the scope confirmation, but no typing.

## Privacy and safety

### What happens if I delete something important?

Cache and temporary files are, by contract, regenerable, but some apps keep
offline content in `Library/Caches`. Read [SAFETY.md](../SAFETY.md); take a
backup first if you are unsure.

### Does the app collect diagnostics?

Only local logs. Icon diagnostics are opt-in (debug builds) and written inside
the app container. Nothing is transmitted.

### Why does the app show "limited" for some apps?

Some containers cannot be opened (permission denied, protected data class, or
the token was refused). Those apps are marked as limited and destructive actions
are disabled for them.

## Development

### The build fails with "Failed to write Objective-C generated asset symbols"

See [BUILDING.md](BUILDING.md#troubleshooting). It is an `actool` file-permission
problem, usually fixed by clearing DerivedData.

### How do I regenerate the docs screenshots?

Run the app with `WQM_UI_FIXTURES=1`, the relevant `WQM_UI_FIXTURES_TAB`, and
`SIMCTL_CHILD_WQM_UI_FIXTURE_NEUTRAL=1` in a debug build to hide the
"UI test data" label, then use `xcrun simctl io <udid> screenshot`.
