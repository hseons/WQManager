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
┌────────────────────────────────────────────────────────────────┐
│ UI       WQMAppsViewController  WQMCleanerViewController       │
│          WQMBackupsViewController  WQMHistoryViewController    │
│          WQMSettingsViewController  WQMCreditsViewController   │
│          WQMSpaceLensViewController                            │
│          WQMStorageChangesViewController                       │
│          WQMFileAuditViewController                            │
│          WQMGlobalFileSearchViewController                     │
│          WQMExportCenterViewController                         │
│          WQMDuplicateGroupViewController                       │
│          WQMFilePreviewViewController  WQMTrashViewController  │
├────────────────────────────────────────────────────────────────┤
│ Services WQMAppScanner  WQMAppIconService  WQMBackupService    │
│          WQMRestoreService  WQMCacheService  WQMScanHistory    │
│          WQMBackupArchiveService  WQMOperationStore            │
│          WQMFileCatalog  WQMFileAudit  WQMTrashStore           │
│          WQMHousekeeping                                       │
├────────────────────────────────────────────────────────────────┤
│ Access   WQAccess (container query + sandbox extension)        │
│          WQAppsSupport (fs helpers, path safety, hashing)      │
│          WQLaunchServices (display names)                      │
└────────────────────────────────────────────────────────────────┘
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

### Access diagnostics

Settings exposes an on-demand access diagnostic for one indexed app data
container. `WQMAccessDiagnostics` receives the existing grant and label helpers
through blocks so its descriptor-based reads can be tested against local
fixtures. `wq_grant_with_diagnostics` uses the same acquisition path as
`wq_grant`, additionally reporting stable failure stages without returning a
token. A cached grant is verified independently by opening a real directory.
The current device/inode and bundle label must match before child reads.

Directory samples are nonrecursive and stop at 64 direct entries. Each of
Documents, Library and tmp attempts a read of at most one byte from one regular
file. Links are not followed; absent samples remain untested. The normal WQ
grant can temporarily swap the tool-owned App Group cache, but diagnostics
never write into the target container. The global operation banner serializes
the user-requested check with backup/restore/cleanup operations.

Reports use an explicit JSON schema containing environment evidence and fixed
stage/reason codes. App identifiers, paths, names, raw logs, tokens and read
bytes are never added. Reports are generated only on export and their temporary
file is removed after the share sheet finishes. Other container categories and
write capability are explicitly untested. Simulator fixtures are marked as
synthetic and do not establish device compatibility.

The visible app/extension version remains 0.4, with an increasing build number.
`WQMReleaseVersion` is the internal release revision used by update detection
and matches the Git tag, avoiding repeated update prompts from comparing 0.4
against older 0.4.x releases.

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

### Directory selections, notes and protection (0.4.0)

Quick/full backups continue to use format 2. Format 3 is used only for custom
backups. It stores `RequestedParts` (the exact selected directories) separately
from `Parts` (directories present in the payload). Paths stay inside Documents,
Library or tmp; canonicalization rejects traversal, case aliases and overlapping
selections. Unregistered payload ancestors/siblings and linked ancestors are
rejected. Older versions reject format 3 rather than interpreting it as a full
restore.

Restore and its automatic safety backup use the same requested directories,
including selections missing from the source or target. Journals retain that
exact scope for rollback and manual recovery. Unselected siblings are preserved.
Retention groups custom backups by app and directory selection.

Optional `Note` and `Protected` fields travel in the manifest. Notes are limited
to 300 characters. Metadata writes stage a separate file outside the backup
unit, synchronize it, and rename it into place. Protection is enforced by both
manual deletion and retention; protected copies do not consume the ordinary
retention allowance. Metadata updates and pruning share a lock.

### Read-only indexes and serial batches (0.4.0)

`WQMScanHistory` stores at most 60 completed scan snapshots and caches the loaded
history. Unknown measurements and changed device/inode identity break a series.
It adds no background scans or new data access.

`WQMFileCatalog` walks directories through no-follow descriptors with limits of
50,000 files, 100,000 entries and 64 directory levels. Search is in the bounded
metadata index, showing up to 1,000 results. Links and special nodes are skipped;
unreadable or limited scans are explicitly partial. Backup comparison requires
complete indexes, excludes manifests, and distinguishes metadata from optional
streamed SHA-256 content comparison. Exact hashing verifies the file identity
captured at index time and rejects mutations while reading.

