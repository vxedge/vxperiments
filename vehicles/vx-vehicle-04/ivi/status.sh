#!/bin/sh
# Exit 0 while this node's QEMU runs. Changes nothing.
pid=$(cat "$VX_RUNTIME_DIR/attach-$VX_NODE/qemu.pid" 2>/dev/null) || exit 1
kill -0 "$pid" 2>/dev/null
