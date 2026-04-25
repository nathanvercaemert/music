#!/usr/bin/env bash

KS_LOGGING_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KS_SCRIPT_DIR="$(cd "${KS_LOGGING_LIB_DIR}/.." && pwd)"
KS_REPO_ROOT="$(cd "${KS_SCRIPT_DIR}/.." && pwd)"
KS_LOG_DIR="${KS_LOG_DIR:-${KS_SCRIPT_DIR}/.runlogs}"
KS_RUNS_DIR="${KS_LOG_DIR}/runs"
KS_RUN_ID="${KS_RUN_ID:-}"
KS_RUN_DIR="${KS_RUN_DIR:-}"
KS_RUN_STARTED_EPOCH="${KS_RUN_STARTED_EPOCH:-}"

ks_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

ks_file_stamp() {
  date '+%Y-%m-%dT%H-%M-%S'
}

ks_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

ks_redact() {
  awk '
    {
      line = $0
      gsub(/SONOBUS_PASSWORD=[^[:space:]]+/, "SONOBUS_PASSWORD=REDACTED", line)
      gsub(/password=[^[:space:]]+/, "password=REDACTED", line)
      if (line ~ /sonobus|SonoBus/) {
        gsub(/-p[[:space:]]+[^[:space:]]+/, "-p REDACTED", line)
      }
      print line
    }
  '
}

ks_git_sha() {
  git -C "${KS_REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || printf 'unknown'
}

