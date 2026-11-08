#!/bin/sh
# Exit 0 while the AAOS guest's launcher answers. Changes nothing.
home=${VXEDGE_AAOS_HOME:?set VXEDGE_AAOS_HOME to the cuttlefish-auto build}
cd "$home" && env HOME="$home" ./bin/cvd_status >/dev/null 2>&1
