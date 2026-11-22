#!/usr/bin/env bash
# Repeat two paid native cycles across SQLite, and fail closed after real
# industry closure in a separate native world with saved coal aboard.
set -euo pipefail
cd "$(dirname "$0")/.."
BAYLINE_RAIL_COAL_QA_MODE=repeat bash tests/rail_coal_live_native.sh
BAYLINE_RAIL_COAL_QA_MODE=fault bash tests/rail_coal_live_native.sh