ks_git_dirty() {
  if [[ -n "$(git -C "${KS_REPO_ROOT}" status --short --untracked-files=no 2>/dev/null)" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

ks_boot_id() {
  if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    tr -d '\n' < /proc/sys/kernel/random/boot_id
  else
    printf 'unknown'
  fi
}

ks_prepare_run_dir() {
  if [[ -z "${KS_RUN_ID}" ]]; then
    KS_RUN_ID="$(ks_file_stamp)"
  fi

  if [[ -z "${KS_RUN_STARTED_EPOCH}" ]]; then
    KS_RUN_STARTED_EPOCH="$(date +%s)"
  fi

  KS_RUN_DIR="${KS_RUNS_DIR}/${KS_RUN_ID}"
  mkdir -p "${KS_RUN_DIR}/logs" "${KS_RUN_DIR}/snapshots" "${KS_RUN_DIR}/deep" "${KS_LOG_DIR}"
  : > "${KS_RUN_DIR}/events.jsonl"
  : > "${KS_RUN_DIR}/health.jsonl"

  {
    printf 'run_id=%s\n' "${KS_RUN_ID}"
    printf 'started_at=%s\n' "$(ks_now)"
    printf 'started_epoch=%s\n' "${KS_RUN_STARTED_EPOCH}"
    printf 'git_sha=%s\n' "$(ks_git_sha)"
    printf 'git_dirty=%s\n' "$(ks_git_dirty)"
    printf 'boot_id=%s\n' "$(ks_boot_id)"
  } > "${KS_RUN_DIR}/meta.env"

  ln -sfn "runs/${KS_RUN_ID}" "${KS_LOG_DIR}/current" 2>/dev/null || true
  export KS_RUN_ID KS_RUN_DIR KS_RUN_STARTED_EPOCH KS_LOG_DIR
}

ks_start_new_run() {
  KS_RUN_ID="${KS_RUN_ID:-$(ks_file_stamp)}"
  KS_RUN_STARTED_EPOCH="$(date +%s)"
  ks_prepare_run_dir
}

ks_use_current_or_new() {
  local current_target

  if [[ -z "${KS_RUN_ID}" && -L "${KS_LOG_DIR}/current" ]]; then
    current_target="$(readlink "${KS_LOG_DIR}/current" 2>/dev/null || true)"
    current_target="${current_target##*/}"
    if [[ -n "${current_target}" ]]; then
      KS_RUN_ID="${current_target}"
    fi
  fi

  if [[ -n "${KS_RUN_ID}" && -d "${KS_RUNS_DIR}/${KS_RUN_ID}" ]]; then
    KS_RUN_DIR="${KS_RUNS_DIR}/${KS_RUN_ID}"
    if [[ -z "${KS_RUN_STARTED_EPOCH}" && -f "${KS_RUN_DIR}/meta.env" ]]; then
      KS_RUN_STARTED_EPOCH="$(awk -F= '$1 == "started_epoch" { print $2; exit }' "${KS_RUN_DIR}/meta.env")"
    fi
    KS_RUN_STARTED_EPOCH="${KS_RUN_STARTED_EPOCH:-$(date +%s)}"
    mkdir -p "${KS_RUN_DIR}/logs" "${KS_RUN_DIR}/snapshots" "${KS_RUN_DIR}/deep" "${KS_LOG_DIR}"
    touch "${KS_RUN_DIR}/events.jsonl" "${KS_RUN_DIR}/health.jsonl"
    ln -sfn "runs/${KS_RUN_ID}" "${KS_LOG_DIR}/current" 2>/dev/null || true
    export KS_RUN_ID KS_RUN_DIR KS_RUN_STARTED_EPOCH KS_LOG_DIR
    return 0
  fi

  ks_start_new_run
}

ks_log_subdir() {
  local name="$1"
  ks_use_current_or_new
  mkdir -p "${KS_RUN_DIR}/${name}"
  printf '%s/%s\n' "${KS_RUN_DIR}" "${name}"
}

ks_component_log_path() {
  local name="$1"
  local path
  path="$(ks_log_subdir logs)/${name}"
  ln -sfn "${path}" "${KS_LOG_DIR}/${name}" 2>/dev/null || true
  printf '%s\n' "${path}"
}

ks_run_age_s() {
  local now
  now="$(date +%s)"
  printf '%s' "$(( now - ${KS_RUN_STARTED_EPOCH:-now} ))"
}

ks_event() {
  local level="$1"
  local component="$2"
  local event="$3"
  local detail="${4:-}"
  shift 4 || true

  ks_use_current_or_new

  local line
  line="{\"ts\":\"$(ks_json_escape "$(ks_now)")\",\"run_id\":\"$(ks_json_escape "${KS_RUN_ID}")\",\"level\":\"$(ks_json_escape "${level}")\",\"component\":\"$(ks_json_escape "${component}")\",\"event\":\"$(ks_json_escape "${event}")\",\"pid\":\"$$\",\"run_age_s\":\"$(ks_run_age_s)\",\"detail\":\"$(ks_json_escape "${detail}")\""

  local key value
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    line+=",\"${key}\":\"$(ks_json_escape "${value}")\""
  done
  line+="}"

  printf '%s\n' "${line}" >> "${KS_RUN_DIR}/events.jsonl" 2>/dev/null || true
}

ks_port_exists() {
  local port_name="$1"
  {
    pw-link -o 2>/dev/null || true
    pw-link -i 2>/dev/null || true
  } | grep -Fxq "${port_name}"
}

ks_missing_ports() {
  local expected=(
    "main:out_0"
    "main:out_1"
    "909:in_0"
    "909:out_0"
    "808:in_0"
    "808:out_0"
    "kick-mix:in_0"
    "kick-mix:in_1"
    "kick-mix:out_0"
    "voice-spectral-governance:in_0"
    "voice-spectral-governance:out_0"
    "send-voice-spectral-governance:in_0"
    "send-voice-spectral-governance:in_1"
    "send-voice-spectral-governance:out_0"
    "voice-saturation:in_0"
    "voice-saturation:out_0"
    "send-voice-saturation:in_0"
    "send-voice-saturation:in_1"
    "send-voice-saturation:out_0"
    "saturation-spectral-governance:in_0"
    "saturation-spectral-governance:out_0"
    "send-saturation-spectral-governance:in_0"
    "send-saturation-spectral-governance:in_1"
    "send-saturation-spectral-governance:out_0"
    "output:in_0"
    "output:out_0"
    "output:out_1"
  )

  local missing=()
  local visible_ports
  visible_ports="$(
    {
      pw-link -o 2>/dev/null || true
      pw-link -i 2>/dev/null || true
    } | sort -u
  )"

  local port
  for port in "${expected[@]}"; do
    if ! grep -Fxq "${port}" <<< "${visible_ports}"; then
      missing+=("${port}")
    fi
  done

  local IFS=,
  printf '%s' "${missing[*]}"
}

ks_graph_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    pw-link -l 2>/dev/null | sha256sum | awk '{ print $1 }'
  else
    pw-link -l 2>/dev/null | cksum | awk '{ print $1 }'
  fi
}

ks_proc_sum() {
  local pattern="$1"
  local field="$2"
  local pids
  pids="$(pgrep -f "${pattern}" 2>/dev/null | paste -sd, -)"
  if [[ -z "${pids}" ]]; then
    printf '0'
    return
  fi

  if [[ "${field}" == "rss_mb" ]]; then
    ps -o rss= -p "${pids}" 2>/dev/null | awk '{ s += $1 } END { printf "%.1f", s / 1024 }'
  else
    ps -o pcpu= -p "${pids}" 2>/dev/null | awk '{ s += $1 } END { printf "%.1f", s }'
  fi
}

ks_sonobus_log_has_error() {
  local log_file="${KS_RUN_DIR}/logs/sonobus.log"
  [[ -f "${log_file}" ]] || log_file="${KS_LOG_DIR}/sonobus.log"
  [[ -f "${log_file}" ]] || return 1
  grep -Eiq "channel count 0 out of range|aoo_source: sink not found|error|failed" "${log_file}"
}

ks_log_health() {
  ks_use_current_or_new

  local missing ports_ok sonobus_ok sonobus_log_anomaly pipewire_active wireplumber_active pulse_active
  missing="$(ks_missing_ports)"
  ports_ok=true
  [[ -n "${missing}" ]] && ports_ok=false

  sonobus_ok=true
  if ! ks_port_exists "SonoBus:in_1"; then
    sonobus_ok=false
  fi
  sonobus_log_anomaly=false
  if ks_sonobus_log_has_error; then
    sonobus_log_anomaly=true
  fi

  pipewire_active="$(systemctl --user is-active pipewire 2>/dev/null || printf 'unknown')"
  wireplumber_active="$(systemctl --user is-active wireplumber 2>/dev/null || printf 'unknown')"
  pulse_active="$(systemctl --user is-active pipewire-pulse 2>/dev/null || printf 'unknown')"

  printf '{"ts":"%s","run_id":"%s","event":"health","run_age_s":%s,"ports_ok":%s,"sonobus_ok":%s,"sonobus_log_anomaly":%s,"missing_ports":"%s","graph_hash":"%s","pipewire_active":"%s","wireplumber_active":"%s","pipewire_pulse_active":"%s","rss_mb":{"sonobus":%s,"pipewire":%s,"wireplumber":%s},"cpu_pct":{"sonobus":%s,"pipewire":%s,"wireplumber":%s}}\n' \
    "$(ks_json_escape "$(ks_now)")" \
    "$(ks_json_escape "${KS_RUN_ID}")" \
    "$(ks_run_age_s)" \
    "${ports_ok}" \
    "${sonobus_ok}" \
    "${sonobus_log_anomaly}" \
    "$(ks_json_escape "${missing}")" \
    "$(ks_json_escape "$(ks_graph_hash)")" \
    "$(ks_json_escape "${pipewire_active}")" \
    "$(ks_json_escape "${wireplumber_active}")" \
    "$(ks_json_escape "${pulse_active}")" \
    "$(ks_proc_sum sonobus rss_mb)" \
    "$(ks_proc_sum pipewire rss_mb)" \
    "$(ks_proc_sum wireplumber rss_mb)" \
    "$(ks_proc_sum sonobus cpu_pct)" \
    "$(ks_proc_sum pipewire cpu_pct)" \
    "$(ks_proc_sum wireplumber cpu_pct)" \
    >> "${KS_RUN_DIR}/health.jsonl" 2>/dev/null || true
}

ks_filtered_pw_link() {
  pw-link -l 2>/dev/null \
    | grep -E '^(alsa_output|main|909|808|kick-mix|voice-spectral-governance|send-voice-spectral-governance|voice-saturation|send-voice-saturation|saturation-spectral-governance|send-saturation-spectral-governance|output|SonoBus|RustDesk):|[|][-<>].*(alsa_output|main|909|808|kick-mix|voice-spectral-governance|send-voice-spectral-governance|voice-saturation|send-voice-saturation|saturation-spectral-governance|send-saturation-spectral-governance|output|SonoBus|RustDesk):' \
    || true
}

ks_process_stats() {
  ps -eo pid,ppid,etimes,rss,pcpu,pmem,comm,args 2>/dev/null \
    | awk '
      NR == 1 { print; next }
      $7 ~ /^(pipewire|wireplumber|pipewire-pulse|sonobus|aooserver|main|kick-mix|909|808|output)$/ { print; next }
      $7 ~ /^(voice-spectral-|send-voice-spec|voice-saturatio|send-voice-satu)$/ { print; next }
      $7 ~ /^(saturation-spec|send-saturatio)$/ { print; next }
      $0 ~ /\/home\/music\/music\/(utilities|kicks|spectral-governance|saturation|saturation-spectral-governance)\// { print; next }
    ' \
    | ks_redact \
    || true
}

ks_service_summary() {
  local service
  for service in pipewire wireplumber pipewire-pulse; do
    printf '%s: %s\n' "${service}" "$(systemctl --user is-active "${service}" 2>/dev/null || printf 'unknown')"
  done
}

ks_default_metadata() {
  {
    pw-metadata -n default 2>/dev/null || true
    pw-metadata -n settings 2>/dev/null | grep -E "clock\\.(rate|quantum|min-quantum|max-quantum|force-rate|force-quantum)" || true
  } | ks_redact
}

ks_pi_health() {
  local value
  if command -v vcgencmd >/dev/null 2>&1; then
    value="$(vcgencmd measure_temp 2>&1 || true)"
    [[ "${value}" == temp=* ]] && printf '%s\n' "${value}"
    value="$(vcgencmd get_throttled 2>&1 || true)"
    [[ "${value}" == throttled=* ]] && printf '%s\n' "${value}"
  fi
  printf 'loadavg: '
  cat /proc/loadavg 2>/dev/null || true
}

ks_recent_relevant_logs() {
  local files=(
    "${KS_RUN_DIR}/logs/watchdog.log"
    "${KS_RUN_DIR}/logs/sonobus.log"
    "${KS_RUN_DIR}/logs/output.log"
  )
  local latest_aoo
  latest_aoo="$(find "${KS_RUN_DIR}/logs" "${KS_LOG_DIR}" -maxdepth 1 -type f -name 'aooserver_log_*.txt' 2>/dev/null | sort | tail -n 1)"
  [[ -n "${latest_aoo}" ]] && files+=("${latest_aoo}")

  local file
  for file in "${files[@]}"; do
    [[ -f "${file}" ]] || continue
    printf -- '--- %s ---\n' "${file}"
    grep -Ei 'error|warn|fail|fallback|fell back|xrun|underrun|overrun|missing|not visible|down|restart|channel count|sink not found|ServerStartError' "${file}" 2>/dev/null \
      | tail -n 30 \
      | ks_redact \
      || tail -n 30 "${file}" | ks_redact
  done
}

ks_snapshot() {
  local event="$1"
  local detail="${2:-}"
  local safe_event file missing

  ks_use_current_or_new
  safe_event="$(printf '%s' "${event}" | tr -cs 'A-Za-z0-9_.-' '_' | sed 's/^_//; s/_$//')"
  file="${KS_RUN_DIR}/snapshots/$(ks_file_stamp)-${safe_event}.md"
  missing="$(ks_missing_ports)"

  {
    printf '# KickSuite Diagnostic Snapshot\n\n'
    printf '%s\n' "- event: \`${event}\`"
    printf '%s\n' "- detail: \`${detail:-none}\`"
    printf '%s\n' "- timestamp: \`$(ks_now)\`"
    printf '%s\n' "- run_id: \`${KS_RUN_ID}\`"
    printf '%s\n' "- run_age_s: \`$(ks_run_age_s)\`"
    printf '%s\n' "- git_sha: \`$(ks_git_sha)\`"
    printf '%s\n' "- git_dirty: \`$(ks_git_dirty)\`"
    printf '%s\n' "- boot_id: \`$(ks_boot_id)\`"
    printf '%s\n' "- graph_hash: \`$(ks_graph_hash)\`"
    printf '%s\n\n' "- missing_ports: \`${missing:-none}\`"

    printf '## Services\n```text\n'
    ks_service_summary
    printf '```\n\n'

    printf '## Default Metadata\n```text\n'
    ks_default_metadata
    printf '```\n\n'

    printf '## Process Stats\n```text\n'
    ks_process_stats
    printf '```\n\n'

    printf '## Filtered PipeWire Graph\n```text\n'
    ks_filtered_pw_link
    printf '```\n\n'

    printf '## Pi/System Health\n```text\n'
    ks_pi_health
    printf '```\n\n'

    printf '## Recent Relevant Logs\n```text\n'
    ks_recent_relevant_logs
    printf '```\n'
  } > "${file}" 2>/dev/null || true

  ks_event warn diagnostics snapshot_created "created compact diagnostic snapshot" file="${file}" trigger="${event}"
  ks_update_summary
}

ks_update_summary() {
  ks_use_current_or_new

  local events_file="${KS_RUN_DIR}/events.jsonl"
  local health_file="${KS_RUN_DIR}/health.jsonl"
  local summary="${KS_RUN_DIR}/summary.md"
  local current_summary="${KS_LOG_DIR}/current-summary.md"
  local total_events core_missing sonobus_down setup_fallback link_failed stale_ports snapshots last_anomaly last_health

  total_events="$(wc -l < "${events_file}" 2>/dev/null || true)"
  core_missing="$(grep -c '"event":"core_missing"' "${events_file}" 2>/dev/null || true)"
  sonobus_down="$(grep -c '"event":"sonobus_down"' "${events_file}" 2>/dev/null || true)"
  setup_fallback="$(grep -c '"event":"setup_fallback"' "${events_file}" 2>/dev/null || true)"
  link_failed="$(grep -c '"event":"link_failed"' "${events_file}" 2>/dev/null || true)"
  stale_ports="$(grep -c '"event":"stale_ports"' "${events_file}" 2>/dev/null || true)"
  total_events="${total_events:-0}"
  core_missing="${core_missing:-0}"
  sonobus_down="${sonobus_down:-0}"
  setup_fallback="${setup_fallback:-0}"
  link_failed="${link_failed:-0}"
  stale_ports="${stale_ports:-0}"
  snapshots="$(find "${KS_RUN_DIR}/snapshots" -type f -name '*.md' 2>/dev/null | wc -l)"
  last_anomaly="$(grep -E '"level":"(warn|error)"' "${events_file}" 2>/dev/null | tail -n 1 || true)"
  last_health="$(tail -n 1 "${health_file}" 2>/dev/null || true)"

  {
    printf '# KickSuite Current Summary\n\n'
    printf '%s\n' "- run_id: \`${KS_RUN_ID}\`"
    printf '%s\n' "- run_dir: \`${KS_RUN_DIR}\`"
    printf '%s\n' "- generated_at: \`$(ks_now)\`"
    printf '%s\n' "- run_age_s: \`$(ks_run_age_s)\`"
    printf '%s\n' "- git_sha: \`$(ks_git_sha)\`"
    printf '%s\n' "- git_dirty: \`$(ks_git_dirty)\`"
    printf '%s\n\n' "- graph_hash: \`$(ks_graph_hash)\`"

    printf '## Counts\n'
    printf '%s\n' "- total_events: \`${total_events}\`"
    printf '%s\n' "- core_missing: \`${core_missing}\`"
    printf '%s\n' "- sonobus_down: \`${sonobus_down}\`"
    printf '%s\n' "- setup_fallback: \`${setup_fallback}\`"
    printf '%s\n' "- link_failed: \`${link_failed}\`"
    printf '%s\n' "- stale_ports: \`${stale_ports}\`"
    printf '%s\n\n' "- snapshots: \`${snapshots}\`"

    printf '## Current Health\n```json\n%s\n```\n\n' "${last_health:-none}"
    printf '## Last Anomaly\n```json\n%s\n```\n\n' "${last_anomaly:-none}"

    printf '## Recent Events\n```json\n'
    tail -n 12 "${events_file}" 2>/dev/null || true
    printf '```\n\n'

    printf '## Recent Snapshots\n'
    find "${KS_RUN_DIR}/snapshots" -type f -name '*.md' 2>/dev/null | sort | tail -n 8 | sed 's/^/- /'
  } > "${summary}" 2>/dev/null || true

  cp "${summary}" "${current_summary}" 2>/dev/null || true
}
