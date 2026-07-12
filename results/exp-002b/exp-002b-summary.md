# exp-002b — H3 decomposition + resource cost

- runs: 30 archives, manifest sha256 `625840eeeb0c…`
- probe: 1000 pps x 60 s per arm, timeout 1000 ms, idle topology
- host: kernel 6.17.0-35-generic, KVM=True, governor=performance
- caveats: shared-host gateway; full profile; resource sampling requires the arm's process to be matched by cmdline regex — 'cpu/rss: n/a' means no sample matched

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | max loss % (lost/sent) | cpu % (mean) | rss MB (mean) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| container | 5 | 60000 | 54.6 (1.3) | 80.1 (2.0) | 94.4 (2.8) | 0.0 (0/60000) | 4.3 | 7.3 |
| microvm-mmio | 5 | 60000 | 113.9 (2.0) | 144.4 (3.4) | 165.0 (6.3) | 0.0 (0/60000) | 14.95 | 146.4 |
| libvirt-q35 | 5 | 60000 | 70.3 (1.6) | 101.6 (1.9) | 117.6 (2.4) | 0.0 (0/60000) | 8.15 | 166.2 |
| q35-pci | 5 | 60000 | 87.6 (2.0) | 119.9 (1.1) | 138.6 (2.6) | 0.0 (0/60000) | 11.28 | 150.9 |
| q35-vhost | 5 | 60000 | 78.1 (2.5) | 106.0 (3.2) | 122.9 (4.4) | 0.0 (0/60000) | 9.12 | 150.6 |
| microvm-pci | 5 | 60000 | 87.9 (2.2) | 120.1 (2.4) | 138.2 (3.2) | 0.0 (0/60000) | 11.4 | 150.2 |

## Decomposition verdicts

- **transport (MMIO vs PCI)** (microvm-pci vs microvm-mmio): MATTERS (Δp50 -26.0 µs, exceeds IQR 2.2 µs)
- **machine (q35 vs microvm)** (q35-pci vs microvm-pci): no measurable effect (Δp50 -0.3 µs, within IQR 2.2 µs)
- **vhost-net (on vs off)** (q35-vhost vs q35-pci): MATTERS (Δp50 -9.5 µs, exceeds IQR 2.5 µs)
- **management (libvirt vs raw QEMU)** (libvirt-q35 vs q35-pci): MATTERS (Δp50 -17.3 µs, exceeds IQR 2.0 µs)
