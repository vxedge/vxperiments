# parts/ — this experiment's own loadables

Empty: this experiment's software is host processes (`local/vxprobe:host-process`,
`local/vxtraffic:host-process`), which name nothing in a registry and need nothing fetched.

A local part belongs here when the experiment grows one — a guest bundle, a container context,
a config layer. `parts.yaml` then references it as `./parts/<name>`, a **local** ref that needs
no registry digest because it is content-hashed into the workspace identity
(`ARCHITECTURE.md` §13) and into the results archive.

A part that outgrows one experiment is promoted to `vxparts`, published and digest-pinned.
That is a ref swap, not a move.
