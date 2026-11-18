#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE_DIR="$ROOT/WQManager/WQManager"
OUTPUT_DIR="${TMPDIR:-/tmp}/wqmanager-tests"

mkdir -p "$OUTPUT_DIR"

clang -fobjc-arc -fblocks -I"$SOURCE_DIR" -framework Foundation \
  "$SOURCE_DIR/WQMLanguageManager.m" "$SOURCE_DIR/WQMAppModel.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" "$SOURCE_DIR/WQMAccessDiagnostics.m" \
  "$ROOT/tests/WQMAccessDiagnosticsTests.m" -o "$OUTPUT_DIR/WQMAccessDiagnosticsTests"
"$OUTPUT_DIR/WQMAccessDiagnosticsTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMLanguageManager.m" \
  "$SOURCE_DIR/WQMSafetyPolicy.m" \
  "$SOURCE_DIR/WQMAppModel.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" \
  "$ROOT/tests/WQMSafetyPolicyTests.m" \
  -o "$OUTPUT_DIR/WQMSafetyPolicyTests"

"$OUTPUT_DIR/WQMSafetyPolicyTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  -framework CoreFoundation \
  "$SOURCE_DIR/WQMLanguageManager.m" \
  "$SOURCE_DIR/WQMAppModel.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" \
  "$SOURCE_DIR/WQMBackupStore.m" \
  "$ROOT/tests/WQMBackupStoreTests.m" \
  -o "$OUTPUT_DIR/WQMBackupStoreTests"

"$OUTPUT_DIR/WQMBackupStoreTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  -framework CoreFoundation \
  "$ROOT/tests/WQMSupportDigestTests.m" \
  -o "$OUTPUT_DIR/WQMSupportDigestTests"

"$OUTPUT_DIR/WQMSupportDigestTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMLanguageManager.m" \
  "$SOURCE_DIR/WQMOperationStore.m" \
  "$ROOT/tests/WQMOperationStoreTests.m" \
  -o "$OUTPUT_DIR/WQMOperationStoreTests"

"$OUTPUT_DIR/WQMOperationStoreTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMLanguageManager.m" \
  "$SOURCE_DIR/WQMAppModel.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" \
  "$SOURCE_DIR/WQMBackupStore.m" \
  "$SOURCE_DIR/WQMOperationStore.m" \
  "$SOURCE_DIR/WQMBackupArchiveService.m" \
  "$ROOT/tests/WQMBackupArchiveTests.m" \
  -o "$OUTPUT_DIR/WQMBackupArchiveTests"

"$OUTPUT_DIR/WQMBackupArchiveTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMLoadController.m" \
  "$SOURCE_DIR/WQMPreferences.m" \
  "$ROOT/tests/WQMLoadControllerTests.m" \
  -o "$OUTPUT_DIR/WQMLoadControllerTests"

"$OUTPUT_DIR/WQMLoadControllerTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMHousekeeping.m" \
  "$SOURCE_DIR/WQMSharedInbox.m" \
  "$ROOT/tests/WQMHousekeepingTests.m" \
  -o "$OUTPUT_DIR/WQMHousekeepingTests"

"$OUTPUT_DIR/WQMHousekeepingTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMStorageService.m" \
  "$SOURCE_DIR/WQMBackupStore.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" \
  "$SOURCE_DIR/WQMSharedInbox.m" \
  "$SOURCE_DIR/WQMLanguageManager.m" \
  "$ROOT/tests/WQMStorageServiceTests.m" \
  -o "$OUTPUT_DIR/WQMStorageServiceTests"

"$OUTPUT_DIR/WQMStorageServiceTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMLanguageManager.m" \
  "$SOURCE_DIR/WQMOperationStore.m" \
  "$ROOT/tests/WQMHistoryExportTests.m" \
  -o "$OUTPUT_DIR/WQMHistoryExportTests"

"$OUTPUT_DIR/WQMHistoryExportTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMLanguageManager.m" \
  "$SOURCE_DIR/WQMAppModel.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" \
  "$ROOT/tests/WQMAppSortTests.m" \
  -o "$OUTPUT_DIR/WQMAppSortTests"

"$OUTPUT_DIR/WQMAppSortTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  -framework CoreFoundation \
  "$SOURCE_DIR/WQMLanguageManager.m" \
  "$SOURCE_DIR/WQMAppModel.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" \
  "$ROOT/tests/WQMSearchTests.m" \
  -o "$OUTPUT_DIR/WQMSearchTests"

"$OUTPUT_DIR/WQMSearchTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  -framework CoreGraphics \
  "$SOURCE_DIR/WQMBubbleLayout.m" \
  "$ROOT/tests/WQMBubbleLayoutTests.m" \
  -o "$OUTPUT_DIR/WQMBubbleLayoutTests"

