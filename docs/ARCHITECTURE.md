# Architecture

This document describes how WQManager is put together, the guarantees it tries
to provide, and where the sharp edges are.

## Goals and non-goals

**Goals**

- Operate on one app's data container at a time, with explicit user intent.
- Never touch system data, system groups, daemons, SpringBoard caches or the
  Keychain.
- Make destructive operations recoverable where the platform allows it: staged
  writes, safety backups, journals, hash verification, rollback.
- Degrade gracefully: no crash, no partial UI, no silent "success" when the
  system actually refused a request.
- Stay buildable with public Xcode tooling on a stock, non-jailbroken device.

**Non-goals**

- Jailbreak-style global file access.
- Cross-app data transplantation.
- Bypassing DRM, entitlements or Apple's icon policy.
- Encryption of backups (left to iOS file protection and the user's storage).

## Layers

```
┌───────────────────────────────────────────────────────────────┐
│ UI        WQMAppsViewController  WQMCleanerViewController      │
│           WQMBackupsViewController  WQMHistoryViewController   │
│           WQMSettingsViewController  WQMCreditsViewController  │
├───────────────────────────────────────────────────────────────┤
│ Services  WQMAppScanner  WQMAppIconService  WQMBackupService   │
│           WQMRestoreService  WQMCacheService                   │
│           WQMBackupArchiveService  WQMOperationStore           │
├───────────────────────────────────────────────────────────────┤
│ Access    WQAccess (container query + sandbox extension token) │
│           WQAppsSupport (fs helpers, path safety, hashing)     │
│           WQLaunchServices (display names)                     │
└───────────────────────────────────────────────────────────────┘
```

The app is Objective-C, iOS 26.0 deployment target, with a small share
extension (`WQManagerShare`) that writes imported `.wqbackup` packages into the
App Group inbox and opens the main app.

## Container access

An app's data container is:

```
/private/var/mobile/Containers/Data/Application/<UUID>
```

A normal third-party process cannot open it. WQManager obtains a **sandbox
extension token** for a container using the container-query API:

1. `container_query_create()`
2. `container_query_set_class(query, 7)` — App Group container class
3. `container_query_set_group_identifiers(query, @[bundleID])`
4. `container_query_set_part(query, 3)` — `Library/Caches`
5. try the standard `set_flags` value, then the `worse_query` fallback value
6. `container_query_get_single_result()` → `sandbox_extension_consume()`

The `Library/Caches` part is the trick published by `worse_query`: the issued
extension covers the container root, not just `Caches`. Once consumed, plain
POSIX calls (`open`, `lstat`, `opendir`, `unlinkat`) work.

`WQAccess` caches consumed handles in a bounded LRU (`kMaxGrants`) and releases
them when evicted. A token is considered invalid only when an open fails with
`EPERM`; `EACCES` is treated as a normal permission error and not retried
forever.

### Identity checks

Every destructive operation re-verifies, immediately before deletion:

- the container's `st_dev` / `st_ino` match the values captured at scan time;
- the canonical path is inside the expected container;
- no symlink in the ancestry redirects outside the container;
- the relative path is in the allow-list (`Library/Caches`, `tmp`).

These checks live in `WQAppsSupport` and `WQMSafetyPolicy`, and are covered by
`tests/run_tests.sh`.

## App enumeration

`WQMAppScanner` enumerates containers under
`/private/var/mobile/Containers/Data/Application`, grants each one, derives the
bundle identifier via the container label and the display name via
`WQLaunchServices` (Launch Services store + built-in table), then measures the
tree. Results are cached in the App Group so the list opens instantly; a refresh
runs on demand.

## Backups

On-disk layout:

```
<BackupRoot>/<UUID>/
  manifest.plist
  Documents/...
  Library/...
  tmp/...            (full backups only)
```

`manifest.plist` contains at least:

- `Format`, `Complete`, `BundleID`, `DisplayName`
- `Scope` (`quick` / `full` / custom), `ScopeCode`
- `Parts` (`Documents`, `Library`, `tmp`), `PartHashes` (content signatures)
- `Created`, `SystemVersion`, optional `Reason`

Writing is staged: copy to a temporary directory, hash, then atomically move into
the store. A backup is only visible once `Complete` is true and every part hash
matches. Identity, shape and byte total come from one tree walk, so a backup
uses four metadata passes per part instead of six.

`.wqbackup` export is a copy of the backup directory with the manifest intact;
import copies the package into a temporary location, re-validates the manifest
and every part hash, then publishes it into the store. No zip layer is involved,
so exports are transparent folders that can be inspected with normal tools.

## Restore state machine

Restore only targets the same bundle identifier. The high-level sequence:

1. Validate the backup (`Complete`, hashes, target bundle ID installed).
2. Ask the user to close the target app; verify the process is gone.
3. Take an automatic safety backup of the current container.
4. Write a recovery journal entry.
5. Copy parts into place, part by part.
6. Re-hash the container.
7. On failure: roll back from the safety backup and record the rollback.
8. On crash: offer manual recovery from the journal on next launch.

Interrupted or failed operations are recorded in the operation store with
enough context for the recovery UI.

In the low-load profile steps 4 and 5 compare metadata captured after the first
verification instead of re-reading every byte, and apply/rollback keep their
post-copy hash check.

## Load profiles

Backup and restore run through `WQMLoadController` (`WQMLoadController.h/.m`),
which chooses the dispatch QoS, the batch size and the pause between batches:

| Profile | Behavior |
|---|---|
| Standard | Full speed; every verification pass runs. |
| Automatic (default) | Full speed while cool; samples `NSProcessInfo.thermalState` every 5 s, backs off at `.serious`, pauses in 2 s slices at `.critical`, and relaxes after 30 s. Drops the two metadata-replaceable verification reads only while backed off. |
| Low-load | Utility queue, larger batches, longer pauses; drops the two metadata-replaceable verification reads. |

Every profile keeps the same SHA-256 content digests, safety backup, recovery
journal, rollback and post-copy target verification. The narrower guarantee of
low-load is documented in [BACKUP_RESTORE_PLAN.md](BACKUP_RESTORE_PLAN.md) §5.4.

## Cache cleaner

`WQMCacheService` scans two targets per app:

| Target | Relative path | Notes |
|---|---|---|
| Cache | `Library/Caches` | may contain offline content |
| Temporary | `tmp` | safe by convention |

Each target can be selected individually. `WQMCleanItem.selectedBytes` is the sum
of selected targets; the cleaner button and the confirmation dialogs use it.
Before deletion the service re-checks container identity, then walks the tree
without following symlinks and deletes regular files and directories bottom-up.

The confirmation flow is two-stage by default: range confirmation, then a typed
confirmation. The second stage can be disabled in Settings
(`WQMCleanDoubleConfirmEnabled`, default on).

## Icons

`WQMAppIconService` tries, in order:

1. `LSApplicationProxy` icon records / sizes / `applicationIconImageForFormat:`
2. private `UIImage _applicationIconImageForBundleIdentifier:format:scale:` —
   only for non-third-party apps
3. `IconServices` (`ISBundleIcon` + `ISImageDescriptor`)
4. `SpringBoardServices` (`SBSCopyIconImagePNGDataForDisplayIdentifier`)
5. the app's `Assets.car` via `CUICatalog`
6. bundle icon files from `Info.plist`
7. parent bundle identifiers, for extensions
8. letter tile

Every candidate goes through two filters: a usability check (≥24 pt, sane aspect
ratio, non-flat luminance) and a placeholder check (fingerprints collected from
known-nonexistent bundle IDs).

On stock iOS, steps 1–4 are refused for third-party apps (`-54`, `-609`), so the
service detects the shared grey placeholder, discards it, and for App Store apps
fetches public artwork from `https://itunes.apple.com/lookup?bundleId=...`.
Results are cached in memory and on disk (`Caches/WQManager/AppIcons-v6`).

## Operation history

`WQMOperationStore` persists an array in `Operations.plist` inside the app
container. Each record has kind, status, app name, bundle ID, byte count,
timestamps, backup path and an optional error message. The history UI groups
records by day and kind; a group of two or more collapses into one card with a
count, total and latest time.

## Localization and theming

Strings live in `zh-Hans.lproj/Localizable.strings` and
`en.lproj/Localizable.strings`; the default is Simplified Chinese. The language
can be switched in Settings without restarting. `WQMTheme` centralizes colors,
Radii and typography; the UI uses Dynamic Type everywhere and avoids fixed
heights that clip large text.

## Security and privacy

- All processing is local; there is no backend.
- The only outbound request is the public iTunes Lookup for icons.
- Backups and logs live inside the app container (and optionally the App Group
  inbox), protected by iOS file protection.
- The app does not read other apps' bundles; it only touches data containers for
  which it holds a sandbox extension.
- The share extension validates package structure and hashes before handing a
  package to the main app.

## Known sharp edges

- `-54` / `-609` are expected on stock devices; code must treat "no icon" as a
  normal state.
- Sandbox tokens can become invalid after app updates or reboots; the access
  layer treats `EPERM` as a hint to re-query once.
- Backup hashing walks every file; very large containers take time and the UI
  must stay cancellable.
- Files can change between scan and delete; identity and hash checks are
  best-effort, not a transaction.
