#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE_DIR="$ROOT/WQManager/WQManager"
OUTPUT_DIR="${TMPDIR:-/tmp}/wqmanager-tests"

mkdir -p "$OUTPUT_DIR"

clang \
  -fobjc-arc \
  -fblocks \
  -I"$SOURCE_DIR" \
  -framework Foundation \
  "$SOURCE_DIR/WQMLanguageManager.m" \
  "$SOURCE_DIR/WQMSafetyPolicy.m" \
  "$SOURCE_DIR/WQMAppModel.m" \
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
  "$SOURCE_DIR/WQMBackupStore.m" \
  "$SOURCE_DIR/WQMOperationStore.m" \
  "$SOURCE_DIR/WQMBackupArchiveService.m" \
  "$ROOT/tests/WQMBackupArchiveTests.m" \
  -o "$OUTPUT_DIR/WQMBackupArchiveTests"

"$OUTPUT_DIR/WQMBackupArchiveTests"
