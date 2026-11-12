# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
semantic versioning once it reaches 1.0.

## [Unreleased]

### Added

- Settings → Data → "Backup & restore load": Standard, Automatic (default) and
  Low-load. Automatic backs off when the device reports serious thermal
  pressure and pauses while it is critical; Low-load always runs at a slower
  fixed pace.
- Backup and restore confirmations show the profile that will be used.
- Long backup, restore, import, export, recovery, delete and clean operations
  now report through a floating capsule below the status bar instead of a
  blocking alert. Tap the capsule for details; the rest of the app stays
  usable while the operation runs.

### Changed

- Copying and hashing now run in bounded batches with short pauses instead of
  holding peak CPU and flash throughput for the whole operation. SHA-256,
  safety backups, recovery journals and rollback are unchanged.
- Low-load restore replaces two full verification reads with metadata checks
  (6 → 3 full reads). The standard profile keeps every full read.
- Backup and restore keep the screen awake while they run.

## [0.3.0] — 2026-11-12

### Added

- Settings → About → Telegram Channel: opens
  [t.me/TheBallnow](https://t.me/TheBallnow).

### Changed

- Backup computes the directory identity, the structure signature and the byte
  total in one tree walk, and no longer re-walks the source after copying
  (6 → 4 metadata passes; the single data read is unchanged).
- Restore reuses the hashes the safety backup already computed during its
  read-back instead of hashing the safety backup a second time (6 → 5 full
  reads). The source verification, target check and post-copy verification are
  unchanged.

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
