#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGGING_LIB="${SCRIPT_DIR}/lib/logging.sh"

# shellcheck disable=SC1090
source "${LOGGING_LIB}"

ks_use_current_or_new

mode="${1:-compact}"
ks_event info diagnose manual_diagnose "manual diagnostic capture requested" mode="${mode}"
ks_log_health
ks_snapshot "manual_diagnose" "manual compact diagnostic capture"

if [[ "${mode}" == "--deep" || "${mode}" == "deep" ]]; then
  deep_dir="$(ks_log_subdir deep)/$(ks_file_stamp)"
  mkdir -p "${deep_dir}"

  pw-link -l > "${deep_dir}/full-pw-link.txt" 2>&1 || true
  pw-top -b -n 5 > "${deep_dir}/pw-top.txt" 2>&1 || true
  systemctl --user status pipewire wireplumber pipewire-pulse --no-pager > "${deep_dir}/systemctl-user.txt" 2>&1 || true
  ps -eo pid,ppid,lstart,etimes,rss,pcpu,pmem,comm,args | ks_redact > "${deep_dir}/processes.txt" 2>&1 || true
  pw-metadata -n default > "${deep_dir}/pw-metadata-default.txt" 2>&1 || true
  pw-metadata -n settings > "${deep_dir}/pw-metadata-settings.txt" 2>&1 || true

  if command -v gzip >/dev/null 2>&1; then
    pw-dump 2>/dev/null | gzip -c > "${deep_dir}/pw-dump.json.gz" || true
  else
    pw-dump > "${deep_dir}/pw-dump.json" 2>&1 || true
  fi

  ks_event info diagnose deep_capture_complete "manual deep diagnostic capture completed" dir="${deep_dir}"
fi

ks_update_summary
printf 'Diagnostics captured in %s\n' "${KS_RUN_DIR}"

