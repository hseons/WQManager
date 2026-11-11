# Safety Model

WQManager manages other applications' data. A bug can destroy user data even
when the device itself remains usable.

## Scope

Cleanup is limited to exact relative paths inside an app data container:

- `Library/Caches`
- `tmp`

The following are outside the product's cleanup scope:

- `Library/Logs` in the current release
- app databases, preferences, downloads, and `Documents`
- System Data and System Groups
- Internal Daemons
- App Group shared containers
- `/var/db`, `/var/MobileAsset`, and `/var/db/uuidtext`
- `/var/mobile/Library/Caches`
- Safari data and WebKit website data outside the selected app
- SpringBoard and other system caches
- Crash Analyzer reports
- Keychain data

## Destructive operations

Clean, clear, delete-backup, restore, and replace operations are destructive.
They must pass two independent confirmations:

1. Show the exact target, file count, size, and consequences. The user
   acknowledges the scope.
2. Show a final warning that the operation changes or removes data. The user
   explicitly authorizes execution.

Cancellation clears the confirmation state. The execution layer must reject an
operation unless both stages have been completed for the same operation ID.

## File-system preconditions

Every target must satisfy all applicable checks:

1. Absolute, normalized path.
2. Expected App Data container prefix with a path-component boundary.
3. Exact relative-path allowlist match.
4. Sandbox token issued for the expected container.
5. Container Bundle ID and inode identity match the scan.
6. No symbolic link in the target ancestry.
7. Target identity is unchanged immediately before mutation.

Replacement additionally requires:

1. Matching Bundle ID.
2. A validated backup manifest and content hashes.
3. A free-space check.
4. A safety backup of the current data.
5. A durable recovery journal.
6. Staged replacement followed by post-write verification.
7. Rollback when commit does not complete.

## Restore transaction

A restore first validates the source backup's manifest and content hashes. It
then creates and validates a separate safety backup of the target's current
data. Before the first destructive write, the engine checks that:

1. source and target Bundle IDs match;
2. the target container still has the scanned device and inode identity;
3. the target has not changed since its safety backup;
4. the source backup still matches its recorded hashes;
5. the user completed both independent confirmation stages.

A durable journal is written before any target directory is purged. A normal
failure triggers an immediate purge-and-copy rollback from the safety backup.
If rollback also fails, the journal and safety backup are retained. On the next
run, the app switches to Backups, shows the interrupted operation, and requires
two confirmations before attempting the recovery rollback.

## No claim of snapshot consistency

Files copied while another app is running can be inconsistent. WQManager must
ask the user to close the target app before backup, restore, replace, or clear.
The UI must not describe these operations as atomic filesystem snapshots.

WQManager must not expand its scope by following symbolic links, by treating a
parent directory as a cache target, or by deleting a path only because its name
contains `Caches`. Scope is based on the exact app container and allowlisted
relative path.

## Backup publication

An app backup is first written to a hidden `.incomplete-*` directory inside
the app's own backup workspace. The source tree is hashed before and after
copying, the staged copy's shape and content are verified, and a manifest is
written only after all selected parts pass. A completed backup is published
with a same-volume rename; incomplete backups are never displayed as valid.

This validates copy integrity, not snapshot consistency while the managed app
is running.

