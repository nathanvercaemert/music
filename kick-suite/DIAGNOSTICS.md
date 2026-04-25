# KickSuite Diagnostics

This is the first file future LLMs should read when investigating long-run audio degradation.

## Start Here

1. Read `kick-suite/.runlogs/current-summary.md`.
2. If the summary references snapshots, read the newest file under `kick-suite/.runlogs/current/snapshots/`.
3. Only inspect raw logs after reading the compact summary and snapshots.

## Runtime Layout

Diagnostics are enabled automatically by `kick-suite/run.sh`, `hard-reset.sh`, `sonobus-run.sh`, and `watchdog.sh`.

```text
kick-suite/.runlogs/
  current -> runs/<run_id>/
  current-summary.md
  runs/<run_id>/
    meta.env
    events.jsonl
    health.jsonl
    summary.md
    logs/
    snapshots/
    deep/
```

`events.jsonl` is concise structured state. `health.jsonl` is periodic trend data. `summary.md` and `current-summary.md` are the LLM-friendly entrypoints.

In health records, `ports_ok` means all expected KickSuite ports are currently visible. `sonobus_ok` means the current SonoBus input port is visible. `sonobus_log_anomaly` means the current or legacy SonoBus log contains a known negotiation/error signature; it does not by itself mean SonoBus is currently down.

## Important Event Types

- `suite_start`: `run.sh` initialized a new run.
- `hard_reset_start` / `hard_reset_complete`: full audio stack reset was requested/completed.
- `previous_hard_reset`: `run.sh` found the most recent standalone hard-reset marker and attached it to this run.
- `client_launch`: a Faust client was started.
- `link_failed`: an expected PipeWire link failed.
- `core_missing`: watchdog could not see an expected core suite port, usually `output:out_0`.
- `sonobus_down`: watchdog could not see SonoBus input ports.
- `setup_fallback`: SonoBus started without the saved setup XML.
- `stale_ports`: ports remained visible after a hard reset.
- `snapshot_created`: a compact diagnostic snapshot was captured.

## Manual Diagnostics

Use compact mode first:

```bash
kick-suite/diagnose.sh
```

Use deep mode only when needed because it captures large artifacts:

```bash
kick-suite/diagnose.sh --deep
```

Deep artifacts are written under `kick-suite/.runlogs/current/deep/`.

`hard-reset.sh` writes `kick-suite/.runlogs/last-hard-reset.env`. The next `run.sh` records that marker as `previous_hard_reset`, so separate reset-then-start workflows remain visible in the current run summary.

## Privacy/Safety

Diagnostic process listings redact SonoBus passwords before writing snapshots. Diagnostics failures should not block audio startup.
