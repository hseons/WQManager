# Backup & Restore Load Plan

Status: Phase 1 and Phase 2 shipped in 0.3.0; storage panel and hardening in 0.3.1
Related: [issue #1](https://github.com/hseons/WQManager/issues/1)

## 1. Problem

Issue #1 reports that backing up or restoring a large app pushes the SoC to
about 55 °C (measured with MiniWatt on an iPhone 17 / iOS 27). The request is a
slower-but-cooler mode, with an explicit requirement that safety backups,
SHA-256 verification, recovery journals and rollback protection stay intact.

Two independent things cause the heat:

1. **Duplicate work.** The same trees are walked and read more often than the
   verification contract requires (see §2).
2. **No duty cycle.** Hashes and copies run at full speed, so the device sits at
   its highest sustained power for the whole operation.

Phase 1 fixes (1) for every user with no UI change and no change in what is
verified. Phase 2 adds (2) as an opt-in load profile and, behind that profile,
the two remaining verification passes that can be replaced by cheaper metadata
checks.

## 2. Cost model today

`WQMBackupService.m` (0.2.1) per part:

| # | Work | Kind |
|---|------|------|
| 1 | `WQAppsSupportTreeSignature(source, YES)` — source identity | metadata walk |
| 2 | `wq_copy_contents(source, destination)` | clone/copy, one fsync per entry |
| 3 | source identity again | metadata walk |
| 4 | source shape | metadata walk |
| 5 | destination shape | metadata walk |
| 6 | `WQAppsSupportTreeContentSignature(destination)` | **full read + SHA-256** |
| 7 | after all parts: identity re-check of every part | metadata walk |
| 8 | `WQMBackupTreeSize(staging)` for `TotalBytes` | metadata walk |

`WQMRestoreService.m`:

| # | Work | Kind |
|---|------|------|
| 1 | `WQMRestoreVerifyBackup(backup)` | full read + SHA-256 |
| 2 | safety backup (`backupApp`, includes its own content hash) | copy + full read |
| 3 | verify the safety backup again | full read |
| 4 | `WQMRestoreTargetMatchesBackup` — live target vs safety hashes | full read |
| 5 | verify the source backup again | full read |
| 6 | after apply: target verification | full read |

On the same volume `copyItemAtPath` is usually a `clonefile`, so copying costs
mostly metadata; reading every byte through SHA-256 plus one `fsync` per entry is
where the sustained power goes. That is why "just sleep a bit" alone was not
enough, and why removing duplicate *reads* matters more than removing duplicate
*copies*.

## 3. Invariants

These do not change in either phase:

- The content digest encoding (`WQAppsSupportTreeContentSignature`, tag `'C'`)
  stays byte-identical. `PartHashes` are persisted and `.wqbackup` packages must
  round-trip between versions.
- Safety backup still runs before a destructive restore; the journal is still
  written ahead of the mutation; rollback stays available.
- Manifest format stays `2`; `WQMBackupStore` validation stays as strict.
- No new network access, no background execution requirement, no removal of
  per-entry `fsync` in the standard profile.
- Failures keep their current error strings and user-visible messages.

## 4. Phase 1 — standard-mode dedupe (0.3.0, no setting)

### 4.1 Backup: 6 metadata walks → 4, one data pass unchanged

Add to `WQAppsSupport.h`:

```objc
static inline BOOL WQAppsSupportTreeDigests(NSString *path, BOOL *exists,
                                            NSString **identityOut,
                                            NSString **shapeOut,
                                            unsigned long long *totalBytesOut,
                                            NSString **errorOut);
```

One sorted enumeration, two `CC_SHA256_CTX` (tags `'I'` and `'S'`) fed in the
same loop, plus a running sum of regular-file sizes. Output must be byte-identical
to today's `WQAppsSupportTreeSignature(path, YES, …)`, `…, NO, …)` and
`WQMBackupTreeSize`; `totalBytes` is exactly the sum of `st_size` over regular
files, matching `fileAttributes.fileSize`.

`WQMBackupService.m` changes:

- Use the merged call for the pre-copy capture (replaces walk 1).
- Drop the post-copy *source shape* walk (4). After the identity comparison
  (3 vs 1) proves the source did not change during the copy, the pre-copy shape
  is a valid reference for the destination.
- **Ordering is load-bearing:** compare identity first, then shape. Comparing
  shape first would compare the destination against a shape that may no longer
  describe the source.
- Take `TotalBytes` from the destination-shape walk (5) and delete
  `WQMBackupTreeSize` (8).
- Keep the cross-part re-check (7). It detects an app writing to an
  already-copied part while later parts are being read, so it is not redundant.
  Net: **6 → 4 metadata walks**; the 1 full-data read is unchanged.

### 4.2 Restore: 6 full reads → 5

`WQMBackupRecord` gains a `manifestFingerprint` — size, mtime, inode and the
SHA-256 of `manifest.plist`, captured whenever a record is loaded.

- Restore pass 3 now reuses the hashes the safety backup computed while reading
  back its staging tree. Re-validate cheaply: reload the record and require the
  fingerprint, bundle ID, parts and `PartHashes` to match the ones returned by
  the backup service. This is a check of a different artifact, not the same
  bytes being re-read.
- Pass 4 (`WQMRestoreTargetMatchesBackup`) and pass 5 stay full verification in
  0.3.0. Pass 4 answers "did the live target change after the safety backup?"
  Reusing the safety hashes there would compare the value with itself; that
  check must never become a tautology.
- `apply` and `rollback` keep their post-copy SHA-256 verification of the
  target, so a backup that changes after this point fails closed instead of
  copying mismatched bytes.

Expected: backup heat unchanged per byte but fewer metadata traversals on
file-heavy apps; restore drops one of six full reads (≈17 %).

## 5. Phase 2 — optional Low-Load mode (0.3.x)

### 5.1 Preference and UI

- `WQMLoadProfilePreferenceKey` with `standard` / `automatic` / `lowload`;
  default `automatic` (`WQMPreferences` follows the existing
  `WQMCleanDoubleConfirm…` pattern).
- Settings → Data → "Backup & restore load", three explicit options.
- Backup/restore confirmation dialogs show the effective profile, so a slow run
  is never a surprise.

### 5.2 Controller

`WQMLoadController` + immutable `WQMLoadPlan`:

- fields: `qos`, `batchBytes`, `batchFiles`, `batchPause`,
  `reduceVerificationPasses`, `consumeBytes:`, `consumeEntry:`, injected clock.
- `automatic` samples `NSProcessInfo.thermalState` every 5 s: `.serious` steps
  the duty cycle down, `.critical` pauses with a resume prompt; 30 s hysteresis
  prevents flapping. `isLowPowerModeEnabled` is only an initial hint.
- Long operations set `idleTimerDisabled = YES` for their duration (the app does
  not do this today) and restore it on completion or failure.

### 5.3 Pacing hooks

- `WQAppsSupportTreeContentSignaturePaced(path, exists, consume, errorOut)` —
  same digest bytes, calls `consume(bytes)` between 64 KB chunks. The existing
  function forwards with a `NULL` block, so every current call site is unchanged.
- `wq_copy_contents_paced(src, dst, consumeEntry, …)` in `WQAccess` — one call
  between entries. `wq_copy_contents` becomes a wrapper with a `NULL` block.
  Never sleep inside a `copyfile` callback; large files stay clone-backed.
- Export/import (`.wqbackup`) is **out of scope for v1**; it uses the same
  content signature and can adopt the paced variant later if measurements ask
  for it.

### 5.4 Low-load verification passes

Only when `reduceVerificationPasses` is on:

- Pass 4: compare live target **metadata** (identity + shape digest captured
  before the safety backup) instead of re-reading every byte.
- Pass 5: `stat`-based manifest fingerprint plus a metadata digest of the
  backup tree captured at first verification, instead of a second full read.
- The manifest fingerprint still gates both. Restore becomes **6 → 3 full
  reads** (initial verify, safety-backup read-back, final target verify).

Trade-off to state in the PR and in the issue: an in-place rewrite that keeps
inode, mtime, ctime, size and mode identical would no longer be detected. Apps
cannot do that while suspended/closed in practice, but it is a real narrowing
compared with the standard profile. That is why it is opt-in.

Implementation notes: the metadata is captured right after the first
verification. Pass 4 compares the live target against the captured metadata;
pass 5 compares `WQMBackupRecord.manifestFingerprint` plus the source metadata.
The automatic profile drops the two reads only while its thermal tier is above
standard, so a cool device behaves exactly like the standard profile. Apply and
rollback still re-hash the target after copying.

## 6. Measurement plan (P0, before Phase 2)

- `Documents/backup-diag-latest.log`, one line per stage: `stage`, `part`,
  `entries`, `bytes`, `seconds`, `thermalState`, `lowPowerMode`.
- Sample `thermalState` every 5 s during the operation; record start/end battery
  temperature if available.
- Decision gates:
  - If hashing + fsync is ≥ 60 % of wall time, Phase 2 is worth its UI surface.
  - If metadata walks dominate on file-heavy apps, Phase 1 alone may be enough
    for the reporter; ask them to re-measure before promising a temperature.
  - If `.serious` never appears during a large run, the automatic profile is
    mostly a no-op and the manual "low load" option carries the feature.

## 7. Testing

- `tests/WQMSupportDigestTests.m`: fixture tree (regular files, empty dirs,
  symlink, non-ASCII names, unusual modes, a file over 64 KB) — merged digests
  and `totalBytes` must equal the legacy functions; content digests unchanged.
- `tests/WQMLoadControllerTests.m`: duty-cycle math with a fake clock, batch
  boundaries, thermal transitions and hysteresis, pass-reduction flags.
- Existing `tests/run_tests.sh` suite must stay green; `.wqbackup` round-trip
  proves digest compatibility.
- Failure injection: mutate the target after the safety backup (must fail in
  both profiles), corrupt a manifest, interrupt a restore (journal recovery),
  delete a part mid-restore.
- Device matrix: one large app (multi-GB), one app with tens of thousands of
  files, one small app; record wall time and thermal state for standard vs
  low-load.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Merged digest drifts from the old one | Byte-equality test against the legacy functions |
| Shape compared before identity | Explicit ordering + comment; test that a mid-copy change fails |
| "Reuse" silently becomes "no check" | `WQMBackupRecord.manifestFingerprint` and captured metadata asserted before apply/rollback; test that a changed target aborts |
| Pacing starves the progress UI | Pauses happen on the worker queue; progress hops to main as today |
| `mtime` granularity hides a change | Identity digest includes ctime and directory metadata; unchanged from today |

## 9. Out of scope

- Removing per-entry `fsync` (that is what makes rollback trustworthy).
- `setiopolicy_np` / `IOPOL_THROTTLE` (likely `EPERM` for third-party apps on
  iOS; verify before relying on it).
- Parallel copying (clone + fsync are already serial and bounded).
- Export/import low-load pacing (revisit after Phase 2 measurements).
- Format 1 migration / deleting the unused `Format == 1` branch in
  `WQAppsSupportManifestFields` (separate cleanup).

## 10. Release checklist

1. Phase 1: bump `MARKETING_VERSION` to 0.3.0, CHANGELOG, README (both
   languages), ARCHITECTURE "Load profiles" section, `tests/run_tests.sh` green.
2. `npm pack` equivalent does not exist; build a device archive manually and
   record its provenance.
3. Tag `v0.3.0`, publish the GitHub release, and reply to issue #1 with measured
   numbers.
4. Phase 2 ships as 0.3.x with its own CHANGELOG entry; low-load stays opt-in.
