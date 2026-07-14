# exp-002b — H3 decomposition + resource cost

- runs: 6 archives, manifest sha256 `625840eeeb0c…`
- probe: 500 pps x 10 s per arm, timeout 1000 ms, idle topology
- host: kernel 6.17.0-35-generic, KVM=True, governor=performance
- caveats: shared-host gateway; QUICK PROFILE — pipeline validation only, NOT reportable; resource sampling requires the arm's process to be matched by cmdline regex — 'cpu/rss: n/a' means no sample matched

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | max loss % (lost/sent) | cpu % (mean) | rss MB (mean) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| container | 1 | 5000 | 54.3 (0.0) | 86.7 (0.0) | 118.7 (0.0) | 0.0 (0/5000) | 2.2 | 7.3 |
| microvm-mmio | 1 | 5000 | 120.3 (0.0) | 155.5 (0.0) | 179.5 (0.0) | 0.0 (0/5000) | 8.7 | 146.5 |
| libvirt-q35 | 1 | 5000 | 73.9 (0.0) | 110.8 (0.0) | 135.4 (0.0) | 0.0 (0/5000) | 4.5 | 166.3 |
| q35-pci | 1 | 5000 | 94.7 (0.0) | 131.8 (0.0) | 157.6 (0.0) | 0.0 (0/5000) | 6.2 | 150.9 |
| q35-vhost | 1 | 5000 | 86.8 (0.0) | 115.1 (0.0) | 137.2 (0.0) | 0.0 (0/5000) | 5.2 | 150.5 |
| microvm-pci | 1 | 5000 | 94.3 (0.0) | 131.5 (0.0) | 154.1 (0.0) | 0.0 (0/5000) | 6.2 | 150.0 |

## Decomposition verdicts

- **transport (MMIO vs PCI)** (microvm-pci vs microvm-mmio): MATTERS (Δp50 -26.0 µs, exceeds IQR 1.0 µs)
- **machine (q35 vs microvm)** (q35-pci vs microvm-pci): no measurable effect (Δp50 +0.4 µs, within IQR 1.0 µs)
- **vhost-net (on vs off)** (q35-vhost vs q35-pci): MATTERS (Δp50 -7.9 µs, exceeds IQR 1.0 µs)
- **management (libvirt vs raw QEMU)** (libvirt-q35 vs q35-pci): MATTERS (Δp50 -20.8 µs, exceeds IQR 1.0 µs)

_(quick profile — indicative only, not for publication)_
