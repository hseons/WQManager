# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
semantic versioning once it reaches 1.0.

## [0.5.0] — 2026-11-18

The app and share extension display version **0.5**, build **1**. The internal
release revision and Git tag are 0.5.0 / v0.5.0.

### Added

- Global file search across accessible apps: streamed scan results, file
  name/relative path/app name matching, type and minimum-size filters,
  path/size/newest sorting, in-place previews and jump-to-containing-folder.
- Space changes can compare the previous scan or the last 7/30 days, with a
  growth ranking, known-total/net-change footer and an all-app trend chart.
  Per-app detail shows current size, previous-scan change and 7-day change.
- Large-file and duplicate audit with SHA-256 confirmation and per-app
  duplicate groups. Cleanup keeps at least one copy per app and moves files to
  the Space Lens bin.
- Export center: choose files across apps, filter by type, then share the
  staged folder or save it through the system document picker. Export history
  is recorded only after the destination completes or the user cancels.
- Space Lens bin entries can be restored to their original folder, removed
  individually, or emptied together.

### Changed

- The Apps tools menu now exposes storage changes, batch backup, file audit and
  global search in one place.
- Duplicate buckets are grouped by app and size; a duplicate in another app is
  never treated as a replacement. The cleanup screen refuses to select the last
  remaining copy of an app.
- Export staging is cleaned on cancel, failure, a missing window or share
  completion; abandoned `WQMDataExport-*` trees are removed by housekeeping.
- History shows a record left Running by a previous process as Interrupted
  instead of a permanent in-progress state.

### Fixed

- Static-analyzer warnings in `wq_drop_grant` (NSNumber pointer used as a
  boolean) and the Space Lens path list (`nil` name passed to `addObject:`).
- Space changes ranking footers no longer sit under the floating tab bar.
- Export history no longer records success merely because the share sheet was
  presented.
- Unused localization keys were removed; English and Simplified Chinese remain
  at parity.

## [0.4.4] — 2026-11-16

The app and share extension display version **0.4**, build **16**. The internal
release revision and Git tag are 0.4.4 / v0.4.4.

### Fixed

- History rows no longer squeeze the status badge: the badge keeps its intrinsic
  width and the secondary line yields instead, so states such as 成功/已回滚 stay
  readable at every text size. Secondary text is capped at two lines.
- The stale-index notice on 应用 now reads "… · 下拉可重试" and uses the warning
  colour, so a failed refresh is visible instead of a neutral caption.

### Changed

- 清理 hides the selection count and the quick-filter row when nothing is
  eligible, and the empty card can be tapped to scan again.
- 备份 timestamps read 今天/昨天/日期 plus the time, making backups of the same app
  easier to tell apart.
- Date formatters are cached per locale instead of being rebuilt for every row in
  记录 and 备份.

## [0.4.3] — 2026-11-16

The app and share extension display version **0.4**, build **15**. The internal
release revision and Git tag are 0.4.3 / v0.4.3.

### Added

- Progressive app-list snapshots during scanning and a single-app refresh action
  that rechecks container identity. Cancelled scans keep the previous index;
  refreshing one app does not create a whole-scan history sample.
- Persistent serial backup jobs with explicit restart/resume and quick/full scope
  confirmation. Jobs store identifiers instead of container paths and resolve
  current apps before execution. Backgrounding pauses subsequent jobs.
- Direct access diagnostics from app actions and backup/restore failure dialogs.
- Read-only binary/XML plist trees and SQLite table/schema browsing with 100-row
  pages, plus user-selected CSV export. SQLite opens only a private working copy
  of the database and WAL; changing files and active rollback journals are rejected.
- GitHub Actions configuration/localization checks, 22 portable test programs,
  simulator builds and five UI regression flows. Hosted Xcode 26 builds use an
  isolated compatibility project generated from the main project's settings.

### Changed

- File catalogs sort once; searches debounce for 180 ms and filter in the
  background with stale-result checks.
- Text/JSON reads and image decoding move off the main thread. Text previews show
  at most 64 KiB, images use thumbnails capped at 4096 pixels, and truncated-text
  footers no longer conflict with the preview's bottom constraint.
- UTF-8 truncation preserves complete characters; expanded JSON must fit the
  display limit. Full source files remain available through sharing.

### Limits

- Plists: 8 MiB, 200 tree items/page. Database + WAL: 512 MiB; close the source
  app first. Each displayed/exported value is bounded to 4 KiB; BLOBs show sizes.
  CSV is limited to 10,000 rows / 16 MiB and incomplete exports are removed.
- Background grace is controlled by iOS. An interrupted active job is backed up
  again on explicit resume. Physical-device access/signing validation is pending.

## [0.4.2] — 2026-11-16

The app and share extension display version **0.4**, build **14**. The release
revision remains 0.4.2 for tags and update detection.

### Added

