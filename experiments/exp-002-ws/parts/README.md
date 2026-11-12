# parts/ — this experiment's own loadables

None. The two VM arms boot the published guest bundle
`ghcr.io/vxedge/parts/zone/linux/stack/probe-bundle` 0.1.1, pinned by digest in `../parts.yaml`
and fetched into the host's part cache when the arm comes up. Its part declares the UDP reflector
its guest runs on port 9800 (`org.vxedge.reflector`), which is what lets a measurement aim at it.

The container arm needs nothing here: the daemon runs `vxprobe` in the node's namespace.
