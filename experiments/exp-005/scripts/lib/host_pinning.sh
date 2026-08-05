#!/usr/bin/env bash
# host_pinning.sh — cpu governor + measurement-process pinning, shared by
# every run-exp-*.sh / calibration script that cares about microsecond-scale
# latency (currently exp-010, whose post-fix effect size is small enough
# that host scheduling noise is the limiting factor — see docs/STATUS.md,
# "Real per-slice HTB isolation delivered and live-verified").
#
# Neither mitigation here is new debt: exp-002b/003 already carry a
# cpu_pinning: "none" field admitting the absence of pinning, and
# docs/STATUS.md already tracks the non-PREEMPT_RT kernel caveat. They just
# never mattered enough to fix before, because every prior campaign's
# effect size was large enough to survive them.
#
# Usage:
#   source "$(dirname "$0")/lib/host_pinning.sh"
#   pin_cpu_governor_performance          # call once, early
#   trap 'restore_cpu_governors' EXIT     # or fold into your own cleanup trap
#   reserve_measurement_cores             # sets $MEAS_CORES / $NPROC
#   pin_if_alive "$some_pid"              # best-effort, safe to call always

ORIG_GOVERNORS=()

# Sets governor to `performance` on every cpufreq-capable core, remembering
# the original value per-core in $ORIG_GOVERNORS so restore_cpu_governors
# can put it back. No-op (with a message) on hosts with no cpufreq sysfs
# (VMs/containers without frequency scaling exposed).
pin_cpu_governor_performance() {
  for gov_file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    ORIG_GOVERNORS+=("$gov_file:$(cat "$gov_file" 2>/dev/null || echo unknown)")
  done
  if [[ ${#ORIG_GOVERNORS[@]} -gt 0 ]]; then
    echo "== pinning cpu governor to performance (was: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)) =="
    for gov_file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      echo performance | sudo tee "$gov_file" >/dev/null 2>&1 || true
    done
  else
    echo "== no cpufreq scaling_governor files found (VM/container host?) — skipping governor pin =="
  fi
}

restore_cpu_governors() {
  echo "== restoring original cpu governor(s) =="
  for entry in "${ORIG_GOVERNORS[@]:-}"; do
    [[ -z "$entry" ]] && continue
    local f="${entry%%:*}" v="${entry#*:}"
    [[ "$v" == "unknown" ]] && continue
    echo "$v" | sudo tee "$f" >/dev/null 2>&1 || true
  done
}

# Reserves the last 1-2 cores (host-size-dependent) for measurement-critical
# processes, sets $MEAS_CORES (a taskset -c compatible range, empty string
# on a single-core host) and $NPROC. Best-effort, not a hard guarantee:
# nothing here cpuset-restricts *other* processes (podman containers) away
# from these cores — it only pins the measurement path onto them, reducing
# contention without eliminating it. Callers should record $MEAS_CORES
# honestly in their own results metadata, not oversell it as isolation.
reserve_measurement_cores() {
  NPROC=$(nproc)
  if [[ "$NPROC" -ge 4 ]]; then
    MEAS_CORES="$((NPROC - 2))-$((NPROC - 1))"
  elif [[ "$NPROC" -ge 2 ]]; then
    MEAS_CORES="$((NPROC - 1))"
  else
    MEAS_CORES=""
  fi
  if [[ -n "$MEAS_CORES" ]]; then
    echo "== reserving cores $MEAS_CORES (of $NPROC) for measurement processes (best-effort, other processes unrestricted) =="
  else
    echo "== single-core host — cannot reserve measurement cores, skipping =="
  fi
}

# Best-effort taskset of $1 (a pid) onto $MEAS_CORES. Safe to call with an
# empty/missing pid (e.g. `pin_if_alive "$(cat maybe-missing.pid 2>/dev/null || true)"`)
# or before reserve_measurement_cores has run (MEAS_CORES unset -> no-op).
#
# The `|| true` is on the taskset call itself, not just this function's trailing `return 0` --
# under `set -e`, a failing command on the right-hand side of `&&` still aborts the whole
# script immediately, so `return 0` below never gets a chance to run. Found live 2026-08-05,
# closing docs/TASKS.md #14's exp-010 run: `taskset -pc` on a process holding an elevated file
# capability (e.g. `vxedged` after `setcap cap_net_admin+ep`, needed once the rtnetlink port
# made the daemon's own process require it) is refused by the kernel for a same-UID,
# non-privileged caller — confirmed directly (`taskset: ... Operation not permitted`), not
# assumed. That is exactly the case this function's own contract ("best-effort, safe to call
# always") says it should tolerate, and previously didn't.
pin_if_alive() {
  [[ -n "${MEAS_CORES:-}" && -n "${1:-}" ]] && { taskset -pc "$MEAS_CORES" "$1" >/dev/null 2>&1 || true; }
  return 0
}

# JSON-safe one-line description of the current pinning state, for
# embedding directly in a run-env.json's own cpu_pinning field.
cpu_pinning_description() {
  if [[ -n "${MEAS_CORES:-}" ]]; then
    echo "measurement processes taskset to cores $MEAS_CORES of $NPROC; best-effort, other processes not cpuset-restricted away from them"
  else
    echo "none (single-core host)"
  fi
}
