#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PYTHON="$(command -v python3)"
exec "$PYTHON" "$HERE/install-memory-monitor.py" "$PYTHON"
