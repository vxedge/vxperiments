# parts/ — this experiment's own loadables

`linux-probe/` is the guest bundle the microvm and libvirt arms boot: a kernel, an initramfs
and the static-musl `vxprobe` payload. It is **fetched, not committed** — 19 MB of binary, and
five sandboxes vendoring it would be 95 MB in git:

```bash
./tools/fetch-parts.sh
```

What *is* committed is `linux-probe.sha256`, the digest the bundle must have. A fetched part is
verified against it rather than trusted, and deliberately not against the `meta.json` that
arrives with the copy — a bundle carrying its own expected hashes proves nothing about which
bundle it is.

`parts.yaml` references it as `./parts/linux-probe`, a **local** ref, which needs no registry
digest because it is content-hashed into the results archive and into the workspace identity
(`ARCHITECTURE.md` §13). When the bundle is published as a vxparts loadable, the ref becomes a
published, digest-pinned one and `tools/fetch-parts.sh` pulls that instead. That is a
promotion, not a rewrite.

The container arm needs nothing here: it runs `vxprobe` as a host process.
