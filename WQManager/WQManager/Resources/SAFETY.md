# Safety

WQManager reads and writes other apps' data. A bug can corrupt that data, so
keep an independent backup before you start.

## Scope

Cleanup only removes `Library/Caches` and `tmp` inside the selected app's data
container. Everything else is out of scope: `Documents`, databases,
preferences, downloads, shared App Group containers, system directories,
SpringBoard caches, and the Keychain.

## Destructive operations

Cleanup, deleting backups, and restore all change data. Before each run the app
shows the target, size, and consequences and asks for confirmation. Cleanup can
also require a typed confirmation.

## Checks

Before touching anything, the app verifies that the path is inside the selected
app's container, that it is one of the allowed directories, that the sandbox
token is valid, that the Bundle ID and inode still match, and that there are no
symbolic links in the path.

Restore also validates the backup manifest, takes a safety backup first, and
rolls back on failure.

## Close the app

Close the target app before backup, restore, or cleanup. While an app is running
its files can change, so a copy may not be consistent, and the app may write its
old state back afterwards.
