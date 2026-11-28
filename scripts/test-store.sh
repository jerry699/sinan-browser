#!/bin/bash
# The production store, AppComposition and importers on a manual clock; no CEF or AppKit windows.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-store-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
source scripts/harness-cracore.sh
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  "${CRACORE[@]}" Sources/Cra/Perf/Perf.swift \
  Sources/Cra/Services/Import/*.swift \
  Sources/Cra/App/L10n.swift Sources/Cra/Services/SidebarStore.swift Sources/Cra/Services/SidebarIntegrity.swift Sources/Cra/Services/Persistence.swift \
  Sources/Cra/Services/SettingsSyncService.swift  Sources/Cra/Services/EaselFolder.swift Sources/Cra/Services/BundleDirectory.swift \
  Tests/Support/LegacyLiveFolderResults.swift Sources/Cra/Services/FaviconCache.swift Sources/Cra/Services/SafeStorage.swift Sources/Cra/App/EngineFramework.swift \
  Sources/Cra/Services/CraLog.swift Sources/Cra/Services/Scheduler.swift \
  Sources/Cra/App/AppComposition.swift Sources/Cra/App/FeatureFlags.swift \
  Tests/Support/ManualScheduler.swift Tests/StoreTests.swift -o "$TEST_DIR/store-tests"
# 自己的数据目录：不设的话 JSONStore 读本机真实的司南数据，测试撞上真浏览记录
# （apple.com.cn 购物页进了 auto-archive 的计数——本机必炸，CI 干净机器不炸）。
CRA_DATA_DIR="$TEST_DIR/data" "$TEST_DIR/store-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/store-tests" "$CRA_TEST_KEEP/"
