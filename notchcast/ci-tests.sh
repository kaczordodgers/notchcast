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
# shellcheck disable=SC2016
grep -q '^    local name=\$1$' Scripts/run-tests.sh || { echo "::error::run-tests.sh changed shape; update the skip hook"; exit 1; }
# shellcheck disable=SC2016
sed -i '' -E 's/^    local name=\$1$/    local name=$1; if [ -n "${NOTCHCAST_ONLY_TESTS:-}" ]; then case " $NOTCHCAST_ONLY_TESTS " in *" $name "*) ;; *) return 0;; esac; fi; case " $CI_SKIP_TESTS " in *" $name "*) echo "skipped on the runner: $name" >\&2; return 0;; esac/' Scripts/run-tests.sh
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
git checkout -- Scripts/run-tests.sh
exit $status
