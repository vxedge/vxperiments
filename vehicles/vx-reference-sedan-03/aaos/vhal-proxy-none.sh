#!/bin/sh
# Cuttlefish's host Vehicle HAL server, disabled: in a vxedge vehicle the cockpit gateway serves it on the slice.
# The launcher still needs the slot (it sets the guest's port), so this waits until the launcher stops it.
exec sleep infinity
