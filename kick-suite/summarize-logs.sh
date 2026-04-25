#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGGING_LIB="${SCRIPT_DIR}/lib/logging.sh"

# shellcheck disable=SC1090
source "${LOGGING_LIB}"

ks_use_current_or_new
ks_log_health
ks_update_summary
printf '%s\n' "${KS_LOG_DIR}/current-summary.md"

