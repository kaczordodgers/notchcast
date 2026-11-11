#!/bin/bash
# Runner hook: a job's build products never outlive it on a maintainer Mac. The compiled-harness cache stays.
rm -rf "${RUNNER_TEMP:?}/DerivedData"
case "${TMPDIR:-}" in
    */gh-runner/*/tmp) find "$TMPDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + ;;
esac
exit 0