New directory readers use the long-operation gate so they do not release a
container token during a conflicting mutation. `WQMBackupQueue` is main-thread
owned and invokes the existing service sequentially. Stop marks pending jobs
cancelled and lets the current backup complete; retry selects failed jobs only.
The queue atomically persists identifiers, names, statuses and quick/full scope,
never container paths. On reload, running jobs become interrupted. Explicit
resume resolves current apps, rejects ambiguous identifiers, and rechecks access
through the existing backup service. Completed jobs are skipped; interrupted
jobs restart as a new backup. Persistence failure prevents starting the next job.
Backgrounding suspends subsequent jobs and requests only iOS's bounded grace for
the active one. Returning to the foreground continues an in-process queue;
process restart always needs explicit resume.

### Progressive scans, search and previews (0.4.3)

`WQMAppScanner` uses a serial queue and emits detached model snapshots every 12
apps, at the end of its quick pass, and after each deferred measurement. UI and
worker models do not share mutable measurement state. Cancelling restores the
previous list and prevents index/history persistence. Single-app refresh checks
container identity before measuring, preserves the full-index timestamp, and
does not append a whole-scan history sample. Index writes use a serial worker.

File catalogs sort once after indexing; queries stop at their result limit.
The file screen debounces for 180 ms, searches on a serial worker, and rejects
stale results by generation. Text/JSON reads and ImageIO thumbnail decoding run
off the main thread. Text is capped at 64 KiB including expanded JSON; truncated
UTF-8 keeps a complete scalar boundary. Thumbnail dimensions are capped at 4096
pixels. Hex previews read at most 4 KiB; sharing still uses the full source file.

### Structured working copies (0.4.3)

`WQMStructuredFile` owns a private `WQMInspect-UUID` workspace. After the user
closes the source app and confirms copying, no-follow descriptor reads copy the
input (and SQLite WAL if present). Device/inode, size, mtime and ctime are checked
before/after each copy and again across all inputs. Links, changing inputs and
nonempty rollback journals fail. This is a best-effort stable copy, not an atomic
snapshot of a concurrently running app. SQLite receives only workspace paths.

Binary/XML plists are limited to 8 MiB; the UI paginates containers at 200 items.
The database and WAL share a 512 MiB budget. SQLite runs with query-only,
defensive and untrusted-schema settings; virtual tables are excluded. Queries
have a 3-second progress deadline, 128 columns, 100 rows and 2 MiB aggregate
display data per page. Values show at most 4 KiB; BLOBs show their byte count.

Selected-table CSV uses the same value bounds, neutralizes formula prefixes,
streams up to 10,000 rows / 16 MiB with a 10-second progress deadline, and removes
incomplete exports. A serial worker and generation checks protect navigation.
Sharing retains the workspace until completion; deallocation removes it and
housekeeping removes stale tool-owned workspaces after interrupted processes.

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

## File catalog, search and export (0.5.0)

`WQMFileCatalog` walks one container at a time with a cancellation token and
hard bounds (50,000 files / 100,000 entries / 64 levels). It skips symlinks and
special files, records device/inode/size/mtime/ctime for identity checks, and
can include or exclude `Library/Caches` and `tmp`. A scan is always tied to a
short-lived container grant; the grant is dropped after the catalog is built.

`WQMFileAudit` turns catalogs into `WQMAuditFile` snapshots and provides the
shared pure helpers: large-file ranking, duplicate size buckets, SHA-256
confirmation and the search predicate/sort used by global search. Duplicate
groups are keyed by bundle identifier and content digest, so an identical file
in another app is never presented as a replacement. The cleanup screen requires
at least one unselected copy per app and moves files through `WQMTrashStore`.

Global search scans apps serially on a utility queue and streams each app's
results to the main table. Filtering/sorting runs on the accumulated snapshot
only, with a 300-row display cap; there is no persistent cross-app index.

Export uses a staging tree named `WQMDataExport-<timestamp>`. Every selected
file is checked against its catalog identity before copying, the free-space
guard keeps 256 MiB headroom, and the result is offered through the share sheet
or `UIDocumentPickerViewController`. Operation history is updated only when the
destination completes or the user cancels; `WQMHousekeeping` removes abandoned
staging trees.

## Operation history

`WQMOperationStore` persists an array in `Operations.plist` inside the app
container. Each record has kind, status, app name, bundle ID, byte count,
timestamps, backup path and an optional error message. The history UI groups
records by day and kind; a group of two or more collapses into one card with a
count, total and latest time. A record still marked Running when the store is
loaded from disk is converted to Interrupted with a finish time and an
explanatory message, so a crash or force-quit never leaves a permanent spinner
in history.

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
