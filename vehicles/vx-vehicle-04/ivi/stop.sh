#!/bin/sh
# Stop this node's QEMU, and only it, by the PID it recorded. The tap stays: it belongs to the host.
set -eu
f=$VX_RUNTIME_DIR/attach-$VX_NODE/qemu.pid
[ -f "$f" ] || exit 0
pid=$(cat "$f")
kill "$pid" 2>/dev/null || true
for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
rm -f "$f"
