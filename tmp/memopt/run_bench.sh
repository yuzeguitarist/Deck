#!/bin/zsh
set -euo pipefail

ROOT="/Users/jerry/Desktop/开发/Deck/Deck-memopt-50"
cd "$ROOT"
mkdir -p "$ROOT/tmp/memopt/fixture" "$ROOT/tmp/memopt/runs" "$ROOT/tmp/memopt/logs"

DERIVED="$ROOT/.memopt-dd"
APP="$DERIVED/Build/Products/Release/Deck.app/Contents/MacOS/Deck"

write_active() {
  local storage="$1"
  local scenario="$2"
  local run="$3"
  python3 - "$storage" "$scenario" "$run" <<'PY'
import json, sys
storage, scenario, run = sys.argv[1:]
path = "/Users/jerry/Desktop/开发/Deck/Deck-memopt-50/tmp/memopt/active.json"
with open(path, "w") as handle:
    json.dump({
        "storage": storage,
        "scenario": scenario,
        "fixture": "/Users/jerry/Desktop/开发/Deck/Deck-memopt-50/tmp/memopt/fixture",
        "output": "/Users/jerry/Desktop/开发/Deck/Deck-memopt-50/tmp/memopt/runs",
        "run": run,
    }, handle)
PY
}

run_app() {
  local log="$1"
  "$APP" > "$log" 2>&1
}

if [[ "${1:-}" != "test-only" ]]; then
  echo "BUILD $(date)"
  xcodebuild \
    -project "$ROOT/Deck.xcodeproj" \
    -scheme Deck \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    CLANG_COVERAGE_MAPPING=NO \
    CLANG_ENABLE_CODE_COVERAGE=NO \
    GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO \
    GCC_GENERATE_TEST_COVERAGE_FILES=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build \
    > "$ROOT/tmp/memopt/logs/build.log" 2>&1
fi

if [[ ! -f "$ROOT/tmp/memopt/fixture/marker.json" ]]; then
  BUILD_STORAGE="$ROOT/tmp/memopt/storage-build"
  rm -rf "$BUILD_STORAGE"
  mkdir -p "$BUILD_STORAGE"
  write_active "$BUILD_STORAGE" build build
  echo "FIXTURE $(date)"
  run_app "$ROOT/tmp/memopt/logs/fixture.log"
fi

for run in 1 2 3; do
  RUN_STORAGE="$ROOT/tmp/memopt/storage-run-$run"
  rm -rf "$RUN_STORAGE"
  mkdir -p "$RUN_STORAGE/Deck"
  cp "$ROOT/tmp/memopt/fixture/Deck.sqlite3" "$RUN_STORAGE/Deck/Deck.sqlite3"
  if [[ -f "$ROOT/tmp/memopt/fixture/Deck.sqlite3-wal" ]]; then
    cp "$ROOT/tmp/memopt/fixture/Deck.sqlite3-wal" "$RUN_STORAGE/Deck/Deck.sqlite3-wal"
  fi
  if [[ -f "$ROOT/tmp/memopt/fixture/Deck.sqlite3-shm" ]]; then
    cp "$ROOT/tmp/memopt/fixture/Deck.sqlite3-shm" "$RUN_STORAGE/Deck/Deck.sqlite3-shm"
  fi
  write_active "$RUN_STORAGE" suite "$run"
  echo "SUITE $run $(date)"
  run_app "$ROOT/tmp/memopt/logs/suite-$run.log"
done

python3 "$ROOT/tmp/memopt/median.py"
rm -f "$ROOT/tmp/memopt/active.json"
echo "DONE $(date)"
