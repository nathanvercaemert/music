#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MAIN_DSP="${REPO_ROOT}/utilities/main.dsp"
KICK_DSP="${REPO_ROOT}/kicks/909.dsp"

if ! command -v pw-jack >/dev/null 2>&1; then
  echo "pw-jack is required but not installed." >&2
  exit 1
fi

if ! command -v faust2jack >/dev/null 2>&1; then
  echo "faust2jack is required but not installed." >&2
  exit 1
fi

cd "${REPO_ROOT}"

pw-jack faust2jack "${MAIN_DSP}"
pw-jack faust2jack "${KICK_DSP}"

cat <<EOF
Build complete.

Generated:
  ${REPO_ROOT}/utilities/main
  ${REPO_ROOT}/kicks/909

Next:
  ${SCRIPT_DIR}/run.sh
EOF
