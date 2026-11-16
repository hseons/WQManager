#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
DEVICE="${1:?Usage: run_ui_tests.sh SIMULATOR_UDID BUILT_APP_PATH}"
APP="${2:?Supply a Debug simulator .app path}"
: "${WQM_UI_DERIVED_DATA:=${TMPDIR:-/tmp}/WQManager-UITests}"
xcrun simctl install "$DEVICE" "$APP"
python3 "$ROOT/tests/UI/prepare_fixtures.py" "$DEVICE"
xcodebuild -project "$ROOT/tests/UI/WQMUITests.xcodeproj" -scheme WQMUITests \
  -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath "$WQM_UI_DERIVED_DATA" -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
