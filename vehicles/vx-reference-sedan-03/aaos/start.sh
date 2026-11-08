#!/bin/sh
# Start the AAOS guest on Cuttlefish's own launcher, after checking the images against SHA256SUMS.
set -eu
home=${VXEDGE_AAOS_HOME:?set VXEDGE_AAOS_HOME to the cuttlefish-auto build}
here=$(pwd)
(cd "$home" && sha256sum --quiet -c "$here/SHA256SUMS")
# The vehicle serves the Vehicle HAL on the slice (ivi-gw); nothing serves it on the host.
install -m 0755 "$here/vhal-proxy-none.sh" "$home/bin/vhal_proxy_server"
cd "$home"
# Only reached when status reports the guest down, so a scoped stop is safe here: it clears an instance
# record a previous run left marked running, which would make the launcher refuse.
env HOME="$home" cvd stop >/dev/null 2>&1 || true
exec sg cvdnetwork -c "env HOME=$home ./bin/launch_cvd --daemon --enable_vhal_proxy_server=true \
  --start_webrtc=false --gpu_mode=guest_swiftshader --cpus=4 --memory_mb=6144 --report_anonymous_usage_stats=n"
