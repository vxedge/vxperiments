"""Cold-start detection, shared by every analyzer.

Three quick campaigns on 2026-07-31 each produced a first-measured arm with a p99 three to five
times the others' and a **normal** p50 — exp-001's load-0 point at 301.6 µs, exp-002's container
arm at 441.1 (frozen: 89.9), exp-003's baseline at 297.0. Positional, not arm-specific:
exp-003's first arm is `baseline`, not a container. A handful of very slow packets at the start
of the first probe — page faults, ARP, veth/netns warm-up, the CPU frequency ramp before the
pinned governor settles — barely move a median over 5000 samples but dominate the top 50. The
full profiles do not show it, because a 10 s warmup absorbs what a 2–3 s one does not.

**This is not suppressed, and the profiles were deliberately left alone.** Cold start is a
phenomenon, not an artifact: an ECU that answers in 440 µs for its first fifty packets and 90 µs
thereafter is a finding an SDV safety argument cares about, and lengthening the quick warmup
would hide it while still not making a quick run reportable. What this module does is stop a
reader mistaking it for a regression — which is exactly what nearly happened when the pattern
was first seen.

Detection is deliberately **order-agnostic**: exp-010 randomises its load order per repetition,
so "the first one" is not a thing an archive knows. What it looks for is the symptom — one
group whose tail-to-median ratio stands far outside the others' — which is what cold start
actually looks like and what a genuine regression does not (a regression moves the median too).
"""

from statistics import median

# A group is flagged when its p99/p50 ratio is at least this multiple of the others' median
# ratio. 2.0 is deliberately blunt: the observed cases were 5-8x, and a threshold tuned to sit
# just under them would fire on ordinary tail variation.
RATIO_MULTIPLE = 2.0

# Below this, tail ratios are noisy enough that the comparison says little. A consequence worth
# knowing: exp-003 has two arms by design (baseline, ota-burst), so it can never be flagged here
# — its cold-start reading has to come from the run-to-run spread instead.
MIN_GROUPS = 3


def tail_outlier(groups):
    """Return `(label, ratio, typical_ratio)` for a group with an anomalous tail, else `None`.

    `groups` is `[(label, p50_us, p99_us), ...]` — one entry per arm or load point.
    """
    usable = [(label, p99 / p50) for label, p50, p99 in groups if p50 and p99]
    if len(usable) < MIN_GROUPS:
        return None

    worst_label, worst_ratio = max(usable, key=lambda x: x[1])
    others = [r for label, r in usable if label != worst_label]
    typical = median(others)
    if typical and worst_ratio >= RATIO_MULTIPLE * typical:
        return worst_label, worst_ratio, typical
    return None


def caveat(groups, quick):
    """A sentence for the report's caveat line, or `''` when nothing stands out."""
    found = tail_outlier(groups)
    if not found:
        return ""
    label, ratio, typical = found
    warmup_note = (
        "the quick profile's 2-3 s warmup does not absorb it (the full profile's 10 s does)"
        if quick
        else "this is unexpected under a full profile, where the 10 s warmup should absorb it"
    )
    return (
        f"**tail anomaly**: `{label}` has a p99/p50 ratio of {ratio:.1f} against a typical "
        f"{typical:.1f} — a blown tail with a normal median, which is what cold start looks "
        f"like (first packets after provisioning: page faults, ARP, veth/netns warm-up, CPU "
        f"frequency ramp) and not what a regression looks like (a regression moves the median "
        f"too). Read the p99 for `{label}` with that in mind — {warmup_note}"
    )
