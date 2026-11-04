# Kuksa use cases on vx-vehicle-03, 2026-11-04

[`exp-015`](../../experiments/exp-015) with kuksa-databroker 0.7.1 as the signal plane of
[`vx-vehicle-03`](../../vehicles/vx-vehicle-03). It repeats every check from
[`signal-plane-2026-11-03`](../signal-plane-2026-11-03), then runs `kuksa.val.v2` cases with real
providers and subscribers. **This is the published run, from merged `main`:** vxedge `8ad34b1`,
vxperiments `a68aa8c`. The branch run before the merge,
[`kuksa-cases-2026-11-03`](../kuksa-cases-2026-11-03), gave the same results.

[`transcript.txt`](transcript.txt) is the whole run, [`databroker.log`](databroker.log) the
broker's log from the v2 cases, and [`vehicle-document.sha256`](vehicle-document.sha256) pins the
workspace documents. Paths in the transcript are shortened to `vxperiments/`, and its times are
in UTC.

| Image | Pinned |
|---|---|
| databroker 0.7.1, under test | `ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd` |
| databroker CLI 0.7.1, v1 checks only | `ghcr.io/eclipse-kuksa/kuksa-databroker-cli@sha256:871649f14576871ca048ed5f4ff2c109656d748877d8ddb8609c67091c9f9c33` |
| can-provider 0.5.1 | `ghcr.io/eclipse-kuksa/kuksa-can-provider/can-provider@sha256:41f5abffe30be4dd0bf6d82f28ca149d327e2d6de8619b562a12035a30da0c8e` |
| kv2, the v2 test client | built from [`tools/kv2`](../../experiments/exp-015/tools/kv2), local to the host |

**47 checks passed, none failed.**

## The signal-plane checks, repeated on 0.7.1

| Check | Result |
|---|---|
| `up`, `status`, the 2 s stay-running check | passed |
| Flows to all four backends, allowed and denied | passed |
| `Vehicle.Speed` written and read with the v1 CLI from `cabin1`, refused from `zone-rl` | passed |
| Second `up` | empty diff of identities, 91 lines compared |
| Another vehicle's `status`, `up` and `down`, before and after a daemon restart | refused, nothing changed |
| `vehicle down` twice, and `down` after a failed `up` | nothing left behind |
| A databroker image that exits straight after starting | job failed: `started, then stopped running within 2 s` |
| `experiment up` with the same signal plane | databroker running with the same flags, `down` left nothing behind |
| `--insecure`, `--address`, `--port` on the pinned image | as on 0.7.0: `--insecure` changes nothing that connects |

## kuksa.val.v2 cases

| Case | Result |
|---|---|
| Server info, publish and get across `adas` | `0.7.1`; `hpc1` reads what `cabin1` wrote |
| A subscriber on `cabin1` | every published value, in order |
| A signal provider on `cabin1` claims a sensor and publishes on its stream | accepted; a subscriber on `hpc1` saw all three values |
| The same provider sends a value above the signal's max | rejected on the stream, `ERROR_CODE_INVALID_ARGUMENT` |
| **CAN feed:** can-provider replays its bundled dump from `cabin1`; a consumer subscribes on `hpc1` | 15 gear values reached the consumer; the gear has no other writer in the run |
| An actuation provider on `cabin1`, actuate from `hpc1` | the provider received the request |
| A second provider for the same actuator | `ALREADY_EXISTS` |
| Actuate with no provider | `UNAVAILABLE` |
| A provider that drops its stream after one answer | the next actuate is `UNAVAILABLE`; a new provider can claim |
| A wrong port on the allowed slice | the client's own refusal |
| Publish, get and subscribe from `zone-rl` on `infotainment` | refused, 5 to 6 frames reached the bridge each time, value unchanged afterwards |

The VLAN membership printed at the end: `vz-hpc1` and `vz-cabin1` on 100, `vz-zone-rl` on 101. The
databroker ran the whole case sequence without a restart.

## Observed, where the documentation does not say

- **`Actuate` returns ok at once, whatever the provider does.** With a provider that never answers,
  one that answers after 3 s, and one that answers with an error, the client got ok in 0.30 to
  0.35 ms each time, and each request did reach the provider. An ok from `Actuate` means the request
  was forwarded, not that the actuator acted. The proto notes the databroker does not react to a
  provider's error answer.
- **A gone provider's claim outlives it by about a second.** After a provider was removed, `Actuate`
  found no provider within 0.14 s, but a new claim was refused with `ALREADY_EXISTS` until 0.98 s,
  when the databroker logged `Actuation Provider gone`.
- **A provider's accepted publish gets no answer.** The databroker answers `PublishValuesRequest`
  only to reject it, and keeps the stream open after the provider half-closes.

The times above are one client's wall clock for one call, to tell an answer from a timeout. They are
not measurements.

## What this does not show

- Signals are unauthenticated (`--insecure`). Slice isolation is their only protection.
- `libvirt` was not part of the run.
- The CAN feed is a recorded dump replayed by can-provider, carrying speed and gear frames. No
  SocketCAN, plant model or vehicle application was involved, and the consumer is a test client.
- can-provider is not pure v2: through kuksa-client 0.6.0 it publishes over v2 with a v1 fallback,
  and its `get` is v1.
- kv2 and the vehicle's local images are local to this host.
