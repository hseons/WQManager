# Contributing

Thanks for taking the time to contribute.

## Before you start

- Read [SAFETY.md](SAFETY.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- This project deals with destructive filesystem operations. Changes that
  weaken identity checks, path validation or confirmation flows will not be
  merged.
- The code is GPL-3.0-or-later. By contributing you agree that your contribution
  is licensed under the same terms.

## Development setup

- Xcode 27.2+, iOS 26 SDK.
- Build for the simulator with the command in [docs/BUILDING.md](docs/BUILDING.md).
- No third-party dependencies are used. Please keep it that way; a change that
  adds a package manager dependency needs a strong justification.

## Code style

- Objective-C, matching the surrounding file (naming, spacing, comments).
- Prefer small, testable C/Objective-C helpers in `WQAppsSupport`,
  `WQMSafetyPolicy`, `WQMBackupStore` and friends over logic embedded in view
  controllers.
- All user-facing strings go through `WQML(key, fallback)` and must be added to
  both `zh-Hans.lproj/Localizable.strings` and `en.lproj/Localizable.strings`.
- Never introduce fixed heights that break Dynamic Type.
- No `NSLog` in release paths; use the existing diagnostic helpers for
  debug-only logging.

## Tests

Run before every pull request:

```sh
bash tests/run_tests.sh
```

Add a portable test when you change:

- path validation / cleanup policy (`tests/run_tests.sh` safety section),
- backup manifest or store layout,
- operation store persistence,
- archive/import validation.

UI changes should be verified on at least one simulator in light mode, with
Dynamic Type at the largest non-accessibility size, and in both languages.

## Pull requests

- Keep changes focused; separate refactors from behavior changes.
- Describe what you changed, why, and how you verified it.
- Include screenshots for UI changes.
- Mention any new debug switches or environment variables.

## Reporting bugs

Use the bug template. Include:

- device model, iOS version, build number;
- how the app was signed (Xcode, sideload, etc.);
- exact steps to reproduce;
- relevant lines from the in-app diagnostic log (if enabled).

Do not attach a full backup package unless it contains no personal data.

## Security

Please do not open public issues for security problems. See
[SECURITY.md](SECURITY.md).