- Settings → Access capabilities: runtime signing evidence, usable App Group,
  exact OS build, device/simulator environment and protected-data availability.
- On-demand checks of one indexed app: token failure stage, current container
  identity, directory open/list results and bounded file-read samples for
  Documents, Library and tmp. Results include actionable failure explanations.
- User-initiated redacted JSON reports without app names, bundle IDs, paths,
  tokens, raw logs or file contents. Untested categories and write access remain
  explicit; no full-disk scan or target mutation is used for diagnostics.

### Changed

- Keep the visible version at 0.4 while increasing the build number. Compare
  the internal release revision when checking for updates.

## [0.4.1] — 2026-11-16

### Fixed

- Complete nullability contracts in the shared backup helpers, including optional
  output pointers and signatures that can fail.
- Use a typed implementation for the process-service lookup instead of
  `performSelector:`, and pass a measurement result for a missing Space Lens path.
- Keep the deletion menu action typed during construction and show a trash icon
  for file-deletion history records.
- Observe Space Lens appearance changes with trait registrations and let the
  image renderer choose its display scale without the deprecated main-screen API.

## [0.4.0] — 2026-11-15

### Added

- Storage changes: keep the last 60 scan snapshots, rank app growth, and show
  per-app history with a trend line. Unknown measurements and changed container
  identities break a series instead of producing misleading deltas.
- Find files: bounded, cancellable metadata indexing inside one app, size ranking,
  filename/path search, extension/minimum-size filters, previews and a direct
  jump to the containing folder in Space Lens. Partial scans are labeled.
- Batch backups: select apps, run quick/full backups sequentially, inspect results,
  retry failed items, and stop pending jobs after the active backup completes.
- Backup notes and important-backup protection, preserved through export/import.
  Protected backups are excluded from automatic retention and manual deletion
  until protection is explicitly removed.
- Browse backup contents and compare same-app, same-scope backups. Metadata
  comparison is the default; optional SHA-256 comparison reads equal-sized file
  contents. Incomplete scans do not produce a complete comparison result.
- Custom backups: select up to 128 directories inside Documents, Library or tmp.
  Format 3 records the exact requested paths; restore and automatic safety backup
  use that same scope, preserving unselected siblings. Format 2 stays readable.
- WQ extension research plan: capability diagnostics, read-only App Groups and
  extension-container overview, structured-file inspection and directory changes.

### Changed

- App action sheet scrolls to accommodate the additional tools and large text.
- New directory reads share the operation gate with mutations. An old banner
  dismissal no longer hides a newly started operation.
- Custom retention groups include the directory selection, keeping unrelated
  custom selections independent. Backup metadata writes are atomic and synced.

### Validation

- Added portable tests for scan history, file catalogs, serial queues, custom
  selection validation and real backup/restore services with an injected access
  bridge, including low-load restore, export/import and failure rollback.
- Container authorization, signing and power-loss behavior still need supported
  physical-device validation. The next-step plan records these gates.

## [0.3.2] — 2026-11-13

### Added

- Apps: filter by size (large / medium / small / unknown) and by source (system /
  third-party), sort by scan order, name, or size. Filters and sort survive a
  relaunch, every menu checks the active option, and a search or filter with no
  match gets its own empty state.
- Apps and Backups: search also matches pinyin initials, so `wx` finds 微信 and
  `zp` finds 照片.
- Backups: grouped per app (newest group first) with per-group totals and a
  search field. An optional retention policy (keep all / 1 / 3 / 5 / 10 per app
  and scope) runs at launch and on demand, never touches automatic safety
  backups, and reports how many old backups it removed.
- History: export every record as CSV, and show each status as a badge on the
  trailing edge of the row.
- Space Lens: browse an app container one level at a time as a bubble map whose
  area follows size. Drill into folder bubbles, tap a file bubble for a preview,
  jump anywhere through the breadcrumb, and switch to a precise list.
- Space Lens: bubbles are transparent rings of light with a type icon — folders,
  databases, videos, images, archives, documents — and the tint follows the
  interface style.
- Space Lens: select several items to export or delete, swipe a list row to
  delete one, or long-press a bubble for preview, share, copy path or delete.
  Deletions ask for scope acknowledgement, land in a bin, and are recorded.
- Space Lens: a file preview — pinch-zoom images, pretty-printed JSON,
  monospaced text up to 2 MB, inline video and audio, and a 4 KB hex dump for
  everything else, readable at full speed even for a multi-gigabyte file.
- Space Lens: a bin under Settings → 数据 that lists every deleted session with
  when and where it came from, restores items to their original folder (a
  same-name file is never overwritten), removes single items, or empties it.

### Fixed

- Space Lens: the back gesture walks the container path one level per swipe and
  only leaves the map at the container root; file bubbles no longer show the
  internal `file:` prefix.
- Restore picker popover is anchored to the table instead of the navigation bar,
  which now holds the filter buttons.

