# Security policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Use GitHub's
private vulnerability reporting (Security → Advisories → Report a
vulnerability) on this repository, or contact the maintainer listed on the
profile.

Include:

- affected version / commit;
- device and iOS version;
- a minimal description and, if possible, steps to reproduce;
- impact assessment (data loss, privilege boundary, privacy).

You can expect an initial response within a few days. This is a volunteer
project, so timelines are best-effort.

## Scope

In scope:

- ways to escape the intended path allow-list (`Library/Caches`, `tmp`);
- symlink or TOCTOU tricks that redirect deletion outside the selected
  container;
- restore path traversal, manifest forgery, or hash-verification bypass;
- sandbox-token misuse or reaching data the user did not select;
- unintended network requests or data exfiltration;
- backup imports that can execute code or write outside the store.

Out of scope:

- the fact that stock iOS denies third-party icon requests;
- jailbreaks, sideloading policy, or DRM circumvention;
- issues that require a malicious local process already at the same privilege
  level;
- Apple framework vulnerabilities (report those to Apple).

## Handling

- Fixes are prepared privately and released together with an advisory when
  appropriate.
- Do not test on other people's devices or data.
- Please give the project reasonable time to respond before public disclosure.

## No warranty

WQManager is distributed under GPL-3.0-or-later without warranty. It deletes and
overwrites app data by design. Read [DISCLAIMER.md](DISCLAIMER.md) before use.
