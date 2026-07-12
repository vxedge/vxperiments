# exp-002b — H3 decomposition + resource cost

- runs: 30 archives, manifest sha256 `625840eeeb0c…`
- probe: 1000 pps x 60 s per arm, idle topology
- host: kernel 6.17.0-35-generic, KVM=True, governor=performance
- caveats: shared-host gateway; full profile; resource sampling requires the arm's process to be matched by cmdline regex — 'cpu/rss: n/a' means no sample matched

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | max loss % | cpu % (mean) | rss MB (mean) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| container | 5 | 60000 | 54.3 (1.8) | 79.9 (1.3) | 94.0 (2.8) | 0.0 | 4.32 | 7.4 |
| microvm-mmio | 5 | 60000 | 113.8 (0.6) | 143.7 (2.3) | 163.2 (4.0) | 0.0 | 15.03 | 146.4 |
| libvirt-q35 | 5 | 60000 | 72.1 (3.4) | 102.8 (3.5) | 120.6 (2.6) | 0.0 | 8.2 | 166.3 |
| q35-pci | 5 | 60000 | 90.7 (3.5) | 123.6 (4.3) | 142.7 (5.4) | 0.0 | 11.45 | 150.7 |
| q35-vhost | 5 | 60000 | 78.6 (1.2) | 106.9 (5.0) | 124.1 (7.1) | 0.0 | 9.22 | 150.7 |
| microvm-pci | 5 | 60000 | 88.8 (1.3) | 121.0 (3.6) | 138.8 (5.0) | 0.0 | 11.22 | 150.1 |

## Decomposition verdicts

- **transport (MMIO vs PCI)** (microvm-pci vs microvm-mmio): MATTERS (Δp50 -25.0 µs, exceeds IQR 1.3 µs)
- **machine (q35 vs microvm)** (q35-pci vs microvm-pci): no measurable effect (Δp50 +1.9 µs, within IQR 3.5 µs)
- **vhost-net (on vs off)** (q35-vhost vs q35-pci): MATTERS (Δp50 -12.1 µs, exceeds IQR 3.5 µs)
- **management (libvirt vs raw QEMU)** (libvirt-q35 vs q35-pci): MATTERS (Δp50 -18.6 µs, exceeds IQR 3.5 µs)
