#!/bin/sh
# Stop this AAOS guest through cvd, which keeps its instance record consistent. Never a host-wide reset.
set -eu
home=${VXEDGE_AAOS_HOME:?set VXEDGE_AAOS_HOME to the cuttlefish-auto build}
cd "$home" && env HOME="$home" cvd stop