## [0.3.1] — 2026-11-12

- Storage panel: inspect and clean invalid or interrupted backups and temp files.
- Keep only the newest automatic safety backup per app.
- Clean up staging left behind by shared imports.

## [0.3.0] — 2026-11-12

### Added

- Low-load profile (Standard / Automatic / Low-load); Automatic follows thermal
  pressure, Low-load always runs slower and cooler.
- Long operations move into a top capsule; tap to expand, keep using the app.
- The app action sheet blurs the screen behind it.
- Telegram channel link in Settings → About.

### Changed

- Backup: 6 → 4 metadata passes. Restore: 6 → 5 full reads; Low-load: 3.
- Copying and hashing run in bounded batches with short pauses.

### Fixed

- Restore journals and backup manifests are fsync'd; corrupt journals block
  new restores.
- No invisible backup directory after a failed publish; stale temp files are
  cleaned at launch.
- Free-space check, delete protection for referenced backups, running-app check.

## [0.2.1] — 2026-11-11

### Added

- Settings → Check for Updates: reads the latest GitHub release and links to it,
  so users can see whether a newer build exists without leaving the app.
- Tab bar uses a dark-green highlight for the selected item.
- Scan diagnostics: `Documents/scan-diag-latest.log` records each app's
  `grant` / `label` / `measure` timings plus a watchdog line.

### Fixed

- Large scans no longer stall around the kernel sandbox-extension limit: each
  app's token is released right after measuring instead of being kept until the
  LRU evicts it.
- Scans no longer stall on a single huge or badly fragmented container: the
  quick pass budgets each tree (12,000 entries / 0.25 s) and deferred apps are
  measured afterwards with their own progress, so the app count keeps moving.
- The update check resolves `releases/latest` via its redirect, avoiding the
  unauthenticated GitHub API rate limit.

## [0.2.0] — 2026-11-11

### Fixed


- Remote icon lookups no longer treat network errors as a permanent "not on
  the store" result: transient failures get one retry, misses expire after
  24 hours, and requests are paced to avoid burst throttling. A late remote
  image can also no longer be overwritten by a letter fallback, and revisiting
  a fallback row reloads a previously downloaded icon from disk.

- The cleaner dashboard ring now re-resolves its colors when the interface
  style changes, so it stays visible in dark mode.

- Builds no longer fail on `Failed to write Objective-C generated asset symbols.`
  The project does not use the generated asset-symbol constants, so
  `ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS` is now `NO` (Xcode's actool was
  denied writing `GeneratedAssetSymbols.h` into DerivedData on this machine).

- The share extension now asks the system to open WQManager after a successful
  import (responder-chain fallback when `NSExtensionContext.openURL:` refuses).
  If the system still keeps the share sheet open, the queued file is imported
  automatically the next time WQManager becomes active.

- Cleaner rows no longer clip text at large Dynamic Type sizes; every row uses
  intrinsic height and a `>= 52 pt` minimum.
- Dashboard progress ring no longer jitters when the selection changes.
- Cleaner drawers expand/collapse inside the table update transaction, so the
  app icon no longer jitters while the card resizes.

### Added

- Settings → About now links to the project on GitHub, with the star icon and a
  short "give it a star" line (0.2).

### Changed

- Version 0.2 (build 2).
- Cleaner list redesigned after the iOS 26 "storage" pattern: big selection
  circle, app icon, title + subtitle, right-aligned size, chevron, and a
  per-app drawer with `Library/Caches` / `tmp` as selectable sub-rows.
- Primary cleaner action shows the selected byte total: "Clean selected X".
- History records are grouped by day and operation type; groups collapse into a
  single card and expand on tap. Added "Expand all / Collapse all groups".
- Removed the sparkle emoji from the cleaner button and tab bar icons.
- New tab bar glyphs for Apps and Clean, plus a dedicated scan glyph for the
  loading state.
- Third-party credits are now an in-app screen with author avatars and links.

## [0.1.0] — 2026-11-11

First public source release.

### Added

- App data overview: container enumeration, sizes, identity status, display
  names from Launch Services.
- Quick and full app-data backups with staged publication and content hashes.
- Validated backup browser and `.wqbackup` export/import through the share
  extension and Files.
- Same-bundle-ID restore with automatic safety backup, recovery journal,
  post-write hash verification, rollback and crash recovery hints.
- Per-app cache cleaner for `Library/Caches` and `tmp`, with per-directory
  selection, container identity re-checks and cancellation.
- Two-stage confirmation for destructive actions; the typed stage can be
  disabled in Settings.
- Operation history with grouping by day and operation type.
- Icon resolver with local sources, generic-placeholder detection, App Store
  artwork fallback and disk cache.
- Localized interface (Simplified Chinese and English), legal gate, safety
  documentation, third-party credits with author avatars.
- Portable safety, backup store, operation store and archive tests runnable
  with `bash tests/run_tests.sh`.
