#!/bin/zsh
set -euo pipefail
here=${0:A:h}
scratch=${NOTCHCAST_GALLERY_SCRATCH:?set NOTCHCAST_GALLERY_SCRATCH to a scratch directory}
helper=$scratch/offscreen-check
xcrun swiftc -D DEBUG -swift-version 6 -default-isolation MainActor -O "$here/offscreen-check.swift" -o "$helper"
exec "$helper" "$@"
