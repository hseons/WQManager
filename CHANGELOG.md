# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
semantic versioning once it reaches 1.0.

## [Unreleased]

### Fixed

- Cleaner rows no longer clip text at large Dynamic Type sizes; every row uses
  intrinsic height and a `>= 52 pt` minimum.
- Dashboard progress ring no longer jitters when the selection changes.

### Changed

- Cleaner list redesigned after the iOS 26 "storage" pattern: big selection
  circle, app icon, title + subtitle, right-aligned size, chevron, and a
  per-app drawer with `Library/Caches` / `tmp` as selectable sub-rows.
- Primary cleaner action shows the selected byte total: "Clean selected X".
- History records are grouped by day and operation type; groups collapse into a
  single card and expand on tap. Added "Expand all / Collapse all groups".
- Removed the sparkle emoji from the cleaner button and tab bar icons.
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
