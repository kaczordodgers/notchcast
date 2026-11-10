#!/bin/bash
set -euo pipefail
TOOLS=$(cd "$(dirname "$0")/.." && pwd)
export CI=1
export LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 NOTCHCAST_TEST_HELPER_EXECUTABLE=1
export TINYCAST_TEST_JOBS=${CHAD_BUILD_QUEUE_JOBS:-4}
set -a
# shellcheck disable=SC1091
source "$TOOLS/notchcast/config.env"
set +a
# The queue filter in notchcast/test-harnesses.sh reads NOTCHCAST_ONLY_TESTS, NOTCHCAST_SHARD and CI_SKIP_TESTS.
if [ -n "${NOTCHCAST_SWIFTC_CACHE:-}" ]; then
  NOTCHCAST_SWIFTC_REAL=$(xcrun -f swiftc)
  NOTCHCAST_SWIFTC_TOOLCHAIN="$("$NOTCHCAST_SWIFTC_REAL" --version 2>&1) $(xcrun --show-sdk-path) $(xcrun --show-sdk-version) $(sw_vers -buildVersion)"
  export NOTCHCAST_SWIFTC_REAL NOTCHCAST_SWIFTC_TOOLCHAIN
  mkdir -p "$NOTCHCAST_SWIFTC_CACHE" "$RUNNER_TEMP/swiftc-shim"
  ln -sf "$TOOLS/notchcast/swiftc-cache.py" "$RUNNER_TEMP/swiftc-shim/swiftc"
  export PATH="$RUNNER_TEMP/swiftc-shim:$PATH"
fi
status=0
./Scripts/run-tests.sh || status=$?
BIN="${TMPDIR:-/tmp}/tinycast-harness"
if [ "$status" -ne 0 ] && ls "$BIN"/*.failed >/dev/null 2>&1; then
  failed="$(for f in "$BIN"/*.failed; do basename "$f" .failed; done)"
  mkdir -p "$RUNNER_TEMP/first-try" && cp "$BIN"/*.log "$RUNNER_TEMP/first-try/" 2>/dev/null || true
  still=""
  for name in $failed; do
    cat "$RUNNER_TEMP/first-try/$name.log"
    echo "::warning::retrying $name alone"
    ./Scripts/run-tests.sh "$name" || { still="$still $name"; cat "$BIN/$name.log"; }
  done
  status=0
  if [ -n "$still" ]; then
    if [ -z "${UPSTREAM:-}" ]; then
      git fetch -q --no-tags "https://github.com/$UPSTREAM_REPO.git" "+refs/heads/main:refs/remotes/upstream/main"
      UPSTREAM=$(git merge-base HEAD refs/remotes/upstream/main)
    fi
    git worktree add -q --detach "$RUNNER_TEMP/pristine" "$UPSTREAM"
    for name in $still; do
      if [ ! -e "$RUNNER_TEMP/pristine/Tests/$name.swift" ]; then
        echo "::error::$name fails with our commits and does not exist on upstream"; status=1
        continue
      fi
      if (cd "$RUNNER_TEMP/pristine" && TMPDIR="$RUNNER_TEMP/pristine-tmp" && mkdir -p "$TMPDIR" && export TMPDIR \
          && ./Scripts/run-tests.sh "$name" >/dev/null 2>&1); then
        echo "::error::$name fails with our commits and passes on upstream ${UPSTREAM:0:7}"; status=1
      else
        echo "::warning::$name fails on upstream ${UPSTREAM:0:7} too; not ours, ignored"
      fi
    done
    git worktree remove --force "$RUNNER_TEMP/pristine"
  fi
fi
if [ "$status" -ne 0 ]; then
  for f in "$BIN"/*.failed; do
    [ -e "$f" ] || continue
    cat "${f%.failed}.log"
  done
fi
exit $status