"$OUTPUT_DIR/WQMBubbleLayoutTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMTrashStore.m" \
  "$SOURCE_DIR/WQMSharedInbox.m" \
  "$ROOT/tests/WQMTrashStoreTests.m" \
  -o "$OUTPUT_DIR/WQMTrashStoreTests"

"$OUTPUT_DIR/WQMTrashStoreTests"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMFilePreviewModel.m" \
  "$ROOT/tests/WQMFilePreviewTests.m" \
  -o "$OUTPUT_DIR/WQMFilePreviewTests"

"$OUTPUT_DIR/WQMFilePreviewTests"

# Feature persistence, bounded reads, serial jobs and partial-restore semantics.
clang -fobjc-arc -fblocks -I"$SOURCE_DIR" -framework Foundation \
  "$SOURCE_DIR/WQMLanguageManager.m" "$SOURCE_DIR/WQMAppModel.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" "$SOURCE_DIR/WQMScanHistory.m" \
  "$ROOT/tests/WQMScanHistoryTests.m" -o "$OUTPUT_DIR/WQMScanHistoryTests"
"$OUTPUT_DIR/WQMScanHistoryTests"

clang -fobjc-arc -fblocks -I"$SOURCE_DIR" -framework Foundation \
  "$SOURCE_DIR/WQMFileCatalog.m" "$ROOT/tests/WQMFileCatalogTests.m" -o "$OUTPUT_DIR/WQMFileCatalogTests"
"$OUTPUT_DIR/WQMFileCatalogTests"

clang -fobjc-arc -fblocks -I"$SOURCE_DIR" -framework Foundation \
  "$SOURCE_DIR/WQMFileCatalog.m" "$SOURCE_DIR/WQMFileAudit.m" \
  "$ROOT/tests/WQMFileAuditTests.m" -o "$OUTPUT_DIR/WQMFileAuditTests"
"$OUTPUT_DIR/WQMFileAuditTests"

clang -fobjc-arc -fblocks -I"$SOURCE_DIR" -framework Foundation \
  "$SOURCE_DIR/WQMLanguageManager.m" "$SOURCE_DIR/WQMAppModel.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" "$SOURCE_DIR/WQMBackupQueue.m" \
  "$ROOT/tests/WQMBackupQueueTests.m" -o "$OUTPUT_DIR/WQMBackupQueueTests"
"$OUTPUT_DIR/WQMBackupQueueTests"

clang -fobjc-arc -fblocks -I"$SOURCE_DIR" -framework Foundation -framework CoreFoundation \
  "$SOURCE_DIR/WQMLanguageManager.m" "$SOURCE_DIR/WQMBackupSelection.m" \
  "$SOURCE_DIR/WQMBackupStore.m" "$ROOT/tests/WQMBackupSelectionTests.m" -o "$OUTPUT_DIR/WQMBackupSelectionTests"
"$OUTPUT_DIR/WQMBackupSelectionTests"

clang -fobjc-arc -fblocks -I"$SOURCE_DIR" -framework Foundation -framework CoreFoundation \
  "$SOURCE_DIR/WQMLanguageManager.m" "$SOURCE_DIR/WQMAppModel.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" "$SOURCE_DIR/WQMBackupService.m" \
  "$SOURCE_DIR/WQMRestoreService.m" "$SOURCE_DIR/WQMBackupStore.m" \
  "$SOURCE_DIR/WQMLoadController.m" "$SOURCE_DIR/WQMPreferences.m" \
  "$SOURCE_DIR/WQMOperationStore.m" "$SOURCE_DIR/WQMStorageService.m" \
  "$SOURCE_DIR/WQMSharedInbox.m" "$SOURCE_DIR/WQMBackupArchiveService.m" "$ROOT/tests/WQMBackupRestoreTests.m" -o "$OUTPUT_DIR/WQMBackupRestoreTests"
"$OUTPUT_DIR/WQMBackupRestoreTests"

clang -fobjc-arc -fblocks -I"$SOURCE_DIR" -framework Foundation -lsqlite3 \
  "$SOURCE_DIR/WQMLanguageManager.m" "$SOURCE_DIR/WQMStructuredFile.m" \
  "$ROOT/tests/WQMStructuredFileTests.m" -o "$OUTPUT_DIR/WQMStructuredFileTests"
"$OUTPUT_DIR/WQMStructuredFileTests"

clang -fobjc-arc -fblocks -I"$SOURCE_DIR" -framework Foundation \
  "$SOURCE_DIR/WQMLanguageManager.m" "$SOURCE_DIR/WQMAppModel.m" \
  "$SOURCE_DIR/WQMBackupSelection.m" "$SOURCE_DIR/WQMScanHistory.m" \
  "$SOURCE_DIR/WQMAppScanner.m" "$ROOT/tests/WQMAppScannerTests.m" \
  -o "$OUTPUT_DIR/WQMAppScannerTests"
"$OUTPUT_DIR/WQMAppScannerTests"
